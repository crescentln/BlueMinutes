import Foundation
import MeetingBuddyDomain

public enum WorkspaceStorageCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case meetings
    case audio
    case documents
    case models
    case database
    case indexes
    case backups
    case temporary
    case logsAndCache = "logs_and_cache"
    case trash
    case other
}

public struct WorkspaceStorageCategoryUsage: Codable, Hashable, Sendable {
    public let category: WorkspaceStorageCategory
    public let byteCount: UInt64
    public let fileCount: UInt64

    public init(
        category: WorkspaceStorageCategory,
        byteCount: UInt64,
        fileCount: UInt64
    ) {
        self.category = category
        self.byteCount = byteCount
        self.fileCount = fileCount
    }
}

public struct WorkspaceTrashItem: Codable, Hashable, Sendable, Identifiable {
    public let storageObjectID: StorageObjectID
    public let byteSize: UInt64
    public let trashedAt: UTCInstant
    public let purgeEligibleAt: UTCInstant
    public let dataClassification: DataClassification
    public let retentionClass: RetentionClass

    public var id: StorageObjectID { storageObjectID }

    public init(
        storageObjectID: StorageObjectID,
        byteSize: UInt64,
        trashedAt: UTCInstant,
        purgeEligibleAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass
    ) {
        self.storageObjectID = storageObjectID
        self.byteSize = byteSize
        self.trashedAt = trashedAt
        self.purgeEligibleAt = purgeEligibleAt
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
    }
}

public struct WorkspaceStorageReport: Codable, Hashable, Sendable {
    public let calculatedAt: UTCInstant
    public let totalByteCount: UInt64
    public let categories: [WorkspaceStorageCategoryUsage]
    public let trashItems: [WorkspaceTrashItem]
    public let permissionIssueCount: UInt64
    public let scanTruncated: Bool

    public init(
        calculatedAt: UTCInstant,
        totalByteCount: UInt64,
        categories: [WorkspaceStorageCategoryUsage],
        trashItems: [WorkspaceTrashItem],
        permissionIssueCount: UInt64,
        scanTruncated: Bool
    ) throws {
        let ordered = categories.sorted { $0.category.rawValue < $1.category.rawValue }
        guard Set(ordered.map(\.category)).count == ordered.count,
              ordered.reduce(UInt64(0), { partial, usage in
                  let (sum, overflow) = partial.addingReportingOverflow(usage.byteCount)
                  return overflow ? UInt64.max : sum
              }) == totalByteCount
        else {
            throw WorkspaceContractError.managedAssetMismatch(
                "The storage report categories do not match its total."
            )
        }
        self.calculatedAt = calculatedAt
        self.totalByteCount = totalByteCount
        self.categories = ordered
        self.trashItems = trashItems.sorted {
            ($0.trashedAt, $0.storageObjectID) < ($1.trashedAt, $1.storageObjectID)
        }
        self.permissionIssueCount = permissionIssueCount
        self.scanTruncated = scanTruncated
    }
}

public protocol WorkspaceStorageReporting: Sendable {
    func storageReport(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32
    ) throws -> WorkspaceStorageReport
}
