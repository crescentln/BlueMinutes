import Foundation
import MeetingBuddyApplication
import MeetingBuddyAutomation
import MeetingBuddyDomain
@testable import MeetingBuddyPersistence
import Testing

@Suite(.serialized)
struct AutomationMCPAdapterTests {
    @Test
    func lifecycleNegotiatesToolsOnlyAndListsExactlySevenReadTools() async throws {
        let executor = RecordingMCPExecutor()
        let adapter = AutomationMCPAdapter(
            executor: executor,
            clock: { Self.timestamp }
        )

        let ping = try mcpObject(
            await adapter.receive(try mcpRequest(id: 1, method: "ping"))
        )
        #expect(try rpcErrorCode(ping) == nil)

        let beforeInitialize = try mcpObject(
            await adapter.receive(try mcpRequest(id: 2, method: "tools/list"))
        )
        #expect(try rpcErrorCode(beforeInitialize) == -32_002)

        let initialized = try await initialize(adapter, id: 3)
        let result = try #require(initialized["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == AutomationMCPProtocol.version)
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        #expect(Set(capabilities.keys) == ["tools"])
        let toolsCapability = try #require(capabilities["tools"] as? [String: Any])
        #expect(toolsCapability["listChanged"] as? Bool == false)

        let toolsResponse = try mcpObject(
            await adapter.receive(try mcpRequest(id: 4, method: "tools/list"))
        )
        let toolsResult = try #require(toolsResponse["result"] as? [String: Any])
        let tools = try #require(toolsResult["tools"] as? [[String: Any]])
        let names = try tools.map { try #require($0["name"] as? String) }
        #expect(
            names == AutomationMCPAdapter.exposedCommands.map(\.rawValue)
        )
        #expect(AutomationMCPAdapter.exposedCommands.allSatisfy {
            AutomationCommandCatalog().descriptor(for: $0).permission == .read
        })
        #expect(
            names == [
                "describe_settings",
                "get_command_catalog",
                "get_meeting_policy_status",
                "get_settings",
                "get_storage_report",
                "get_workspace_status",
                "list_activity"
            ]
        )
        #expect(tools.allSatisfy { tool in
            guard let schema = tool["inputSchema"] as? [String: Any],
                  let execution = tool["execution"] as? [String: Any]
            else { return false }
            return schema["additionalProperties"] as? Bool == false
                && execution["taskSupport"] as? String == "forbidden"
                && tool["annotations"] == nil
        })
        #expect(await executor.executionCount == 0)
    }

    @Test
    func toolCallsRejectAuthorityInjectionAndReturnCanonicalStructuredOutput() async throws {
        let executor = RecordingMCPExecutor()
        let fixedUUID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let adapter = AutomationMCPAdapter(
            executor: executor,
            clock: { Self.timestamp },
            makeUUID: { fixedUUID }
        )
        _ = try await initialize(adapter, id: 1)

        let forgedEnvelope = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 2,
                    method: "tools/call",
                    params: ["name": "get_settings", "arguments": [:]],
                    extra: ["authority": "sensitive"]
                )
            )
        )
        #expect(try rpcErrorCode(forgedEnvelope) == -32_600)
        #expect(forgedEnvelope["id"] as? Int == 2)

        let hiddenMutation = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 3,
                    method: "tools/call",
                    params: ["name": "update_settings", "arguments": [:]]
                )
            )
        )
        #expect(try rpcErrorCode(hiddenMutation) == -32_602)

        let forgedArguments = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 4,
                    method: "tools/call",
                    params: [
                        "name": "get_settings",
                        "arguments": ["permission": "sensitive"]
                    ]
                )
            )
        )
        #expect(try rpcErrorCode(forgedArguments) == -32_602)
        #expect(await executor.executionCount == 0)

        let success = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 5,
                    method: "tools/call",
                    params: ["name": "get_settings", "arguments": [:]]
                )
            )
        )
        let result = try #require(success["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let structuredBytes = try JSONSerialization.data(
            withJSONObject: structured,
            options: [.sortedKeys]
        )
        let execution = try JSONDecoder().decode(
            AutomationCommandExecution.self,
            from: structuredBytes
        )
        #expect(execution.commandName == .getSettings)
        guard case let .settings(settings) = execution.result else {
            Issue.record("The MCP result did not preserve its typed settings payload.")
            return
        }
        #expect(settings == .compiledDefault)

        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let canonical = try CanonicalJSON.encode(execution)
        #expect(text == String(data: canonical, encoding: .utf8))

        let requests = await executor.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.command == .getSettings)
        #expect(requests.first?.commandID.canonicalString == fixedUUID.uuidString.lowercased())
        #expect(requests.first?.replayNonce.canonicalString == fixedUUID.uuidString.lowercased())
    }

    @Test
    func boundedInputRateLimitAndFailuresDegradeSafely() async throws {
        let malformedAdapter = AutomationMCPAdapter(executor: RecordingMCPExecutor())
        let malformed = try mcpObject(
            await malformedAdapter.receive(Data("{not-json".utf8))
        )
        #expect(try rpcErrorCode(malformed) == -32_700)
        #expect(malformed["id"] is NSNull)
        let oversized = try mcpObject(
            await malformedAdapter.receive(
                Data(
                    repeating: 0x20,
                    count: AutomationMCPProtocol.maximumMessageBytes + 1
                )
            )
        )
        #expect(try rpcErrorCode(oversized) == -32_700)
        #expect(oversized["id"] is NSNull)

        let executor = RecordingMCPExecutor()
        let rateLimited = AutomationMCPAdapter(
            executor: executor,
            maximumToolCallsPerMinute: 1,
            clock: { Self.timestamp }
        )
        _ = try await initialize(rateLimited, id: 1)
        let first = try mcpObject(
            await rateLimited.receive(
                try mcpRequest(
                    id: 2,
                    method: "tools/call",
                    params: ["name": "get_settings", "arguments": [:]]
                )
            )
        )
        #expect(try toolErrorCode(first) == nil)
        let second = try mcpObject(
            await rateLimited.receive(
                try mcpRequest(
                    id: 3,
                    method: "tools/call",
                    params: ["name": "list_activity", "arguments": [:]]
                )
            )
        )
        #expect(try toolErrorCode(second) == "rate_limit_exceeded")
        #expect(await executor.executionCount == 1)

        let failureAdapter = AutomationMCPAdapter(
            executor: FailingMCPExecutor(),
            clock: { Self.timestamp }
        )
        _ = try await initialize(failureAdapter, id: 4)
        let failureData = try #require(
            await failureAdapter.receive(
                try mcpRequest(
                    id: 5,
                    method: "tools/call",
                    params: ["name": "get_settings", "arguments": [:]]
                )
            )
        )
        let failure = try mcpObject(failureData)
        #expect(try toolErrorCode(failure) == "internal_failure")
        let rendered = String(decoding: failureData, as: UTF8.self)
        #expect(!rendered.contains("secret-token"))
        #expect(!rendered.contains("/private/meeting"))
    }

    @Test
    func localMCPUsesReadAuthorityAndPersistsTruthfulAuditOrigin() async throws {
        let fixture = try TestAutomationFixture()
        defer { fixture.remove() }
        let actorID = try AutomationActorID("local_mcp")
        let caller = try AutomationCallerContext(
            workspaceID: fixture.workspace.manifest.workspaceID,
            actorID: actorID,
            origin: .mcp,
            maximumPermission: .read,
            adapterVersion: AutomationMCPProtocol.adapterVersion,
            ancestorBoundaries: [.externalAgent]
        )
        let service = AutomationCommandService(
            repository: fixture.repository,
            temporaryStorage: LocalTaskTemporaryStorage(workspace: fixture.workspace),
            caller: caller,
            clock: { Self.timestamp }
        )
        let adapter = AutomationMCPAdapter(
            executor: service,
            clock: { Self.timestamp }
        )
        _ = try await initialize(adapter, id: 1)

        let success = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 2,
                    method: "tools/call",
                    params: ["name": "get_settings", "arguments": [:]]
                )
            )
        )
        let unexpectedCode = try toolErrorCode(success)
        #expect(unexpectedCode == nil, "Unexpected MCP error: \(String(describing: unexpectedCode))")

        let deniedBeforeExecution = try mcpObject(
            await adapter.receive(
                try mcpRequest(
                    id: 3,
                    method: "tools/call",
                    params: ["name": "run_workspace_diagnostics", "arguments": [:]]
                )
            )
        )
        #expect(try rpcErrorCode(deniedBeforeExecution) == -32_602)

        let trails = try fixture.repository.automationActivity(
            limit: 10,
            excludingCommandID: nil
        )
        #expect(trails.count == 1)
        let trail = try #require(trails.first)
        #expect(trail.record.commandName == .getSettings)
        #expect(trail.record.origin == .mcp)
        #expect(trail.record.actorID == actorID)
        #expect(trail.record.adapterVersion == AutomationMCPProtocol.adapterVersion)
        #expect(trail.record.grantedPermission == .read)
        #expect(trail.record.requiredPermission == .read)
        #expect(trail.record.decision == .authorized)
        #expect(trail.resultEvents.map(\.outcome) == [.completed])
        #expect(try fixture.repository.currentAutomationSettings() == .compiledDefault)
    }

    @Test
    func stdioFramingIsIncrementalAndBounded() throws {
        var framer = AutomationMCPLineFramer(maximumMessageBytes: 5)
        #expect(try framer.append(Data("{}\n{".utf8)) == [Data("{}".utf8)])
        #expect(try framer.append(Data("}\n".utf8)) == [Data("{}".utf8)])
        try framer.validateEndOfFile()

        var oversized = AutomationMCPLineFramer(maximumMessageBytes: 5)
        do {
            _ = try oversized.append(Data("123456".utf8))
            Issue.record("An oversized stdio message was accepted.")
        } catch let error as AutomationMCPTransportFailure {
            #expect(error == .messageTooLarge)
        }

        var incomplete = AutomationMCPLineFramer(maximumMessageBytes: 5)
        _ = try incomplete.append(Data("{}".utf8))
        do {
            try incomplete.validateEndOfFile()
            Issue.record("An unterminated stdio message was accepted at EOF.")
        } catch let error as AutomationMCPTransportFailure {
            #expect(error == .incompleteMessageAtEndOfFile)
        }
    }

    private static let timestamp = try! UTCInstant(
        millisecondsSinceUnixEpoch: 1_800_000_000_000
    )
}

