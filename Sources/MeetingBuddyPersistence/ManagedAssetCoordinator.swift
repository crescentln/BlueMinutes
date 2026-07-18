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
/// SQLite and the filesystem cannot share one transaction. This service uses
/// synchronous compensation and never permanently deletes bytes. Task 004B
/// remains responsible for startup reconciliation after process interruption.
public final class ManagedAssetCoordinator: StorageService, @unchecked Sendable {
    private let storage: LocalStorageService
    private let metadata: SQLitePersistenceStore

    public init(
        storage: LocalStorageService,
        metadata: SQLitePersistenceStore
    ) {
        self.storage = storage
        self.metadata = metadata
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
        let record = try storage.storeFile(
            from: authorizedSource,
            meetingID: meetingID,
            storageObjectID: storageObjectID,
            fileExtension: fileExtension,
            createdAt: createdAt,
            dataClassification: dataClassification,
            retentionClass: retentionClass
        )
        do {
            try metadata.registerManagedAsset(record)
            return record
        } catch {
            do {
                let trashed = try storage.moveToTrash(record, at: createdAt)
                throw ManagedAssetCoordinationError.registrationFailed(
                    recoverableTrashRecord: trashed,
                    cause: String(describing: error)
                )
            } catch let coordination as ManagedAssetCoordinationError {
                throw coordination
            } catch {
                throw ManagedAssetCoordinationError.compensationFailed(
                    cause: String(describing: error),
                    recoveryPath: record.relativePath
                )
            }
        }
    }

    public func moveToTrash(
        storageObjectID: StorageObjectID,
        at trashedAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        guard let current = try metadata.managedAsset(storageObjectID: storageObjectID) else {
            throw PersistenceContractError.managedAssetNotFound(storageObjectID)
        }
        guard trashedAt >= current.createdAt else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset cannot enter Trash before it was created."
            )
        }
        let trashed = try storage.moveToTrash(current, at: trashedAt)
        do {
            try metadata.recordTrashMove(trashed)
            return trashed
        } catch {
            do {
                _ = try storage.restoreFromTrash(trashed)
                throw ManagedAssetCoordinationError.metadataTransitionFailedAndCompensated(
                    cause: String(describing: error)
                )
            } catch let coordination as ManagedAssetCoordinationError {
                throw coordination
            } catch {
                throw ManagedAssetCoordinationError.compensationFailed(
                    cause: String(describing: error),
                    recoveryPath: trashed.relativePath
                )
            }
        }
    }

    public func restoreFromTrash(
        storageObjectID: StorageObjectID,
        at restoredAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        guard let current = try metadata.managedAsset(storageObjectID: storageObjectID) else {
            throw PersistenceContractError.managedAssetNotFound(storageObjectID)
        }
        guard let trashedAt = current.trashedAt, restoredAt >= trashedAt else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset restore timestamp cannot precede its Trash transition."
            )
        }
        let restored = try storage.restoreFromTrash(current)
        do {
            try metadata.recordTrashRestore(restored, at: restoredAt)
            return restored
        } catch {
            do {
                _ = try storage.moveToTrash(restored, at: trashedAt)
                throw ManagedAssetCoordinationError.metadataTransitionFailedAndCompensated(
                    cause: String(describing: error)
                )
            } catch let coordination as ManagedAssetCoordinationError {
                throw coordination
            } catch {
                throw ManagedAssetCoordinationError.compensationFailed(
                    cause: String(describing: error),
                    recoveryPath: restored.relativePath
                )
            }
        }
    }
}
