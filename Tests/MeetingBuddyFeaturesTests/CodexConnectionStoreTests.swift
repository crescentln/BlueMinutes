import Foundation
@testable import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyAI
@testable import MeetingBuddyFeatures

@Suite
struct CodexConnectionStoreTests {
    @Test @MainActor
    func storeProjectsConnectionLoginStreamingAndFailureEvents()
        async throws
    {
        let service = CodexMeetingSessionServiceProbe()
        let store = CodexConnectionStore(service: service)
        let meetingID = MeetingID(UUID())
        let scope = CodexConversationScope(
            workspaceID: WorkspaceID(UUID()),
            meetingID: meetingID
        )

        await store.connect()
        #expect(store.snapshot.phase == .connected)
        #expect(store.snapshot.account == .connected(plan: .plus))

        let challenge = CodexLoginChallenge(
            kind: .deviceCode,
            loginID: "login-1",
            verificationURL: try #require(
                URL(string: "https://auth.openai.com/device")
            ),
            userCode: "SAFE-CODE"
        )
        await service.emit(.loginChallenge(challenge))
        await waitUntil {
            store.loginChallenge == challenge
        }

        await service.emit(
            .agentMessageDelta(
                scope: scope,
                turnID: "turn-1",
                itemID: "item-1",
                delta: "Bounded "
            )
        )
        await service.emit(
            .agentMessageDelta(
                scope: scope,
                turnID: "turn-1",
                itemID: "item-1",
                delta: "response"
            )
        )
        await waitUntil {
            store.messages(for: scope).first?.text
                == "Bounded response"
        }
        #expect(store.hasActiveTurn(for: scope))

        await service.emit(
            .turnCompleted(
                scope: scope,
                turnID: "turn-1",
                status: .completed
            )
        )
        await waitUntil {
            !store.hasActiveTurn(for: scope)
        }
        #expect(
            store.messages(for: scope).first?.status
                == .completed
        )

        await service.emit(
            .safeFailure(
                scope: scope,
                turnID: nil,
                category: .networkUnavailable,
                willRetry: false
            )
        )
        await waitUntil {
            store.safeErrorMessage?.contains(
                "No provider fallback"
            ) == true
        }
    }

    @Test @MainActor
    func disconnectPreservesConversationButClearsConnectionState()
        async
    {
        let service = CodexMeetingSessionServiceProbe()
        let store = CodexConnectionStore(service: service)
        let meetingID = MeetingID(UUID())
        let scope = CodexConversationScope(
            workspaceID: WorkspaceID(UUID()),
            meetingID: meetingID
        )
        await store.connect()
        await service.emit(
            .agentMessageDelta(
                scope: scope,
                turnID: "turn-retained",
                itemID: "item-retained",
                delta: "Retained in memory"
            )
        )
        await waitUntil {
            !store.messages(for: scope).isEmpty
        }

        await store.disconnect()

        #expect(store.snapshot.phase == .disconnected)
        #expect(
            store.messages(for: scope).first?.text
                == "Retained in memory"
        )
        #expect(!store.hasActiveTurn(for: scope))
        #expect(
            store.messages(for: scope).first?.status
                == .interrupted
        )
    }

    @Test @MainActor
    func conversationsAreWorkspaceScopedAndStaleCompletionCannotClearCurrentTurn()
        async
    {
        let service = CodexMeetingSessionServiceProbe()
        let store = CodexConnectionStore(service: service)
        let meetingID = MeetingID(UUID())
        let first = CodexConversationScope(
            workspaceID: WorkspaceID(UUID()),
            meetingID: meetingID
        )
        let copied = CodexConversationScope(
            workspaceID: WorkspaceID(UUID()),
            meetingID: meetingID
        )

        await service.emit(
            .agentMessageDelta(
                scope: first,
                turnID: "turn-current",
                itemID: "item-current",
                delta: "First workspace"
            )
        )
        await service.emit(
            .agentMessageDelta(
                scope: copied,
                turnID: "turn-copy",
                itemID: "item-copy",
                delta: "Copied workspace"
            )
        )
        await waitUntil {
            store.messages(for: first).count == 1
                && store.messages(for: copied).count == 1
        }

        #expect(
            store.messages(for: first).first?.text
                == "First workspace"
        )
        #expect(
            store.messages(for: copied).first?.text
                == "Copied workspace"
        )
        await service.emit(
            .turnCompleted(
                scope: first,
                turnID: "turn-stale",
                status: .completed
            )
        )
        await Task.yield()
        #expect(store.hasActiveTurn(for: first))

        await service.emit(
            .safeFailure(
                scope: first,
                turnID: "turn-stale",
                category: .networkUnavailable,
                willRetry: false
            )
        )
        await Task.yield()
        #expect(store.hasActiveTurn(for: first))

        await service.emit(
            .turnCompleted(
                scope: first,
                turnID: "turn-current",
                status: .completed
            )
        )
        await waitUntil {
            !store.hasActiveTurn(for: first)
        }
        #expect(store.hasActiveTurn(for: copied))
    }

    @Test @MainActor
    func concurrentSendIsReservedBeforeTheFirstAwait()
        async throws
    {
        let service = CodexMeetingSessionServiceProbe(
            sendDelay: .milliseconds(50)
        )
        let store = CodexConnectionStore(service: service)
        await store.connect()
        let request =
            try featureCodexTurnRequest()

        let first = Task { @MainActor in
            await store.send(request)
        }
        for _ in 0..<200 {
            if await service.sendCount() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await service.sendCount() == 1)

        let secondAccepted = await store.send(request)
        let firstAccepted = await first.value

        #expect(firstAccepted)
        #expect(!secondAccepted)
        #expect(await service.sendCount() == 1)
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        #expect(predicate())
    }
}

