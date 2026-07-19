import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public actor LocalTaskTemporaryStorage: TaskTemporaryStorage {
    private static let maximumEntriesPerJob: UInt32 = 10_000

    private let workspace: LocalWorkspaceDescriptor
    private let fileManager: FileManager
    private let capacityProvider: (@Sendable () throws -> UInt64?)?

    public init(
        workspace: LocalWorkspaceDescriptor,
        fileManager: FileManager = .default,
        capacityProvider: (@Sendable () throws -> UInt64?)? = nil
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.capacityProvider = capacityProvider
    }

    public func allocateDirectory(
        for jobID: JobID,
        diskBudgetBytes: UInt64
    ) async throws -> TaskDirectoryLease {
        let lease = try canonicalLease(jobID: jobID, diskBudgetBytes: diskBudgetBytes)
        if let available = try await availableCapacityBytes(), available < diskBudgetBytes {
            throw TaskRuntimeError.insufficientDiskCapacity
        }
        let url = taskURL(for: lease)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw TaskRuntimeError.temporaryStorageConflict(jobID)
        }
        _ = try WorkspacePathSecurity.createPrivateDirectory(
            url,
            within: workspace.layout.tasks,
            fileManager: fileManager
        )
        return lease
    }

    public func reuseDirectory(_ lease: TaskDirectoryLease) async throws {
        try validate(lease)
        let url = taskURL(for: lease)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TaskRuntimeError.temporaryStorageConflict(lease.jobID)
        }
        let currentUsage = try directoryUsage(at: url, budget: lease.diskBudgetBytes)
        guard currentUsage.byteSize <= lease.diskBudgetBytes else {
            throw TaskRuntimeError.diskBudgetExceeded(lease.jobID)
        }
    }

    public func write(
        _ data: Data,
        to relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor {
        try validate(lease)
        guard !data.isEmpty else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePathWithinTask.rawValue)
        }
        let root = taskURL(for: lease)
        try await reuseDirectory(lease)
        let usage = try directoryUsage(at: root, budget: lease.diskBudgetBytes)
        let (projected, overflow) = usage.byteSize.addingReportingOverflow(UInt64(data.count))
        guard !overflow, projected <= lease.diskBudgetBytes else {
            throw TaskRuntimeError.diskBudgetExceeded(lease.jobID)
        }

        let components = relativePathWithinTask.rawValue.split(separator: "/").map(String.init)
        var parent = root
        for component in components.dropLast() {
            parent = parent.appendingPathComponent(component, isDirectory: true)
            _ = try WorkspacePathSecurity.createPrivateDirectory(
                parent,
                within: root,
                fileManager: fileManager
            )
        }
        let destination = parent.appendingPathComponent(components.last!)
        _ = try WorkspacePathSecurity.confinedURL(
            destination,
            within: root,
            allowMissingLeaf: true
        )
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.createFile(atPath: destination.path, contents: nil)
        else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePathWithinTask.rawValue)
        }
        do {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try TaskTemporaryFileDescriptor(
            relativePathWithinTask: relativePathWithinTask,
            contentHash: ContentDigest(algorithm: .sha256, lowercaseHex: hash),
            byteSize: UInt64(data.count)
        )
    }

    public func prepareWritableFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskWritableFileLease {
        try validate(lease)
        try await reuseDirectory(lease)
        _ = try directoryUsage(at: taskURL(for: lease), budget: lease.diskBudgetBytes)
        let destination = try prepareDestination(
            relativePathWithinTask,
            in: lease,
            createParents: true
        )
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.createFile(atPath: destination.path, contents: nil)
        else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePathWithinTask.rawValue)
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return TaskWritableFileLease(
            jobID: lease.jobID,
            relativePathWithinTask: relativePathWithinTask,
            fileURL: destination
        )
    }

    public func finalizeWritableFile(
        _ writableFile: TaskWritableFileLease,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor {
        try validate(writableFile, in: lease)
        let descriptor = try descriptor(
            at: writableFile.fileURL,
            relativePath: writableFile.relativePathWithinTask
        )
        _ = try directoryUsage(at: taskURL(for: lease), budget: lease.diskBudgetBytes)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: writableFile.fileURL.path
        )
        return descriptor
    }

    public func inspectFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor? {
        try validate(lease)
        try await reuseDirectory(lease)
        let file = try prepareDestination(
            relativePathWithinTask,
            in: lease,
            createParents: false
        )
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        let result = try descriptor(at: file, relativePath: relativePathWithinTask)
        _ = try directoryUsage(at: taskURL(for: lease), budget: lease.diskBudgetBytes)
        return result
    }

    public func verifiedFileURL(
        for descriptor: TaskTemporaryFileDescriptor,
        in lease: TaskDirectoryLease
    ) async throws -> URL {
        guard let current = try await inspectFile(
            at: descriptor.relativePathWithinTask,
            in: lease
        ), current == descriptor else {
            throw TaskRuntimeError.temporaryPathInvalid(
                descriptor.relativePathWithinTask.rawValue
            )
        }
        return try prepareDestination(
            descriptor.relativePathWithinTask,
            in: lease,
            createParents: false
        )
    }

    public func discardWritableFile(
        _ writableFile: TaskWritableFileLease,
        in lease: TaskDirectoryLease
    ) async throws {
        try validate(writableFile, in: lease)
        try discard(file: writableFile.fileURL)
    }

    public func discardFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws {
        try validate(lease)
        let file = try prepareDestination(
            relativePathWithinTask,
            in: lease,
            createParents: false
        )
        try discard(file: file)
    }

    public func usage(of lease: TaskDirectoryLease) async throws -> TaskDirectoryUsage {
        try validate(lease)
        return try directoryUsage(at: taskURL(for: lease), budget: lease.diskBudgetBytes)
    }

    public func cleanupDirectory(_ lease: TaskDirectoryLease) async throws {
        try validate(lease)
        let url = taskURL(for: lease)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(url.path)
        }
        // Cleanup stays possible even if an external writer made the owned
        // directory exceed its normal execution budget. The bounded symlink
        // walk preserves the deletion boundary without turning overage into a
        // permanent sensitive-data leak.
        try rejectNestedSymbolicLinks(in: url)
        try fileManager.removeItem(at: url)
    }

    public func availableCapacityBytes() async throws -> UInt64? {
        if let capacityProvider {
            return try capacityProvider()
        }
        let values = try workspace.layout.tasks.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let capacity = values.volumeAvailableCapacityForImportantUsage,
              capacity >= 0
        else {
            return nil
        }
        return UInt64(capacity)
    }

    public func scanOrphans(
        expectedJobIDs: Set<JobID>,
        maximumEntries: UInt32
    ) async throws -> TaskOrphanScan {
        guard maximumEntries > 0, maximumEntries <= 4_096 else {
            throw TaskRuntimeError.startupCheckFailed("The orphan scan bound is invalid.")
        }
        let tasksRoot = try WorkspacePathSecurity.confinedURL(
            workspace.layout.tasks,
            within: workspace.layout.root
        )
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: tasksRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey
            ],
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw TaskRuntimeError.startupCheckFailed(
                "The task directory could not be enumerated."
            )
        }
        var entries: [URL] = []
        while entries.count <= Int(maximumEntries),
              let entry = enumerator.nextObject() as? URL
        {
            entries.append(entry)
            enumerator.skipDescendants()
        }
        guard !enumerationFailed else {
            throw TaskRuntimeError.startupCheckFailed(
                "The bounded task orphan scan encountered an unreadable entry."
            )
        }
        let truncated = entries.count > Int(maximumEntries)
        let inspected = entries.prefix(Int(maximumEntries)).sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        var candidates: [TaskOrphanDirectory] = []
        for entry in inspected {
            let name = entry.lastPathComponent
            let candidateID = try? JobID(validating: name)
            if let candidateID, expectedJobIDs.contains(candidateID) {
                continue
            }
            let values = try entry.resourceValues(
                forKeys: [.isSymbolicLinkKey, .contentModificationDateKey]
            )
            let milliseconds = Int64(
                max((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000, 0)
                    .rounded(.down)
            )
            candidates.append(
                TaskOrphanDirectory(
                    relativePath: try WorkspaceRelativePath(".tasks/\(name)"),
                    candidateJobID: candidateID,
                    modifiedAt: try UTCInstant(millisecondsSinceUnixEpoch: milliseconds),
                    isSymbolicLink: values.isSymbolicLink == true
                )
            )
        }
        return TaskOrphanScan(
            candidates: candidates,
            inspectedEntryCount: UInt32(inspected.count),
            truncated: truncated
        )
    }

    public func cleanupOrphans(
        _ candidates: [TaskOrphanDirectory],
        olderThan cutoff: UTCInstant,
        maximumRemovals: UInt32
    ) async throws -> TaskOrphanCleanupReport {
        guard maximumRemovals <= 4_096 else {
            throw TaskRuntimeError.startupCheckFailed("The orphan cleanup bound is invalid.")
        }
        var removed: [WorkspaceRelativePath] = []
        var retained: [WorkspaceRelativePath] = []
        for candidate in candidates.sorted(by: { $0.relativePath.rawValue < $1.relativePath.rawValue }) {
            let components = candidate.relativePath.rawValue.split(separator: "/")
            guard components.count == 2,
                  components[0] == ".tasks",
                  !candidate.isSymbolicLink,
                  candidate.modifiedAt < cutoff,
                  removed.count < Int(maximumRemovals)
            else {
                retained.append(candidate.relativePath)
                continue
            }
            let target = workspace.layout.root.appendingPathComponent(candidate.relativePath.rawValue)
            guard fileManager.fileExists(atPath: target.path) else { continue }
            let values = try target.resourceValues(
                forKeys: [.isSymbolicLinkKey, .contentModificationDateKey]
            )
            let currentMilliseconds = Int64(
                max((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000, 0)
                    .rounded(.down)
            )
            guard values.isSymbolicLink != true,
                  currentMilliseconds <= candidate.modifiedAt.millisecondsSinceUnixEpoch
            else {
                retained.append(candidate.relativePath)
                continue
            }
            _ = try WorkspacePathSecurity.confinedURL(target, within: workspace.layout.tasks)
            try rejectNestedSymbolicLinks(in: target)
            try fileManager.removeItem(at: target)
            removed.append(candidate.relativePath)
        }
        return TaskOrphanCleanupReport(removed: removed, retained: retained)
    }

    private func canonicalLease(jobID: JobID, diskBudgetBytes: UInt64) throws -> TaskDirectoryLease {
        try TaskDirectoryLease(
            jobID: jobID,
            relativePath: WorkspaceRelativePath(".tasks/\(jobID.canonicalString)"),
            diskBudgetBytes: diskBudgetBytes
        )
    }

    private func validate(_ lease: TaskDirectoryLease) throws {
        _ = try canonicalLease(jobID: lease.jobID, diskBudgetBytes: lease.diskBudgetBytes)
        guard lease.relativePath.rawValue == ".tasks/\(lease.jobID.canonicalString)" else {
            throw TaskRuntimeError.temporaryPathInvalid(lease.relativePath.rawValue)
        }
    }

    private func taskURL(for lease: TaskDirectoryLease) -> URL {
        workspace.layout.root.appendingPathComponent(lease.relativePath.rawValue, isDirectory: true)
    }

    private func prepareDestination(
        _ relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease,
        createParents: Bool
    ) throws -> URL {
        let root = taskURL(for: lease)
        let components = relativePathWithinTask.rawValue.split(separator: "/").map(String.init)
        guard let leaf = components.last else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePathWithinTask.rawValue)
        }
        var parent = root
        for component in components.dropLast() {
            parent = parent.appendingPathComponent(component, isDirectory: true)
            if createParents {
                _ = try WorkspacePathSecurity.createPrivateDirectory(
                    parent,
                    within: root,
                    fileManager: fileManager
                )
            } else if fileManager.fileExists(atPath: parent.path) {
                _ = try WorkspacePathSecurity.confinedURL(parent, within: root)
                let values = try parent.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw TaskRuntimeError.temporaryPathInvalid(
                        relativePathWithinTask.rawValue
                    )
                }
            } else {
                return parent.appendingPathComponent(leaf)
            }
        }
        let destination = parent.appendingPathComponent(leaf)
        _ = try WorkspacePathSecurity.confinedURL(
            destination,
            within: root,
            allowMissingLeaf: true
        )
        return destination.standardizedFileURL
    }

    private func validate(
        _ writableFile: TaskWritableFileLease,
        in lease: TaskDirectoryLease
    ) throws {
        try validate(lease)
        guard writableFile.jobID == lease.jobID else {
            throw TaskRuntimeError.temporaryPathInvalid(
                writableFile.relativePathWithinTask.rawValue
            )
        }
        let expected = try prepareDestination(
            writableFile.relativePathWithinTask,
            in: lease,
            createParents: false
        )
        guard expected == writableFile.fileURL.standardizedFileURL else {
            throw TaskRuntimeError.temporaryPathInvalid(
                writableFile.relativePathWithinTask.rawValue
            )
        }
    }

    private func descriptor(
        at file: URL,
        relativePath: WorkspaceRelativePath
    ) throws -> TaskTemporaryFileDescriptor {
        let values = try file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePath.rawValue)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteSize: UInt64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            let (next, overflow) = byteSize.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw TaskRuntimeError.temporaryPathInvalid(relativePath.rawValue)
            }
            byteSize = next
        }
        guard byteSize > 0 else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePath.rawValue)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return try TaskTemporaryFileDescriptor(
            relativePathWithinTask: relativePath,
            contentHash: ContentDigest(algorithm: .sha256, lowercaseHex: hash),
            byteSize: byteSize
        )
    }

    private func discard(file: URL) throws {
        guard fileManager.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(file.path)
        }
        try fileManager.removeItem(at: file)
    }

    private func directoryUsage(at root: URL, budget: UInt64) throws -> TaskDirectoryUsage {
        guard fileManager.fileExists(atPath: root.path) else {
            throw TaskRuntimeError.temporaryStorageConflict(
                try JobID(validating: root.lastPathComponent)
            )
        }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(root.path)
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw TaskRuntimeError.temporaryPathInvalid(root.path)
        }
        var bytes: UInt64 = 0
        var entries: UInt32 = 0
        while let item = enumerator.nextObject() as? URL {
            let (nextEntries, entryOverflow) = entries.addingReportingOverflow(1)
            guard !entryOverflow, nextEntries <= Self.maximumEntriesPerJob else {
                throw TaskRuntimeError.diskBudgetExceeded(
                    try JobID(validating: root.lastPathComponent)
                )
            }
            entries = nextEntries
            let values = try item.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw WorkspaceContractError.symbolicLinkNotAllowed(item.path)
            }
            if values.isRegularFile == true {
                let size = UInt64(max(values.fileSize ?? 0, 0))
                let (nextBytes, overflow) = bytes.addingReportingOverflow(size)
                guard !overflow, nextBytes <= budget else {
                    throw TaskRuntimeError.diskBudgetExceeded(
                        try JobID(validating: root.lastPathComponent)
                    )
                }
                bytes = nextBytes
            }
        }
        return TaskDirectoryUsage(byteSize: bytes, entryCount: entries)
    }

    private func rejectNestedSymbolicLinks(in root: URL) throws {
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(root.path)
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            return
        }
        var inspected: UInt32 = 0
        while let item = enumerator.nextObject() as? URL {
            inspected += 1
            guard inspected <= Self.maximumEntriesPerJob else {
                throw TaskRuntimeError.startupCheckFailed(
                    "An orphan exceeded the bounded cleanup entry count."
                )
            }
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WorkspaceContractError.symbolicLinkNotAllowed(item.path)
            }
        }
    }
}
