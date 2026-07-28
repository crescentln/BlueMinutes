import Foundation
@testable import MeetingBuddyAI
@testable import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite(.serialized)
struct CodexAppServerTransportTests {
    @Test
    func typedTransportCompletesAccountThreadStreamInterruptAndReadOnlyTool()
        async throws
    {
        let fixture = try await transportFixture(behavior: .normal)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transport = fixture.transport
        try await transport.start()

        #expect(
            try await transport.account()
                == .signedOut(requiresOpenAIAuthentication: true)
        )
        let browser = try await transport.startBrowserLogin()
        #expect(browser.kind == .browser)
        #expect(browser.verificationURL.host == "auth.openai.com")
        let device = try await transport.startDeviceCodeLogin()
        #expect(device.kind == .deviceCode)
        #expect(device.userCode == "ABCD-EFGH")
        try await transport.cancelLogin(loginID: device.loginID)
        try await transport.logout()

        let quota = try await transport.quota()
        #expect(quota.plan == .pro)
        #expect(quota.primary?.usedPercent == 25)
        #expect(quota.secondary?.usedPercent == 40)
        #expect(quota.hasCredits == true)
        #expect(!quota.isUnavailable)

        let session = try await transport.startMeetingThread(
            context: fixture.turnRequest.context
        )
        #expect(session.handle.threadID == ScriptedCodexServer.threadID)
        #expect(session.handle.modelProvider == "openai")
        let turn = try await transport.startTurn(
            in: session,
            request: fixture.turnRequest
        )
        #expect(turn.turnID == ScriptedCodexServer.turnID)

