import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class LocalStorageService: @unchecked Sendable {
    private static let chunkSize = 1_048_576

    private let workspace: LocalWorkspaceDescriptor
    private let fileManager: FileManager

    public init(
        workspace: LocalWorkspaceDescriptor,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func storeFile(
        from source: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass,
        operationID: UUID? = nil,
        maximumByteSize: UInt64? = nil,
        cancellationCheck: @Sendable () throws -> Void = {}
    ) throws -> ManagedAssetRecord {
        try cancellationCheck()
        guard maximumByteSize.map({ $0 > 0 }) ?? true else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A managed asset byte limit must be positive."
            )
        }
        guard dataClassification.isKnown, retentionClass.isKnown else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Managed asset classification and retention must be recognized before intake."
            )
        }
        try rejectSymbolicLink(source)
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Only regular files can become managed assets."
            )
        }

        let normalizedExtension = fileExtension?.rawValue
        let meetingRoot = workspace.layout.meetings
            .appendingPathComponent(meetingID.canonicalString, isDirectory: true)
        let meetingDirectory = meetingRoot.appendingPathComponent("assets", isDirectory: true)
        try createPrivateDirectory(meetingRoot)
        try createPrivateDirectory(meetingDirectory)

        let filename = storageObjectID.canonicalString
            + (normalizedExtension.map { ".\($0)" } ?? "")
        let destination = meetingDirectory.appendingPathComponent(filename)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A managed asset destination already exists."
            )
        }
        let relativePath = try workspaceRelativePath(for: destination, allowMissingLeaf: true)

        let staging = operationID.map(stagingFileURL)
            ?? workspace.layout.temporary
                .appendingPathComponent("storage-\(UUID().uuidString.lowercased()).partial")
        try ensureConfined(staging, allowMissingLeaf: true)
        guard !fileManager.fileExists(atPath: staging.path) else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset operation already owns its deterministic staging file."
            )
        }
        guard fileManager.createFile(atPath: staging.path, contents: nil) else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A private staging file could not be created."
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        var movedToDestination = false
        do {
            let (digest, byteSize) = try copyAndHash(
                from: source,
                to: staging,
                maximumByteSize: maximumByteSize,
                cancellationCheck: cancellationCheck
            )
            guard byteSize > 0 else {
                throw WorkspaceContractError.managedAssetMismatch(
                    "A managed asset must contain at least one byte."
                )
            }
            let record = try ManagedAssetRecord(
                storageObjectID: storageObjectID,
                meetingID: meetingID,
                relativePath: relativePath,
                contentHash: digest,
                byteSize: byteSize,
                createdAt: createdAt,
                dataClassification: dataClassification,
                retentionClass: retentionClass
            )
            try fileManager.moveItem(at: staging, to: destination)
            movedToDestination = true
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return record
        } catch {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
            if movedToDestination, fileManager.fileExists(atPath: destination.path) {
                do {
                    try fileManager.removeItem(at: destination)
                } catch let cleanupError {
                    throw WorkspaceContractError.managedAssetMismatch(
                        "Managed-file intake failed and its unregistered copy could not be removed: \(cleanupError)"
                    )
                }
            }
            throw error
        }
    }

    func verifyFile(for record: ManagedAssetRecord) throws {
        let file = try confinedURL(for: record.relativePath)
        try rejectSymbolicLink(file)
        let (digest, byteSize) = try hashFile(at: file)
        guard digest == record.contentHash, byteSize == record.byteSize else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Managed asset bytes do not match recorded hash and size."
            )
        }
    }

    func verifiedFileURL(for record: ManagedAssetRecord) throws -> URL {
        guard record.state == .active else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Only an active managed asset can be opened for media processing."
            )
        }
        try verifyFile(for: record)
        return try confinedURL(for: record.relativePath)
    }

    func containsVerifiedFile(for record: ManagedAssetRecord) throws -> Bool {
        let file = try confinedURL(for: record.relativePath, allowMissingLeaf: true)
        guard fileManager.fileExists(atPath: file.path) else {
            return false
        }
        try verifyFile(for: record)
        return true
    }

    func recoveredImportRecord(
        from plan: ManagedAssetImportPlan
    ) throws -> ManagedAssetRecord? {
        let destination = importDestinationURL(
            meetingID: plan.meetingID,
            storageObjectID: plan.storageObjectID,
            fileExtension: plan.fileExtension
        )
        try ensureConfined(destination, allowMissingLeaf: true)
        guard fileManager.fileExists(atPath: destination.path) else {
            return nil
        }
        try rejectSymbolicLink(destination)
        let values = try destination.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset import destination is not a regular file."
            )
        }
        let (digest, byteSize) = try hashFile(at: destination)
        guard byteSize > 0 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A recovered managed asset cannot be empty."
            )
        }
        return try ManagedAssetRecord(
            storageObjectID: plan.storageObjectID,
            meetingID: plan.meetingID,
            relativePath: workspaceRelativePath(for: destination),
            contentHash: digest,
            byteSize: byteSize,
            createdAt: plan.createdAt,
            dataClassification: plan.dataClassification,
            retentionClass: plan.retentionClass
        )
    }

    func deterministicStagingFileExists(operationID: UUID) throws -> Bool {
        let staging = stagingFileURL(operationID)
        try ensureConfined(staging, allowMissingLeaf: true)
        guard fileManager.fileExists(atPath: staging.path) else {
            return false
        }
        try rejectSymbolicLink(staging)
        let values = try staging.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset staging artifact is not a regular file."
            )
        }
        return true
    }

    func removeDeterministicStagingFile(operationID: UUID) throws {
        guard try deterministicStagingFileExists(operationID: operationID) else {
            return
        }
        try fileManager.removeItem(at: stagingFileURL(operationID))
    }

    func plannedTrashRecord(
        for record: ManagedAssetRecord,
        at trashedAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        guard record.state == .active, record.trashedAt == nil else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Only an active managed asset can move to Trash."
            )
        }
        guard trashedAt >= record.createdAt else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset cannot enter Trash before it was created."
            )
        }
        try verifyFile(for: record)
        let source = try confinedURL(for: record.relativePath)
        let destination = workspace.layout.trash
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(record.storageObjectID.canonicalString, isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
        try ensureConfined(destination, allowMissingLeaf: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceContractError.invalidStorageTransition(
                "The managed asset already has a Trash destination."
            )
        }
        return try ManagedAssetRecord(
            storageObjectID: record.storageObjectID,
            meetingID: record.meetingID,
            relativePath: workspaceRelativePath(for: destination, allowMissingLeaf: true),
            originalRelativePath: record.originalRelativePath,
            contentHash: record.contentHash,
            byteSize: record.byteSize,
            createdAt: record.createdAt,
            dataClassification: record.dataClassification,
            retentionClass: record.retentionClass,
            state: .trashed,
            trashedAt: trashedAt
        )
    }

    func plannedRestoredRecord(for record: ManagedAssetRecord) throws -> ManagedAssetRecord {
        guard record.state == .trashed, record.trashedAt != nil else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Only a trashed managed asset can be restored."
            )
        }
        try verifyFile(for: record)
        let destination = try confinedURL(
            for: record.originalRelativePath,
            allowMissingLeaf: true
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceContractError.invalidStorageTransition(
                "The original managed asset location is occupied."
            )
        }
        return try ManagedAssetRecord(
            storageObjectID: record.storageObjectID,
            meetingID: record.meetingID,
            relativePath: record.originalRelativePath,
            originalRelativePath: record.originalRelativePath,
            contentHash: record.contentHash,
            byteSize: record.byteSize,
            createdAt: record.createdAt,
            dataClassification: record.dataClassification,
            retentionClass: record.retentionClass
        )
    }

    func moveToTrash(
        _ record: ManagedAssetRecord,
        at trashedAt: UTCInstant
    ) throws -> ManagedAssetRecord {
        let trashed = try plannedTrashRecord(for: record, at: trashedAt)
        let source = try confinedURL(for: record.relativePath)
        let trashAssets = workspace.layout.trash.appendingPathComponent("assets", isDirectory: true)
        let trashDirectory = trashAssets
            .appendingPathComponent(record.storageObjectID.canonicalString, isDirectory: true)
        try createPrivateDirectory(trashAssets)
        try createPrivateDirectory(trashDirectory)
        let destination = trashDirectory.appendingPathComponent(source.lastPathComponent)
        try fileManager.moveItem(at: source, to: destination)
        return trashed
    }

    func restoreFromTrash(_ record: ManagedAssetRecord) throws -> ManagedAssetRecord {
        let restored = try plannedRestoredRecord(for: record)
        let source = try confinedURL(for: record.relativePath)
        let destination = try confinedURL(for: record.originalRelativePath, allowMissingLeaf: true)
        try createPrivateDirectory(destination.deletingLastPathComponent())
        try fileManager.moveItem(at: source, to: destination)
        return restored
    }

    func permanentlyUnlinkFromTrash(_ record: ManagedAssetRecord) throws {
        guard record.state == .trashed, record.trashedAt != nil else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Only a verified Trash item can be permanently unlinked."
            )
        }
        try verifyFile(for: record)
        let source = try confinedURL(for: record.relativePath)
        try fileManager.removeItem(at: source)
    }

    private func copyAndHash(
        from source: URL,
        to destination: URL,
        maximumByteSize: UInt64?,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> (ContentDigest, UInt64) {
        let sourceHandle = try FileHandle(forReadingFrom: source)
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        var hasher = SHA256()
        var total: UInt64 = 0
        while let data = try sourceHandle.read(upToCount: Self.chunkSize), !data.isEmpty {
            try cancellationCheck()
            let (next, overflow) = total.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw WorkspaceContractError.managedAssetMismatch(
                    "Managed asset size exceeded the supported range."
                )
            }
            guard maximumByteSize.map({ next <= $0 }) ?? true else {
                throw WorkspaceContractError.managedAssetMismatch(
                    "The selected source exceeded its inspected byte size during intake."
                )
            }
            hasher.update(data: data)
            try destinationHandle.write(contentsOf: data)
            total = next
        }
        try cancellationCheck()
        try destinationHandle.synchronize()
        return (try digest(from: hasher.finalize()), total)
    }

    private func hashFile(at url: URL) throws -> (ContentDigest, UInt64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: UInt64 = 0
        while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
            hasher.update(data: data)
            let (next, overflow) = total.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw WorkspaceContractError.managedAssetMismatch(
                    "Managed asset size exceeded the supported range."
                )
            }
            total = next
        }
        return (try digest(from: hasher.finalize()), total)
    }

    private func digest<D: Sequence>(from bytes: D) throws -> ContentDigest where D.Element == UInt8 {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: hex)
    }

    private func stagingFileURL(_ operationID: UUID) -> URL {
        workspace.layout.temporary.appendingPathComponent(
            "managed-asset-\(operationID.uuidString.lowercased()).partial"
        )
    }

    private func importDestinationURL(
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?
    ) -> URL {
        let filename = storageObjectID.canonicalString
            + (fileExtension.map { ".\($0.rawValue)" } ?? "")
        return workspace.layout.meetings
            .appendingPathComponent(meetingID.canonicalString, isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw WorkspaceContractError.symbolicLinkNotAllowed(url.path)
            }
        }
    }

    private func createPrivateDirectory(_ url: URL) throws {
        _ = try WorkspacePathSecurity.createPrivateDirectory(
            url,
            within: workspace.layout.root,
            fileManager: fileManager
        )
    }

    private func confinedURL(
        for relativePath: WorkspaceRelativePath,
        allowMissingLeaf: Bool = false
    ) throws -> URL {
        let url = workspace.layout.root.appendingPathComponent(relativePath.rawValue)
        try ensureConfined(url, allowMissingLeaf: allowMissingLeaf)
        return url.standardizedFileURL
    }

    private func ensureConfined(_ url: URL, allowMissingLeaf: Bool = false) throws {
        _ = try WorkspacePathSecurity.confinedURL(
            url,
            within: workspace.layout.root,
            allowMissingLeaf: allowMissingLeaf
        )
    }

    private func workspaceRelativePath(
        for url: URL,
        allowMissingLeaf: Bool = false
    ) throws -> WorkspaceRelativePath {
        try ensureConfined(url, allowMissingLeaf: allowMissingLeaf)
        let rootPath = workspace.layout.root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            throw WorkspaceContractError.pathEscapesWorkspace(path)
        }
        return try WorkspaceRelativePath(String(path.dropFirst(rootPath.count)))
    }
}
