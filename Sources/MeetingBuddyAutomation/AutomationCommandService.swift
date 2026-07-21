import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// The sole Task 009A command dispatcher. Transports supply a trusted caller
/// context at composition time; command payloads cannot raise their authority.
public actor AutomationCommandService: AutomationCommandExecuting {
    private static let diagnosticsDiskBudgetBytes: UInt64 = 65_536

    private let repository: any AutomationCommandRepository
    private let temporaryStorage: any TaskTemporaryStorage
    private let caller: AutomationCallerContext
    private let clock: @Sendable () throws -> UTCInstant
    private let makeUUID: @Sendable () -> UUID

    public init(
        repository: any AutomationCommandRepository,
        temporaryStorage: any TaskTemporaryStorage,
        caller: AutomationCallerContext,
        clock: @escaping @Sendable () throws -> UTCInstant = {
            try UTCInstant(
                millisecondsSinceUnixEpoch: Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded(.down)
                )
            )
        },
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.temporaryStorage = temporaryStorage
        self.caller = caller
        self.clock = clock
        self.makeUUID = makeUUID
    }

    public func execute(
        _ request: AutomationCommandRequest
    ) async throws -> AutomationCommandExecution {
        let recordedAt = try clock()
        let requestDigest = try digest(request)
        let descriptor = AutomationCommandCatalog().descriptor(for: request.command.name)

        var decision: AutomationAuthorizationDecision = .authorized
        var reasonCode = "authorized"
        var policyEvidence = AutomationPolicyEvidence.workspace
        var securityContext: AutomationSecurityContext?

        if caller.isRecursiveOrProviderOrigin {
            decision = .denied
            reasonCode = "recursive_or_provider_call_denied"
        } else if caller.maximumPermission < descriptor.permission {
            decision = .denied
            reasonCode = "permission_denied"
        } else if let meetingID = request.command.meetingID {
            do {
                let resolved = try repository.currentAutomationSecurityContext(
                    meetingID: meetingID
                )
                securityContext = resolved
                policyEvidence = try resolved.evidence
            } catch {
                decision = .denied
                reasonCode = "current_meeting_policy_unavailable"
            }
        }

        let record = try AutomationCommandRecord(
            commandID: request.commandID,
            replayNonce: request.replayNonce,
            claimsReplayNonce: true,
            replayOfCommandID: nil,
            commandName: request.command.name,
            requestDigest: requestDigest,
            caller: caller,
            meetingID: request.command.meetingID,
            requiredPermission: descriptor.permission,
            decision: decision,
            safeReasonCode: reasonCode,
            policyEvidence: policyEvidence,
            confirmationRequirement: descriptor.confirmation,
            recordedAt: recordedAt
        )
        let inputRevisions = policyInputRevisions(policyEvidence)

        switch try repository.claimAutomationCommand(record, inputRevisions: inputRevisions) {
        case .claimed:
            break
        case let .replayed(originalCommandID):
            try recordReplay(
                request: request,
                requestDigest: requestDigest,
                policyEvidence: policyEvidence,
                originalCommandID: originalCommandID,
                recordedAt: recordedAt
            )
            throw AutomationContractError.replayDetected(originalCommandID)
        case .duplicateCommandID:
            throw AutomationContractError.replayDetected(request.commandID)
        }

        guard decision == .authorized else {
            let event = try makeResultEvent(
                commandID: request.commandID,
                outcome: .rejected,
                safeCode: reasonCode,
                resultDigest: nil,
                occurredAt: recordedAt
            )
            try repository.appendAutomationResult(event)
            if reasonCode == "permission_denied" {
                throw AutomationContractError.unauthorized(reasonCode)
            }
            throw AutomationContractError.policyDenied(reasonCode)
        }

        do {
            return try await executeClaimed(
                request,
                securityContext: securityContext,
                occurredAt: recordedAt
            )
        } catch {
            let normalized = normalize(error)
            let event = try makeResultEvent(
                commandID: request.commandID,
                outcome: failureOutcome(for: normalized),
                safeCode: safeCode(for: normalized),
                resultDigest: nil,
                occurredAt: recordedAt
            )
            try? repository.appendAutomationResult(event)
            throw normalized
        }
    }

    private func executeClaimed(
        _ request: AutomationCommandRequest,
        securityContext: AutomationSecurityContext?,
        occurredAt: UTCInstant
    ) async throws -> AutomationCommandExecution {
        switch request.command {
        case .getCommandCatalog:
            return try finish(
                request,
                result: .commandCatalog(AutomationCommandCatalog()),
                occurredAt: occurredAt
            )
        case .getWorkspaceStatus:
            return try finish(
                request,
                result: .workspaceStatus(
                    try repository.automationWorkspaceStatus(
                        excludingCommandID: request.commandID
                    )
                ),
                occurredAt: occurredAt
            )
        case .getMeetingPolicyStatus:
            guard let securityContext else {
                throw AutomationContractError.policyDenied(
                    "current_meeting_policy_unavailable"
                )
            }
            return try finish(
                request,
                result: .meetingPolicyStatus(try securityContext.status),
                occurredAt: occurredAt
            )
        case let .getStorageReport(payload):
            return try finish(
                request,
                result: .storageReport(
                    try repository.automationStorageReport(
                        calculatedAt: occurredAt,
                        maximumEntries: payload.maximumEntries
                    )
                ),
                occurredAt: occurredAt
            )
        case .getSettings:
            return try finish(
                request,
                result: .settings(try repository.currentAutomationSettings()),
                occurredAt: occurredAt
            )
        case .describeSettings:
            return try finish(
                request,
                result: .settingsDescription(AutomationSettingsDescription()),
                occurredAt: occurredAt
            )
        case let .updateSettings(patch):
            return try updateSettings(
                request,
                patch: patch,
                occurredAt: occurredAt
            )
        case let .rollbackSettings(rollback):
            return try rollbackSettings(
                request,
                rollback: rollback,
                occurredAt: occurredAt
            )
        case let .listActivity(payload):
            let configured = try repository.currentAutomationSettings()
            let limit = payload.limit ?? configured.values.statusListLimit
            return try finish(
                request,
                result: .activity(
                    try repository.automationActivity(
                        limit: limit,
                        excludingCommandID: request.commandID
                    )
                ),
                occurredAt: occurredAt
            )
        case let .runWorkspaceDiagnostics(payload):
            let report = try await runDiagnostics(
                commandID: request.commandID,
                maximumEntries: payload.maximumEntries,
                occurredAt: occurredAt
            )
            return try finish(
                request,
                result: .diagnostics(report),
                usedRestrictedTaskDirectory: true,
                occurredAt: occurredAt
            )
        }
    }

    private func updateSettings(
        _ request: AutomationCommandRequest,
        patch: AutomationSettingsPatch,
        occurredAt: UTCInstant
    ) throws -> AutomationCommandExecution {
        let prior = try repository.currentAutomationSettings()
        guard prior.version == patch.expectedVersion else {
            throw AutomationContractError.settingsConflict
        }
        let replacement = try VersionedAutomationSettings(
            version: prior.version + 1,
            values: AutomationSettingsValues(statusListLimit: patch.statusListLimit),
            updatedAt: occurredAt,
            updatedByCommandID: request.commandID
        )
        let settingsEvent = try AutomationSettingsEvent(
            eventID: AutomationSettingsEventID(makeUUID()),
            commandID: request.commandID,
            prior: prior,
            replacement: replacement,
            rollbackOfCommandID: nil,
            occurredAt: occurredAt
        )
        let execution = AutomationCommandExecution(
            commandID: request.commandID,
            commandName: request.command.name,
            result: .settings(replacement)
        )
        let resultEvent = try makeResultEvent(
            commandID: request.commandID,
            outcome: .completed,
            safeCode: "settings_updated",
            resultDigest: try digest(execution),
            priorSettingsVersion: prior.version,
            replacementSettingsVersion: replacement.version,
            occurredAt: occurredAt
        )
        try repository.applyAutomationSettings(
            replacement,
            event: settingsEvent,
            result: resultEvent,
            expectedVersion: patch.expectedVersion
        )
        return execution
    }

    private func rollbackSettings(
        _ request: AutomationCommandRequest,
        rollback: AutomationSettingsRollbackRequest,
        occurredAt: UTCInstant
    ) throws -> AutomationCommandExecution {
        guard let target = try repository.automationSettingsEvent(
            commandID: rollback.targetCommandID
        ) else {
            throw AutomationContractError.invalidRequest(
                "The settings rollback target is unavailable."
            )
        }
        let prior = try repository.currentAutomationSettings()
        guard prior.version == rollback.expectedVersion,
              prior.values == target.replacement.values
        else {
            throw AutomationContractError.settingsConflict
        }
        let replacement = try VersionedAutomationSettings(
            version: prior.version + 1,
            values: target.prior.values,
            updatedAt: occurredAt,
            updatedByCommandID: request.commandID
        )
        let settingsEvent = try AutomationSettingsEvent(
            eventID: AutomationSettingsEventID(makeUUID()),
            commandID: request.commandID,
            prior: prior,
            replacement: replacement,
            rollbackOfCommandID: rollback.targetCommandID,
            occurredAt: occurredAt
        )
        let execution = AutomationCommandExecution(
            commandID: request.commandID,
            commandName: request.command.name,
            result: .settings(replacement)
        )
        let resultEvent = try makeResultEvent(
            commandID: request.commandID,
            outcome: .rolledBack,
            safeCode: "settings_rolled_back",
            resultDigest: try digest(execution),
            priorSettingsVersion: prior.version,
            replacementSettingsVersion: replacement.version,
            rollbackOfCommandID: rollback.targetCommandID,
            occurredAt: occurredAt
        )
        try repository.applyAutomationSettings(
            replacement,
            event: settingsEvent,
            result: resultEvent,
            expectedVersion: rollback.expectedVersion
        )
        return execution
    }

    private func runDiagnostics(
        commandID: AutomationCommandID,
        maximumEntries: UInt32,
        occurredAt: UTCInstant
    ) async throws -> AutomationDiagnosticsReport {
        guard let uuid = UUID(uuidString: commandID.canonicalString) else {
            throw AutomationContractError.invalidRequest("The command identifier is invalid.")
        }
        let lease = try await temporaryStorage.allocateDirectory(
            for: JobID(uuid),
            diskBudgetBytes: Self.diagnosticsDiskBudgetBytes
        )
        do {
            let report = try repository.automationDiagnostics(
                calculatedAt: occurredAt,
                maximumEntries: maximumEntries,
                usedRestrictedTaskDirectory: true,
                excludingCommandID: commandID
            )
            try await temporaryStorage.cleanupDirectory(lease)
            return report
        } catch {
            try? await temporaryStorage.cleanupDirectory(lease)
            throw error
        }
    }

    private func finish(
        _ request: AutomationCommandRequest,
        result: AutomationCommandResult,
        usedRestrictedTaskDirectory: Bool = false,
        occurredAt: UTCInstant
    ) throws -> AutomationCommandExecution {
        let execution = AutomationCommandExecution(
            commandID: request.commandID,
            commandName: request.command.name,
            result: result
        )
        let event = try makeResultEvent(
            commandID: request.commandID,
            outcome: .completed,
            safeCode: "completed",
            resultDigest: try digest(execution),
            usedRestrictedTaskDirectory: usedRestrictedTaskDirectory,
            occurredAt: occurredAt
        )
        try repository.appendAutomationResult(event)
        return execution
    }

    private func recordReplay(
        request: AutomationCommandRequest,
        requestDigest: ContentDigest,
        policyEvidence: AutomationPolicyEvidence,
        originalCommandID: AutomationCommandID,
        recordedAt: UTCInstant
    ) throws {
        let replayRecord = try AutomationCommandRecord(
            commandID: request.commandID,
            replayNonce: request.replayNonce,
            claimsReplayNonce: false,
            replayOfCommandID: originalCommandID,
            commandName: request.command.name,
            requestDigest: requestDigest,
            caller: caller,
            meetingID: request.command.meetingID,
            requiredPermission: request.command.requiredPermission,
            decision: .replayed,
            safeReasonCode: "replay_nonce_reused",
            policyEvidence: policyEvidence,
            recordedAt: recordedAt
        )
        let result = try makeResultEvent(
            commandID: request.commandID,
            outcome: .rejected,
            safeCode: "replay_nonce_reused",
            resultDigest: nil,
            occurredAt: recordedAt
        )
        try repository.recordAutomationReplay(replayRecord, result: result)
    }

    private func makeResultEvent(
        commandID: AutomationCommandID,
        outcome: AutomationCommandOutcome,
        safeCode: String,
        resultDigest: ContentDigest?,
        priorSettingsVersion: UInt64? = nil,
        replacementSettingsVersion: UInt64? = nil,
        rollbackOfCommandID: AutomationCommandID? = nil,
        usedRestrictedTaskDirectory: Bool = false,
        occurredAt: UTCInstant
    ) throws -> AutomationCommandResultEvent {
        try AutomationCommandResultEvent(
            eventID: AutomationAuditEventID(makeUUID()),
            commandID: commandID,
            outcome: outcome,
            safeCode: safeCode,
            resultDigest: resultDigest,
            priorSettingsVersion: priorSettingsVersion,
            replacementSettingsVersion: replacementSettingsVersion,
            rollbackOfCommandID: rollbackOfCommandID,
            usedRestrictedTaskDirectory: usedRestrictedTaskDirectory,
            occurredAt: occurredAt
        )
    }

    private func digest<Value: Encodable>(_ value: Value) throws -> ContentDigest {
        let bytes = try CanonicalJSON.encode(value)
        return try ContentDigest.sha256(ofUTF8Text: String(decoding: bytes, as: UTF8.self))
    }

    private func policyInputRevisions(
        _ evidence: AutomationPolicyEvidence
    ) -> [SemanticRevisionReference] {
        [
            evidence.meetingRevision,
            evidence.sensitivityLabelRevision,
            evidence.accessPolicyRevision
        ].compactMap { $0 }.sorted()
    }

    private func normalize(_ error: Error) -> AutomationContractError {
        if let error = error as? AutomationContractError { return error }
        return .persistenceFailure("automation_operation_failed")
    }

    private func failureOutcome(
        for error: AutomationContractError
    ) -> AutomationCommandOutcome {
        switch error {
        case .invalidRequest, .unauthorized, .policyDenied, .replayDetected,
             .settingsConflict, .commandUnavailable:
            .rejected
        case .invalidCaller, .persistenceFailure:
            .failed
        }
    }

    private func safeCode(for error: AutomationContractError) -> String {
        switch error {
        case .invalidRequest: "invalid_request"
        case .invalidCaller: "invalid_caller"
        case .unauthorized: "permission_denied"
        case .policyDenied: "policy_denied"
        case .replayDetected: "replay_detected"
        case .settingsConflict: "settings_conflict"
        case .commandUnavailable: "command_unavailable"
        case .persistenceFailure: "automation_operation_failed"
        }
    }
}