        var iterator = transport.events.makeAsyncIterator()
        fixture.probe.emit(
            .object([
                "method": .string(
                    "thread/status/changed"
                ),
                "params": .object([
                    "threadId": .string(
                        turn.threadID
                    ),
                    "status": .object([
                        "type": .string("active"),
                        "activeFlags": .array([])
                    ])
                ])
            ])
        )
        fixture.probe.emit(
            .object([
                "method": .string(
                    "turn/started"
                ),
                "params": .object([
                    "threadId": .string(
                        turn.threadID
                    ),
                    "turn":
                        ScriptedCodexServer
                        .turn(
                            status:
                                "inProgress"
                        )
                ])
            ])
        )
        fixture.probe.emit(
            .object([
                "method": .string("item/agentMessage/delta"),
                "params": .object([
                    "threadId": .string(turn.threadID),
                    "turnId": .string(turn.turnID),
                    "itemId": .string("agent-message-1"),
                    "delta": .string("Synthetic reply")
                ])
            ])
        )
        fixture.probe.emit(
            .object([
                "id": .integer(900),
                "method": .string("item/tool/call"),
                "params": .object([
                    "arguments": .object([
                        "query": .string("synthetic"),
                        "limit": .integer(5)
                    ]),
                    "callId": .string("tool-call-1"),
                    "threadId": .string(turn.threadID),
                    "tool": .string(
                        CodexCurrentMeetingSearchTool.name
                    ),
                    "turnId": .string(turn.turnID)
                ])
            ])
        )
        let toolResponse = try await fixture.probe.waitForResponse(
            id: 900
        )
        let result = try #require(
            toolResponse.objectValue?["result"]?.objectValue
        )
        #expect(result["success"]?.boolValue == true)
        let content = try #require(
            result["contentItems"]?.arrayValue?.first?
                .objectValue?["text"]?.stringValue
        )
        #expect(content.contains("synthetic segment"))
        #expect(content.contains("\"start_milliseconds\":500"))
        #expect(!content.contains("/Users/"))
        #expect(!content.contains("\"path\""))
        #expect(!content.contains("canonical_audio"))

        fixture.probe.emit(
            .object([
                "method": .string("turn/completed"),
                "params": .object([
                    "threadId": .string(turn.threadID),
                    "turn": ScriptedCodexServer.turn(
                        status: "completed"
                    )
                ])
            ])
        )

        #expect(
            await iterator.next()
                == .threadStateChanged(
                    threadID: turn.threadID,
                    state: .active
                )
        )
        #expect(
            await iterator.next()
                == .turnStarted(turn)
        )
        #expect(
            await iterator.next()
                == .agentMessageDelta(
                    threadID: turn.threadID,
                    turnID: turn.turnID,
                    itemID: "agent-message-1",
                    delta: "Synthetic reply"
                )
        )
        #expect(
            await iterator.next()
                == .turnCompleted(turn, status: .completed)
        )

        _ = try await transport.readMeetingThread(session)
        let resumed = try await transport.resumeMeetingThread(
            session,
            context: fixture.turnRequest.context
        )
        #expect(resumed.handle.threadID == session.handle.threadID)

        let secondTurn = try await transport.startTurn(
            in: resumed,
            request: fixture.turnRequest
        )
        try await transport.interrupt(secondTurn)
        try await transport.deleteMeetingThread(resumed)

        let sent = fixture.probe.sentMessages()
        let initialize = try #require(
            sent.first(where: {
                $0.objectValue?["method"]?.stringValue
                    == "initialize"
            })?.objectValue
        )
        #expect(
            initialize["params"]?.objectValue?["capabilities"]?
                .objectValue?["experimentalApi"]?.boolValue == true
        )
        #expect(
            initialize["params"]?.objectValue?["clientInfo"]?
                .objectValue?["name"]?.stringValue == "BlueMinutes"
        )
        #expect(
            initialize["params"]?.objectValue?["clientInfo"]?
                .objectValue?["title"]?.stringValue == "BlueMinutes"
        )
        #expect(
            initialize["params"]?.objectValue?["clientInfo"]?
                .objectValue?["version"]?.stringValue == "0.4.0"
        )
        let threadStart = try #require(
            sent.first(where: {
                $0.objectValue?["method"]?.stringValue
                    == "thread/start"
            })?.objectValue?["params"]?.objectValue
        )
        #expect(
            threadStart["approvalPolicy"]?.stringValue == "never"
        )
        #expect(threadStart["sandbox"]?.stringValue == "read-only")
        #expect(
            threadStart["dynamicTools"]?.arrayValue?.count == 1
        )
        let turnStart = try #require(
            sent.first(where: {
                $0.objectValue?["method"]?.stringValue
                    == "turn/start"
            })?.objectValue?["params"]?.objectValue
        )
        let input = try #require(
            turnStart["input"]?.arrayValue?.first?.objectValue
        )
        #expect(input["type"]?.stringValue == "text")
        #expect(input["path"] == nil)
        #expect(input["url"] == nil)
        #expect(input["audio"] == nil)

        await transport.shutdown()
    }

    @Test
    func forbiddenCommandAndPermissionEventsTerminateTheTransport()
        async throws
    {
        for behavior in [
            ScriptedCodexServer.Behavior.forbiddenCommandOnAccountRead,
            .permissionRequestOnAccountRead,
            .malformedAccountRead
        ] {
            let fixture = try await transportFixture(
                behavior: behavior
            )
            defer {
                try? FileManager.default.removeItem(at: fixture.root)
            }
            try await fixture.transport.start()
            await #expect(
                throws: CodexAppServerError.self
            ) {
                _ = try await fixture.transport.account()
            }
            await #expect(throws: CodexAppServerError.notStarted) {
                _ = try await fixture.transport.account()
            }
            await fixture.transport.shutdown()
        }
    }

    @Test
    func notificationsRejectTurnThreadMismatchesAcrossConcurrentSessions()
        throws
    {
        let threadA = "thread-a"
        let threadB = "thread-b"
        let turnA = "turn-a"
        let knownThreads: Set<String> = [threadA, threadB]
        let activeTurns = [turnA: threadA]

        #expect(
            throws: CodexAppServerError.protocolViolation(
                .crossSessionIdentifier
            )
        ) {
            _ = try CodexProtocolBoundary.event(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string(threadB),
                    "turnId": .string(turnA),
                    "itemId": .string("item-a"),
                    "delta": .string("cross-session")
                ]),
                knownThreadIDs: knownThreads,
                activeTurnToThread: activeTurns,
                contextToolEnabled: true
            )
        }
        #expect(
            throws: CodexAppServerError.protocolViolation(
                .crossSessionIdentifier
            )
        ) {
            _ = try CodexProtocolBoundary.event(
                method: "turn/completed",
                params: .object([
                    "threadId": .string(threadB),
                    "turn": .object([
                        "id": .string(turnA),
                        "status": .string("completed"),
                        "items": .array([])
                    ])
                ]),
                knownThreadIDs: knownThreads,
                activeTurnToThread: activeTurns,
                contextToolEnabled: true
            )
        }
        #expect(
            throws: CodexAppServerError.protocolViolation(
                .crossSessionIdentifier
            )
        ) {
            _ = try CodexProtocolBoundary.event(
                method: "error",
                params: .object([
                    "threadId": .string(threadB),
                    "turnId": .string(turnA),
                    "willRetry": .bool(false),
                    "error": .object([
                        "codexErrorInfo": .string("unavailable")
                    ])
                ]),
                knownThreadIDs: knownThreads,
                activeTurnToThread: activeTurns,
                contextToolEnabled: true
            )
        }
    }

    @Test
    func turnStartedRequiresOnePendingOrResponseValidatedPair()
        throws
    {
        let threadID = "thread-a"
        let turnID = "turn-a"
        let params = CodexJSONValue.object([
            "threadId": .string(threadID),
            "turn": .object([
                "id": .string(turnID),
                "status": .string(
                    "inProgress"
                ),
                "items": .array([])
            ])
        ])

        #expect(
            throws:
                CodexAppServerError
                .protocolViolation(
                    .crossSessionIdentifier
                )
        ) {
            _ = try CodexProtocolBoundary
                .event(
                    method: "turn/started",
                    params: params,
                    knownThreadIDs: [
                        threadID
                    ],
                    activeTurnToThread: [:],
                    contextToolEnabled: true
                )
        }
        #expect(
            try CodexProtocolBoundary
                .event(
                    method: "turn/started",
                    params: params,
                    knownThreadIDs: [
                        threadID
                    ],
                    activeTurnToThread: [
                        turnID: threadID
                    ],
                    expectedTurnStartedToThread: [
                        turnID: threadID
                    ],
                    contextToolEnabled: true
                )
                == .turnStarted(
                    CodexTurnHandle(
                        threadID: threadID,
                        turnID: turnID
                    )
                )
        )
    }

    @Test
    func notificationAndTurnStartResponseMustUseTheSameTurnID()
        async throws
    {
        let fixture = try await
            transportFixture(
                behavior:
                    .mismatchedTurnStartNotification
            )
        defer {
            try? FileManager.default
                .removeItem(at: fixture.root)
        }
        try await fixture.transport.start()
        let session = try await fixture
            .transport.startMeetingThread(
                context:
                    fixture.turnRequest
                    .context
            )

        await #expect(
            throws: CodexAppServerError.self
        ) {
            _ = try await fixture.transport
                .startTurn(
                    in: session,
                    request:
                        fixture.turnRequest
                )
        }
        await #expect(
            throws:
                CodexAppServerError.notStarted
        ) {
            _ = try await fixture
                .transport.account()
        }
        _ = await fixture.transport.shutdown()
    }

    @Test
    func duplicateTurnStartedNotificationFailsClosed()
        async throws
    {
        let fixture = try await
            transportFixture(
                behavior: .normal
            )
        defer {
            try? FileManager.default
                .removeItem(at: fixture.root)
        }
        try await fixture.transport.start()
        let session = try await fixture
            .transport.startMeetingThread(
                context:
                    fixture.turnRequest
                    .context
            )
        let turn = try await fixture.transport
            .startTurn(
                in: session,
                request:
                    fixture.turnRequest
            )
        let notification =
            CodexJSONValue.object([
                "method":
                    .string("turn/started"),
                "params": .object([
                    "threadId":
                        .string(turn.threadID),
                    "turn":
                        ScriptedCodexServer
                        .turn(
                            status:
                                "inProgress"
                        )
                ])
            ])
        fixture.probe.emit(notification)
        fixture.probe.emit(notification)
        for _ in 0..<200 {
            do {
                _ = try await fixture
                    .transport.account()
            } catch {
                break
            }
            await Task.yield()
        }
        await #expect(
            throws:
                CodexAppServerError.notStarted
        ) {
            _ = try await fixture
                .transport.account()
        }
        _ = await fixture.transport.shutdown()
    }

    @Test
    func shutdownReportsAnUnconfirmedProcessExit()
        async throws
    {
        let fixture = try await
            transportFixture(
                behavior: .normal
            )
        defer {
            try? FileManager.default
                .removeItem(at: fixture.root)
        }
        try await fixture.transport.start()
        fixture.probe.setStopSucceeds(
            false
        )

        #expect(
            await fixture.transport
                .shutdown() == false
        )
        #expect(
            await fixture.transport
                .shutdown() == false
        )
        #expect(
            fixture.probe.stopCallCount()
                == 2
        )
        fixture.probe.setStopSucceeds(
            true
        )
        #expect(
            await fixture.transport
                .shutdown()
        )
        #expect(
            fixture.probe.stopCallCount()
                == 3
        )
    }

    @Test
    func meetingSessionKeysIncludeTheWorkspaceBoundary() throws {
        let request = try codexTurnRequest()
        let original = CodexMeetingSessionKey(
            context: request.context
        )
        let otherWorkspaceContext = CodexMeetingTextContext(
            workspaceID: WorkspaceID(UUID()),
            meetingID: request.context.meetingID,
            meetingRevision:
                request.context.meetingRevision,
            segments: request.context.segments,
            totalUTF8Bytes:
                request.context.totalUTF8Bytes
        )
        let copiedWorkspace = CodexMeetingSessionKey(
            context: otherWorkspaceContext
        )

        #expect(original != copiedWorkspace)
    }

    @Test
    func processLossAndTimeoutAreTypedAndReconnectable() async throws {
        let crashFixture = try await transportFixture(
            behavior: .hangOnAccountRead
        )
        defer {
            try? FileManager.default.removeItem(at: crashFixture.root)
        }
        try await crashFixture.transport.start()
        let accountTask = Task {
            try await crashFixture.transport.account()
        }
        await Task.yield()
        crashFixture.probe.crash()
        await #expect(throws: CodexAppServerError.processExited) {
            _ = try await accountTask.value
        }
        crashFixture.probe.setBehavior(.normal)
        try await crashFixture.transport.reconnect()
        #expect(
            try await crashFixture.transport.account()
                == .signedOut(requiresOpenAIAuthentication: true)
        )
        await crashFixture.transport.shutdown()

        let timeoutFixture = try await transportFixture(
            behavior: .hangOnAccountRead,
            timeout: .milliseconds(50)
        )
        defer {
            try? FileManager.default.removeItem(at: timeoutFixture.root)
        }
        try await timeoutFixture.transport.start()
        await #expect(
            throws:
                CodexAppServerError.requestTimedOut(.accountRead)
        ) {
            _ = try await timeoutFixture.transport.account()
        }
        await timeoutFixture.transport.shutdown()
    }

    @Test
    func disconnectWaitsForAndCancelsAnInFlightRuntimeDiscovery()
        async throws
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "blueminutes-codex-connect-cancel-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        let gate =
            BlockingRuntimeDiscoveryGate()
        defer {
            gate.release()
            try? FileManager.default
                .removeItem(at: root)
        }
        let policy =
            CodexRuntimeCompatibilityPolicy(
                version:
                    "0.146.0-alpha.3.1",
                executableSHA256:
                    "synthetic-digest",
                signingIdentifier:
                    "codex",
                signingTeamIdentifier:
                    "2DC432GLL2"
            )
        let runtime =
            CodexRuntimeManager(
                policy: policy,
                candidates: [
                    CodexRuntimeCandidate(
                        url: URL(
                            fileURLWithPath:
                                "/synthetic/codex"
                        ),
                        source:
                            .verifiedSystemInstallation
                    )
                ],
                verifier:
                    CodexRuntimeVerificationDependencies(
                        isExecutable: {
                            _ in true
                        },
                        hasTrustedSignature: {
                            _,
                            _,
                            _ in true
                        },
                        version: {
                            _ in policy.version
                        },
                        sha256: {
                            _ in
                            gate.waitAndReturn(
                                policy
                                    .executableSHA256
                            )
                        }
                    )
            )
        let transportCreations =
            SynchronousCounter()
        let service =
            CodexMeetingSessionService(
                storageRootURL: root,
                runtimeManager: runtime,
                transportFactory: {
                    configuration in
                    transportCreations
                        .increment()
                    return CodexAppServerTransport(
                        configuration:
                            configuration
                    )
                }
            )
        let connectTask = Task {
            try await service.connect()
        }
        try await gate
            .waitUntilBlocked()
        let disconnectCompletion =
            AsyncCompletionProbe()
        let disconnectTask = Task {
            await service.disconnect()
            await disconnectCompletion
                .finish()
        }
        try await Task.sleep(
            for: .milliseconds(40)
        )
        #expect(
            !(await disconnectCompletion
                .isFinished)
        )

        gate.release()
        await #expect(
            throws: (any Error).self
        ) {
            _ = try await connectTask.value
        }
        await disconnectTask.value

        #expect(
            await service.currentSnapshot()
                .phase == .disconnected
        )
        #expect(
            transportCreations.value == 0
        )
        #expect(
            !FileManager.default
                .fileExists(
                    atPath:
                        root.path
                )
        )
    }

    @Test
    func ephemeralDisconnectPurgesHistoryAndStartsANewThreadAfterReconnect()
        async throws
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "blueminutes-codex-ephemeral-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let policy =
            CodexRuntimeCompatibilityPolicy(
                version:
                    "0.146.0-alpha.3.1",
                executableSHA256:
                    "synthetic-digest",
                signingIdentifier:
                    "codex",
                signingTeamIdentifier:
                    "2DC432GLL2"
            )
        let runtime =
            CodexRuntimeManager(
                policy: policy,
                candidates: [
                    CodexRuntimeCandidate(
                        url: URL(
                            fileURLWithPath:
                                "/synthetic/codex"
                        ),
                        source:
                            .verifiedSystemInstallation
                    )
                ],
                verifier:
                    CodexRuntimeVerificationDependencies(
                        isExecutable: { _ in true },
                        hasTrustedSignature: {
                            _,
                            _,
                            _ in true
                        },
                        version: {
                            _ in policy.version
                        },
                        sha256: {
                            _ in
                            policy
                                .executableSHA256
                        }
                    )
            )
        let probe =
            ScriptedCodexProcessProbe(
                behavior:
                    .connectedAccount
            )
        let transportCreations =
            SynchronousCounter()
        let service =
            CodexMeetingSessionService(
                storageRootURL: root,
                runtimeManager: runtime,
                transportFactory: {
                    configuration in
                    transportCreations
                        .increment()
                    let factory =
                        CodexLineProcessFactory {
                            configuration,
                            onLine,
                            onProtocolFailure,
                            onExit in
                            let process =
                                ScriptedCodexProcess(
                                    configuration:
                                        configuration,
                                    probe: probe,
                                    onLine: onLine,
                                    onProtocolFailure:
                                        onProtocolFailure,
                                    onExit: onExit
                                )
                            probe.install(process)
                            return process
                        }
                    return CodexAppServerTransport(
                        configuration:
                            configuration,
                        requestTimeout:
                            .seconds(2),
                        processFactory:
                            factory
                    )
                }
            )
        let request =
            try codexTurnRequest()

        #expect(
            try await service.connect()
                .phase == .connected
        )
        _ = try await service.send(request)
        await service.disconnect()
        #expect(
            await service.currentSnapshot()
                .phase == .disconnected
        )
        #expect(
            !FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        "home",
                        isDirectory: true
                    ).path
            )
        )

        #expect(
            try await service.connect()
                .phase == .connected
        )
        _ = try await service.send(request)
        let methods = probe.sentMessages()
            .compactMap {
                $0.objectValue?["method"]?
                    .stringValue
            }
        #expect(
            methods.filter {
                $0 == "thread/start"
            }.count == 1
        )
        #expect(
            !methods.contains(
                "thread/resume"
            )
        )
        #expect(
            transportCreations.value == 2
        )
        probe.setStopSucceeds(false)
        await service.disconnect()
        #expect(
            await service.currentSnapshot()
                .phase == .failed
        )
        await #expect(
            throws:
                CodexMeetingSessionServiceError
                .requestFailed(
                    .runtimeExited
                )
        ) {
            _ = try await service.connect()
        }
        #expect(
            transportCreations.value == 2
        )
        probe.setStopSucceeds(true)
        await service.disconnect()
        #expect(
            await service.currentSnapshot()
                .phase == .disconnected
        )
        #expect(
            try await service.connect()
                .phase == .connected
        )
        #expect(
            transportCreations.value == 3
        )
        let home = root.appendingPathComponent(
            "home",
            isDirectory: true
        )
        try FileManager.default
            .removeItem(at: home)
        try Data("cleanup-obstacle".utf8)
            .write(to: home)
        await service.disconnect()
        #expect(
            await service.currentSnapshot()
                .phase == .failed
        )
        #expect(
            FileManager.default.fileExists(
                atPath: home.path
            )
        )
        try FileManager.default
            .removeItem(at: home)
        await service.disconnect()
        #expect(
            await service.currentSnapshot()
                .phase == .disconnected
        )
        #expect(
            !FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        "sessions",
                        isDirectory: true
                    ).path
            )
        )
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment[
                "MEETINGBUDDY_RUN_LIVE_CODEX_APP_SERVER"
            ] == "1",
            "Live official Codex app-server verification is opt-in."
        )
    )
    func installedOfficialAppServerPassesConfinementAndAccountRead()
        async throws
    {
        guard case let .ready(authorization) =
            await CodexRuntimeManager().discover()
        else {
            Issue.record(
                "The installed official Codex runtime did not match the pinned build."
            )
            return
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blueminutes-live-codex-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try CodexRuntimeEnvironmentManager(
            rootURL: root
        )
        let configuration = try await environment.prepare(
            authorization: authorization,
            contextToolEnabled: true
        )
        let transport = CodexAppServerTransport(
            configuration: configuration,
            requestTimeout: .seconds(15)
        )
        do {
            do {
                try await transport.start()
            } catch {
                Issue.record(
                    "The live app-server failed during initialization or configuration validation."
                )
                throw error
            }
            switch try await transport.account() {
            case .signedOut, .connected:
                break
            }
        } catch {
            await transport.shutdown()
            try await environment.removeDisposableDirectories(
                for: configuration
            )
            throw error
        }
        await transport.shutdown()
        try await environment.removeDisposableDirectories(
            for: configuration
        )
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment[
                "MEETINGBUDDY_RUN_LIVE_CODEX_APP_SERVER"
            ] == "1",
            "Live official Codex app-server verification is opt-in."
        )
    )
    func installedOfficialSessionServiceConnectsWithoutMeetingData()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blueminutes-live-codex-service-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CodexMeetingSessionService(
            storageRootURL: root
        )

        let connected = try await service.connect()
        #expect(
            connected.phase == .connected
                || connected.phase == .signedOut
        )
        #expect(
            connected.runtimeVersion
                == CodexRuntimeCompatibilityPolicy.verified.version
        )
        #expect(
            connected.runtimeSource
                == .chatGPTApplication
        )

        await service.disconnect()
        #expect(
            await service.currentSnapshot().phase
                == .disconnected
        )
    }
}

