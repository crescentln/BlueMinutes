import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum AutomationMCPProtocol {
    public static let version = "2025-11-25"
    public static let adapterVersion = "meetingbuddy-mcp-stdio-v1"
    public static let maximumMessageBytes = 1_048_576
}

public enum AutomationMCPTransportFailure: Error, Equatable, Sendable {
    case messageTooLarge
    case incompleteMessageAtEndOfFile
}

/// Incremental newline framing for MCP's stdio transport. It never interprets
/// payload bytes and enforces the bound before a complete line is allocated.
public struct AutomationMCPLineFramer: Sendable {
    private let maximumMessageBytes: Int
    private var buffered = Data()

    public init(
        maximumMessageBytes: Int = AutomationMCPProtocol.maximumMessageBytes
    ) {
        precondition(maximumMessageBytes > 0)
        self.maximumMessageBytes = maximumMessageBytes
    }

    public mutating func append(_ bytes: Data) throws -> [Data] {
        var messages: [Data] = []
        for byte in bytes {
            if byte == 0x0a {
                messages.append(buffered)
                buffered.removeAll(keepingCapacity: true)
            } else {
                guard buffered.count < maximumMessageBytes else {
                    throw AutomationMCPTransportFailure.messageTooLarge
                }
                buffered.append(byte)
            }
        }
        return messages
    }

    public func validateEndOfFile() throws {
        guard buffered.isEmpty else {
            throw AutomationMCPTransportFailure.incompleteMessageAtEndOfFile
        }
    }
}

