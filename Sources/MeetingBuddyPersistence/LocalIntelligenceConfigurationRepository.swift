import Foundation
import MeetingBuddyApplication

public final class LocalIntelligenceConfigurationRepository:
    IntelligenceConfigurationRepository,
    @unchecked Sendable
{
    public static let maximumFileBytes = 1 * 1_024 * 1_024

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
              standardized.path.hasPrefix("/"),
              standardized.path != "/",
              standardized.path
                  != fileManager.homeDirectoryForCurrentUser.path,
              !standardized.hasDirectoryPath
        else {
            throw IntelligenceConfigurationError
                .persistenceUnavailable
        }
        self.fileURL = standardized
        self.fileManager = fileManager
    }

    public func load() throws
        -> IntelligenceConfigurationState
    {
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    public func save(
        _ state: IntelligenceConfigurationState,
        expectedRevision: UInt64
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let current = try loadLocked()
        guard current.revision == expectedRevision,
              state.revision == expectedRevision + 1
        else {
            throw IntelligenceConfigurationError
                .revisionConflict
        }
        try preparePrivateParentDirectory()
        if fileManager.fileExists(atPath: fileURL.path) {
            let values = try fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw IntelligenceConfigurationError
                    .persistenceUnavailable
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        let data = try encoder.encode(state)
        guard !data.isEmpty,
              data.count <= Self.maximumFileBytes
        else {
            throw IntelligenceConfigurationError
                .persistenceUnavailable
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw IntelligenceConfigurationError
                .persistenceUnavailable
        }
    }

    private func loadLocked() throws
        -> IntelligenceConfigurationState
    {
        guard fileManager.fileExists(atPath: fileURL.path)
        else {
            return try IntelligenceConfigurationState
                .compiledDefault()
        }
        do {
            let values = try fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey
                ]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size > 0,
                  size <= Self.maximumFileBytes
            else {
                throw IntelligenceConfigurationError
                    .persistenceUnavailable
            }
            return try JSONDecoder().decode(
                IntelligenceConfigurationState.self,
                from: Data(contentsOf: fileURL)
            )
        } catch let error as IntelligenceConfigurationError {
            throw error
        } catch {
            throw IntelligenceConfigurationError
                .persistenceUnavailable
        }
    }

    private func preparePrivateParentDirectory() throws {
        let parent = fileURL.deletingLastPathComponent()
        let parentParent = parent.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentParent.path) {
            let values = try parentParent.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey
                ]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw IntelligenceConfigurationError
                    .persistenceUnavailable
            }
        }
        do {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let values = try parent.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey
                ]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw IntelligenceConfigurationError
                    .persistenceUnavailable
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: parent.path
            )
        } catch let error as IntelligenceConfigurationError {
            throw error
        } catch {
            throw IntelligenceConfigurationError
                .persistenceUnavailable
        }
    }
}
