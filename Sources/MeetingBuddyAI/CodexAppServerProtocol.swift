import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum CodexAppServerOperation: String, Hashable, Sendable {
    case initialize
    case configuration
    case accountRead
    case accountLogin
    case accountLoginCancel
    case accountLogout
    case quotaRead
    case threadStart
    case threadResume
    case threadRead
    case threadDelete
    case turnStart
    case turnInterrupt
}

public enum CodexProtocolViolation: String, Hashable, Sendable {
    case malformedEnvelope = "malformed_envelope"
    case oversizedMessage = "oversized_message"
    case unexpectedResponse = "unexpected_response"
    case unknownNotification = "unknown_notification"
    case forbiddenServerRequest = "forbidden_server_request"
    case forbiddenItem = "forbidden_item"
    case crossSessionIdentifier = "cross_session_identifier"
    case invalidConfinementEvidence = "invalid_confinement_evidence"
    case outputLimitExceeded = "output_limit_exceeded"
}

public enum CodexSafeFailureCategory: String, Hashable, Sendable {
    case authenticationRequired = "authentication_required"
    case quotaUnavailable = "quota_unavailable"
    case networkUnavailable = "network_unavailable"
    case runtimeExited = "runtime_exited"
    case requestRejected = "request_rejected"
    case contextWindowExceeded = "context_window_exceeded"
    case interrupted
    case unavailable
}

public enum CodexAppServerError: Error, Equatable, Sendable {
    case notStarted
    case alreadyStarted
    case requestTimedOut(CodexAppServerOperation)
    case processExited
    case protocolViolation(CodexProtocolViolation)
    case serverRejected(CodexSafeFailureCategory)
}

public enum CodexPlanType: String, Hashable, Sendable {
    case free
    case go
    case plus
    case pro
    case prolite
    case team
    case business
    case enterprise
    case education
    case unknown
}

public enum CodexAccountState: Hashable, Sendable {
    case signedOut(requiresOpenAIAuthentication: Bool)
    case connected(plan: CodexPlanType)
}

public struct CodexLoginChallenge: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case browser
        case deviceCode = "device_code"
    }

    public let kind: Kind
    public let loginID: String
    public let verificationURL: URL
    public let userCode: String?

    init(
        kind: Kind,
        loginID: String,
        verificationURL: URL,
        userCode: String?
    ) {
        self.kind = kind
        self.loginID = loginID
        self.verificationURL = verificationURL
        self.userCode = userCode
    }
}

public struct CodexQuotaWindow: Hashable, Sendable {
    public let usedPercent: Int
    public let resetsAtUnixSeconds: Int64?
    public let durationMinutes: Int64?
}

public struct CodexQuotaState: Hashable, Sendable {
    public let plan: CodexPlanType
    public let primary: CodexQuotaWindow?
    public let secondary: CodexQuotaWindow?
    public let hasCredits: Bool?
    public let creditsUnlimited: Bool?
    public let spendControlReached: Bool?
    public let isUnavailable: Bool
}

public struct CodexThreadHandle: Hashable, Sendable {
    public let threadID: String
    public let model: String
    public let modelProvider: String
}

public struct CodexMeetingThreadSession: Hashable, Sendable {
    public let handle: CodexThreadHandle
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let runtimeVersion: String

    init(
        handle: CodexThreadHandle,
        context: CodexMeetingTextContext,
        runtimeVersion: String
    ) {
        self.handle = handle
        workspaceID = context.workspaceID
        meetingID = context.meetingID
        meetingRevision = context.meetingRevision
        self.runtimeVersion = runtimeVersion
    }
}

public struct CodexTurnHandle: Hashable, Sendable {
    public let threadID: String
    public let turnID: String
}

public enum CodexTurnCompletionStatus: String, Hashable, Sendable {
    case completed
    case interrupted
    case failed
}

public enum CodexThreadState: String, Hashable, Sendable {
    case idle
    case active
    case systemError = "system_error"
    case closed
    case deleted
}

public enum CodexAppServerEvent: Hashable, Sendable {
    case accountChanged(CodexAccountState)
    case loginCompleted(loginID: String?, success: Bool)
    case quotaChanged(CodexQuotaState)
    case agentMessageDelta(
        threadID: String,
        turnID: String,
        itemID: String,
        delta: String
    )
    case turnStarted(CodexTurnHandle)
    case turnCompleted(
        CodexTurnHandle,
        status: CodexTurnCompletionStatus
    )
    case threadStateChanged(
        threadID: String,
        state: CodexThreadState
    )
    case safeFailure(
        threadID: String?,
        turnID: String?,
        category: CodexSafeFailureCategory,
        willRetry: Bool
    )
    case warning
    case processExited
}

