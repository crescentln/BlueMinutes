import Foundation
import MeetingBuddyDomain

public enum TaskRuntimeError: Error, Equatable, Sendable {
    case executorUnavailable(JobType)
    case duplicateExecutor(JobType)
    case dependencyMissing(JobID)
    case dependencyFailed(JobID)
    case pauseUnsupported(JobID)
    case cancellationRequested(JobID)
    case diskBudgetExceeded(JobID)
    case insufficientDiskCapacity
    case temporaryPathInvalid(String)
    case temporaryStorageConflict(JobID)
    case logConfigurationInvalid(String)
    case startupCheckFailed(String)
}

public struct JobExecutionResult: Sendable {
    public let outputRevisionIDs: [SemanticRevisionReference]
    public let providerUsage: [ProviderUsageMetadata]

    public init(
        outputRevisionIDs: [SemanticRevisionReference] = [],
        providerUsage: [ProviderUsageMetadata] = []
    ) throws {
        let sorted = outputRevisionIDs.sorted()
        guard Set(sorted).count == sorted.count else {
            throw JobContractError.invalidRequest(
                "A job result cannot publish a duplicate output revision."
            )
        }
        self.outputRevisionIDs = sorted
        self.providerUsage = providerUsage
    }
}

/// An executor-visible error whose persisted summary is explicitly safe.
/// Raw provider output and source content must be sent only as private log
/// values and never placed in this record.
public struct JobExecutionFailure: Error, Sendable {
    public let code: String
    public let safeSummary: String
    public let retryable: Bool
    public let privateDiagnostic: String?

    public init(
        code: String,
        safeSummary: String,
        retryable: Bool,
        privateDiagnostic: String? = nil
    ) throws {
        _ = try JobFailureRecord(
            code: code,
            safeSummary: safeSummary,
            retryable: retryable,
            occurredAt: UTCInstant(millisecondsSinceUnixEpoch: 0)
        )
        self.code = code
        self.safeSummary = safeSummary
        self.retryable = retryable
        self.privateDiagnostic = privateDiagnostic
    }
}

public struct TaskTemporaryFileDescriptor: Codable, Hashable, Sendable {
    public let relativePathWithinTask: WorkspaceRelativePath
    public let contentHash: ContentDigest
    public let byteSize: UInt64

    public init(
        relativePathWithinTask: WorkspaceRelativePath,
        contentHash: ContentDigest,
        byteSize: UInt64
    ) throws {
        guard contentHash.algorithm == .sha256, byteSize > 0 else {
            throw TaskRuntimeError.temporaryPathInvalid(relativePathWithinTask.rawValue)
        }
        self.relativePathWithinTask = relativePathWithinTask
        self.contentHash = contentHash
        self.byteSize = byteSize
    }
}

/// A narrowly scoped capability for one not-yet-finalized task-owned file.
///
/// Only trusted local executors receive the URL. The temporary-storage
/// implementation validates the job, relative path, symlinks, size, and hash
/// again before returning a durable descriptor.
public struct TaskWritableFileLease: Hashable, Sendable {
    public let jobID: JobID
    public let relativePathWithinTask: WorkspaceRelativePath
    public let fileURL: URL

    public init(
        jobID: JobID,
        relativePathWithinTask: WorkspaceRelativePath,
        fileURL: URL
    ) {
        self.jobID = jobID
        self.relativePathWithinTask = relativePathWithinTask
        self.fileURL = fileURL
    }
}

public struct TaskDirectoryUsage: Codable, Hashable, Sendable {
    public let byteSize: UInt64
    public let entryCount: UInt32

    public init(byteSize: UInt64, entryCount: UInt32) {
        self.byteSize = byteSize
        self.entryCount = entryCount
    }
}

public struct TaskOrphanDirectory: Codable, Hashable, Sendable {
    public let relativePath: WorkspaceRelativePath
    public let candidateJobID: JobID?
    public let modifiedAt: UTCInstant
    public let isSymbolicLink: Bool

