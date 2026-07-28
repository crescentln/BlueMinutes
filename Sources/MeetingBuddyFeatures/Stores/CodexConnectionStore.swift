import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

public enum CodexConversationRole:
    String,
    Hashable,
    Sendable
{
    case user
    case assistant
}

public enum CodexConversationMessageStatus:
    String,
    Hashable,
    Sendable
{
    case pending
    case streaming
    case completed
    case interrupted
    case failed
}

public struct CodexConversationMessage:
    Identifiable,
    Hashable,
    Sendable
{
    public let id: String
    public let role: CodexConversationRole
    public private(set) var text: String
    public private(set) var status:
        CodexConversationMessageStatus
    public let turnID: String?

    init(
        id: String,
        role: CodexConversationRole,
        text: String,
        status: CodexConversationMessageStatus,
        turnID: String?
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.turnID = turnID
    }

    mutating func append(_ delta: String) {
        text.append(delta)
        status = .streaming
    }

    mutating func complete(
        _ status: CodexConversationMessageStatus
    ) {
        self.status = status
    }
}

@MainActor
@Observable
public final class CodexConnectionStore {
    public private(set) var snapshot =
        CodexConnectionSnapshot(phase: .disconnected)
    public private(set) var loginChallenge:
        CodexLoginChallenge?
    public private(set) var isWorking = false
    public private(set) var safeErrorMessage: String?
    public private(set) var messagesByScope:
        [CodexConversationScope:
            [CodexConversationMessage]] = [:]
    public private(set) var activeTurnByScope:
        [CodexConversationScope: String] = [:]

    @ObservationIgnored
    private let service: any CodexMeetingSessionServing
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var inFlightSendScopes =
        Set<CodexConversationScope>()

    public init(service: any CodexMeetingSessionServing) {
        self.service = service
        let events = service.events
        observationTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else {
                    return
                }
                consume(event)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    public var isConnected: Bool {
        snapshot.phase == .connected
    }

    public var isSignedOut: Bool {
        snapshot.phase == .signedOut
    }

    public var requiresTerminationCleanup: Bool {
        snapshot.phase != .disconnected
            || isWorking
            || !activeTurnByScope.isEmpty
            || !inFlightSendScopes.isEmpty
    }

    public func messages(
        for scope: CodexConversationScope?
    ) -> [CodexConversationMessage] {
        guard let scope else { return [] }
        return messagesByScope[scope] ?? []
    }

    public func hasActiveTurn(
        for scope: CodexConversationScope?
    ) -> Bool {
        guard let scope else { return false }
        return activeTurnByScope[scope] != nil
            || inFlightSendScopes.contains(scope)
    }

    public func connect() async {
        await perform {
            snapshot = try await service.connect()
        }
    }

    public func reconnect() async {
        await perform {
            snapshot = try await service.reconnect()
            finishActiveMessagesAsInterrupted()
        }
    }

    public func testConnection() async {
        await perform {
            snapshot = try await service.testConnection()
        }
    }

    public func startBrowserLogin() async {
        await perform {
            loginChallenge =
                try await service.startBrowserLogin()
        }
    }

    public func startDeviceCodeLogin() async {
        await perform {
            loginChallenge =
                try await service.startDeviceCodeLogin()
        }
    }

    public func cancelLogin() async {
        guard let loginChallenge else { return }
        await perform {
            try await service.cancelLogin(
                loginID: loginChallenge.loginID
            )
            self.loginChallenge = nil
        }
    }

    public func refreshAccount() async {
        await perform {
            snapshot = try await service.refreshAccount()
        }
    }

    public func logout() async {
        await perform {
            snapshot = try await service.logout()
            loginChallenge = nil
        }
    }

    public func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        safeErrorMessage = nil
        await service.disconnect()
        snapshot = await service.currentSnapshot()
        loginChallenge = nil
        finishActiveMessagesAsInterrupted()
        isWorking = false
    }

    public func shutdownForApplicationTermination()
        async -> Bool
    {
        await service.disconnect()
        snapshot = await service.currentSnapshot()
        loginChallenge = nil
        finishActiveMessagesAsInterrupted()
        isWorking = false
        return snapshot.phase == .disconnected
    }

    public func send(
        _ request: CodexMeetingTurnRequest
    ) async -> Bool {
        let scope = CodexConversationScope(
            context: request.context
        )
        guard !hasActiveTurn(
            for: scope
        ),
            inFlightSendScopes.insert(scope).inserted
        else {
            safeErrorMessage =
                "Stop the active Codex response before sending another request."
            return false
        }
        defer {
            inFlightSendScopes.remove(scope)
        }
        let pendingMessageID =
            "user:\(UUID().uuidString.lowercased())"
        messagesByScope[scope, default: []].append(
            CodexConversationMessage(
                id: pendingMessageID,
                role: .user,
                text: request.prompt,
                status: .pending,
                turnID: nil
            )
        )
        safeErrorMessage = nil
        do {
            let handle = try await service.send(request)
            activeTurnByScope[scope] = handle.turnID
            updateMessage(
                pendingMessageID,
                for: scope
            ) {
                $0.complete(.completed)
            }
            return true
        } catch {
            updateMessage(
                pendingMessageID,
                for: scope
            ) {
                $0.complete(.failed)
            }
            safeErrorMessage = safeMessage(for: error)
            return false
        }
    }

