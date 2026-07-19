import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class LocalWorkspaceStorageReporter: WorkspaceStorageReporting,
    @unchecked Sendable
{
    private let workspace: LocalWorkspaceDescriptor
    private let store: SQLitePersistenceStore
    private let fileManager: FileManager

    public init(
        workspace: LocalWorkspaceDescriptor,
        store: SQLitePersistenceStore,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.store = store
        self.fileManager = fileManager
    }

    public func storageReport(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32
    ) throws -> WorkspaceStorageReport {
        guard maximumEntries > 0, maximumEntries <= 1_000_000 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Workspace storage inspection requires a bounded entry count."
            )
        }
        let root = try WorkspacePathSecurity.confinedURL(
            workspace.layout.root,
            within: workspace.layout.root
        )
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw WorkspaceContractError.managedAssetMismatch(
                "The workspace storage inventory could not start."
            )
        }

        var byteCounts = Dictionary(
            uniqueKeysWithValues: WorkspaceStorageCategory.allCases.map { ($0, UInt64(0)) }
        )
        var fileCounts = Dictionary(
            uniqueKeysWithValues: WorkspaceStorageCategory.allCases.map { ($0, UInt64(0)) }
        )
        var permissionIssues: UInt64 = 0
        var inspected: UInt32 = 0
        var scanTruncated = false

        while let candidate = enumerator.nextObject() as? URL {
            if inspected == maximumEntries {
                scanTruncated = true
                break
            }
            inspected += 1
            let url = try WorkspacePathSecurity.confinedURL(
                candidate,
                within: root
            )
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                permissionIssues += 1
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true {
                if try posixMode(at: url) & 0o077 != 0 {
                    permissionIssues += 1
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            if try posixMode(at: url) & 0o077 != 0 {
                permissionIssues += 1
            }
            let byteCount = UInt64(max(values.fileSize ?? 0, 0))
            let relativePath = try relativePath(for: url, root: root)
            let category = category(for: relativePath)
            byteCounts[category] = try adding(byteCount, to: byteCounts[category] ?? 0)
            fileCounts[category] = try adding(1, to: fileCounts[category] ?? 0)
        }

        let requestedAssets = maximumEntries == 1_000_000
            ? maximumEntries
            : maximumEntries + 1
        let assets = try store.managedAssets(maximumEntries: requestedAssets)
        if assets.count > Int(maximumEntries) { scanTruncated = true }
        var trashItems: [WorkspaceTrashItem] = []
        for record in assets.prefix(Int(maximumEntries)) where record.state == .trashed {
            guard try store.managedAssetPurgeReceipt(
                storageObjectID: record.storageObjectID
            ) == nil,
                let trashedAt = record.trashedAt
            else { continue }
            trashItems.append(
                WorkspaceTrashItem(
                    storageObjectID: record.storageObjectID,
                    byteSize: record.byteSize,
                    trashedAt: trashedAt,
                    purgeEligibleAt: try ManagedAssetPurgeAuthorization.purgeEligibleAt(
                        trashedAt: trashedAt
                    ),
                    dataClassification: record.dataClassification,
                    retentionClass: record.retentionClass
                )
            )
        }

        let categories = WorkspaceStorageCategory.allCases.map {
            WorkspaceStorageCategoryUsage(
                category: $0,
                byteCount: byteCounts[$0] ?? 0,
                fileCount: fileCounts[$0] ?? 0
            )
        }
        let total = try categories.reduce(UInt64(0)) {
            try adding($1.byteCount, to: $0)
        }
        return try WorkspaceStorageReport(
            calculatedAt: calculatedAt,
            totalByteCount: total,
            categories: categories,
            trashItems: trashItems,
            permissionIssueCount: permissionIssues,
            scanTruncated: scanTruncated
        )
    }

    private func category(for relativePath: String) -> WorkspaceStorageCategory {
        let components = relativePath.split(separator: "/")
        guard let first = components.first else { return .other }
        switch first {
        case "Meetings":
            if components.count >= 3, components[2] == "assets" { return .audio }
            if components.count >= 3, components[2] == "documents" { return .documents }
            return .meetings
        case "Models": return .models
        case "Database": return .database
        case "Indexes": return .indexes
        case "Backups": return .backups
        case ".tasks", ".temp": return .temporary
        case "Logs", "Cache", "Caches": return .logsAndCache
        case ".Trash": return .trash
        default: return .other
        }
    }

    private func relativePath(for url: URL, root: URL) throws -> String {
        let prefix = root.path + "/"
        guard url.path.hasPrefix(prefix) else {
            throw WorkspaceContractError.pathEscapesWorkspace(url.path)
        }
        return String(url.path.dropFirst(prefix.count))
    }

    private func posixMode(at url: URL) throws -> UInt16 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A workspace item has no POSIX permission metadata."
            )
        }
        return permissions.uint16Value
    }

    private func adding(_ value: UInt64, to current: UInt64) throws -> UInt64 {
        let (result, overflow) = current.addingReportingOverflow(value)
        guard !overflow else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Workspace storage accounting exceeded the supported range."
            )
        }
        return result
    }
}