private func featureCodexTurnRequest()
    throws -> CodexMeetingTurnRequest
{
    let workspaceID = WorkspaceID(UUID())
    let meetingID = MeetingID(UUID())
    let meetingRevision =
        try SemanticRevisionReference(
            logicalID: meetingID,
            revisionID: RevisionID(UUID())
        )
    let sensitivity =
        try SemanticRevisionReference(
            logicalID:
                SensitivityLabelID(UUID()),
            revisionID: RevisionID(UUID())
        )
    let access =
        try SemanticRevisionReference(
            logicalID:
                AccessPolicyID(UUID()),
            revisionID: RevisionID(UUID())
        )
    let securityPolicy =
        try ModelSecurityPolicySnapshot(
            sensitivityLabelRevision:
                sensitivity,
            accessPolicyRevision: access,
            effectiveClassification:
                .internal,
            noOutboundMode: false,
            localProcessingAllowed: true,
            manualLocalReviewAllowed: true,
            externalProcessingAllowed: true,
            approvedExternalProviderIdentifiers: [
                CodexTextExecutionAuthorization
                    .providerIdentifier
            ],
            approvedDeploymentEnvironments: [
                .production
            ],
            approvedRetentionPolicies: [
                .noProviderRetention
            ]
        )
    let routeRequest = try ModelRouteRequest(
        capability: .analysis,
        dataClassification: .internal,
        offlineMode: false,
        organizationAllowsExternalProcessing:
            true,
        deploymentEnvironment: .production,
        destination: .approvedProvider(
            identifier:
                CodexTextExecutionAuthorization
                .providerIdentifier
        ),
        retentionPolicy:
            .noProviderRetention,
        dataCategories: [
            .userPromptText,
            .transcriptText
        ],
        visibleUserAuthorization: true,
        localModelAvailable: false,
        securityPolicy: securityPolicy
    )
    let route = ResolvedTaskRoute(
        task: .meetingChat,
        providerIdentifier:
            CodexTextExecutionAuthorization
            .providerIdentifier,
        modelIdentifier: "codex-default",
        capability: .meetingChat,
        dataRoute:
            .codexSubscriptionText,
        costOwner: .codexSubscription,
        meetingRevision: meetingRevision,
        sensitivityLabelRevision:
            sensitivity,
        accessPolicyRevision: access,
        effectiveClassification:
            .internal,
        noOutboundMode: false,
        workspaceID: workspaceID,
        meetingID: meetingID,
        routeOrigin: .global(
            profileIdentifier:
                "feature-test"
        )
    )
    let authorization =
        CodexTextExecutionAuthorization(
            route: route,
            policyAuthorization:
                try ModelPolicyRouter()
                .authorizeExternal(
                    routeRequest,
                    expectedProviderIdentifier:
                        CodexTextExecutionAuthorization
                        .providerIdentifier
                )
        )
    let segmentReference =
        try SemanticRevisionReference(
            logicalID:
                TranscriptSegmentID(UUID()),
            revisionID: RevisionID(UUID())
        )
    let segment =
        CodexTranscriptContextSegment(
            segmentRevision:
                segmentReference,
            startMilliseconds: 0,
            endMilliseconds: 1_000,
            language: try LanguageTag("en"),
            text: "Synthetic feature test."
        )
    let context = CodexMeetingTextContext(
        workspaceID: workspaceID,
        meetingID: meetingID,
        meetingRevision:
            meetingRevision,
        segments: [segment],
        totalUTF8Bytes:
            segment.text.utf8.count
    )
    return try CodexMeetingTurnRequest(
        authorization: authorization,
        context: context,
        prompt: "Summarize."
    )
}

