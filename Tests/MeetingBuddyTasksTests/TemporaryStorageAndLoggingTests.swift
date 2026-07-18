import Foundation
import MeetingBuddyApplication
import MeetingBuddyPersistence
import Testing

@Suite(.serialized)
struct TemporaryStorageAndLoggingTests {
    @Test
    func taskFilesStayConfinedAndWithinTheirOwnedBudget() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let jobID = testJobID(31)
        let lease = try await workspace.temporaryStorage.allocateDirectory(
            for: jobID,
            diskBudgetBytes: 4_096
        )
        let first = try await workspace.temporaryStorage.write(
            Data(repeating: 0x41, count: 3_000),
            to: WorkspaceRelativePath("chunks/first.bin"),
            in: lease
        )
        #expect(first.byteSize == 3_000)
        #expect(try await workspace.temporaryStorage.usage(of: lease).byteSize == 3_000)
        await #expect(throws: TaskRuntimeError.self) {
            _ = try await workspace.temporaryStorage.write(
                Data(repeating: 0x42, count: 1_097),
                to: WorkspaceRelativePath("chunks/second.bin"),
                in: lease
            )
        }
        #expect(throws: WorkspaceContractError.self) {
            _ = try WorkspaceRelativePath("../escape")
        }

        let taskRoot = workspace.root.appendingPathComponent(lease.relativePath.rawValue)
        let outside = workspace.container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = taskRoot.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: WorkspaceContractError.self) {
            _ = try await workspace.temporaryStorage.usage(of: lease)
        }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        try FileManager.default.removeItem(at: link)
        try Data(repeating: 0x43, count: 2_000).write(
            to: taskRoot.appendingPathComponent("externally-created-overage.bin"),
            options: [.withoutOverwriting]
        )
        await #expect(throws: TaskRuntimeError.self) {
            _ = try await workspace.temporaryStorage.usage(of: lease)
        }
        try await workspace.temporaryStorage.cleanupDirectory(lease)
        #expect(!FileManager.default.fileExists(atPath: taskRoot.path))
    }

    @Test
    func redactionAndRotationKeepSecretsOutOfBoundedLogs() async throws {
        let configuration = try TaskLogConfiguration(
            maximumFileBytes: 4_096,
            maximumArchivedFiles: 2,
            retentionMilliseconds: 10_000,
            maximumPublicValueBytes: 512
        )
        let workspace = try TaskTestWorkspace(logConfiguration: configuration)
        defer { workspace.cleanup() }
        let secret = "super-secret-meeting-token"
        for index in 0..<30 {
            let event = try TaskLogEvent(
                timestamp: testInstant(1_800_000_400_000 + Int64(index)),
                level: .info,
                category: "redaction-test",
                jobID: testJobID(32),
                message: .publicValue(
                    "authorization: Bearer abcdef1234567890 "
                        + String(repeating: "bounded-public-status ", count: 10)
                ),
                metadata: [
                    "private_source": .privateValue(secret),
                    "api_key": .publicValue("api_key=sk-test-value")
                ]
            )
            try await workspace.logStore.record(event)
        }
        let report = try await workspace.logStore.rotate(at: testInstant(1_800_000_400_100))
        #expect(report.archivedFileCount <= 2)
        #expect(report.activeFileByteSize <= configuration.maximumFileBytes)

        let logDirectory = workspace.root
            .appendingPathComponent("Logs/Tasks", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(files.count <= 3)
        let bytes = try files.reduce(into: Data()) { combined, file in
            combined.append(try Data(contentsOf: file))
        }
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(secret))
        #expect(!text.contains("abcdef1234567890"))
        #expect(!text.contains("sk-test-value"))
        #expect(text.contains("<redacted>"))
    }

    @Test
    func orphanCleanupIsAgeCountAndSymlinkBounded() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let tasksRoot = workspace.root.appendingPathComponent(".tasks", isDirectory: true)
        let old = tasksRoot.appendingPathComponent("not-a-job-old", isDirectory: true)
        let recent = tasksRoot.appendingPathComponent("not-a-job-recent", isDirectory: true)
        let outside = workspace.container.appendingPathComponent("outside-orphan", isDirectory: true)
        let link = tasksRoot.appendingPathComponent("not-a-job-link", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_500)],
            ofItemAtPath: recent.path
        )
        let boundedScan = try await workspace.temporaryStorage.scanOrphans(
            expectedJobIDs: [],
            maximumEntries: 2
        )
        #expect(boundedScan.inspectedEntryCount == 2)
        #expect(boundedScan.truncated)
        let scan = try await workspace.temporaryStorage.scanOrphans(
            expectedJobIDs: [],
            maximumEntries: 10
        )
        #expect(scan.candidates.count == 3)
        let cleanup = try await workspace.temporaryStorage.cleanupOrphans(
            scan.candidates,
            olderThan: testInstant(1_000_000),
            maximumRemovals: 1
        )
        #expect(cleanup.removed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: link.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