enum CodexJSONValue: Codable, Equatable, Sendable {
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self),
                  value.isFinite
        {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [CodexJSONValue].self
        ) {
            self = .array(value)
        } else if let value = try? container.decode(
            [String: CodexJSONValue].self
        ) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .unsignedInteger(value):
            try container.encode(value)
        case let .number(value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription:
                            "JSON numbers must be finite."
                    )
                )
            }
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var objectValue: [String: CodexJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [CodexJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var int64Value: Int64? {
        switch self {
        case let .integer(value):
            value
        case let .unsignedInteger(value) where value <= Int64.max:
            Int64(value)
        default:
            nil
        }
    }
}

enum CodexProtocolMessage: Equatable, Sendable {
    case response(
        id: Int64,
        result: CodexJSONValue?,
        error: CodexJSONValue?
    )
    case notification(method: String, params: CodexJSONValue)
    case serverRequest(
        id: CodexJSONValue,
        method: String,
        params: CodexJSONValue
    )
}

enum CodexProtocolCodec {
    static let maximumLineBytes = 1_048_576

    static func decodeLine(_ data: Data) throws -> CodexProtocolMessage {
        guard !data.isEmpty,
              data.count <= maximumLineBytes,
              let root = try? JSONDecoder().decode(
                  CodexJSONValue.self,
                  from: data
              ),
              let object = root.objectValue
        else {
            throw CodexAppServerError.protocolViolation(
                data.count > maximumLineBytes
                    ? .oversizedMessage
                    : .malformedEnvelope
            )
        }
        let allowedKeys: Set<String> = [
            "jsonrpc",
            "id",
            "method",
            "params",
            "result",
            "error",
            "emittedAtMs"
        ]
        guard Set(object.keys).isSubset(of: allowedKeys),
              object["jsonrpc"] == nil
                  || object["jsonrpc"]?.stringValue == "2.0"
        else {
            throw CodexAppServerError.protocolViolation(
                .malformedEnvelope
            )
        }

        let method = object["method"]?.stringValue
        if let method {
            if let emittedAt = object["emittedAtMs"] {
                guard object["id"] == nil,
                      emittedAt.int64Value.map({ $0 >= 0 }) == true
                else {
                    throw CodexAppServerError.protocolViolation(
                        .malformedEnvelope
                    )
                }
            }
            guard isBoundedIdentifier(method) else {
                throw CodexAppServerError.protocolViolation(
                    .malformedEnvelope
                )
            }
            let params = object["params"] ?? .object([:])
            if let id = object["id"] {
                return .serverRequest(
                    id: id,
                    method: method,
                    params: params
                )
            }
            return .notification(method: method, params: params)
        }

        guard object["emittedAtMs"] == nil,
              let id = object["id"]?.int64Value,
              (object["result"] == nil) != (object["error"] == nil)
        else {
            throw CodexAppServerError.protocolViolation(
                .malformedEnvelope
            )
        }
        return .response(
            id: id,
            result: object["result"],
            error: object["error"]
        )
    }

    static func request(
        id: Int64,
        method: String,
        params: CodexJSONValue
    ) throws -> Data {
        try encode(
            .object([
                "id": .integer(id),
                "method": .string(method),
                "params": params
            ])
        )
    }

    static func notification(
        method: String
    ) throws -> Data {
        try encode(
            .object([
                "method": .string(method)
            ])
        )
    }

    static func response(
        id: CodexJSONValue,
        result: CodexJSONValue
    ) throws -> Data {
        try encode(
            .object([
                "id": id,
                "result": result
            ])
        )
    }

    private static func encode(
        _ value: CodexJSONValue
    ) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumLineBytes else {
            throw CodexAppServerError.protocolViolation(
                .oversizedMessage
            )
        }
        return data
    }
}

enum CodexProtocolBoundary {
    static let maximumDeltaUTF8Bytes = 64 * 1_024
    static let maximumItemTextUTF8Bytes = 256 * 1_024

