import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyPersistence
import MeetingBuddyTasks

final class TaskTestWorkspace: @unchecked Sendable {
    let container: URL
    let root: URL
    let descriptor: LocalWorkspaceDescriptor
    let store: SQLitePersistenceStore
    let repository: SQLiteJobRepository
    let temporaryStorage: LocalTaskTemporaryStorage
    let logStore: RotatingTaskLogStore

    init(
        suffix: String = UUID().uuidString.lowercased(),
        logConfiguration: TaskLogConfiguration? = nil
    ) throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingbuddy-task004b-\(suffix)", isDirectory: true)
        root = container.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        descriptor = try LocalWorkspaceService().createWorkspace(
            at: root,
            workspaceID: testWorkspaceID(1),
            createdAt: testInstant(1_800_000_000_000)
        )
        store = try SQLitePersistenceStore(
            workspace: descriptor,
            migrationTimestamp: testInstant(1_800_000_000_001)
        )
        repository = SQLiteJobRepository(store: store)
        temporaryStorage = LocalTaskTemporaryStorage(workspace: descriptor)
        logStore = RotatingTaskLogStore(
            workspace: descriptor,
            configuration: try logConfiguration ?? TaskLogConfiguration()
        )
    }

    func cleanup() {
        try? store.close()
        try? FileManager.default.removeItem(at: container)
    }
}

final class SteppingTaskClock: TaskClock, @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: Int64

    init(start: Int64 = 1_800_000_100_000) {
        milliseconds = start
    }

    func now() -> UTCInstant {
        lock.lock()
        defer { lock.unlock() }
        let value = milliseconds
        milliseconds += 1
        return testInstant(value)
    }
}

struct ClosureTaskExecutor: TaskJobExecutor {
    let jobType: JobType
    let operation: @Sendable (JobExecutionContext) async throws -> JobExecutionResult

    init(
        jobType: JobType,
        operation: @escaping @Sendable (JobExecutionContext) async throws -> JobExecutionResult
    ) {
        self.jobType = jobType
        self.operation = operation
    }

    func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        try await operation(context)
    }
}

func makeTaskRequest(
    suffix: Int,
    jobType: JobType,
    resumeCapability: JobResumeCapability = .restartOnly,
    maximumRetryCount: UInt32 = 0,
    totalUnitCount: UInt64 = 1,
    diskBudgetBytes: UInt64 = 65_536,
    dependencies: [JobID] = []
) throws -> JobRequest {
    try JobRequest(
        jobID: testJobID(suffix),
        jobType: jobType,
        origin: .application,
        requestedBy: JobRequester("meetingbuddy-test"),
        dependencyJobIDs: dependencies,
        dataClassification: .internal,
        idempotencyKey: testIdempotencyKey(UInt8(truncatingIfNeeded: suffix)),
        resumeCapability: resumeCapability,
        maximumRetryCount: maximumRetryCount,
        totalUnitCount: totalUnitCount,
        diskBudgetBytes: diskBudgetBytes
    )
}

func waitForJob(
    _ manager: LocalTaskManager,
    jobID: JobID,
    state: JobState,
    attempts: Int = 400
) async throws -> JobRecord {
    for _ in 0..<attempts {
        if let record = try await manager.job(id: jobID), record.state == state {
            return record
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    let latest = try await manager.job(id: jobID)
    throw TaskRuntimeError.startupCheckFailed(
        "Timed out waiting for job \(jobID) to reach \(state.rawValue); latest="
            + (latest?.state.rawValue ?? "missing")
            + ", error="
            + (latest?.errorRecord?.code ?? "none")
    )
}

func testWorkspaceID(_ suffix: Int) -> WorkspaceID {
    WorkspaceID(
        UUID(uuidString: String(format: "4b100000-0000-0000-0000-%012d", suffix))!
    )
}

func testInstant(_ milliseconds: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
}