/// Local, tools-only MCP adapter over the accepted application command port.
/// It owns no workspace, persistence, filesystem, provider, or authority API.
public actor AutomationMCPAdapter {
    /// This allowlist is intentionally independent of the wider command
    /// catalog. Adding a future read command never exposes it over MCP without
    /// a separate review and explicit source change here.
    public static let exposedCommands: [AutomationCommandName] = [
        .describeSettings,
        .getCommandCatalog,
        .getMeetingPolicyStatus,
        .getSettings,
        .getStorageReport,
        .getWorkspaceStatus,
        .listActivity
    ]

    private enum LifecycleState: Sendable {
        case awaitingInitialize
        case awaitingInitializedNotification
        case operational
    }

    private let executor: any AutomationCommandExecuting
    private let clock: @Sendable () throws -> UTCInstant
    private let makeUUID: @Sendable () -> UUID
    private let maximumToolCallsPerMinute: Int
    private var recentToolCallMilliseconds: [Int64] = []
    private var lifecycleState: LifecycleState = .awaitingInitialize

    public init(
        executor: any AutomationCommandExecuting,
        maximumToolCallsPerMinute: Int = 120,
        clock: @escaping @Sendable () throws -> UTCInstant = {
            try UTCInstant(
                millisecondsSinceUnixEpoch: Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded(.down)
                )
            )
        },
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        precondition((1...10_000).contains(maximumToolCallsPerMinute))
        self.executor = executor
        self.maximumToolCallsPerMinute = maximumToolCallsPerMinute
        self.clock = clock
        self.makeUUID = makeUUID
    }

    /// Handles one MCP message without its newline delimiter. Notifications
    /// return nil, as required by JSON-RPC.
    public func receive(_ message: Data) async -> Data? {
        guard !message.isEmpty,
              message.count <= AutomationMCPProtocol.maximumMessageBytes
        else {
            return encodedError(id: nil, code: -32700, message: "Parse error")
        }

        let decoded: MCPJSONValue
        do {
            decoded = try JSONDecoder().decode(MCPJSONValue.self, from: message)
        } catch {
            return encodedError(id: nil, code: -32700, message: "Parse error")
        }
        guard case let .object(envelope) = decoded else {
            return encodedError(id: nil, code: -32600, message: "Invalid Request")
        }
        let detectedRequestID = envelope["id"].flatMap(MCPRequestID.init)
        guard Set(envelope.keys).isSubset(of: ["jsonrpc", "id", "method", "params"]),
              envelope["jsonrpc"] == .string("2.0"),
              case let .string(method)? = envelope["method"],
              !method.isEmpty,
              method.utf8.count <= 128
        else {
            return encodedError(
                id: detectedRequestID,
                code: -32600,
                message: "Invalid Request"
            )
        }

        let requestID: MCPRequestID?
        if let value = envelope["id"] {
            guard let parsed = MCPRequestID(value) else {
                return encodedError(id: nil, code: -32600, message: "Invalid Request")
            }
            requestID = parsed
        } else {
            requestID = nil
        }

        if requestID == nil {
            receiveNotification(method: method, params: envelope["params"])
            return nil
        }

        let id = requestID!
        if method == "ping" {
            guard isEmptyParameters(envelope["params"]) else {
                return encodedError(id: id, code: -32602, message: "Invalid params")
            }
            return encodedResult(id: id, result: .object([:]))
        }

        if method == "initialize" {
            guard lifecycleState == .awaitingInitialize,
                  validInitializeParameters(envelope["params"])
            else {
                return encodedError(id: id, code: -32602, message: "Invalid params")
            }
            lifecycleState = .awaitingInitializedNotification
            return encodedResult(id: id, result: initializeResult)
        }

        guard lifecycleState == .operational else {
            return encodedError(id: id, code: -32002, message: "Server not initialized")
        }

        switch method {
        case "tools/list":
            guard validToolsListParameters(envelope["params"]) else {
                return encodedError(id: id, code: -32602, message: "Invalid params")
            }
            return encodedResult(id: id, result: toolsListResult)
        case "tools/call":
            return await callTool(id: id, params: envelope["params"])
        default:
            return encodedError(id: id, code: -32601, message: "Method not found")
        }
    }

    private func receiveNotification(method: String, params: MCPJSONValue?) {
        switch method {
        case "notifications/initialized":
            if lifecycleState == .awaitingInitializedNotification,
               isEmptyParameters(params)
            {
                lifecycleState = .operational
            }
        case "notifications/cancelled":
            // Task-augmented tools are not advertised. Current read tools are
            // bounded and serialized, so there is no cancellable server task.
            break
        default:
            break
        }
    }

    private func callTool(id: MCPRequestID, params: MCPJSONValue?) async -> Data {
        guard case let .object(parameters)? = params,
              Set(parameters.keys).isSubset(of: ["name", "arguments", "_meta"]),
              case let .string(name)? = parameters["name"],
              name.utf8.count <= 128,
              parameters["_meta"].map({ $0.isObject }) ?? true
        else {
            return encodedError(id: id, code: -32602, message: "Invalid params")
        }
        guard let commandName = AutomationCommandName(rawValue: name),
              Self.exposedCommands.contains(commandName)
        else {
            return encodedError(id: id, code: -32602, message: "Unknown tool")
        }
        let arguments: [String: MCPJSONValue]
        switch parameters["arguments"] {
        case nil:
            arguments = [:]
        case let .object(value):
            arguments = value
        default:
            return encodedError(id: id, code: -32602, message: "Invalid params")
        }

        let now: UTCInstant
        do {
            now = try clock()
        } catch {
            return encodedResult(
                id: id,
                result: safeToolError(code: "clock_unavailable", message: "The local tool failed safely.")
            )
        }
        guard admitToolCall(at: now.millisecondsSinceUnixEpoch) else {
            return encodedResult(
                id: id,
                result: safeToolError(code: "rate_limit_exceeded", message: "The local MCP rate limit was reached.")
            )
        }

        let command: AutomationCommand
        do {
            command = try makeCommand(name: commandName, arguments: arguments)
        } catch {
            return encodedError(id: id, code: -32602, message: "Invalid params")
        }

        do {
            let execution = try await executor.execute(
                AutomationCommandRequest(
                    commandID: AutomationCommandID(makeUUID()),
                    replayNonce: AutomationReplayNonce(makeUUID()),
                    command: command,
                    issuedAt: now
                )
            )
            let canonical = try CanonicalJSON.encode(execution)
            guard canonical.count <= AutomationMCPProtocol.maximumMessageBytes,
                  let text = String(data: canonical, encoding: .utf8),
                  let structured = try? JSONDecoder().decode(
                      MCPJSONValue.self,
                      from: canonical
                  ),
                  structured.isObject
            else {
                return encodedResult(
                    id: id,
                    result: safeToolError(code: "result_too_large", message: "The local result exceeded its safe bound.")
                )
            }
            return encodedResult(
                id: id,
                result: .object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string(text)])
                    ]),
                    "structuredContent": structured,
                    "isError": .bool(false)
                ])
            )
        } catch {
            let mapped = safeToolFailure(error)
            return encodedResult(
                id: id,
                result: safeToolError(code: mapped.code, message: mapped.message)
            )
        }
    }

    private func admitToolCall(at milliseconds: Int64) -> Bool {
        let cutoff = milliseconds - 60_000
        recentToolCallMilliseconds.removeAll { $0 <= cutoff }
        guard recentToolCallMilliseconds.count < maximumToolCallsPerMinute else {
            return false
        }
        recentToolCallMilliseconds.append(milliseconds)
        return true
    }

    private func makeCommand(
        name: AutomationCommandName,
        arguments: [String: MCPJSONValue]
    ) throws -> AutomationCommand {
        switch name {
        case .getCommandCatalog:
            try require(arguments, allowed: [])
            return .getCommandCatalog
        case .getWorkspaceStatus:
            try require(arguments, allowed: [])
            return .getWorkspaceStatus
        case .getMeetingPolicyStatus:
            try require(arguments, allowed: ["meeting_id"], required: ["meeting_id"])
            guard case let .string(raw)? = arguments["meeting_id"] else {
                throw AutomationMCPCommandError.invalidArguments
            }
            return .getMeetingPolicyStatus(
                AutomationMeetingPolicyRequest(meetingID: try MeetingID(validating: raw))
            )
        case .getStorageReport:
            try require(arguments, allowed: ["maximum_entries"])
            let maximum = try unsignedInteger(
                arguments["maximum_entries"],
                defaultValue: 10_000,
                maximum: 100_000
            )
            return .getStorageReport(
                try AutomationStorageReportRequest(maximumEntries: UInt32(maximum))
            )
        case .getSettings:
            try require(arguments, allowed: [])
            return .getSettings
        case .describeSettings:
            try require(arguments, allowed: [])
            return .describeSettings
        case .listActivity:
            try require(arguments, allowed: ["limit"])
            let limit: UInt16?
            if let value = arguments["limit"] {
                limit = UInt16(
                    try unsignedInteger(value, defaultValue: 1, maximum: 200)
                )
            } else {
                limit = nil
            }
            return .listActivity(try AutomationActivityRequest(limit: limit))
        case .updateSettings, .rollbackSettings, .runWorkspaceDiagnostics:
            throw AutomationMCPCommandError.commandNotExposed
        }
    }

    private func require(
        _ arguments: [String: MCPJSONValue],
        allowed: Set<String>,
        required: Set<String> = []
    ) throws {
        guard Set(arguments.keys).isSubset(of: allowed),
              required.isSubset(of: Set(arguments.keys))
        else {
            throw AutomationMCPCommandError.invalidArguments
        }
    }

    private func unsignedInteger(
        _ value: MCPJSONValue?,
        defaultValue: UInt64,
        maximum: UInt64
    ) throws -> UInt64 {
        guard let value else { return defaultValue }
        let number: UInt64
        switch value {
        case let .unsigned(candidate): number = candidate
        case let .integer(candidate) where candidate >= 0: number = UInt64(candidate)
        default: throw AutomationMCPCommandError.invalidArguments
        }
        guard (1...maximum).contains(number) else {
            throw AutomationMCPCommandError.invalidArguments
        }
        return number
    }

    private func validInitializeParameters(_ value: MCPJSONValue?) -> Bool {
        guard case let .object(parameters)? = value,
              case let .string(protocolVersion)? = parameters["protocolVersion"],
              !protocolVersion.isEmpty,
              protocolVersion.utf8.count <= 32,
              case .object? = parameters["capabilities"],
              case let .object(clientInfo)? = parameters["clientInfo"],
              case let .string(clientName)? = clientInfo["name"],
              !clientName.isEmpty,
              clientName.utf8.count <= 128,
              case let .string(clientVersion)? = clientInfo["version"],
              !clientVersion.isEmpty,
              clientVersion.utf8.count <= 64
        else {
            return false
        }
        return true
    }

    private func validToolsListParameters(_ value: MCPJSONValue?) -> Bool {
        guard let value else { return true }
        guard case let .object(parameters) = value,
              Set(parameters.keys).isSubset(of: ["cursor", "_meta"]),
              parameters["cursor"] == nil,
              parameters["_meta"].map({ $0.isObject }) ?? true
        else {
            return false
        }
        return true
    }

    private func isEmptyParameters(_ value: MCPJSONValue?) -> Bool {
        guard let value else { return true }
        guard case let .object(parameters) = value else { return false }
        return parameters.isEmpty || (
            Set(parameters.keys) == ["_meta"]
                && parameters["_meta"]?.isObject == true
        )
    }

    private var initializeResult: MCPJSONValue {
        .object([
            "protocolVersion": .string(AutomationMCPProtocol.version),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(false)])
            ]),
            "serverInfo": .object([
                "name": .string("meetingbuddy"),
                "title": .string("MeetingBuddy Local MCP"),
                "version": .string(AutomationMCPProtocol.adapterVersion),
                "description": .string(
                    "Local read-only access to bounded MeetingBuddy status metadata."
                )
            ]),
            "instructions": .string(
                "Only the listed read tools are available. Calls append bounded local audit metadata."
            )
        ])
    }

    private var toolsListResult: MCPJSONValue {
        .object([
            "tools": .array(Self.exposedCommands.map(toolDescriptor))
        ])
    }

    private func toolDescriptor(_ command: AutomationCommandName) -> MCPJSONValue {
        let title: String
        let description: String
        let schema: MCPJSONValue
        switch command {
        case .getCommandCatalog:
            title = "Get Command Catalog"
            description = "Lists MeetingBuddy's typed command policy without exposing meeting content. The call writes bounded local audit metadata."
            schema = emptyObjectSchema
        case .getWorkspaceStatus:
            title = "Get Workspace Status"
            description = "Reads aggregate local workspace status without returning paths or meeting content. The call writes bounded local audit metadata."
            schema = emptyObjectSchema
        case .getMeetingPolicyStatus:
            title = "Get Meeting Policy Status"
            description = "Reads the exact current published policy graph for one opaque meeting ID. The call writes bounded local audit metadata."
            schema = objectSchema(
                properties: [
                    "meeting_id": .object([
                        "type": .string("string"),
                        "format": .string("uuid"),
                        "minLength": .unsigned(36),
                        "maxLength": .unsigned(36)
                    ])
                ],
                required: ["meeting_id"]
            )
        case .getStorageReport:
            title = "Get Storage Report"
            description = "Reads bounded aggregate storage counts without returning filenames or paths. The call writes bounded local audit metadata."
            schema = objectSchema(
                properties: [
                    "maximum_entries": integerSchema(maximum: 100_000)
                ]
            )
        case .getSettings:
            title = "Get Settings"
            description = "Reads the current bounded automation settings projection. The call writes bounded local audit metadata."
            schema = emptyObjectSchema
        case .describeSettings:
            title = "Describe Settings"
            description = "Describes patchable and protected automation settings without revealing protected values. The call writes bounded local audit metadata."
            schema = emptyObjectSchema
        case .listActivity:
            title = "List Activity"
            description = "Reads a bounded content-free automation audit list. The call itself appends bounded local audit metadata."
            schema = objectSchema(
                properties: ["limit": integerSchema(maximum: 200)]
            )
        case .updateSettings, .rollbackSettings, .runWorkspaceDiagnostics:
            preconditionFailure("A non-read command cannot become an MCP tool.")
        }
        return .object([
            "name": .string(command.rawValue),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": schema,
            "execution": .object(["taskSupport": .string("forbidden")])
        ])
    }

    private var emptyObjectSchema: MCPJSONValue {
        objectSchema(properties: [:])
    }

    private func objectSchema(
        properties: [String: MCPJSONValue],
        required: [String] = []
    ) -> MCPJSONValue {
        var schema: [String: MCPJSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.sorted().map(MCPJSONValue.string))
        }
        return .object(schema)
    }

    private func integerSchema(maximum: UInt64) -> MCPJSONValue {
        .object([
            "type": .string("integer"),
            "minimum": .unsigned(1),
            "maximum": .unsigned(maximum)
        ])
    }

    private func safeToolFailure(_ error: Error) -> (code: String, message: String) {
        guard let error = error as? AutomationContractError else {
            return ("internal_failure", "The local tool failed safely.")
        }
        switch error {
        case .invalidRequest:
            return ("invalid_request", "The command input is invalid.")
        case .invalidCaller:
            return ("invalid_caller", "The caller context was rejected.")
        case .unauthorized:
            return ("permission_denied", "The caller is not authorized.")
        case .policyDenied:
            return ("policy_denied", "Current policy denied the command.")
        case .replayDetected:
            return ("replay_detected", "The command replay was rejected.")
        case .settingsConflict:
            return ("settings_conflict", "The settings version changed.")
        case .commandUnavailable:
            return ("command_unavailable", "That capability is unavailable.")
        case .persistenceFailure:
            return ("persistence_failure", "The local operation failed safely.")
        }
    }

    private func safeToolError(code: String, message: String) -> MCPJSONValue {
        let structured = MCPJSONValue.object([
            "schema_version": .unsigned(1),
            "error": .object(["code": .string(code), "message": .string(message)])
        ])
        let text = (try? CanonicalJSON.encode(structured))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{\"error\":{\"code\":\"internal_failure\",\"message\":\"The local tool failed safely.\"},\"schema_version\":1}"
        return .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(text)])
            ]),
            "structuredContent": structured,
            "isError": .bool(true)
        ])
    }

    private func encodedResult(id: MCPRequestID, result: MCPJSONValue) -> Data {
        encodedEnvelope(
            .object([
                "jsonrpc": .string("2.0"),
                "id": id.jsonValue,
                "result": result
            ]),
            fallbackID: id
        )
    }

    private func encodedError(
        id: MCPRequestID?,
        code: Int64,
        message: String
    ) -> Data {
        var envelope: [String: MCPJSONValue] = [
            "jsonrpc": .string("2.0"),
            "error": .object([
                "code": .integer(code),
                "message": .string(message)
            ])
        ]
        envelope["id"] = id?.jsonValue ?? .null
        return encodedEnvelope(.object(envelope), fallbackID: id)
    }

    private func encodedEnvelope(
        _ value: MCPJSONValue,
        fallbackID: MCPRequestID?
    ) -> Data {
        if let encoded = try? CanonicalJSON.encode(value),
           encoded.count <= AutomationMCPProtocol.maximumMessageBytes
        {
            return encoded
        }
        var fallback: [String: MCPJSONValue] = [
            "jsonrpc": .string("2.0"),
            "error": .object([
                "code": .integer(-32603),
                "message": .string("Internal error")
            ])
        ]
        fallback["id"] = fallbackID?.jsonValue ?? .null
        return (try? CanonicalJSON.encode(MCPJSONValue.object(fallback)))
            ?? Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}".utf8)
    }
}

private enum AutomationMCPCommandError: Error, Sendable {
    case invalidArguments
    case commandNotExposed
}

private enum MCPRequestID: Sendable, Equatable {
    case string(String)
    case unsigned(UInt64)
    case integer(Int64)

    init?(_ value: MCPJSONValue) {
        switch value {
        case let .string(raw) where !raw.isEmpty && raw.utf8.count <= 128:
            self = .string(raw)
        case let .unsigned(raw):
            self = .unsigned(raw)
        case let .integer(raw):
            self = .integer(raw)
        default:
            return nil
        }
    }

    var jsonValue: MCPJSONValue {
        switch self {
        case let .string(value): .string(value)
        case let .unsigned(value): .unsigned(value)
        case let .integer(value): .integer(value)
        }
    }
}

private indirect enum MCPJSONValue: Codable, Equatable, Sendable {
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case string(String)
    case unsigned(UInt64)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode([String: MCPJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsigned(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else {
            let value = try container.decode(Double.self)
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A JSON number must be finite."
                )
            }
            self = .double(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .unsigned(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "A JSON number must be finite."
                    )
                )
            }
            try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var isObject: Bool {
        if case .object = self { true } else { false }
    }
}
