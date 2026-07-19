import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import OSLog

public struct TaskLogConfiguration: Sendable {
    public let maximumFileBytes: UInt64
    public let maximumArchivedFiles: UInt32
    public let retentionMilliseconds: Int64
    public let maximumPublicValueBytes: Int

    public init(
        maximumFileBytes: UInt64 = 4_194_304,
        maximumArchivedFiles: UInt32 = 14,
        retentionMilliseconds: Int64 = 1_209_600_000,
        maximumPublicValueBytes: Int = 1_024
    ) throws {
        guard maximumFileBytes >= 4_096,
              maximumFileBytes <= 67_108_864,
              maximumArchivedFiles > 0,
              maximumArchivedFiles <= 128,
              retentionMilliseconds > 0,
              maximumPublicValueBytes >= 64,
              maximumPublicValueBytes <= 4_096
        else {
            throw TaskRuntimeError.logConfigurationInvalid(
                "Task log rotation and value limits are outside the approved bounds."
            )
        }
        self.maximumFileBytes = maximumFileBytes
        self.maximumArchivedFiles = maximumArchivedFiles
        self.retentionMilliseconds = retentionMilliseconds
        self.maximumPublicValueBytes = maximumPublicValueBytes
    }
}

public actor RotatingTaskLogStore: TaskLogStore {
    private static let activeFilename = "task-runtime.jsonl"
    private static let archivePrefix = "task-runtime-"
    private static let maximumArchiveScanCount = 1_024

    private let workspace: LocalWorkspaceDescriptor
    private let configuration: TaskLogConfiguration
    private let fileManager: FileManager
    private let osLogger = Logger(subsystem: "MeetingBuddy", category: "TaskRuntime")

    public init(
        workspace: LocalWorkspaceDescriptor,
        configuration: TaskLogConfiguration,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func record(_ event: TaskLogEvent) async throws {
        let record = sanitize(event)
        let line = try encode(record) + Data([0x0A])
        guard UInt64(line.count) <= configuration.maximumFileBytes else {
            throw TaskRuntimeError.logConfigurationInvalid(
                "One sanitized log event exceeds the active-file budget."
            )
        }
        let directory = try logsDirectory()
        let active = directory.appendingPathComponent(Self.activeFilename)
        if fileManager.fileExists(atPath: active.path) {
            try rejectSymbolicLink(active)
        }
        let currentSize = try fileByteSize(active)
        let (projected, overflow) = currentSize.addingReportingOverflow(UInt64(line.count))
        if overflow || projected > configuration.maximumFileBytes {
            try archiveActiveFile(active, at: event.timestamp)
        }
        if !fileManager.fileExists(atPath: active.path) {
            guard fileManager.createFile(atPath: active.path, contents: nil) else {
                throw TaskRuntimeError.logConfigurationInvalid(
                    "The bounded task log could not be created."
                )
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: active.path)
        }
        let handle = try FileHandle(forWritingTo: active)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
        emitToOSLog(record)
        _ = try enforceRetention(in: directory, at: event.timestamp)
    }

    public func rotate(at timestamp: UTCInstant) async throws -> TaskLogRotationReport {
        let directory = try logsDirectory()
        let active = directory.appendingPathComponent(Self.activeFilename)
        if try fileByteSize(active) > configuration.maximumFileBytes {
            try archiveActiveFile(active, at: timestamp)
        }
        let removed = try enforceRetention(in: directory, at: timestamp)
        let archives = try archiveFiles(in: directory)
        return TaskLogRotationReport(
            archivedFileCount: UInt32(clamping: archives.count),
            removedFileCount: UInt32(clamping: removed),
            activeFileByteSize: try fileByteSize(active)
        )
    }

    private func logsDirectory() throws -> URL {
        let directory = workspace.layout.logs.appendingPathComponent("Tasks", isDirectory: true)
        return try WorkspacePathSecurity.createPrivateDirectory(
            directory,
            within: workspace.layout.root,
            fileManager: fileManager
        )
    }

    private func sanitize(_ event: TaskLogEvent) -> SanitizedTaskLogRecord {
        var metadata: [String: String] = [:]
        for (key, value) in event.metadata {
            metadata[key] = sanitize(value)
        }
        return SanitizedTaskLogRecord(
            timestamp: event.timestamp,
            level: event.level,
            category: event.category,
            jobID: event.jobID?.canonicalString,
            message: sanitize(event.message),
            metadata: metadata
        )
    }

    private func sanitize(_ value: TaskLogValue) -> String {
        switch value {
        case .privateValue:
            return "<redacted>"
        case let .publicValue(raw):
            let bounded = boundedUTF8(raw, maximumBytes: configuration.maximumPublicValueBytes)
            let credentialRedacted = redactCredentialPatterns(in: bounded)
            guard isApprovedPublicDiagnosticValue(credentialRedacted) else {
                return "<redacted-unapproved-public-value>"
            }
            return credentialRedacted
        }
    }

    private func isApprovedPublicDiagnosticValue(_ value: String) -> Bool {
        let approvedMessages: Set<String> = [
            "Job queued",
            "Pause requested",
            "Job resumed",
            "Job cancelled",
            "Cancellation requested",
            "Job queued for retry",
            "Job started",
            "Job paused at a durable checkpoint",
            "Job succeeded",
            "Job cancelled cooperatively",
            "Job failed"
        ]
        if approvedMessages.contains(value) { return true }
        if value == "none" { return true }
        if UUID(uuidString: value) != nil { return true }
        return !value.isEmpty
            && value.utf8.count <= 96
            && value.utf8.allSatisfy { byte in
                (byte >= 97 && byte <= 122)
                    || (byte >= 48 && byte <= 57)
                    || byte == 45
                    || byte == 95
            }
    }

    private func redactCredentialPatterns(in value: String) -> String {
        var result = value
        let patterns: [(String, String)] = [
            (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <redacted>"),
            (
                #"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|authorization)\s*[:=]\s*[^\s,;]+"#,
                "$1=<redacted>"
            )
        ]
        for (pattern, template) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template
            )
        }
        return result
    }

    private func boundedUTF8(_ value: String, maximumBytes: Int) -> String {
        let bytes = Array(value.utf8)
        guard bytes.count > maximumBytes else { return value }
        var prefix = Array(bytes.prefix(maximumBytes))
        while String(bytes: prefix, encoding: .utf8) == nil, !prefix.isEmpty {
            prefix.removeLast()
        }
        return (String(bytes: prefix, encoding: .utf8) ?? "") + "…"
    }

    private func encode(_ record: SanitizedTaskLogRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(record)
    }

    private func archiveActiveFile(_ active: URL, at timestamp: UTCInstant) throws {
        guard fileManager.fileExists(atPath: active.path), try fileByteSize(active) > 0 else {
            return
        }
        try rejectSymbolicLink(active)
        let archive = active.deletingLastPathComponent().appendingPathComponent(
            Self.archivePrefix
                + "\(timestamp.millisecondsSinceUnixEpoch)-"
                + UUID().uuidString.lowercased()
                + ".jsonl"
        )
        _ = try WorkspacePathSecurity.confinedURL(
            archive,
            within: active.deletingLastPathComponent(),
            allowMissingLeaf: true
        )
        try fileManager.moveItem(at: active, to: archive)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
    }

    private func enforceRetention(in directory: URL, at timestamp: UTCInstant) throws -> Int {
        let archives = try archiveFiles(in: directory)
        guard archives.count <= Self.maximumArchiveScanCount else {
            throw TaskRuntimeError.startupCheckFailed(
                "The task log archive count exceeds the bounded startup scan."
            )
        }
        let cutoff = timestamp.millisecondsSinceUnixEpoch - configuration.retentionMilliseconds
        let sortedNewestFirst = try archives.sorted { lhs, rhs in
            try modificationMilliseconds(lhs) > modificationMilliseconds(rhs)
        }
        var removed = 0
        for (index, archive) in sortedNewestFirst.enumerated() {
            try rejectSymbolicLink(archive)
            let expired = try modificationMilliseconds(archive) < cutoff
            let overCount = index >= Int(configuration.maximumArchivedFiles)
            if expired || overCount {
                try fileManager.removeItem(at: archive)
                removed += 1
            }
        }
        return removed
    }

    private func archiveFiles(in directory: URL) throws -> [URL] {
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw TaskRuntimeError.startupCheckFailed(
                "The task log directory could not be enumerated."
            )
        }
        var inspected = 0
        var archives: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            inspected += 1
            guard inspected <= Self.maximumArchiveScanCount else {
                throw TaskRuntimeError.startupCheckFailed(
                    "The task log directory exceeds the bounded rotation scan."
                )
            }
            enumerator.skipDescendants()
            if entry.lastPathComponent.hasPrefix(Self.archivePrefix),
               entry.pathExtension == "jsonl"
            {
                archives.append(entry)
            }
        }
        guard !enumerationFailed else {
            throw TaskRuntimeError.startupCheckFailed(
                "The bounded task log scan encountered an unreadable entry."
            )
        }
        return archives
    }

    private func fileByteSize(_ url: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        try rejectSymbolicLink(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw TaskRuntimeError.logConfigurationInvalid("A task log is not a regular file.")
        }
        return UInt64(max(values.fileSize ?? 0, 0))
    }

    private func modificationMilliseconds(_ url: URL) throws -> Int64 {
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate ?? .distantPast
        return Int64(max(date.timeIntervalSince1970 * 1_000, 0).rounded(.down))
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(url.path)
        }
    }

    private func emitToOSLog(_ record: SanitizedTaskLogRecord) {
        let job = record.jobID ?? "none"
        switch record.level {
        case .debug:
            osLogger.debug(
                "\(record.category, privacy: .public) job=\(job, privacy: .public) \(record.message, privacy: .private(mask: .hash))"
            )
        case .info:
            osLogger.info(
                "\(record.category, privacy: .public) job=\(job, privacy: .public) \(record.message, privacy: .private(mask: .hash))"
            )
        case .notice:
            osLogger.notice(
                "\(record.category, privacy: .public) job=\(job, privacy: .public) \(record.message, privacy: .private(mask: .hash))"
            )
        case .error:
            osLogger.error(
                "\(record.category, privacy: .public) job=\(job, privacy: .public) \(record.message, privacy: .private(mask: .hash))"
            )
        }
    }
}

private struct SanitizedTaskLogRecord: Codable {
    let timestamp: UTCInstant
    let level: TaskLogLevel
    let category: String
    let jobID: String?
    let message: String
    let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case level
        case category
        case jobID = "job_id"
        case message
        case metadata
    }
}