    public init(
        relativePath: WorkspaceRelativePath,
        candidateJobID: JobID?,
        modifiedAt: UTCInstant,
        isSymbolicLink: Bool
    ) {
        self.relativePath = relativePath
        self.candidateJobID = candidateJobID
        self.modifiedAt = modifiedAt
        self.isSymbolicLink = isSymbolicLink
    }
}

public struct TaskOrphanScan: Codable, Hashable, Sendable {
    public let candidates: [TaskOrphanDirectory]
    public let inspectedEntryCount: UInt32
    public let truncated: Bool

    public init(
        candidates: [TaskOrphanDirectory],
        inspectedEntryCount: UInt32,
        truncated: Bool
    ) {
        self.candidates = candidates
        self.inspectedEntryCount = inspectedEntryCount
        self.truncated = truncated
    }
}

public struct TaskOrphanCleanupReport: Codable, Hashable, Sendable {
    public let removed: [WorkspaceRelativePath]
    public let retained: [WorkspaceRelativePath]

    public init(removed: [WorkspaceRelativePath], retained: [WorkspaceRelativePath]) {
        self.removed = removed
        self.retained = retained
    }
}

public struct TaskDatabaseHealth: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let expectedSchemaVersion: UInt32
    public let journalMode: String
    public let quickCheckPassed: Bool
    public let foreignKeyFailureCount: UInt32

    public init(
        schemaVersion: UInt32,
        expectedSchemaVersion: UInt32,
        journalMode: String,
        quickCheckPassed: Bool,
        foreignKeyFailureCount: UInt32
    ) {
        self.schemaVersion = schemaVersion
        self.expectedSchemaVersion = expectedSchemaVersion
        self.journalMode = journalMode
        self.quickCheckPassed = quickCheckPassed
        self.foreignKeyFailureCount = foreignKeyFailureCount
    }

    public var isHealthy: Bool {
        schemaVersion == expectedSchemaVersion
            && journalMode.lowercased() == "wal"
            && quickCheckPassed
            && foreignKeyFailureCount == 0
    }
}

public protocol JobRepository: Sendable {
    func create(_ record: JobRecord) async throws
    func job(id: JobID) async throws -> JobRecord?
    func job(jobType: JobType, idempotencyKey: JobIdempotencyKey) async throws -> JobRecord?
    func jobs(states: Set<JobState>?) async throws -> [JobRecord]
    func replace(
        _ record: JobRecord,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) async throws
    func validateInputRevisionsAreCurrent(_ revisions: [SemanticRevisionReference]) async throws
    func databaseHealth() async throws -> TaskDatabaseHealth
}

public protocol TaskTemporaryStorage: Sendable {
    func allocateDirectory(
        for jobID: JobID,
        diskBudgetBytes: UInt64
    ) async throws -> TaskDirectoryLease

    func reuseDirectory(_ lease: TaskDirectoryLease) async throws