    static func event(
        method: String,
        params: CodexJSONValue,
        knownThreadIDs: Set<String>,
        activeTurnToThread: [String: String],
        pendingTurnStartThreads: Set<String> = [],
        notifiedTurnByPendingThread: [String: String] = [:],
        expectedTurnStartedToThread: [String: String] = [:],
        contextToolEnabled: Bool
    ) throws -> CodexAppServerEvent? {
        switch method {
        case "account/login/completed":
            let object = try requireObject(params)
            let loginID = object["loginId"]?.stringValue
            if let loginID {
                try requireOpaqueIdentifier(loginID)
            }
            guard let success = object["success"]?.boolValue else {
                throw violation(.malformedEnvelope)
            }
            return .loginCompleted(
                loginID: loginID,
                success: success
            )
        case "account/updated":
            let object = try requireObject(params)
            let plan = planType(object["planType"]?.stringValue)
            if object["authMode"] == nil,
               object["planType"] == nil
            {
                return .accountChanged(
                    .signedOut(requiresOpenAIAuthentication: true)
                )
            }
            return .accountChanged(.connected(plan: plan))
        case "account/rateLimits/updated":
            let object = try requireObject(params)
            guard let rateLimits = object["rateLimits"] else {
                throw violation(.malformedEnvelope)
            }
            return .quotaChanged(try quotaState(rateLimits))
        case "item/agentMessage/delta":
            let object = try requireObject(params)
            let identifiers = try requireThreadTurn(
                object,
                knownThreadIDs: knownThreadIDs,
                activeTurnToThread: activeTurnToThread
            )
            guard let itemID = object["itemId"]?.stringValue,
                  let delta = object["delta"]?.stringValue,
                  delta.utf8.count <= maximumDeltaUTF8Bytes
            else {
                throw violation(.outputLimitExceeded)
            }
            try requireOpaqueIdentifier(itemID)
            return .agentMessageDelta(
                threadID: identifiers.threadID,
                turnID: identifiers.turnID,
                itemID: itemID,
                delta: delta
            )
        case "item/started", "item/completed":
            let object = try requireObject(params)
            _ = try requireThreadTurn(
                object,
                knownThreadIDs: knownThreadIDs,
                activeTurnToThread: activeTurnToThread
            )
            guard let item = object["item"] else {
                throw violation(.malformedEnvelope)
            }
            try validateThreadItem(
                item,
                contextToolEnabled: contextToolEnabled
            )
            return nil
        case "item/plan/delta",
             "item/reasoning/summaryPartAdded",
             "item/reasoning/summaryTextDelta",
             "item/reasoning/textDelta":
            let object = try requireObject(params)
            _ = try requireThreadTurn(
                object,
                knownThreadIDs: knownThreadIDs,
                activeTurnToThread: activeTurnToThread
            )
            guard let delta = object["delta"]?.stringValue,
                  delta.utf8.count <= maximumDeltaUTF8Bytes
            else {
                throw violation(.outputLimitExceeded)
            }
            return nil
        case "turn/started":
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID),
                  let turn = object["turn"]?.objectValue,
                  let turnID = turn["id"]?.stringValue
            else {
                throw violation(.crossSessionIdentifier)
            }
            let matchesPendingRequest =
                pendingTurnStartThreads.contains(threadID)
                && notifiedTurnByPendingThread[threadID] == nil
                && activeTurnToThread[turnID] == nil
                && !activeTurnToThread.values.contains(threadID)
            let matchesValidatedResponse =
                expectedTurnStartedToThread[turnID] == threadID
                && activeTurnToThread[turnID] == threadID
            guard matchesPendingRequest
                    || matchesValidatedResponse
            else {
                throw violation(.crossSessionIdentifier)
            }
            try validateTurn(
                turn,
                contextToolEnabled: contextToolEnabled
            )
            return .turnStarted(
                CodexTurnHandle(
                    threadID: threadID,
                    turnID: turnID
                )
            )
        case "turn/completed":
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID),
                  let turn = object["turn"]?.objectValue,
                  let turnID = turn["id"]?.stringValue,
                  activeTurnToThread[turnID] == threadID,
                  let statusValue = turn["status"]?.stringValue,
                  let status = CodexTurnCompletionStatus(
                      rawValue: statusValue
                  )
            else {
                throw violation(.crossSessionIdentifier)
            }
            try validateTurn(
                turn,
                contextToolEnabled: contextToolEnabled
            )
            return .turnCompleted(
                CodexTurnHandle(
                    threadID: threadID,
                    turnID: turnID
                ),
                status: status
            )
        case "thread/status/changed":
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID),
                  let status = object["status"]?.objectValue,
                  let type = status["type"]?.stringValue
            else {
                throw violation(.crossSessionIdentifier)
            }
            let state: CodexThreadState
            switch type {
            case "idle":
                state = .idle
            case "active":
                guard status["activeFlags"]?.arrayValue?.isEmpty == true
                else {
                    throw violation(.forbiddenServerRequest)
                }
                state = .active
            case "systemError":
                state = .systemError
            case "notLoaded":
                return nil
            default:
                throw violation(.malformedEnvelope)
            }
            return .threadStateChanged(
                threadID: threadID,
                state: state
            )
        case "thread/compacted", "thread/tokenUsage/updated":
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID)
            else {
                throw violation(.crossSessionIdentifier)
            }
            return nil
        case "thread/closed", "thread/deleted":
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID)
            else {
                throw violation(.crossSessionIdentifier)
            }
            return .threadStateChanged(
                threadID: threadID,
                state: method == "thread/closed" ? .closed : .deleted
            )
        case "turn/plan/updated":
            let object = try requireObject(params)
            _ = try requireThreadTurn(
                object,
                knownThreadIDs: knownThreadIDs,
                activeTurnToThread: activeTurnToThread
            )
            guard let plan = object["plan"]?.arrayValue,
                  plan.count <= 64
            else {
                throw violation(.outputLimitExceeded)
            }
            return nil
        case "error":
            let object = try requireObject(params)
            let threadID = object["threadId"]?.stringValue
            let turnID = object["turnId"]?.stringValue
            guard let threadID,
                  let turnID,
                  knownThreadIDs.contains(threadID),
                  activeTurnToThread[turnID] == threadID,
                  let willRetry = object["willRetry"]?.boolValue,
                  let error = object["error"]
            else {
                throw violation(.crossSessionIdentifier)
            }
            return .safeFailure(
                threadID: threadID,
                turnID: turnID,
                category: safeFailure(from: error),
                willRetry: willRetry
            )
        case "warning", "deprecationNotice":
            let object = try requireObject(params)
            let key = method == "warning" ? "message" : "summary"
            guard let summary = object[key]?.stringValue,
                  summary.utf8.count <= 4_096
            else {
                throw violation(.malformedEnvelope)
            }
            if let threadID = object["threadId"]?.stringValue,
               !knownThreadIDs.contains(threadID)
            {
                throw violation(.crossSessionIdentifier)
            }
            return .warning
        case "remoteControl/status/changed":
            let object = try requireObject(params)
            guard object["status"]?.stringValue == "disabled" else {
                throw violation(.forbiddenServerRequest)
            }
            return nil
        case "serverRequest/resolved":
            guard contextToolEnabled else {
                throw violation(.forbiddenServerRequest)
            }
            let object = try requireObject(params)
            guard let threadID = object["threadId"]?.stringValue,
                  knownThreadIDs.contains(threadID),
                  object["requestId"] != nil
            else {
                throw violation(.crossSessionIdentifier)
            }
            return nil
        default:
            throw violation(.unknownNotification)
        }
    }

    static func validateThreadItem(
        _ value: CodexJSONValue,
        contextToolEnabled: Bool
    ) throws {
        let object = try requireObject(value)
        guard let type = object["type"]?.stringValue,
              let itemID = object["id"]?.stringValue
        else {
            throw violation(.malformedEnvelope)
        }
        try requireOpaqueIdentifier(itemID)
        switch type {
        case "userMessage":
            guard let content = object["content"]?.arrayValue,
                  !content.isEmpty
            else {
                throw violation(.malformedEnvelope)
            }
            var total = 0
            for value in content {
                let input = try requireObject(value)
                guard input["type"]?.stringValue == "text",
                      let text = input["text"]?.stringValue
                else {
                    throw violation(.forbiddenItem)
                }
                total += text.utf8.count
                guard total <= maximumItemTextUTF8Bytes else {
                    throw violation(.outputLimitExceeded)
                }
            }
        case "agentMessage":
            guard let text = object["text"]?.stringValue,
                  text.utf8.count <= maximumItemTextUTF8Bytes,
                  object["memoryCitation"] == nil
                      || object["memoryCitation"] == .null
            else {
                throw violation(.forbiddenItem)
            }
        case "plan":
            guard let text = object["text"]?.stringValue,
                  text.utf8.count <= maximumItemTextUTF8Bytes
            else {
                throw violation(.outputLimitExceeded)
            }
        case "reasoning":
            for key in ["content", "summary"] {
                let parts = object[key]?.arrayValue ?? []
                guard parts.count <= 64,
                      parts.allSatisfy({
                          ($0.stringValue?.utf8.count ?? Int.max)
                              <= maximumDeltaUTF8Bytes
                      })
                else {
                    throw violation(.outputLimitExceeded)
                }
            }
        case "contextCompaction":
            break
        case "dynamicToolCall":
            guard contextToolEnabled,
                  object["tool"]?.stringValue
                      == CodexCurrentMeetingSearchTool.name
            else {
                throw violation(.forbiddenItem)
            }
        default:
            throw violation(.forbiddenItem)
        }
    }

    static func validateTurn(
        _ object: [String: CodexJSONValue],
        contextToolEnabled: Bool
    ) throws {
        guard let turnID = object["id"]?.stringValue,
              let status = object["status"]?.stringValue,
              [
                  "completed",
                  "interrupted",
                  "failed",
                  "inProgress"
              ].contains(status),
              let items = object["items"]?.arrayValue,
              items.count <= 256
        else {
            throw violation(.malformedEnvelope)
        }
        try requireOpaqueIdentifier(turnID)
        for item in items {
            try validateThreadItem(
                item,
                contextToolEnabled: contextToolEnabled
            )
        }
    }

    static func quotaState(
        _ value: CodexJSONValue
    ) throws -> CodexQuotaState {
        let object = try requireObject(value)
        let credits = object["credits"]?.objectValue
        return CodexQuotaState(
            plan: planType(object["planType"]?.stringValue),
            primary: try quotaWindow(object["primary"]),
            secondary: try quotaWindow(object["secondary"]),
            hasCredits: credits?["hasCredits"]?.boolValue,
            creditsUnlimited: credits?["unlimited"]?.boolValue,
            spendControlReached:
                object["spendControlReached"]?.boolValue,
            isUnavailable:
                object["rateLimitReachedType"]?.stringValue != nil
                    || object["spendControlReached"]?.boolValue == true
        )
    }

    static func planType(_ value: String?) -> CodexPlanType {
        switch value {
        case "free": .free
        case "go": .go
        case "plus": .plus
        case "pro": .pro
        case "prolite": .prolite
        case "team": .team
        case "self_serve_business_usage_based", "business": .business
        case "enterprise_cbp_usage_based", "enterprise": .enterprise
        case "edu": .education
        default: .unknown
        }
    }

    static func safeFailure(
        from value: CodexJSONValue
    ) -> CodexSafeFailureCategory {
        guard let error = value.objectValue,
              let info = error["codexErrorInfo"]
        else {
            return .unavailable
        }
        if let code = info.stringValue {
            switch code {
            case "unauthorized":
                return .authenticationRequired
            case "usageLimitExceeded", "sessionBudgetExceeded":
                return .quotaUnavailable
            case "contextWindowExceeded":
                return .contextWindowExceeded
            default:
                return .unavailable
            }
        }
        guard let object = info.objectValue else {
            return .unavailable
        }
        if object["httpConnectionFailed"] != nil
            || object["responseStreamConnectionFailed"] != nil
            || object["responseStreamDisconnected"] != nil
            || object["responseTooManyFailedAttempts"] != nil
        {
            return .networkUnavailable
        }
        return .unavailable
    }

    static func requireObject(
        _ value: CodexJSONValue
    ) throws -> [String: CodexJSONValue] {
        guard let object = value.objectValue else {
            throw violation(.malformedEnvelope)
        }
        return object
    }

    static func requireOpaqueIdentifier(_ value: String) throws {
        guard isBoundedIdentifier(value) else {
            throw violation(.malformedEnvelope)
        }
    }

    private static func requireThreadTurn(
        _ object: [String: CodexJSONValue],
        knownThreadIDs: Set<String>,
        activeTurnToThread: [String: String]
    ) throws -> (threadID: String, turnID: String) {
        guard let threadID = object["threadId"]?.stringValue,
              let turnID = object["turnId"]?.stringValue,
              knownThreadIDs.contains(threadID),
              activeTurnToThread[turnID] == threadID
        else {
            throw violation(.crossSessionIdentifier)
        }
        return (threadID, turnID)
    }

    private static func quotaWindow(
        _ value: CodexJSONValue?
    ) throws -> CodexQuotaWindow? {
        guard let value, value != .null else { return nil }
        let object = try requireObject(value)
        guard let usedPercent64 = object["usedPercent"]?.int64Value,
              (0...100).contains(usedPercent64)
        else {
            throw violation(.malformedEnvelope)
        }
        return CodexQuotaWindow(
            usedPercent: Int(usedPercent64),
            resetsAtUnixSeconds:
                object["resetsAt"]?.int64Value,
            durationMinutes:
                object["windowDurationMins"]?.int64Value
        )
    }

    private static func violation(
        _ value: CodexProtocolViolation
    ) -> CodexAppServerError {
        .protocolViolation(value)
    }
}

func isBoundedIdentifier(_ value: String) -> Bool {
    !value.isEmpty
        && value.utf8.count <= 256
        && value == value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        && !value.unicodeScalars.contains(
            where: CharacterSet.controlCharacters.contains
        )
}
