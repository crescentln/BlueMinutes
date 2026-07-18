import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum ManagedAssetCoordinationError: Error, Sendable {
    case registrationFailed(recoverableTrashRecord: ManagedAssetRecord, cause: String)
    case metadataTransitionFailedAndCompensated(cause: String)
    case compensationFailed(cause: String, recoveryPath: WorkspaceRelativePath)
}

/// Coordinates the filesystem and metadata halves of managed-asset changes.
///
/// SQLite and the filesystem cannot share one transaction. Every operation is
/// journaled before bytes move, and startup reconciliation deterministically
/// completes or rolls back interrupted work without deleting managed bytes.
public final class ManagedAssetCoordinator: StorageService, ManagedAssetRecoveryService,
    @unchecked Sendable
{
    private enum ReconciliationOutcome {
        case reconciled
        case rolledBack
        case repairRequired
    }

    private let storage: LocalStorageService
    private let metadata: SQLitePersistenceStore
    private let operationLock = NSLock()
    private let injectedFaultPoint: ManagedAssetFaultPoint?

    public init(
        storage: LocalStorageService,
        metadata: SQLitePersistenceStore
    ) {
        self.storage = storage
        self.metadata = metadata
        injectedFaultPoint = nil
    }

    init(
        storage: LocalStorageService,
        metadata: SQLitePersistenceStore,
        injectedFaultPoint: ManagedAssetFaultPoint?
    ) {
        self.storage = storage
        self.metadata = metadata
        self.injectedFaultPoint = injectedFaultPoint
    }

    public func importFile(
        from authorizedSource: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass
    ) throws -> ManagedAssetRecord {
        try withOperationLock {
            let operationID = UUID()
            let plan = try ManagedAssetImportPlan(
                meetingID: meetingID,
                storageObjectID: storageObjectID,
                fileExtension: fileExtension,
                createdAt: createdAt,
                dataClassification: dataClassification,
                retentionClass: retentionClass
            )
            let intent = ManagedAssetOperationIntent.importing(
                operationID: operationID,
                plan: plan
            )
            try metadata.beginManagedAssetOperation(intent)
            try interruptIfInjected(.afterIntent)

            let record: ManagedAssetRecord
            do {
                record = try storage.storeFile(
                    from: authorizedSource,
                    meetingID: meetingID,
                    storageObjectID: storageObjectID,
                    fileExtension: fileExtension,
                    createdAt: createdAt,
                    dataClassification: dataClassification,
                    retentionClass: retentionClass,
                    operationID: operationID
                )
            } catch {
                try? metadata.rollBackManagedAssetOperation(
                    operationID: operationID,
                    at: createdAt
                )
                throw error
            }

            try interruptIfInjected(.afterFilesystemBeforeJournal)
            do {
                try metadata.markManagedAssetFilesystemApplied(
                    operationID: operationID,
                    resultRecord: record,
                    at: createdAt
                )
            } catch {
                try compensateFailedImport(
                    record,
                    operationID: operationID,
                    at: createdAt,
                    cause: "filesystem_journal_failed"
                )
            }
            try interruptIfInjected(.afterFilesystemJournal)

            do {
                try metadata.registerManagedAsset(record)
            } catch {
                try compensateFailedImport(
                    record,
                    operationID: operationID,
                    at: createdAt,
                    cause: "metadata_registration_failed"
                )
            }

            try interruptIfInjected(.afterMetadata)
            do {
                try metadata.completeManagedAssetOperation(
                    operationID: operationID,
                    at: createdAt
                )
            } catch {
                try? metadata.markManagedAssetOperationRepairRequired(
                    operationID: operationID,
                    resultRecord: record,
                    failureCode: "completion_journal_failed",
                    at: createdAt
                )
                throw error
            }
            return record
        }
    }

    public func moveToTrash(
        storageObjectID: StorageObjectID,
        at trashedAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        try withOperationLock {
            guard let current = try metadata.managedAsset(storageObjectID: storageObjectID) else {
                throw PersistenceContractError.managedAssetNotFound(storageObjectID)
            }
            let planned = try storage.plannedTrashRecord(for: current, at: trashedAt)
            let operationID = UUID()
            let intent = try ManagedAssetOperationIntent.transitioning(
                operationID: operationID,
                kind: .trash,
                requestedAt: trashedAt,
                beforeRecord: current,
                plannedRecord: planned
            )
            try metadata.beginManagedAssetOperation(intent)
            try interruptIfInjected(.afterIntent)

            let trashed: ManagedAssetRecord
            do {
                trashed = try storage.moveToTrash(current, at: trashedAt)
            } catch {
                try? metadata.rollBackManagedAssetOperation(
                    operationID: operationID,
                    resultRecord: current,
                    at: trashedAt
                )
                throw error
            }
            try interruptIfInjected(.afterFilesystemBeforeJournal)
            do {
                try metadata.markManagedAssetFilesystemApplied(
                    operationID: operationID,
                    resultRecord: trashed,
                    at: trashedAt
                )
            } catch {
                try compensateTrashMove(
                    trashed,
                    operationID: operationID,
                    at: trashedAt,
                    cause: "filesystem_journal_failed"
                )
            }
            try interruptIfInjected(.afterFilesystemJournal)

            do {
                try metadata.recordTrashMove(trashed)
            } catch {
                try compensateTrashMove(
                    trashed,
                    operationID: operationID,
                    at: trashedAt,
                    cause: "metadata_transition_failed"
                )
            }
            try interruptIfInjected(.afterMetadata)
            do {
                try metadata.completeManagedAssetOperation(
                    operationID: operationID,
                    at: trashedAt
                )
            } catch {
                try? metadata.markManagedAssetOperationRepairRequired(
                    operationID: operationID,
                    resultRecord: trashed,
                    failureCode: "completion_journal_failed",
                    at: trashedAt
                )
                throw error
            }
            return trashed
        }
    }

    public func restoreFromTrash(
        storageObjectID: StorageObjectID,
        at restoredAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        try withOperationLock {
            guard let current = try metadata.managedAsset(storageObjectID: storageObjectID) else {
                throw PersistenceContractError.managedAssetNotFound(storageObjectID)
            }
            guard let trashedAt = current.trashedAt, restoredAt >= trashedAt else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "A managed asset restore timestamp cannot precede its Trash transition."
                )
            }
            let planned = try storage.plannedRestoredRecord(for: current)
            let operationID = UUID()
            let intent = try ManagedAssetOperationIntent.transitioning(
                operationID: operationID,
                kind: .restore,
                requestedAt: restoredAt,
                beforeRecord: current,
                plannedRecord: planned
            )
            try metadata.beginManagedAssetOperation(intent)
            try interruptIfInjected(.afterIntent)

            let restored: ManagedAssetRecord
            do {
                restored = try storage.restoreFromTrash(current)
            } catch {
                try? metadata.rollBackManagedAssetOperation(
                    operationID: operationID,
                    resultRecord: current,
                    at: restoredAt
                )
                throw error
            }
            try interruptIfInjected(.afterFilesystemBeforeJournal)
            do {
                try metadata.markManagedAssetFilesystemApplied(
                    operationID: operationID,
                    resultRecord: restored,
                    at: restoredAt
                )
            } catch {
                try compensateTrashRestore(
                    restored,
                    originalTrashTimestamp: trashedAt,
                    operationID: operationID,
                    at: restoredAt,
                    cause: "filesystem_journal_failed"
                )
            }
            try interruptIfInjected(.afterFilesystemJournal)

            do {
                try metadata.recordTrashRestore(restored, at: restoredAt)
            } catch {
                try compensateTrashRestore(
                    restored,
                    originalTrashTimestamp: trashedAt,
                    operationID: operationID,
                    at: restoredAt,
                    cause: "metadata_transition_failed"
                )
            }
            try interruptIfInjected(.afterMetadata)
            do {
                try metadata.completeManagedAssetOperation(
                    operationID: operationID,
                    at: restoredAt
                )
            } catch {
                try? metadata.markManagedAssetOperationRepairRequired(
                    operationID: operationID,
                    resultRecord: restored,
                    failureCode: "completion_journal_failed",
                    at: restoredAt
                )
                throw error
            }
            return restored
        }
    }

    public func reconcileInterruptedOperations(
        at timestamp: UTCInstant,
        maximumOperations: UInt32
    ) async throws -> ManagedAssetRecoveryReport {
        try await Task.detached(priority: .utility) { [self] in
            try withOperationLock {
                try reconcileInterruptedOperationsLocked(
                    at: timestamp,
                    maximumOperations: maximumOperations
                )
            }
        }.value
    }

    private func reconcileInterruptedOperationsLocked(
        at timestamp: UTCInstant,
        maximumOperations: UInt32
    ) throws -> ManagedAssetRecoveryReport {
        let scan = try metadata.unfinishedManagedAssetOperations(
            maximumOperations: maximumOperations
        )
        var reconciled: UInt32 = 0
        var rolledBack: UInt32 = 0
        var repairRequired: UInt32 = 0

        for entry in scan.entries {
            let outcome: ReconciliationOutcome
            do {
                switch entry.intent.kind {
                case .import:
                    outcome = try reconcileImport(entry, at: timestamp)
                case .trash, .restore:
                    outcome = try reconcileTransition(entry, at: timestamp)
                }
            } catch {
                try metadata.markManagedAssetOperationRepairRequired(
                    operationID: entry.intent.operationID,
                    resultRecord: entry.resultRecord,
                    failureCode: "reconciliation_failed",
                    at: timestamp
                )
                outcome = .repairRequired
            }

            switch outcome {
            case .reconciled:
                reconciled += 1
            case .rolledBack:
                rolledBack += 1
            case .repairRequired:
                repairRequired += 1
            }
        }

        return ManagedAssetRecoveryReport(
            reconciledOperationCount: reconciled,
            rolledBackOperationCount: rolledBack,
            repairRequiredOperationCount: repairRequired,
            truncated: scan.truncated
        )
    }

    private func reconcileImport(
        _ entry: ManagedAssetOperationEntry,
        at timestamp: UTCInstant
    ) throws -> ReconciliationOutcome {
        guard let plan = entry.intent.importPlan,
              entry.intent.beforeRecord == nil,
              entry.intent.plannedRecord == nil
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "An import operation is missing its recovery plan."
            )
        }

        let persisted = try metadata.managedAsset(storageObjectID: plan.storageObjectID)
        let recovered = try storage.recoveredImportRecord(from: plan)
        let hasStaging = try storage.deterministicStagingFileExists(
            operationID: entry.intent.operationID
        )

        if let persisted {
            guard let recovered, recovered == persisted else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "Imported bytes and registered metadata disagree during recovery."
                )
            }
            if hasStaging {
                try storage.removeDeterministicStagingFile(operationID: entry.intent.operationID)
            }
            try metadata.completeManagedAssetOperation(
                operationID: entry.intent.operationID,
                at: timestamp
            )
            return .reconciled
        }

        if let recovered {
            if let result = entry.resultRecord {
                guard result == recovered else {
                    throw WorkspaceContractError.recoveryArtifactInvalid(
                        "The import journal result does not match recovered bytes."
                    )
                }
            }
            if entry.state == .intent {
                try metadata.markManagedAssetFilesystemApplied(
                    operationID: entry.intent.operationID,
                    resultRecord: recovered,
                    at: timestamp
                )
            }
            try metadata.registerManagedAsset(recovered)
            if hasStaging {
                try storage.removeDeterministicStagingFile(operationID: entry.intent.operationID)
            }
            try metadata.completeManagedAssetOperation(
                operationID: entry.intent.operationID,
                at: timestamp
            )
            return .reconciled
        }

        if let result = entry.resultRecord,
           result.state == .trashed,
           try storage.containsVerifiedFile(for: result)
        {
            try metadata.rollBackManagedAssetOperation(
                operationID: entry.intent.operationID,
                resultRecord: result,
                at: timestamp
            )
            return .rolledBack
        }
        if hasStaging {
            try storage.removeDeterministicStagingFile(operationID: entry.intent.operationID)
        }
        try metadata.rollBackManagedAssetOperation(
            operationID: entry.intent.operationID,
            at: timestamp
        )
        return .rolledBack
    }

    private func reconcileTransition(
        _ entry: ManagedAssetOperationEntry,
        at timestamp: UTCInstant
    ) throws -> ReconciliationOutcome {
        guard let before = entry.intent.beforeRecord,
              let planned = entry.intent.plannedRecord
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset transition is missing its before/after records."
            )
        }
        let beforeExists = try storage.containsVerifiedFile(for: before)
        let plannedExists = try storage.containsVerifiedFile(for: planned)
        let persisted = try metadata.managedAsset(storageObjectID: entry.intent.storageObjectID)

        if plannedExists, !beforeExists {
            if persisted == before {
                try applyMetadata(planned, for: entry.intent.kind, at: timestamp)
            } else if persisted != planned {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "Managed-asset metadata matches neither side of an interrupted transition."
                )
            }
            if entry.state == .intent {
                try metadata.markManagedAssetFilesystemApplied(
                    operationID: entry.intent.operationID,
                    resultRecord: planned,
                    at: timestamp
                )
            } else if let result = entry.resultRecord, result != planned {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The transition journal result does not match the filesystem."
                )
            }
            try metadata.completeManagedAssetOperation(
                operationID: entry.intent.operationID,
                at: timestamp
            )
            return .reconciled
        }

        if beforeExists, !plannedExists {
            if persisted == planned {
                try restoreMetadata(before, for: entry.intent.kind, at: timestamp)
            } else if persisted != before {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "Managed-asset metadata is missing during transition rollback."
                )
            }
            try metadata.rollBackManagedAssetOperation(
                operationID: entry.intent.operationID,
                resultRecord: before,
                at: timestamp
            )
            return .rolledBack
        }

        throw WorkspaceContractError.recoveryArtifactInvalid(
            "An interrupted managed-asset transition has ambiguous file placement."
        )
    }

    private func applyMetadata(
        _ record: ManagedAssetRecord,
        for kind: ManagedAssetOperationKind,
        at timestamp: UTCInstant
    ) throws {
        switch kind {
        case .trash:
            try metadata.recordTrashMove(record)
        case .restore:
            try metadata.recordTrashRestore(record, at: timestamp)
        case .import:
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "An import cannot use transition metadata recovery."
            )
        }
    }

    private func restoreMetadata(
        _ before: ManagedAssetRecord,
        for kind: ManagedAssetOperationKind,
        at timestamp: UTCInstant
    ) throws {
        switch kind {
        case .trash:
            try metadata.recordTrashRestore(before, at: timestamp)
        case .restore:
            try metadata.recordTrashMove(before)
        case .import:
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "An import cannot roll back transition metadata."
            )
        }
    }

    private func compensateFailedImport(
        _ record: ManagedAssetRecord,
        operationID: UUID,
        at timestamp: UTCInstant,
        cause: String
    ) throws -> Never {
        do {
            let trashed = try storage.moveToTrash(record, at: timestamp)
            do {
                try metadata.rollBackManagedAssetOperation(
                    operationID: operationID,
                    resultRecord: trashed,
                    at: timestamp
                )
            } catch {
                try? metadata.markManagedAssetOperationRepairRequired(
                    operationID: operationID,
                    resultRecord: trashed,
                    failureCode: "compensation_journal_failed",
                    at: timestamp
                )
                throw ManagedAssetCoordinationError.compensationFailed(
                    cause: "\(cause)_and_compensation_journal_failed",
                    recoveryPath: trashed.relativePath
                )
            }
            throw ManagedAssetCoordinationError.registrationFailed(
                recoverableTrashRecord: trashed,
                cause: cause
            )
        } catch let coordination as ManagedAssetCoordinationError {
            throw coordination
        } catch {
            try? metadata.markManagedAssetOperationRepairRequired(
                operationID: operationID,
                resultRecord: record,
                failureCode: "compensation_failed",
                at: timestamp
            )
            throw ManagedAssetCoordinationError.compensationFailed(
                cause: cause,
                recoveryPath: record.relativePath
            )
        }
    }

    private func compensateTrashMove(
        _ trashed: ManagedAssetRecord,
        operationID: UUID,
        at timestamp: UTCInstant,
        cause: String
    ) throws -> Never {
        do {
            let restored = try storage.restoreFromTrash(trashed)
            try metadata.rollBackManagedAssetOperation(
                operationID: operationID,
                resultRecord: restored,
                at: timestamp
            )
            throw ManagedAssetCoordinationError.metadataTransitionFailedAndCompensated(
                cause: cause
            )
        } catch let coordination as ManagedAssetCoordinationError {
            throw coordination
        } catch {
            try? metadata.markManagedAssetOperationRepairRequired(
                operationID: operationID,
                resultRecord: trashed,
                failureCode: "compensation_failed",
                at: timestamp
            )
            throw ManagedAssetCoordinationError.compensationFailed(
                cause: cause,
                recoveryPath: trashed.relativePath
            )
        }
    }

    private func compensateTrashRestore(
        _ restored: ManagedAssetRecord,
        originalTrashTimestamp: UTCInstant,
        operationID: UUID,
        at timestamp: UTCInstant,
        cause: String
    ) throws -> Never {
        do {
            let trashed = try storage.moveToTrash(restored, at: originalTrashTimestamp)
            try metadata.rollBackManagedAssetOperation(
                operationID: operationID,
                resultRecord: trashed,
                at: timestamp
            )
            throw ManagedAssetCoordinationError.metadataTransitionFailedAndCompensated(
                cause: cause
            )
        } catch let coordination as ManagedAssetCoordinationError {
            throw coordination
        } catch {
            try? metadata.markManagedAssetOperationRepairRequired(
                operationID: operationID,
                resultRecord: restored,
                failureCode: "compensation_failed",
                at: timestamp
            )
            throw ManagedAssetCoordinationError.compensationFailed(
                cause: cause,
                recoveryPath: restored.relativePath
            )
        }
    }

    private func interruptIfInjected(_ point: ManagedAssetFaultPoint) throws {
        if injectedFaultPoint == point {
            throw SimulatedManagedAssetProcessInterruption()
        }
    }

    private func withOperationLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try body()
    }
}
