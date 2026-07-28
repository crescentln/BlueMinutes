import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum CodexConnectionPhase:
    String, Hashable, Sendable
{
    case disconnected
    case connecting
    case runtimeMissing = "runtime_missing"
    case runtimeUntrusted = "runtime_untrusted"
    case runtimeIncompatible = "runtime_incompatible"
    case signedOut = "signed_out"
    case connected
    case failed
}

public struct CodexConnectionSnapshot: Hashable, Sendable {
    public let phase: CodexConnectionPhase
    public let runtimeVersion: String?
    public let runtimeSource: CodexRuntimeSource?
    public let account: CodexAccountState?
    public let quota: CodexQuotaState?

    public init(
        phase: CodexConnectionPhase,
        runtimeVersion: String? = nil,
        runtimeSource: CodexRuntimeSource? = nil,
        account: CodexAccountState? = nil,
        quota: CodexQuotaState? = nil
    ) {
        self.phase = phase
        self.runtimeVersion = runtimeVersion
        self.runtimeSource = runtimeSource
        self.account = account
        self.quota = quota
    }
}

public struct CodexConversationScope: Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID

    public init(
        workspaceID: WorkspaceID,
        meetingID: MeetingID
    ) {
        self.workspaceID = workspaceID
        self.meetingID = meetingID
    }

    public init(context: CodexMeetingTextContext) {
        self.init(
            workspaceID: context.workspaceID,
            meetingID: context.meetingID
        )
    }
}

public enum CodexMeetingSessionServiceError:
    Error, Equatable, LocalizedError, Sendable
{
    case runtimeMissing
    case runtimeUntrusted
    case runtimeIncompatible(observedVersion: String?)
    case privateStorageUnavailable
    case notConnected
    case authenticationRequired
    case quotaUnavailable
    case requestInProgress
    case requestFailed(CodexSafeFailureCategory)

    public var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "Install the supported official Codex runtime before connecting."
        case .runtimeUntrusted:
            "The detected Codex runtime did not pass signature verification."
        case let .runtimeIncompatible(observedVersion):
            if let observedVersion {
                "Codex \(observedVersion) is not the exact tested runtime version."
            } else {
                "The detected Codex runtime version is unsupported."
            }
        case .privateStorageUnavailable:
            "BlueMinutes could not prepare its private Codex runtime area."
        case .notConnected:
            "Connect Codex before starting a text request."
        case .authenticationRequired:
            "Sign in with the official ChatGPT flow before using Codex."
        case .quotaUnavailable:
            "Codex quota is currently unavailable. Wait for it to reset or continue with non-AI features."
        case .requestInProgress:
            "Finish or stop the active Codex request before sending another one for this meeting."
        case let .requestFailed(category):
            switch category {
            case .authenticationRequired:
                "Codex authentication is required."
            case .quotaUnavailable:
                "Codex quota is currently unavailable."
            case .networkUnavailable:
                "Codex could not reach its service."
            case .runtimeExited:
                "The local Codex runtime exited."
            case .requestRejected:
                "Codex rejected the text request."
            case .contextWindowExceeded:
                "The selected text exceeds the current Codex context window."
            case .interrupted:
                "Codex generation was stopped."
            case .unavailable:
                "Codex is currently unavailable."
            }
        }
    }
}

public enum CodexMeetingSessionEvent: Hashable, Sendable {
    case connectionChanged(CodexConnectionSnapshot)
    case loginChallenge(CodexLoginChallenge)
    case loginCompleted(success: Bool)
    case agentMessageDelta(
        scope: CodexConversationScope,
        turnID: String,
        itemID: String,
        delta: String
    )
    case turnCompleted(
        scope: CodexConversationScope,
        turnID: String,
        status: CodexTurnCompletionStatus
    )
    case safeFailure(
        scope: CodexConversationScope?,
        turnID: String?,
        category: CodexSafeFailureCategory,
        willRetry: Bool
    )
    case processExited
}

public protocol CodexMeetingSessionServing: Sendable {
    var events: AsyncStream<CodexMeetingSessionEvent> { get }

