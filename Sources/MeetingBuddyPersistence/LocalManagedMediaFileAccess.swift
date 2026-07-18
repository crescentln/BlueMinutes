import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class LocalManagedMediaFileAccess: ManagedMediaFileAccess, @unchecked Sendable {
    private let storage: LocalStorageService
    private let metadata: SQLitePersistenceStore

    public init(
        storage: LocalStorageService,
        metadata: SQLitePersistenceStore
    ) {
        self.storage = storage
        self.metadata = metadata
    }

    public func verifiedFileURL(for reference: ManagedAssetReference) throws -> URL {
        guard let record = try metadata.managedAsset(
            storageObjectID: reference.storageObjectID
        ) else {
            throw MediaContractError.managedSourceUnavailable(reference.storageObjectID)
        }
        return try storage.verifiedFileURL(for: record)
    }
}