private struct TransportFixture {
    let transport: CodexAppServerTransport
    let probe: ScriptedCodexProcessProbe
    let root: URL
    let turnRequest: CodexMeetingTurnRequest
}

private func transportFixture(
    behavior: ScriptedCodexServer.Behavior,
    timeout: Duration = .seconds(2)
) async throws -> TransportFixture {
    let policy = CodexRuntimeCompatibilityPolicy(
        version: "0.146.0-alpha.3.1",
        executableSHA256: "synthetic-digest",
        signingIdentifier: "codex",
        signingTeamIdentifier: "2DC432GLL2"
    )
    let runtime = CodexRuntimeManager(
        policy: policy,
        candidates: [
            CodexRuntimeCandidate(
                url: URL(fileURLWithPath: "/synthetic/codex"),
                source: .verifiedSystemInstallation
            )
        ],
        verifier: CodexRuntimeVerificationDependencies(
            isExecutable: { _ in true },
            hasTrustedSignature: { _, _, _ in true },
            version: { _ in policy.version },
            sha256: { _ in policy.executableSHA256 }
        )
    )
    guard case let .ready(authorization) = await runtime.discover()
    else {
        throw CodexAppServerError.processExited
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "blueminutes-codex-transport-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
    let environment = try CodexRuntimeEnvironmentManager(
        rootURL: root,
        sourceEnvironment: [
            "HOME": "/Users/synthetic",
            "USER": "synthetic",
            "LOGNAME": "synthetic"
        ]
    )
    let configuration = try await environment.prepare(
        authorization: authorization,
        contextToolEnabled: true
    )
    let probe = ScriptedCodexProcessProbe(behavior: behavior)
    let factory = CodexLineProcessFactory {
        configuration,
        onLine,
        onProtocolFailure,
        onExit in
        let process = ScriptedCodexProcess(
            configuration: configuration,
            probe: probe,
            onLine: onLine,
            onProtocolFailure: onProtocolFailure,
            onExit: onExit
        )
        probe.install(process)
        return process
    }
    let transport = CodexAppServerTransport(
        configuration: configuration,
        requestTimeout: timeout,
        processFactory: factory
    )
    return TransportFixture(
        transport: transport,
        probe: probe,
        root: root,
        turnRequest: try codexTurnRequest()
    )
}

func codexTurnRequest() throws -> CodexMeetingTurnRequest {
    let workspaceID = WorkspaceID(
        UUID(
            uuidString:
                "71000000-0000-0000-0000-000000000001"
        )!
    )
    let meetingID = MeetingID(
        UUID(
            uuidString:
                "71000000-0000-0000-0000-000000000002"
        )!
    )
    let meetingRevision = try SemanticRevisionReference(
        logicalID: meetingID,
        revisionID: RevisionID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000003"
            )!
        )
    )
    let sensitivity = try SemanticRevisionReference(
        logicalID: SensitivityLabelID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000004"
            )!
        ),
        revisionID: RevisionID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000005"
            )!
        )
    )
    let access = try SemanticRevisionReference(
        logicalID: AccessPolicyID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000006"
            )!
        ),
        revisionID: RevisionID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000007"
            )!
        )
    )
    let policy = try ModelSecurityPolicySnapshot(
        sensitivityLabelRevision: sensitivity,
        accessPolicyRevision: access,
        effectiveClassification: .internal,
        noOutboundMode: false,
        localProcessingAllowed: true,
        manualLocalReviewAllowed: true,
        externalProcessingAllowed: true,
        approvedExternalProviderIdentifiers: [
            CodexTextExecutionAuthorization.providerIdentifier
        ],
        approvedDeploymentEnvironments: [.production],
        approvedRetentionPolicies: [.noProviderRetention]
    )
    let routeRequest = try ModelRouteRequest(
        capability: .analysis,
        dataClassification: .internal,
        offlineMode: false,
        organizationAllowsExternalProcessing: true,
        deploymentEnvironment: .production,
        destination: .approvedProvider(
            identifier:
                CodexTextExecutionAuthorization.providerIdentifier
        ),
        retentionPolicy: .noProviderRetention,
        dataCategories: [.userPromptText, .transcriptText],
        visibleUserAuthorization: true,
        localModelAvailable: false,
        securityPolicy: policy
    )
    let route = ResolvedTaskRoute(
        task: .meetingChat,
        providerIdentifier:
            CodexTextExecutionAuthorization.providerIdentifier,
        modelIdentifier: "codex-default",
        capability: .meetingChat,
        dataRoute: .codexSubscriptionText,
        costOwner: .codexSubscription,
        meetingRevision: meetingRevision,
        sensitivityLabelRevision: sensitivity,
        accessPolicyRevision: access,
        effectiveClassification: .internal,
        noOutboundMode: false,
        workspaceID: workspaceID,
        meetingID: meetingID,
        routeOrigin: .global(profileIdentifier: "synthetic")
    )
    let authorization = CodexTextExecutionAuthorization(
        route: route,
        policyAuthorization: try ModelPolicyRouter()
            .authorizeExternal(
                routeRequest,
                expectedProviderIdentifier:
                    CodexTextExecutionAuthorization
                    .providerIdentifier
            )
    )
    let segmentReference = try SemanticRevisionReference(
        logicalID: TranscriptSegmentID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000008"
            )!
        ),
        revisionID: RevisionID(
            UUID(
                uuidString:
                    "71000000-0000-0000-0000-000000000009"
            )!
        )
    )
    let segment = CodexTranscriptContextSegment(
        segmentRevision: segmentReference,
        startMilliseconds: 500,
        endMilliseconds: 1_500,
        language: try LanguageTag("en"),
        text: "one synthetic segment for transport tests"
    )
    let context = CodexMeetingTextContext(
        workspaceID: workspaceID,
        meetingID: meetingID,
        meetingRevision: meetingRevision,
        segments: [segment],
        totalUTF8Bytes: segment.text.utf8.count
    )
    return try CodexMeetingTurnRequest(
        authorization: authorization,
        context: context,
        prompt: "Summarize the synthetic selection."
    )
}

