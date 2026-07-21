import CryptoKit
import Darwin
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class LocalRecordingFileStore: RecordingSegmentFileStore, @unchecked Sendable {
    private static let hashChunkBytes = 1_048_576

    private let workspace: LocalWorkspaceDescriptor
    private let fileManager: FileManager
    private let operationLock = NSLock()

    public init(
        workspace: LocalWorkspaceDescriptor,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    public func prepareSegment(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        diskBudgetBytes: UInt64
    ) throws -> RecordingWritableSegmentLease {
        try withLock {
            guard diskBudgetBytes > 0, diskBudgetBytes <= JobRequest.maximumDiskBudgetBytes else {
                throw RecordingContractError.invalidIntent("The recording file budget is invalid.")
            }
            let directory = try sessionDirectory(sessionID: sessionID, meetingID: meetingID)
            try createPrivateDirectory(directory)
            let finalURL = directory.appendingPathComponent(
                "\(storageObjectID.canonicalString).caf",
                isDirectory: false
            )
            let partialURL = directory.appendingPathComponent(
                "\(storageObjectID.canonicalString).caf.partial",
                isDirectory: false
            )
            try ensureConfined(finalURL, allowMissingLeaf: true)
            try ensureConfined(partialURL, allowMissingLeaf: true)
            guard !fileManager.fileExists(atPath: finalURL.path),
                  !fileManager.fileExists(atPath: partialURL.path),
                  fileManager.createFile(atPath: partialURL.path, contents: nil)
            else {
                throw RecordingContractError.integrityFailure("A recording segment destination is already owned.")
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partialURL.path)
            return RecordingWritableSegmentLease(
                sessionID: sessionID,
                meetingID: meetingID,
                storageObjectID: storageObjectID,
                partialFileURL: partialURL,
                finalRelativePath: try relativePath(for: finalURL, allowMissingLeaf: true),
                diskBudgetBytes: diskBudgetBytes
            )
        }
    }

    public func sealSegment(
        _ lease: RecordingWritableSegmentLease
    ) throws -> RecordingSealedFileDescriptor {
        try withLock {
            let (expectedPartial, expectedFinal) = try validate(lease)
            if fileManager.fileExists(atPath: expectedFinal.path),
               !fileManager.fileExists(atPath: expectedPartial.path)
            {
                return try descriptor(for: expectedFinal, lease: lease)
            }
            guard fileManager.fileExists(atPath: expectedPartial.path) else {
                throw RecordingContractError.integrityFailure("The writable recording segment disappeared before sealing.")
            }
            try rejectSymbolicLink(expectedPartial)
            let values = try expectedPartial.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 8,
                  UInt64(fileSize) <= lease.diskBudgetBytes
            else {
                throw RecordingContractError.invalidSegment("The partial recording segment is empty, invalid, or over budget.")
            }
            try validateCAFHeader(at: expectedPartial)
            let handle = try FileHandle(forWritingTo: expectedPartial)
            try handle.synchronize()
            try handle.close()
            try fileManager.moveItem(at: expectedPartial, to: expectedFinal)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: expectedFinal.path)
            try synchronizeDirectory(expectedFinal.deletingLastPathComponent())
            return try descriptor(for: expectedFinal, lease: lease)
        }
    }

    public func discardPartial(_ lease: RecordingWritableSegmentLease) throws {
        try withLock {
            let (partial, _) = try validate(lease)
            guard fileManager.fileExists(atPath: partial.path) else { return }
            try rejectSymbolicLink(partial)
            try fileManager.removeItem(at: partial)
            try synchronizeDirectory(partial.deletingLastPathComponent())
        }
    }

    public func verifySealedFile(_ descriptor: RecordingSealedFileDescriptor) throws {
        let url = try confinedURL(for: descriptor.relativePath)
        try rejectSymbolicLink(url)
        try validateCAFHeader(at: url)
        let (digest, size) = try hashFile(at: url)
        guard digest == descriptor.contentHash, size == descriptor.byteSize else {
            throw RecordingContractError.integrityFailure("The sealed CAF bytes no longer match their descriptor.")
        }
    }

    public func verifiedSealedFileURL(_ descriptor: RecordingSealedFileDescriptor) throws -> URL {
        try verifySealedFile(descriptor)
        return try confinedURL(for: descriptor.relativePath)
    }

    public func recoveryInventory(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        maximumEntries: UInt32 = 10_000
    ) throws -> RecordingRecoveryFileInventory {
        guard maximumEntries > 0, maximumEntries <= 10_000 else {
            throw RecordingContractError.integrityFailure("The recording recovery scan is unbounded.")
        }
        return try withLock {
            let directory = try sessionDirectory(sessionID: sessionID, meetingID: meetingID)
            guard fileManager.fileExists(atPath: directory.path) else {
                return RecordingRecoveryFileInventory(
                    sealedFiles: [],
                    partialRelativePaths: [],
                    quarantinedRelativePaths: [],
                    truncated: false
                )
            }
            try rejectSymbolicLink(directory)
            let entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let truncated = entries.count > Int(maximumEntries)
            var sealed: [RecordingSealedFileDescriptor] = []
            var partial: [WorkspaceRelativePath] = []
            var quarantined: [WorkspaceRelativePath] = []
            for entry in entries.prefix(Int(maximumEntries)) {
                let relative = try relativePath(for: entry)
                let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    quarantined.append(relative)
                    continue
                }
                if entry.lastPathComponent.hasSuffix(".caf.partial") {
                    partial.append(relative)
                    continue
                }
                guard entry.pathExtension.lowercased() == "caf",
                      let storageID = try? StorageObjectID(
                          validating: entry.deletingPathExtension().lastPathComponent
                      )
                else {
                    quarantined.append(relative)
                    continue
                }
                do {
                    try validateCAFHeader(at: entry)
                    let (digest, size) = try hashFile(at: entry)
                    sealed.append(
                        try RecordingSealedFileDescriptor(
                            sessionID: sessionID,
                            meetingID: meetingID,
                            storageObjectID: storageID,
                            relativePath: relative,
                            contentHash: digest,
                            byteSize: size
                        )
                    )
                } catch {
                    quarantined.append(relative)
                }
            }
            return RecordingRecoveryFileInventory(
                sealedFiles: sealed,
                partialRelativePaths: partial,
                quarantinedRelativePaths: quarantined,
                truncated: truncated
            )
        }
    }

    public func prepareFinalizationFile(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        trackID: RecordingTrackID?,
        fileExtension: ManagedFileExtension,
        diskBudgetBytes: UInt64
    ) throws -> RecordingFinalizationFileLease {
        try withLock {
            guard diskBudgetBytes > 0, diskBudgetBytes <= JobRequest.maximumDiskBudgetBytes else {
                throw RecordingContractError.invalidIntent("The recording finalization budget is invalid.")
            }
            let directory = try finalizationDirectory(sessionID: sessionID, meetingID: meetingID)
            try createPrivateDirectory(directory)
            let stem = trackID?.canonicalString ?? "manifest"
            let sealed = directory.appendingPathComponent("\(stem).\(fileExtension.rawValue)")
            let partial = directory.appendingPathComponent("\(stem).\(fileExtension.rawValue).partial")
            try ensureConfined(sealed, allowMissingLeaf: true)
            try ensureConfined(partial, allowMissingLeaf: true)
            let sealedExists = fileManager.fileExists(atPath: sealed.path)
            let partialExists = fileManager.fileExists(atPath: partial.path)
            if sealedExists {
                guard !partialExists else {
                    throw RecordingContractError.integrityFailure(
                        "Finalization contains both sealed and partial files."
                    )
                }
                try rejectSymbolicLink(sealed)
                let values = try sealed.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize > 0,
                      UInt64(fileSize) <= diskBudgetBytes
                else {
                    throw RecordingContractError.integrityFailure(
                        "The retained finalization file is invalid or over budget."
                    )
                }
                return RecordingFinalizationFileLease(
                    sessionID: sessionID,
                    meetingID: meetingID,
                    trackID: trackID,
                    partialFileURL: partial,
                    sealedFileURL: sealed,
                    diskBudgetBytes: diskBudgetBytes,
                    sealedFileAlreadyExists: true
                )
            }
            guard !partialExists,
                  fileManager.createFile(atPath: partial.path, contents: nil)
            else {
                throw RecordingContractError.integrityFailure("A recording finalization file is already owned.")
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
            return RecordingFinalizationFileLease(
                sessionID: sessionID,
                meetingID: meetingID,
                trackID: trackID,
                partialFileURL: partial,
                sealedFileURL: sealed,
                diskBudgetBytes: diskBudgetBytes,
                sealedFileAlreadyExists: false
            )
        }
    }

    public func sealFinalizationFile(_ lease: RecordingFinalizationFileLease) throws -> URL {
        try withLock {
            try validateFinalizationLease(lease)
            if fileManager.fileExists(atPath: lease.sealedFileURL.path),
               !fileManager.fileExists(atPath: lease.partialFileURL.path)
            {
                return lease.sealedFileURL
            }
            try rejectSymbolicLink(lease.partialFileURL)
            let values = try lease.partialFileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  UInt64(fileSize) <= lease.diskBudgetBytes
            else {
                throw RecordingContractError.integrityFailure("The recording finalization file is empty or over budget.")
            }
            let handle = try FileHandle(forWritingTo: lease.partialFileURL)
            try handle.synchronize()
            try handle.close()
            try fileManager.moveItem(at: lease.partialFileURL, to: lease.sealedFileURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lease.sealedFileURL.path)
            try synchronizeDirectory(lease.sealedFileURL.deletingLastPathComponent())
            return lease.sealedFileURL
        }
    }

    public func discardFinalizationFile(_ lease: RecordingFinalizationFileLease) throws {
        try withLock {
            try validateFinalizationLease(lease)
            for url in [lease.partialFileURL, lease.sealedFileURL]
                where fileManager.fileExists(atPath: url.path)
            {
                try rejectSymbolicLink(url)
                try fileManager.removeItem(at: url)
            }
            try synchronizeDirectory(lease.sealedFileURL.deletingLastPathComponent())
        }
    }

    private func descriptor(
        for url: URL,
        lease: RecordingWritableSegmentLease
    ) throws -> RecordingSealedFileDescriptor {
        try rejectSymbolicLink(url)
        try validateCAFHeader(at: url)
        let (digest, size) = try hashFile(at: url)
        guard size <= lease.diskBudgetBytes else {
            throw RecordingContractError.invalidSegment("The sealed segment exceeded its durable disk budget.")
        }
        return try RecordingSealedFileDescriptor(
            sessionID: lease.sessionID,
            meetingID: lease.meetingID,
            storageObjectID: lease.storageObjectID,
            relativePath: lease.finalRelativePath,
            contentHash: digest,
            byteSize: size
        )
    }

    private func validate(
        _ lease: RecordingWritableSegmentLease
    ) throws -> (partial: URL, final: URL) {
        let directory = try sessionDirectory(
            sessionID: lease.sessionID,
            meetingID: lease.meetingID
        )
        let expectedFinal = directory.appendingPathComponent(
            "\(lease.storageObjectID.canonicalString).caf"
        )
        let expectedPartial = directory.appendingPathComponent(
            "\(lease.storageObjectID.canonicalString).caf.partial"
        )
        guard expectedPartial.standardizedFileURL == lease.partialFileURL.standardizedFileURL,
              try relativePath(for: expectedFinal, allowMissingLeaf: true) == lease.finalRelativePath
        else {
            throw RecordingContractError.integrityFailure("The recording file lease does not match its session authority.")
        }
        try ensureConfined(expectedPartial, allowMissingLeaf: true)
        try ensureConfined(expectedFinal, allowMissingLeaf: true)
        return (expectedPartial, expectedFinal)
    }

    private func sessionDirectory(
        sessionID: RecordingSessionID,
        meetingID: MeetingID
    ) throws -> URL {
        let directory = workspace.layout.meetings
            .appendingPathComponent(meetingID.canonicalString, isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(sessionID.canonicalString, isDirectory: true)
            .appendingPathComponent("segments", isDirectory: true)
        try ensureConfined(directory, allowMissingLeaf: true)
        return directory
    }

    private func finalizationDirectory(
        sessionID: RecordingSessionID,
        meetingID: MeetingID
    ) throws -> URL {
        let directory = workspace.layout.meetings
            .appendingPathComponent(meetingID.canonicalString, isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(sessionID.canonicalString, isDirectory: true)
            .appendingPathComponent("finalizing", isDirectory: true)
        try ensureConfined(directory, allowMissingLeaf: true)
        return directory
    }

    private func validateFinalizationLease(_ lease: RecordingFinalizationFileLease) throws {
        let directory = try finalizationDirectory(
            sessionID: lease.sessionID,
            meetingID: lease.meetingID
        )
        guard lease.partialFileURL.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL,
              lease.sealedFileURL.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL,
              lease.partialFileURL.lastPathComponent
                == lease.sealedFileURL.lastPathComponent + ".partial",
              !lease.sealedFileURL.lastPathComponent.contains(".."),
              lease.diskBudgetBytes > 0
        else {
            throw RecordingContractError.integrityFailure("The recording finalization lease escaped its session authority.")
        }
        try ensureConfined(lease.partialFileURL, allowMissingLeaf: true)
        try ensureConfined(lease.sealedFileURL, allowMissingLeaf: true)
    }

    private func createPrivateDirectory(_ directory: URL) throws {
        try ensureConfined(directory, allowMissingLeaf: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var cursor = directory
        let meetingRoot = workspace.layout.meetings
        while cursor.path.hasPrefix(meetingRoot.path), cursor != meetingRoot {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cursor.path)
            cursor.deleteLastPathComponent()
        }
    }

    private func validateCAFHeader(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8) ?? Data()
        guard header.count == 8,
              Array(header.prefix(4)) == Array("caff".utf8),
              header[4] == 0,
              header[5] == 1
        else {
            throw RecordingContractError.invalidSegment("The sealed recording file is not a readable CAF v1 container.")
        }
    }

    private func hashFile(at url: URL) throws -> (ContentDigest, UInt64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteSize: UInt64 = 0
        while true {
            let chunk = try handle.read(upToCount: Self.hashChunkBytes) ?? Data()
            if chunk.isEmpty { break }
            byteSize += UInt64(chunk.count)
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (
            try ContentDigest(algorithm: .sha256, lowercaseHex: digest),
            byteSize
        )
    }

    private func confinedURL(
        for relativePath: WorkspaceRelativePath,
        allowMissingLeaf: Bool = false
    ) throws -> URL {
        try WorkspacePathSecurity.confinedURL(
            workspace.layout.root.appendingPathComponent(relativePath.rawValue),
            within: workspace.layout.root,
            allowMissingLeaf: allowMissingLeaf
        )
    }

    private func relativePath(
        for url: URL,
        allowMissingLeaf: Bool = false
    ) throws -> WorkspaceRelativePath {
        let confined = try WorkspacePathSecurity.confinedURL(
            url,
            within: workspace.layout.root,
            allowMissingLeaf: allowMissingLeaf
        )
        let prefix = workspace.layout.root.path + "/"
        guard confined.path.hasPrefix(prefix) else {
            throw WorkspaceContractError.pathEscapesWorkspace(confined.path)
        }
        return try WorkspaceRelativePath(String(confined.path.dropFirst(prefix.count)))
    }

    private func ensureConfined(_ url: URL, allowMissingLeaf: Bool) throws {
        _ = try WorkspacePathSecurity.confinedURL(
            url,
            within: workspace.layout.root,
            allowMissingLeaf: allowMissingLeaf
        )
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(url.path)
        }
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw RecordingContractError.integrityFailure("The recording directory could not be synchronized.")
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw RecordingContractError.integrityFailure("The recording directory synchronization failed.")
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try operation()
    }
}