    public func interrupt(
        scope: CodexConversationScope
    ) async {
        guard hasActiveTurn(for: scope) else { return }
        do {
            try await service.interrupt(scope: scope)
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func clearThread(
        scope: CodexConversationScope
    ) async {
        guard !hasActiveTurn(for: scope) else {
            safeErrorMessage =
                "Stop the active Codex response before starting a new thread."
            return
        }
        do {
            try await service.clearThread(scope: scope)
            messagesByScope.removeValue(forKey: scope)
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func clearError() {
        safeErrorMessage = nil
    }

    private func perform(
        _ operation: () async throws -> Void
    ) async {
        guard !isWorking else { return }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            safeErrorMessage = safeMessage(for: error)
            snapshot = await service.currentSnapshot()
        }
    }

    private func consume(
        _ event: CodexMeetingSessionEvent
    ) {
        switch event {
        case let .connectionChanged(value):
            snapshot = value
            if value.phase == .disconnected {
                finishActiveMessagesAsInterrupted()
            }
        case let .loginChallenge(challenge):
            loginChallenge = challenge
        case let .loginCompleted(success):
            if success {
                loginChallenge = nil
            } else {
                safeErrorMessage =
                    "Codex sign-in did not complete."
            }
        case let .agentMessageDelta(
            scope,
            turnID,
            itemID,
            delta
        ):
            let messageID =
                "assistant:\(turnID):\(itemID)"
            if messageIndex(
                messageID,
                for: scope
            ) == nil {
                messagesByScope[
                    scope,
                    default: []
                ].append(
                    CodexConversationMessage(
                        id: messageID,
                        role: .assistant,
                        text: "",
                        status: .streaming,
                        turnID: turnID
                    )
                )
            }
            updateMessage(messageID, for: scope) {
                $0.append(delta)
            }
            activeTurnByScope[scope] = turnID
        case let .turnCompleted(
            scope,
            turnID,
            status
        ):
            if activeTurnByScope[scope] == turnID {
                activeTurnByScope.removeValue(
                    forKey: scope
                )
            }
            let messageStatus:
                CodexConversationMessageStatus
            switch status {
            case .completed:
                messageStatus = .completed
            case .interrupted:
                messageStatus = .interrupted
            case .failed:
                messageStatus = .failed
            }
            for index in messagesByScope[
                scope,
                default: []
            ].indices where messagesByScope[
                scope,
                default: []
            ][index].turnID == turnID {
                messagesByScope[
                    scope,
                    default: []
                ][index].complete(messageStatus)
            }
        case let .safeFailure(
            scope,
            turnID,
            category,
            willRetry
        ):
            if !willRetry,
               let scope,
               let turnID,
               activeTurnByScope[scope] == turnID
            {
                activeTurnByScope.removeValue(
                    forKey: scope
                )
            }
            safeErrorMessage = safeMessage(for: category)
        case .processExited:
            finishActiveMessagesAsInterrupted()
            safeErrorMessage =
                "The isolated Codex runtime exited. Reconnect to continue."
        }
    }

    private func updateMessage(
        _ messageID: String,
        for scope: CodexConversationScope,
        update: (inout CodexConversationMessage) -> Void
    ) {
        guard let index = messageIndex(
            messageID,
            for: scope
        ) else { return }
        update(
            &messagesByScope[scope, default: []][index]
        )
    }

    private func messageIndex(
        _ messageID: String,
        for scope: CodexConversationScope
    ) -> Int? {
        messagesByScope[scope]?.firstIndex {
            $0.id == messageID
        }
    }

    private func finishActiveMessagesAsInterrupted() {
        activeTurnByScope.removeAll()
        inFlightSendScopes.removeAll()
        for scope in Array(messagesByScope.keys) {
            for index in messagesByScope[
                scope,
                default: []
            ].indices {
                switch messagesByScope[
                    scope,
                    default: []
                ][index].status {
                case .pending, .streaming:
                    messagesByScope[
                        scope,
                        default: []
                    ][index].complete(
                        .interrupted
                    )
                case .completed,
                     .interrupted,
                     .failed:
                    break
                }
            }
        }
    }

    private func safeMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription
        {
            return description
        }
        return "Codex is currently unavailable. No meeting text was sent."
    }

    private func safeMessage(
        for category: CodexSafeFailureCategory
    ) -> String {
        switch category {
        case .authenticationRequired:
            "Sign in to Codex with ChatGPT before sending text."
        case .quotaUnavailable:
            "Codex quota is currently unavailable. Non-AI meeting features remain available."
        case .networkUnavailable:
            "Codex could not reach its service. No provider fallback was used."
        case .runtimeExited:
            "The isolated Codex runtime exited. Reconnect to continue."
        case .requestRejected:
            "Codex rejected this text request. No provider fallback was used."
        case .contextWindowExceeded:
            "The selected transcript text exceeds the Codex context window."
        case .interrupted:
            "Codex generation was stopped."
        case .unavailable:
            "Codex is currently unavailable. No provider fallback was used."
        }
    }
}