private actor CodexMeetingSessionServiceProbe:
    CodexMeetingSessionServing
{
    nonisolated let events:
        AsyncStream<CodexMeetingSessionEvent>
    private let continuation:
        AsyncStream<CodexMeetingSessionEvent>.Continuation
    private var snapshot =
        CodexConnectionSnapshot(phase: .disconnected)
    private let sendDelay: Duration?
    private var observedSendCount = 0

    init(sendDelay: Duration? = nil) {
        self.sendDelay = sendDelay
        let pair =
            AsyncStream<CodexMeetingSessionEvent>
            .makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func emit(_ event: CodexMeetingSessionEvent) {
        continuation.yield(event)
    }

    func currentSnapshot() -> CodexConnectionSnapshot {
        snapshot
    }

    func connect() -> CodexConnectionSnapshot {
        snapshot = CodexConnectionSnapshot(
            phase: .connected,
            runtimeVersion: "test",
            runtimeSource: .chatGPTApplication,
            account: .connected(plan: .plus)
        )
        continuation.yield(.connectionChanged(snapshot))
        return snapshot
    }

    func reconnect() -> CodexConnectionSnapshot {
        connect()
    }

    func testConnection() -> CodexConnectionSnapshot {
        snapshot
    }

    func startBrowserLogin() throws -> CodexLoginChallenge {
        try challenge(kind: .browser)
    }

    func startDeviceCodeLogin() throws
        -> CodexLoginChallenge
    {
        try challenge(kind: .deviceCode)
    }

    func cancelLogin(loginID: String) {}

    func refreshAccount() -> CodexConnectionSnapshot {
        snapshot
    }

    func logout() -> CodexConnectionSnapshot {
        snapshot = CodexConnectionSnapshot(
            phase: .signedOut,
            account: .signedOut(
                requiresOpenAIAuthentication: true
            )
        )
        return snapshot
    }

    func disconnect() {
        snapshot = CodexConnectionSnapshot(
            phase: .disconnected
        )
        continuation.yield(.connectionChanged(snapshot))
    }

    func send(
        _ request: CodexMeetingTurnRequest
    ) async -> CodexTurnHandle {
        observedSendCount += 1
        if let sendDelay {
            try? await Task.sleep(for: sendDelay)
        }
        return CodexTurnHandle(
            threadID: "thread-probe",
            turnID: "turn-probe"
        )
    }

    func sendCount() -> Int {
        observedSendCount
    }

    func interrupt(scope: CodexConversationScope) {}

    func clearThread(scope: CodexConversationScope) {}

    private func challenge(
        kind: CodexLoginChallenge.Kind
    ) throws -> CodexLoginChallenge {
        CodexLoginChallenge(
            kind: kind,
            loginID: "login-probe",
            verificationURL: try #require(
                URL(string: "https://auth.openai.com/device")
            ),
            userCode: kind == .deviceCode
                ? "SAFE-CODE"
                : nil
        )
    }
}