private actor RecordingMCPExecutor: AutomationCommandExecuting {
    private var requests: [AutomationCommandRequest] = []

    var executionCount: Int { requests.count }

    func snapshot() -> [AutomationCommandRequest] { requests }

    func execute(_ request: AutomationCommandRequest) async throws -> AutomationCommandExecution {
        requests.append(request)
        return AutomationCommandExecution(
            commandID: request.commandID,
            commandName: request.command.name,
            result: .settings(.compiledDefault)
        )
    }
}

private struct FailingMCPExecutor: AutomationCommandExecuting {
    func execute(_ request: AutomationCommandRequest) async throws -> AutomationCommandExecution {
        throw NSError(
            domain: "secret-token-at-/private/meeting",
            code: 7
        )
    }
}

private func initialize(
    _ adapter: AutomationMCPAdapter,
    id: Int
) async throws -> [String: Any] {
    let response = try mcpObject(
        await adapter.receive(
            try mcpRequest(
                id: id,
                method: "initialize",
                params: [
                    "protocolVersion": "2099-01-01",
                    "capabilities": ["sampling": [:]],
                    "clientInfo": [
                        "name": "untrusted-test-client",
                        "version": "1.0"
                    ]
                ]
            )
        )
    )
    #expect(try rpcErrorCode(response) == nil)

    let beforeNotification = try mcpObject(
        await adapter.receive(try mcpRequest(id: id + 10_000, method: "tools/list"))
    )
    #expect(try rpcErrorCode(beforeNotification) == -32_002)

    let notification = try mcpNotification(
        method: "notifications/initialized",
        params: [:]
    )
    #expect(await adapter.receive(notification) == nil)
    return response
}

private func mcpRequest(
    id: Int,
    method: String,
    params: [String: Any]? = nil,
    extra: [String: Any] = [:]
) throws -> Data {
    var value: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id,
        "method": method
    ]
    if let params { value["params"] = params }
    for (key, item) in extra { value[key] = item }
    return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func mcpNotification(
    method: String,
    params: [String: Any]? = nil
) throws -> Data {
    var value: [String: Any] = ["jsonrpc": "2.0", "method": method]
    if let params { value["params"] = params }
    return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func mcpObject(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    return try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
}

private func rpcErrorCode(_ response: [String: Any]) throws -> Int? {
    guard let error = response["error"] as? [String: Any] else { return nil }
    return try #require(error["code"] as? NSNumber).intValue
}

private func toolErrorCode(_ response: [String: Any]) throws -> String? {
    guard let result = response["result"] as? [String: Any],
          result["isError"] as? Bool == true,
          let structured = result["structuredContent"] as? [String: Any],
          let error = structured["error"] as? [String: Any]
    else { return nil }
    return error["code"] as? String
}