    func currentSnapshot() async -> CodexConnectionSnapshot
    func connect() async throws -> CodexConnectionSnapshot
    func reconnect() async throws -> CodexConnectionSnapshot
    func testConnection() async throws -> CodexConnectionSnapshot
    func startBrowserLogin() async throws -> CodexLoginChallenge
    func startDeviceCodeLogin() async throws -> CodexLoginChallenge
    func cancelLogin(loginID: String) async throws
    func refreshAccount() async throws -> CodexConnectionSnapshot
    func logout() async throws -> CodexConnectionSnapshot
    func disconnect() async
    func send(
        _ request: CodexMeetingTurnRequest
    ) async throws -> CodexTurnHandle
    func interrupt(scope: CodexConversationScope) async throws
    func clearThread(scope: CodexConversationScope) async throws
}

public actor CodexMeetingSessionService:
    CodexMeetingSessionServing
{
    public nonisolated let events:
        AsyncStream<CodexMeetingSessionEvent>

    private let storageRootURL: URL
    private let runtimeManager: CodexRuntimeManager
    private let transportFactory:
        @Sendable (
            CodexRuntimeProcessConfiguration
        ) -> CodexAppServerTransport
    private let eventContinuation:
        AsyncStream<CodexMeetingSessionEvent>.Continuation

    private var environmentManager:
        CodexRuntimeEnvironmentManager?
    private var configuration:
        CodexRuntimeProcessConfiguration?
    private var transport: CodexAppServerTransport?
    private var transportEventTask: Task<Void, Never>?
    private var transportGeneration: UInt64 = 0
    private var nextConnectionAttemptID: UInt64 = 0
    private var activeConnectionAttempt:
        (
            id: UInt64,
            task:
                Task<
                    CodexConnectionSnapshot,
                    Error
                >
        )?
    private var snapshot = CodexConnectionSnapshot(
        phase: .disconnected
    )
    private var sessions:
        [CodexMeetingSessionKey: CodexMeetingThreadSession] = [:]
    private var scopeByThreadID:
        [String: CodexConversationScope] = [:]
    private var attachedThreadIDs = Set<String>()
    private var activeTurnByScope:
        [CodexConversationScope: CodexTurnHandle] = [:]
    private var inFlightSendScopes =
        Set<CodexConversationScope>()

    public init(storageRootURL: URL) {
        self.init(
            storageRootURL: storageRootURL,
            runtimeManager: CodexRuntimeManager(),
            transportFactory: {
                CodexAppServerTransport(
                    configuration: $0
                )
            }
        )
    }

    init(
        storageRootURL: URL,
        runtimeManager: CodexRuntimeManager,
        transportFactory:
            @escaping @Sendable (
                CodexRuntimeProcessConfiguration
            ) -> CodexAppServerTransport = {
                CodexAppServerTransport(
                    configuration: $0
                )
            }
    ) {
        self.storageRootURL = storageRootURL
            .standardizedFileURL
        self.runtimeManager = runtimeManager
        self.transportFactory =
            transportFactory
        let pair =
            AsyncStream<CodexMeetingSessionEvent>
            .makeStream(
                bufferingPolicy: .bufferingOldest(512)
            )
        events = pair.stream
        eventContinuation = pair.continuation
    }

    deinit {
        transportEventTask?.cancel()
        eventContinuation.finish()
    }

    public func currentSnapshot() -> CodexConnectionSnapshot {
        snapshot
    }

    public func connect() async throws
        -> CodexConnectionSnapshot
    {
        if snapshot.phase == .connected
            || snapshot.phase == .signedOut
        {
            return snapshot
        }
        if let activeConnectionAttempt {
            return try await
                activeConnectionAttempt
                .task.value
        }
        nextConnectionAttemptID &+= 1
        let attemptID =
            nextConnectionAttemptID
        let task =
            Task<
                CodexConnectionSnapshot,
                Error
            > {
                try await self
                    .performConnect()
            }
        activeConnectionAttempt = (
            id: attemptID,
            task: task
        )
        do {
            let result = try await task.value
            clearConnectionAttempt(
                id: attemptID
            )
            return result
        } catch {
            clearConnectionAttempt(
                id: attemptID
            )
            throw error
        }
    }

    private func performConnect() async throws
        -> CodexConnectionSnapshot
    {
        try Task.checkCancellation()
        if transport != nil
            || environmentManager != nil
            || configuration != nil
        {
            guard await
                stopTransportAndDiscardSessionDirectories()
            else {
                throw CodexMeetingSessionServiceError
                    .requestFailed(.runtimeExited)
            }
        }
        try Task.checkCancellation()
        setSnapshot(
            CodexConnectionSnapshot(phase: .connecting)
        )
        let discovery = await runtimeManager.discover()
        try Task.checkCancellation()
        let authorization: CodexRuntimeLaunchAuthorization
        switch discovery {
        case let .ready(value):
            authorization = value
        case .missing:
            setSnapshot(
                CodexConnectionSnapshot(
                    phase: .runtimeMissing
                )
            )
            throw CodexMeetingSessionServiceError.runtimeMissing
        case .untrustedInstallation:
            setSnapshot(
                CodexConnectionSnapshot(
                    phase: .runtimeUntrusted
                )
            )
            throw CodexMeetingSessionServiceError.runtimeUntrusted
        case let .incompatible(version, _):
            setSnapshot(
                CodexConnectionSnapshot(
                    phase: .runtimeIncompatible,
                    runtimeVersion: version
                )
            )
            throw CodexMeetingSessionServiceError
                .runtimeIncompatible(
                    observedVersion: version
                )
        }

        do {
            let environment = try CodexRuntimeEnvironmentManager(
                rootURL: storageRootURL
            )
            let nextConfiguration = try await environment.prepare(
                authorization: authorization,
                contextToolEnabled: true
            )
            let nextTransport =
                transportFactory(
                    nextConfiguration
                )
            environmentManager = environment
            configuration = nextConfiguration
            transport = nextTransport
            try Task.checkCancellation()
            try await nextTransport.start()
            try Task.checkCancellation()
            attachedThreadIDs.removeAll()
            beginForwardingEvents(from: nextTransport)
            let connected =
                try await refreshAccount()
            try Task.checkCancellation()
            return connected
        } catch {
            _ = await
                stopTransportAndDiscardSessionDirectories()
            let mapped = map(error)
            setSnapshot(
                CodexConnectionSnapshot(
                    phase: .failed,
                    runtimeVersion:
                        authorization.descriptor.version,
                    runtimeSource:
                        authorization.descriptor.source
                )
            )
            throw mapped
        }
    }

    public func reconnect() async throws
        -> CodexConnectionSnapshot
    {
        await cancelActiveConnectionAttempt()
        guard await
            stopTransportAndDiscardSessionDirectories()
        else {
            throw CodexMeetingSessionServiceError
                .requestFailed(.runtimeExited)
        }
        setSnapshot(
            CodexConnectionSnapshot(phase: .disconnected)
        )
        return try await connect()
    }

    public func testConnection() async throws
        -> CodexConnectionSnapshot
    {
        if activeConnectionAttempt != nil {
            return try await connect()
        }
        if transport == nil {
            return try await connect()
        }
        return try await refreshAccount()
    }

    public func startBrowserLogin() async throws
        -> CodexLoginChallenge
    {
        let transport = try requireTransport()
        let challenge = try await transport.startBrowserLogin()
        yield(.loginChallenge(challenge))
        return challenge
    }

    public func startDeviceCodeLogin() async throws
        -> CodexLoginChallenge
    {
        let transport = try requireTransport()
        let challenge = try await transport
            .startDeviceCodeLogin()
        yield(.loginChallenge(challenge))
        return challenge
    }

    public func cancelLogin(loginID: String) async throws {
        try await requireTransport().cancelLogin(
            loginID: loginID
        )
    }

    public func refreshAccount() async throws
        -> CodexConnectionSnapshot
    {
        let transport = try requireTransport()
        let account = try await transport.account()
        let quota: CodexQuotaState?
        let phase: CodexConnectionPhase
        switch account {
        case .signedOut:
            quota = nil
            phase = .signedOut
        case .connected:
            let value = try await transport.quota()
            quota = value
            phase = .connected
        }
        let next = snapshotWith(
            phase: phase,
            account: account,
            quota: quota
        )
        setSnapshot(next)
        return next
    }

    public func logout() async throws
        -> CodexConnectionSnapshot
    {
        guard activeTurnByScope.isEmpty,
              inFlightSendScopes.isEmpty
        else {
            throw CodexMeetingSessionServiceError
                .requestInProgress
        }
        let transport = try requireTransport()
        try await transport.logout()
        let next = snapshotWith(
            phase: .signedOut,
            account: .signedOut(
                requiresOpenAIAuthentication: true
            ),
            quota: nil
        )
        setSnapshot(next)
        return next
    }

    public func disconnect() async {
        await cancelActiveConnectionAttempt()
        let stopped = await
            stopTransportAndDiscardSessionDirectories()
        setSnapshot(
            CodexConnectionSnapshot(
                phase: stopped
                    ? .disconnected
                    : .failed
            )
        )
    }

    public func send(
        _ request: CodexMeetingTurnRequest
    ) async throws -> CodexTurnHandle {
        guard snapshot.phase == .connected else {
            if snapshot.phase == .signedOut {
                throw CodexMeetingSessionServiceError
                    .authenticationRequired
            }
            throw CodexMeetingSessionServiceError.notConnected
        }
        let transport = try requireTransport()
        let scope = CodexConversationScope(
            context: request.context
        )
        guard activeTurnByScope[scope] == nil,
              inFlightSendScopes.insert(scope).inserted
        else {
            throw CodexMeetingSessionServiceError
                .requestInProgress
        }
        defer {
            inFlightSendScopes.remove(scope)
        }
        let key = CodexMeetingSessionKey(
            context: request.context
        )
        let session: CodexMeetingThreadSession
        if let existing = sessions[key] {
            if attachedThreadIDs.contains(
                existing.handle.threadID
            ) {
                session = existing
            } else {
                session = try await transport
                    .resumeMeetingThread(
                        existing,
                        context: request.context
                    )
                sessions[key] = session
                attachedThreadIDs.insert(
                    session.handle.threadID
                )
            }
        } else {
            session = try await transport.startMeetingThread(
                context: request.context
            )
            sessions[key] = session
            attachedThreadIDs.insert(session.handle.threadID)
        }
        scopeByThreadID[session.handle.threadID] =
            scope
        let turn = try await transport.startTurn(
            in: session,
            request: request
        )
        activeTurnByScope[scope] = turn
        return turn
    }

    public func interrupt(
        scope: CodexConversationScope
    ) async throws {
        guard let turn = activeTurnByScope[scope] else {
            throw CodexMeetingSessionServiceError.notConnected
        }
        try await requireTransport().interrupt(turn)
    }

    public func clearThread(
        scope: CodexConversationScope
    ) async throws {
        let matches = sessions.filter {
            $0.key.workspaceID == scope.workspaceID
                && $0.key.meetingID == scope.meetingID
        }
        if let transport {
            for (_, session) in matches
            where attachedThreadIDs.contains(
                session.handle.threadID
            ) {
                try await transport.deleteMeetingThread(session)
            }
        }
        for (key, session) in matches {
            sessions.removeValue(forKey: key)
            attachedThreadIDs.remove(
                session.handle.threadID
            )
            scopeByThreadID.removeValue(
                forKey: session.handle.threadID
            )
        }
        activeTurnByScope.removeValue(forKey: scope)
        inFlightSendScopes.remove(scope)
    }

    private func beginForwardingEvents(
        from transport: CodexAppServerTransport
    ) {
        transportEventTask?.cancel()
        transportGeneration &+= 1
        let generation = transportGeneration
        transportEventTask = Task { [weak self] in
            for await event in transport.events {
                guard !Task.isCancelled else { return }
                await self?.consume(
                    event,
                    generation: generation
                )
            }
        }
    }

    private func consume(
        _ event: CodexAppServerEvent,
        generation: UInt64
    ) async {
        guard generation == transportGeneration else { return }
        switch event {
        case let .accountChanged(account):
            let phase: CodexConnectionPhase
            switch account {
            case .signedOut:
                phase = .signedOut
            case .connected:
                phase = .connected
            }
            setSnapshot(
                snapshotWith(
                    phase: phase,
                    account: account,
                    quota: phase == .signedOut
                        ? nil
                        : snapshot.quota
                )
            )
        case let .quotaChanged(quota):
            setSnapshot(
                snapshotWith(
                    phase: snapshot.phase,
                    account: snapshot.account,
                    quota: quota
                )
            )
        case let .loginCompleted(_, success):
            yield(.loginCompleted(success: success))
            if success {
                Task { [weak self] in
                    do {
                        _ = try await self?.refreshAccount()
                    } catch let error
                        as CodexMeetingSessionServiceError
                    {
                        await self?.yield(
                            .safeFailure(
                                scope: nil,
                                turnID: nil,
                                category:
                                    Self.safeCategory(for: error),
                                willRetry: false
                            )
                        )
                    } catch {
                        await self?.yield(
                            .safeFailure(
                                scope: nil,
                                turnID: nil,
                                category: .unavailable,
                                willRetry: false
                            )
                        )
                    }
                }
            }
            if !success {
                yield(
                    .safeFailure(
                        scope: nil,
                        turnID: nil,
                        category: .authenticationRequired,
                        willRetry: false
                    )
                )
            }
        case let .agentMessageDelta(
            threadID,
            turnID,
            itemID,
            delta
        ):
            guard let scope =
                    scopeByThreadID[threadID]
            else { return }
            yield(
                .agentMessageDelta(
                    scope: scope,
                    turnID: turnID,
                    itemID: itemID,
                    delta: delta
                )
            )
        case let .turnCompleted(turn, status):
            guard let scope =
                    scopeByThreadID[turn.threadID]
            else { return }
            if activeTurnByScope[scope] == turn {
                activeTurnByScope.removeValue(
                    forKey: scope
                )
            }
            yield(
                .turnCompleted(
                    scope: scope,
                    turnID: turn.turnID,
                    status: status
                )
            )
        case let .safeFailure(
            threadID,
            turnID,
            category,
            willRetry
        ):
            let scope = threadID.flatMap {
                scopeByThreadID[$0]
            }
            if !willRetry,
               let scope,
               let turnID,
               activeTurnByScope[scope]?.turnID
                    == turnID
            {
                activeTurnByScope.removeValue(
                    forKey: scope
                )
            }
            yield(
                .safeFailure(
                    scope: scope,
                    turnID: turnID,
                    category: category,
                    willRetry: willRetry
                )
            )
        case .processExited:
            transport = nil
            attachedThreadIDs.removeAll()
            activeTurnByScope.removeAll()
            inFlightSendScopes.removeAll()
            _ = await discardPrivateRuntimeState()
            setSnapshot(
                snapshotWith(
                    phase: .failed,
                    account: snapshot.account,
                    quota: snapshot.quota
                )
            )
            yield(.processExited)
        case .turnStarted,
             .threadStateChanged,
             .warning:
            break
        }
    }

    private func stopTransportAndDiscardSessionDirectories()
        async -> Bool
    {
        transportEventTask?.cancel()
        transportEventTask = nil
        transportGeneration &+= 1
        if let transport,
           !(await transport.shutdown())
        {
            setSnapshot(
                snapshotWith(
                    phase: .failed,
                    account: snapshot.account,
                    quota: snapshot.quota
                )
            )
            return false
        }
        transport = nil
        sessions.removeAll()
        scopeByThreadID.removeAll()
        attachedThreadIDs.removeAll()
        activeTurnByScope.removeAll()
        inFlightSendScopes.removeAll()
        guard await discardPrivateRuntimeState()
        else {
            setSnapshot(
                snapshotWith(
                    phase: .failed,
                    account: snapshot.account,
                    quota: snapshot.quota
                )
            )
            return false
        }
        return true
    }

    private func cancelActiveConnectionAttempt()
        async
    {
        guard let attempt =
                activeConnectionAttempt
        else { return }
        attempt.task.cancel()
        _ = try? await attempt.task.value
        clearConnectionAttempt(id: attempt.id)
    }

    private func clearConnectionAttempt(
        id: UInt64
    ) {
        guard activeConnectionAttempt?.id
                == id
        else { return }
        activeConnectionAttempt = nil
    }

    /// Returns false and retains the cleanup handle when private runtime bytes
    /// could not be removed, allowing a later disconnect/reconnect to retry.
    private func discardPrivateRuntimeState() async -> Bool {
        if let environmentManager,
           let configuration
        {
            do {
                try await environmentManager
                    .removePrivateRuntimeState(
                        for: configuration
                    )
            } catch {
                sessions.removeAll()
                scopeByThreadID.removeAll()
                attachedThreadIDs.removeAll()
                activeTurnByScope.removeAll()
                inFlightSendScopes.removeAll()
                return false
            }
        }
        sessions.removeAll()
        scopeByThreadID.removeAll()
        attachedThreadIDs.removeAll()
        activeTurnByScope.removeAll()
        inFlightSendScopes.removeAll()
        self.environmentManager = nil
        configuration = nil
        return true
    }

    private func requireTransport() throws
        -> CodexAppServerTransport
    {
        guard let transport else {
            throw CodexMeetingSessionServiceError.notConnected
        }
        return transport
    }

    private func snapshotWith(
        phase: CodexConnectionPhase,
        account: CodexAccountState?,
        quota: CodexQuotaState?
    ) -> CodexConnectionSnapshot {
        CodexConnectionSnapshot(
            phase: phase,
            runtimeVersion:
                configuration?.runtimeVersion
                    ?? snapshot.runtimeVersion,
            runtimeSource:
                configuration?.runtimeSource
                    ?? snapshot.runtimeSource,
            account: account,
            quota: quota
        )
    }

    private func setSnapshot(
        _ value: CodexConnectionSnapshot
    ) {
        snapshot = value
        yield(.connectionChanged(value))
    }

    private func yield(_ event: CodexMeetingSessionEvent) {
        switch eventContinuation.yield(event) {
        case .enqueued:
            break
        case .dropped:
            snapshot = snapshotWith(
                phase: .failed,
                account: snapshot.account,
                quota: snapshot.quota
            )
        case .terminated:
            break
        @unknown default:
            break
        }
    }

    private func map(
        _ error: any Error
    ) -> CodexMeetingSessionServiceError {
        if let value =
            error as? CodexMeetingSessionServiceError
        {
            return value
        }
        if error is CodexRuntimeConfigurationError {
            return .privateStorageUnavailable
        }
        guard let value = error as? CodexAppServerError else {
            return .requestFailed(.unavailable)
        }
        switch value {
        case .serverRejected(.authenticationRequired):
            return .authenticationRequired
        case .serverRejected(.quotaUnavailable):
            return .quotaUnavailable
        case let .serverRejected(category):
            return .requestFailed(category)
        case .processExited:
            return .requestFailed(.runtimeExited)
        case .notStarted,
             .alreadyStarted,
             .requestTimedOut,
             .protocolViolation:
            return .requestFailed(.unavailable)
        }
    }

    private static func safeCategory(
        for error: CodexMeetingSessionServiceError
    ) -> CodexSafeFailureCategory {
        switch error {
        case .authenticationRequired:
            .authenticationRequired
        case .quotaUnavailable:
            .quotaUnavailable
        case let .requestFailed(category):
            category
        case .runtimeMissing,
             .runtimeUntrusted,
             .runtimeIncompatible,
             .privateStorageUnavailable,
             .notConnected,
             .requestInProgress:
            .unavailable
        }
    }
}

struct CodexMeetingSessionKey: Hashable, Sendable {
    let workspaceID: WorkspaceID
    let meetingID: MeetingID
    let meetingRevisionID: RevisionID

    init(context: CodexMeetingTextContext) {
        workspaceID = context.workspaceID
        meetingID = context.meetingID
        meetingRevisionID =
            context.meetingRevision.revisionID
    }
}