private final class SynchronousCounter:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock {
            storedValue
        }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private final class BlockingRuntimeDiscoveryGate:
    @unchecked Sendable
{
    private let condition = NSCondition()
    private var blocked = false
    private var released = false

    func waitAndReturn(
        _ value: String
    ) -> String {
        condition.lock()
        blocked = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        condition.unlock()
        return value
    }

    func waitUntilBlocked() async throws {
        for _ in 0..<1_000 {
            let isBlocked =
                condition.withLock {
                    blocked
                }
            if isBlocked {
                return
            }
            try await Task.sleep(
                for: .milliseconds(2)
            )
        }
        throw CodexAppServerError
            .requestTimedOut(.initialize)
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private actor AsyncCompletionProbe {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

private final class ScriptedCodexProcessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var behavior: ScriptedCodexServer.Behavior
    private weak var process: ScriptedCodexProcess?
    private var stopSucceeds = true
    private var observedStopCount = 0

    init(behavior: ScriptedCodexServer.Behavior) {
        self.behavior = behavior
    }

    func install(_ process: ScriptedCodexProcess) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func currentBehavior() -> ScriptedCodexServer.Behavior {
        lock.lock()
        defer { lock.unlock() }
        return behavior
    }

    func setBehavior(_ behavior: ScriptedCodexServer.Behavior) {
        lock.lock()
        self.behavior = behavior
        lock.unlock()
    }

    func setStopSucceeds(_ value: Bool) {
        lock.lock()
        stopSucceeds = value
        lock.unlock()
    }

    func shouldStopSucceed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopSucceeds
    }

    func recordStopAttempt() {
        lock.lock()
        observedStopCount += 1
        lock.unlock()
    }

    func stopCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observedStopCount
    }

    func emit(_ value: CodexJSONValue) {
        lock.lock()
        let process = self.process
        lock.unlock()
        process?.emit(value)
    }

    func crash() {
        lock.lock()
        let process = self.process
        lock.unlock()
        process?.crash()
    }

    func sentMessages() -> [CodexJSONValue] {
        lock.lock()
        let process = self.process
        lock.unlock()
        return process?.sentMessages() ?? []
    }

    func waitForResponse(id: Int64) async throws -> CodexJSONValue {
        for _ in 0..<1_000 {
            if let response = sentMessages().first(where: {
                $0.objectValue?["id"]?.int64Value == id
                    && $0.objectValue?["result"] != nil
            }) {
                return response
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw CodexAppServerError.requestTimedOut(.turnStart)
    }
}

private final class ScriptedCodexProcess:
    CodexLineProcessHandling,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let configuration: CodexRuntimeProcessConfiguration
    private let probe: ScriptedCodexProcessProbe
    private let onLine: @Sendable (Data) -> Void
    private let onProtocolFailure:
        @Sendable (CodexProtocolViolation) -> Void
    private let onExit: @Sendable () -> Void
    private var messages: [CodexJSONValue] = []
    private var stopped = false

    init(
        configuration: CodexRuntimeProcessConfiguration,
        probe: ScriptedCodexProcessProbe,
        onLine: @escaping @Sendable (Data) -> Void,
        onProtocolFailure:
            @escaping @Sendable (CodexProtocolViolation) -> Void,
        onExit: @escaping @Sendable () -> Void
    ) {
        self.configuration = configuration
        self.probe = probe
        self.onLine = onLine
        self.onProtocolFailure = onProtocolFailure
        self.onExit = onExit
    }

    func send(_ data: Data) throws {
        let value = try JSONDecoder().decode(
            CodexJSONValue.self,
            from: data
        )
        lock.lock()
        guard !stopped else {
            lock.unlock()
            throw CodexAppServerError.processExited
        }
        messages.append(value)
        lock.unlock()
        let responses = ScriptedCodexServer.responses(
            to: value,
            configuration: configuration,
            behavior: probe.currentBehavior()
        )
        for response in responses {
            emit(response)
        }
    }

    func stop() async -> Bool {
        probe.recordStopAttempt()
        guard probe.shouldStopSucceed() else {
            return false
        }
        finishStop()
        return true
    }

    private func finishStop() {
        lock.lock()
        let shouldExit = !stopped
        stopped = true
        lock.unlock()
        if shouldExit { onExit() }
    }

    func crash() {
        finishStop()
    }

    func emit(_ value: CodexJSONValue) {
        guard let data = try? JSONEncoder().encode(value) else {
            onProtocolFailure(.malformedEnvelope)
            return
        }
        onLine(data)
    }

    func sentMessages() -> [CodexJSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

private enum ScriptedCodexServer {
    enum Behavior: Sendable, Equatable {
        case normal
        case connectedAccount
        case mismatchedTurnStartNotification
        case forbiddenCommandOnAccountRead
        case permissionRequestOnAccountRead
        case malformedAccountRead
        case hangOnAccountRead
    }

    static let threadID =
        "019fb000-0000-7000-8000-000000000001"
    static let turnID =
        "019fb000-0000-7000-8000-000000000002"

    static func responses(
        to value: CodexJSONValue,
        configuration: CodexRuntimeProcessConfiguration,
        behavior: Behavior
    ) -> [CodexJSONValue] {
        guard let request = value.objectValue,
              let method = request["method"]?.stringValue,
              let id = request["id"]
        else {
            return []
        }
        if method == "account/read" {
            switch behavior {
            case .forbiddenCommandOnAccountRead:
                return [
                    .object([
                        "method": .string("item/started"),
                        "params": .object([
                            "threadId": .string(threadID),
                            "turnId": .string(turnID),
                            "startedAtMs": .integer(1),
                            "item": .object([
                                "id": .string("command-1"),
                                "type": .string("commandExecution"),
                                "command": .string("whoami"),
                                "commandActions": .array([]),
                                "cwd": .string("/"),
                                "status": .string("inProgress")
                            ])
                        ])
                    ])
                ]
            case .permissionRequestOnAccountRead:
                return [
                    .object([
                        "id": .integer(991),
                        "method": .string(
                            "item/permissions/requestApproval"
                        ),
                        "params": .object([:])
                    ])
                ]
            case .hangOnAccountRead:
                return []
            case .malformedAccountRead:
                return [
                    .object([
                        "id": id,
                        "result": .object([
                            "account": .null
                        ])
                    ])
                ]
            case .normal,
                 .connectedAccount,
                 .mismatchedTurnStartNotification:
                break
            }
        }
        let result: CodexJSONValue
        switch method {
        case "initialize":
            result = .object([
                "codexHome": .string(
                    configuration.codexHomeURL.path
                ),
                "platformFamily": .string("unix"),
                "platformOs": .string("macos"),
                "userAgent": .string(
                    "codex_cli_rs/\(configuration.runtimeVersion)"
                )
            ])
        case "config/read":
            result = configResult()
        case "account/read":
            if behavior == .connectedAccount {
                result = .object([
                    "account": .object([
                        "type": .string(
                            "chatgpt"
                        ),
                        "planType":
                            .string("plus")
                    ]),
                    "requiresOpenaiAuth":
                        .bool(true)
                ])
            } else {
                result = .object([
                    "account": .null,
                    "requiresOpenaiAuth": .bool(true)
                ])
            }
        case "account/login/start":
            let type = request["params"]?
                .objectValue?["type"]?.stringValue
            if type == "chatgptDeviceCode" {
                result = .object([
                    "type": .string("chatgptDeviceCode"),
                    "loginId": .string("login-device-1"),
                    "userCode": .string("ABCD-EFGH"),
                    "verificationUrl": .string(
                        "https://auth.openai.com/device"
                    )
                ])
            } else {
                result = .object([
                    "type": .string("chatgpt"),
                    "loginId": .string("login-browser-1"),
                    "authUrl": .string(
                        "https://auth.openai.com/authorize"
                    )
                ])
            }
        case "account/login/cancel", "account/logout":
            result = .object([:])
        case "account/rateLimits/read":
            result = .object([
                "rateLimits": .object([
                    "planType": .string("pro"),
                    "primary": .object([
                        "usedPercent": .integer(25),
                        "resetsAt": .integer(2_000_000_000),
                        "windowDurationMins": .integer(300)
                    ]),
                    "secondary": .object([
                        "usedPercent": .integer(40),
                        "resetsAt": .integer(2_000_100_000),
                        "windowDurationMins": .integer(10_080)
                    ]),
                    "credits": .object([
                        "hasCredits": .bool(true),
                        "unlimited": .bool(false)
                    ]),
                    "spendControlReached": .bool(false)
                ])
            ])
        case "thread/start", "thread/resume":
            result = threadResponse(configuration: configuration)
        case "thread/read":
            result = .object([
                "thread": threadObject(
                    configuration: configuration,
                    turns: []
                )
            ])
        case "turn/start":
            if behavior
                == .mismatchedTurnStartNotification
            {
                return [
                    .object([
                        "method":
                            .string(
                                "turn/started"
                            ),
                        "params": .object([
                            "threadId":
                                .string(
                                    threadID
                                ),
                            "turn":
                                turn(
                                    status:
                                        "inProgress"
                                )
                        ])
                    ]),
                    .object([
                        "id": id,
                        "result": .object([
                            "turn": turn(
                                id:
                                    "019fb000-0000-7000-8000-000000000099",
                                status:
                                    "inProgress"
                            )
                        ])
                    ])
                ]
            }
            result = .object([
                "turn": turn(status: "inProgress")
            ])
        case "turn/interrupt", "thread/delete":
            result = .object([:])
        default:
            return []
        }
        return [
            .object([
                "id": id,
                "result": result
            ])
        ]
    }

    static func turn(
        id: String = turnID,
        status: String
    ) -> CodexJSONValue {
        .object([
            "id": .string(id),
            "status": .string(status),
            "items": .array([])
        ])
    }

    private static func threadResponse(
        configuration: CodexRuntimeProcessConfiguration
    ) -> CodexJSONValue {
        .object([
            "approvalPolicy": .string("never"),
            "approvalsReviewer": .string("user"),
            "cwd": .string(
                configuration.disposableWorkingDirectoryURL.path
            ),
            "instructionSources": .array([]),
            "model": .string("gpt-5.6-codex"),
            "modelProvider": .string("openai"),
            "sandbox": .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(false)
            ]),
            "thread": threadObject(
                configuration: configuration,
                turns: []
            )
        ])
    }

    private static func threadObject(
        configuration: CodexRuntimeProcessConfiguration,
        turns: [CodexJSONValue]
    ) -> CodexJSONValue {
        .object([
            "id": .string(threadID),
            "cwd": .string(
                configuration.disposableWorkingDirectoryURL.path
            ),
            "modelProvider": .string("openai"),
            "ephemeral": .bool(true),
            "parentThreadId": .null,
            "gitInfo": .null,
            "turns": .array(turns)
        ])
    }

    private static func configResult() -> CodexJSONValue {
        let featureNames = [
            "apps",
            "auth_elicitation",
            "browser_use",
            "browser_use_external",
            "browser_use_full_cdp_access",
            "code_mode",
            "code_mode_buffered_exec",
            "code_mode_host",
            "code_mode_only",
            "computer_use",
            "default_mode_request_user_input",
            "deferred_executor",
            "enable_mcp_apps",
            "executor_capability_discovery",
            "external_agent_memory_import",
            "goals",
            "guardian_approval",
            "hooks",
            "image_generation",
            "in_app_browser",
            "memories",
            "mentions_v2",
            "multi_agent",
            "multi_agent_v2",
            "network_proxy",
            "plugin_sharing",
            "plugins",
            "realtime_conversation",
            "remote_plugin",
            "request_permissions_tool",
            "shell_snapshot",
            "shell_tool",
            "skill_mcp_dependency_install",
            "skill_search",
            "standalone_web_search",
            "tool_call_mcp_elicitation",
            "tool_suggest",
            "unified_exec",
            "unified_exec_zsh_fork",
            "workspace_dependencies"
        ]
        return .object([
            "config": .object([
                "approval_policy": .string("never"),
                "sandbox_mode": .string("read-only"),
                "web_search": .string("disabled"),
                "forced_login_method": .string("chatgpt"),
                "analytics": .object([
                    "enabled": .bool(false)
                ]),
                "tools": .object([
                    "web_search": .null
                ]),
                "apps": .object([
                    "_default": .object([
                        "enabled": .bool(false),
                        "destructive_enabled": .bool(false),
                        "open_world_enabled": .bool(false)
                    ])
                ]),
                "shell_environment_policy": .object([
                    "inherit": .string("none")
                ]),
                "features": .object(
                    Dictionary(
                        uniqueKeysWithValues: featureNames.map {
                            ($0, CodexJSONValue.bool(false))
                        }
                    )
                ),
                "plugins": .object([:])
            ]),
            "origins": .object([:])
        ])
    }
}