    func write(
        _ data: Data,
        to relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor

    func prepareWritableFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskWritableFileLease

    func finalizeWritableFile(
        _ writableFile: TaskWritableFileLease,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor

    func inspectFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor?

    func verifiedFileURL(
        for descriptor: TaskTemporaryFileDescriptor,
        in lease: TaskDirectoryLease
    ) async throws -> URL

    func discardWritableFile(
        _ writableFile: TaskWritableFileLease,
        in lease: TaskDirectoryLease
    ) async throws

    func discardFile(
        at relativePathWithinTask: WorkspaceRelativePath,
        in lease: TaskDirectoryLease
    ) async throws

    func usage(of lease: TaskDirectoryLease) async throws -> TaskDirectoryUsage
    func cleanupDirectory(_ lease: TaskDirectoryLease) async throws
    func availableCapacityBytes() async throws -> UInt64?

    /// Inspects only immediate `.tasks` children and stops at `maximumEntries`.
    func scanOrphans(
        expectedJobIDs: Set<JobID>,
        maximumEntries: UInt32
    ) async throws -> TaskOrphanScan

    /// Removes only previously identified, non-symlink candidates older than
    /// the cutoff, and never removes more than `maximumRemovals`.
    func cleanupOrphans(
        _ candidates: [TaskOrphanDirectory],
        olderThan cutoff: UTCInstant,
        maximumRemovals: UInt32
    ) async throws -> TaskOrphanCleanupReport
}

public enum TaskLogLevel: String, Codable, Hashable, Sendable {
    case debug
    case info
    case notice
    case error
}

public enum TaskLogValue: Sendable {
    case publicValue(String)
    case privateValue(String)
}

public struct TaskLogEvent: Sendable {
    public let timestamp: UTCInstant
    public let level: TaskLogLevel
    public let category: String
    public let jobID: JobID?
    public let message: TaskLogValue
    public let metadata: [String: TaskLogValue]

    public init(
        timestamp: UTCInstant,
        level: TaskLogLevel,
        category: String,
        jobID: JobID? = nil,
        message: TaskLogValue,
        metadata: [String: TaskLogValue] = [:]
    ) throws {
        guard !category.isEmpty,
              category.utf8.count <= 64,
              category.utf8.allSatisfy({
                  ($0 >= 97 && $0 <= 122)
                      || ($0 >= 48 && $0 <= 57)
                      || $0 == 45
                      || $0 == 95
              }),
              metadata.count <= 32,
              metadata.keys.allSatisfy({ key in
                  !key.isEmpty && key.utf8.count <= 64
                      && key.utf8.allSatisfy({
                          ($0 >= 97 && $0 <= 122)
                              || ($0 >= 48 && $0 <= 57)
                              || $0 == 45
                              || $0 == 95
                      })
              })
        else {
            throw TaskRuntimeError.logConfigurationInvalid(
                "Log categories and metadata keys must be bounded lowercase identifiers."
            )
        }
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.jobID = jobID
        self.message = message
        self.metadata = metadata
    }
}

public struct TaskLogRotationReport: Codable, Hashable, Sendable {
    public let archivedFileCount: UInt32
    public let removedFileCount: UInt32
    public let activeFileByteSize: UInt64

    public init(
        archivedFileCount: UInt32,
        removedFileCount: UInt32,
        activeFileByteSize: UInt64
    ) {
        self.archivedFileCount = archivedFileCount
        self.removedFileCount = removedFileCount
        self.activeFileByteSize = activeFileByteSize
    }
}

public protocol TaskLogStore: Sendable {
    func record(_ event: TaskLogEvent) async throws
    func rotate(at timestamp: UTCInstant) async throws -> TaskLogRotationReport
}

public struct ManagedAssetRecoveryReport: Codable, Hashable, Sendable {
    public let reconciledOperationCount: UInt32
    public let rolledBackOperationCount: UInt32
    public let repairRequiredOperationCount: UInt32
    public let truncated: Bool

    public init(
        reconciledOperationCount: UInt32,
        rolledBackOperationCount: UInt32,
        repairRequiredOperationCount: UInt32,
        truncated: Bool
    ) {
        self.reconciledOperationCount = reconciledOperationCount
        self.rolledBackOperationCount = rolledBackOperationCount
        self.repairRequiredOperationCount = repairRequiredOperationCount
        self.truncated = truncated
    }

    public static let empty = ManagedAssetRecoveryReport(
        reconciledOperationCount: 0,
        rolledBackOperationCount: 0,
        repairRequiredOperationCount: 0,
        truncated: false
    )
}

public protocol ManagedAssetRecoveryService: Sendable {
    func reconcileInterruptedOperations(
        at timestamp: UTCInstant,
        maximumOperations: UInt32
    ) async throws -> ManagedAssetRecoveryReport
}

public struct StartupRecoveryPolicy: Sendable {
    public let maximumOrphansToInspect: UInt32
    public let maximumOrphansToRemove: UInt32
    public let orphanGracePeriodMilliseconds: Int64
    public let minimumAvailableCapacityBytes: UInt64
    public let maximumManagedAssetOperations: UInt32

    public init(
        maximumOrphansToInspect: UInt32 = 256,
        maximumOrphansToRemove: UInt32 = 32,
        orphanGracePeriodMilliseconds: Int64 = 86_400_000,
        minimumAvailableCapacityBytes: UInt64 = 536_870_912,
        maximumManagedAssetOperations: UInt32 = 128
    ) throws {
        guard maximumOrphansToInspect > 0,
              maximumOrphansToInspect <= 4_096,
              maximumOrphansToRemove <= maximumOrphansToInspect,
              orphanGracePeriodMilliseconds >= 0,
              maximumManagedAssetOperations > 0,
              maximumManagedAssetOperations <= 4_096
        else {
            throw TaskRuntimeError.startupCheckFailed("Startup recovery bounds are invalid.")
        }
        self.maximumOrphansToInspect = maximumOrphansToInspect
        self.maximumOrphansToRemove = maximumOrphansToRemove
        self.orphanGracePeriodMilliseconds = orphanGracePeriodMilliseconds
        self.minimumAvailableCapacityBytes = minimumAvailableCapacityBytes
        self.maximumManagedAssetOperations = maximumManagedAssetOperations
    }
}

public struct StartupHealthReport: Sendable {
    public let checkedAt: UTCInstant
    public let databaseHealth: TaskDatabaseHealth
    public let interruptedJobIDs: [JobID]
    public let orphanScan: TaskOrphanScan
    public let orphanCleanup: TaskOrphanCleanupReport
    public let managedAssetRecovery: ManagedAssetRecoveryReport
    public let logRotation: TaskLogRotationReport
    public let availableCapacityBytes: UInt64?
    public let capacityIsSufficient: Bool

    public init(
        checkedAt: UTCInstant,
        databaseHealth: TaskDatabaseHealth,
        interruptedJobIDs: [JobID],
        orphanScan: TaskOrphanScan,
        orphanCleanup: TaskOrphanCleanupReport,
        managedAssetRecovery: ManagedAssetRecoveryReport,
        logRotation: TaskLogRotationReport,
        availableCapacityBytes: UInt64?,
        capacityIsSufficient: Bool
    ) {
        self.checkedAt = checkedAt
        self.databaseHealth = databaseHealth
        self.interruptedJobIDs = interruptedJobIDs.sorted()
        self.orphanScan = orphanScan
        self.orphanCleanup = orphanCleanup
        self.managedAssetRecovery = managedAssetRecovery
        self.logRotation = logRotation
        self.availableCapacityBytes = availableCapacityBytes
        self.capacityIsSufficient = capacityIsSufficient
    }

    public var isHealthy: Bool {
        databaseHealth.isHealthy
            && capacityIsSufficient
            && managedAssetRecovery.repairRequiredOperationCount == 0
            && !managedAssetRecovery.truncated
            && !orphanScan.truncated
    }
}

public protocol TaskClock: Sendable {
    func now() -> UTCInstant
}

public struct JobExecutionContext: Sendable {
    public let job: JobRecord
    public let temporaryDirectory: TaskDirectoryLease

    private let checkpointOperation: @Sendable (JobProgress, JobCheckpoint?) async throws -> Void
    private let writeOperation: @Sendable (
        Data,
        WorkspaceRelativePath
    ) async throws -> TaskTemporaryFileDescriptor
    private let prepareWritableFileOperation: @Sendable (
        WorkspaceRelativePath
    ) async throws -> TaskWritableFileLease
    private let finalizeWritableFileOperation: @Sendable (
        TaskWritableFileLease
    ) async throws -> TaskTemporaryFileDescriptor
    private let inspectFileOperation: @Sendable (
        WorkspaceRelativePath
    ) async throws -> TaskTemporaryFileDescriptor?
    private let verifiedFileURLOperation: @Sendable (
        TaskTemporaryFileDescriptor
    ) async throws -> URL
    private let discardWritableFileOperation: @Sendable (
        TaskWritableFileLease
    ) async throws -> Void
    private let discardFileOperation: @Sendable (
        WorkspaceRelativePath
    ) async throws -> Void

    public init(
        job: JobRecord,
        checkpointOperation: @escaping @Sendable (
            JobProgress,
            JobCheckpoint?
        ) async throws -> Void,
        writeOperation: @escaping @Sendable (
            Data,
            WorkspaceRelativePath
        ) async throws -> TaskTemporaryFileDescriptor,
        prepareWritableFileOperation: @escaping @Sendable (
            WorkspaceRelativePath
        ) async throws -> TaskWritableFileLease,
        finalizeWritableFileOperation: @escaping @Sendable (
            TaskWritableFileLease
        ) async throws -> TaskTemporaryFileDescriptor,
        inspectFileOperation: @escaping @Sendable (
            WorkspaceRelativePath
        ) async throws -> TaskTemporaryFileDescriptor?,
        verifiedFileURLOperation: @escaping @Sendable (
            TaskTemporaryFileDescriptor
        ) async throws -> URL,
        discardWritableFileOperation: @escaping @Sendable (
            TaskWritableFileLease
        ) async throws -> Void,
        discardFileOperation: @escaping @Sendable (
            WorkspaceRelativePath
        ) async throws -> Void
    ) {
        self.job = job
        self.temporaryDirectory = job.temporaryDirectory
        self.checkpointOperation = checkpointOperation
        self.writeOperation = writeOperation
        self.prepareWritableFileOperation = prepareWritableFileOperation
        self.finalizeWritableFileOperation = finalizeWritableFileOperation
        self.inspectFileOperation = inspectFileOperation
        self.verifiedFileURLOperation = verifiedFileURLOperation
        self.discardWritableFileOperation = discardWritableFileOperation
        self.discardFileOperation = discardFileOperation
    }

    public func checkpoint(
        progress: JobProgress,
        durableCheckpoint: JobCheckpoint? = nil
    ) async throws {
        try Task.checkCancellation()
        try await checkpointOperation(progress, durableCheckpoint)
    }

    public func writeTemporaryFile(
        _ data: Data,
        to relativePathWithinTask: WorkspaceRelativePath
    ) async throws -> TaskTemporaryFileDescriptor {
        try Task.checkCancellation()
        return try await writeOperation(data, relativePathWithinTask)
    }

    public func prepareWritableFile(
        at relativePathWithinTask: WorkspaceRelativePath
    ) async throws -> TaskWritableFileLease {
        try Task.checkCancellation()
        return try await prepareWritableFileOperation(relativePathWithinTask)
    }

    public func finalizeWritableFile(
        _ writableFile: TaskWritableFileLease
    ) async throws -> TaskTemporaryFileDescriptor {
        try Task.checkCancellation()
        return try await finalizeWritableFileOperation(writableFile)
    }

    public func inspectTemporaryFile(
        at relativePathWithinTask: WorkspaceRelativePath
    ) async throws -> TaskTemporaryFileDescriptor? {
        try Task.checkCancellation()
        return try await inspectFileOperation(relativePathWithinTask)
    }

    public func verifiedTemporaryFileURL(
        for descriptor: TaskTemporaryFileDescriptor
    ) async throws -> URL {
        try Task.checkCancellation()
        return try await verifiedFileURLOperation(descriptor)
    }

    public func discardWritableFile(
        _ writableFile: TaskWritableFileLease
    ) async throws {
        try await discardWritableFileOperation(writableFile)
    }

    public func discardTemporaryFile(
        at relativePathWithinTask: WorkspaceRelativePath
    ) async throws {
        try await discardFileOperation(relativePathWithinTask)
    }
}

public protocol TaskJobExecutor: Sendable {
    var jobType: JobType { get }
    func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult
}

public protocol TaskRuntimeManaging: Sendable {
    func enqueue(_ request: JobRequest) async throws -> JobRecord
    func job(id: JobID) async throws -> JobRecord?
    func jobs() async throws -> [JobRecord]
    func pause(jobID: JobID) async throws -> JobRecord
    func resume(jobID: JobID) async throws -> JobRecord
    func cancel(jobID: JobID) async throws -> JobRecord
    func retry(jobID: JobID) async throws -> JobRecord
    func runEligibleJobs() async throws
    func recoverAtStartup(policy: StartupRecoveryPolicy) async throws -> StartupHealthReport
}
