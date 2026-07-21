import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyPersistence
import MeetingBuddyTasks
import Testing

@Suite(.serialized)
struct TaskManagerTests {
    @Test
    func enqueueRejectsUnregisteredJobTypeWithoutAllocatingTemporaryData() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            executors: []
        )
        let request = try makeTaskRequest(
            suffix: 40,
            jobType: JobType("unregistered-job")
        )
        await #expect(throws: TaskRuntimeError.self) {
            _ = try await manager.enqueue(request)
        }
        #expect(try await manager.job(id: request.jobID) == nil)
        let directory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)"
        )
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func schedulerEnforcesConcurrencyAndCompletesQueuedJobs() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let probe = ConcurrencyProbe()
        let jobType = try JobType("bounded-concurrency")
        let executor = ClosureTaskExecutor(jobType: jobType) { _ in
            await probe.enter()
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                await probe.leave()
                let usage = try ProviderUsageMetadata(
                    provider: ProviderMetadata(
                        providerIdentifier: "synthetic-provider",
                        modelIdentifier: "synthetic-model"
                    ),
                    inputUnitCount: 100,
                    outputUnitCount: 20
                )
                return try JobExecutionResult(providerUsage: [usage])
            } catch {
                await probe.leave()
                throw error
            }
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 2,
            executors: [executor]
        )
        for suffix in 41...43 {
            _ = try await manager.enqueue(
                makeTaskRequest(suffix: suffix, jobType: jobType)
            )
        }
        for suffix in 41...43 {
            let succeeded = try await waitForJob(
                manager,
                jobID: testJobID(suffix),
                state: .succeeded
            )
            #expect(succeeded.providerUsage.first?.inputUnitCount == 100)
            #expect(succeeded.providerUsage.first?.outputUnitCount == 20)
        }
        #expect(await probe.maximumActive == 2)
        #expect(await probe.active == 0)
    }

    @Test
    func pauseWaitsForDurableCheckpointAndResumeContinuesSameAttempt() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let jobType = try JobType("checkpointed-work")
        let executor = ClosureTaskExecutor(jobType: jobType) { context in
            for unit in 1...40 {
                let checkpoint = try JobCheckpoint(
                    formatVersion: 1,
                    payload: Data("checkpoint-\(unit)".utf8)
                )
                try await context.checkpoint(
                    progress: JobProgress(
                        completedUnitCount: UInt64(unit),
                        totalUnitCount: 40,
                        currentNode: "unit-\(unit)"
                    ),
                    durableCheckpoint: checkpoint
                )
                try await Task.sleep(nanoseconds: 3_000_000)
            }
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(
            suffix: 51,
            jobType: jobType,
            resumeCapability: .checkpointed,
            totalUnitCount: 40
        )
        _ = try await manager.enqueue(request)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .running)
        _ = try await manager.pause(jobID: request.jobID)
        let paused = try await waitForJob(manager, jobID: request.jobID, state: .paused)
        #expect(paused.checkpoint != nil)
        #expect(paused.progress.completedUnitCount > 0)
        _ = try await manager.resume(jobID: request.jobID)
        let succeeded = try await waitForJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        #expect(succeeded.retryCount == 0)
        #expect(succeeded.progress.completedUnitCount == 40)
    }

    @Test
    func naturalCompletionWinsWhenPauseArrivesAfterLastCheckpoint() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let release = ExecutionRelease()
        let jobType = try JobType("pause-completion-race")
        let executor = ClosureTaskExecutor(jobType: jobType) { _ in
            await release.wait()
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(
            suffix: 52,
            jobType: jobType,
            resumeCapability: .checkpointed
        )
        _ = try await manager.enqueue(request)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .running)
        let pauseRequested = try await manager.pause(jobID: request.jobID)
        #expect(pauseRequested.state == .pauseRequested)
        await release.release()
        let succeeded = try await waitForJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        #expect(succeeded.checkpoint == nil)
    }

    @Test
    func naturalCompletionWinsWhenCancellationArrivesAfterExecutorCommit() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let release = ExecutionRelease()
        let jobType = try JobType("cancellation-completion-race")
        let executor = ClosureTaskExecutor(jobType: jobType) { _ in
            await release.wait()
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(suffix: 53, jobType: jobType)
        _ = try await manager.enqueue(request)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .running)
        let cancellationRequested = try await manager.cancel(jobID: request.jobID)
        #expect(cancellationRequested.state == .cancellationRequested)
        await release.release()
        _ = try await waitForJob(manager, jobID: request.jobID, state: .succeeded)
    }

    @Test
    func cancellationIsCooperativeAndCleansJobOwnedTemporaryData() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let jobType = try JobType("cancellable-work")
        let executor = ClosureTaskExecutor(jobType: jobType) { context in
            _ = try await context.writeTemporaryFile(
                Data("temporary-sensitive-input".utf8),
                to: WorkspaceRelativePath("work/input.bin")
            )
            for unit in 1...100 {
                try await context.checkpoint(
                    progress: JobProgress(
                        completedUnitCount: UInt64(unit),
                        totalUnitCount: 100
                    )
                )
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(
            suffix: 61,
            jobType: jobType,
            totalUnitCount: 100
        )
        _ = try await manager.enqueue(request)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .running)
        _ = try await manager.cancel(jobID: request.jobID)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .cancelled)
        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))
    }

    @Test
    func retryIncrementsMetadataAndRerunsOnlyAfterExplicitRequest() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let attempts = AttemptCounter()
        let jobType = try JobType("retryable-work")
        let executor = ClosureTaskExecutor(jobType: jobType) { _ in
            let attempt = await attempts.next()
            if attempt == 1 {
                throw try JobExecutionFailure(
                    code: "synthetic_failure",
                    safeSummary: "The synthetic first attempt failed.",
                    retryable: true,
                    privateDiagnostic: "private fixture detail"
                )
            }
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(
            suffix: 71,
            jobType: jobType,
            maximumRetryCount: 1
        )
        _ = try await manager.enqueue(request)
        let failed = try await waitForJob(manager, jobID: request.jobID, state: .failed)
        #expect(failed.retryCount == 0)
        #expect(failed.errorRecord?.code == "synthetic_failure")
        _ = try await manager.retry(jobID: request.jobID)
        let succeeded = try await waitForJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        #expect(succeeded.retryCount == 1)
        #expect(await attempts.value == 2)
    }

    @Test
    func checkpointedFailureRetriesFromDurableNodeAndOwnedDirectory() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let attempts = AttemptCounter()
        let observation = ResumeObservation()
        let jobType = try JobType("checkpoint-retry")
        let executor = ClosureTaskExecutor(jobType: jobType) { context in
            let attempt = await attempts.next()
            if attempt == 1 {
                _ = try await context.writeTemporaryFile(
                    Data("retained-checkpoint-input".utf8),
                    to: WorkspaceRelativePath("checkpoint/input.bin")
                )
                try await context.checkpoint(
                    progress: JobProgress(
                        completedUnitCount: 2,
                        totalUnitCount: 4,
                        currentNode: "chunk-2"
                    ),
                    durableCheckpoint: JobCheckpoint(
                        formatVersion: 1,
                        payload: Data("resume-chunk-2".utf8)
                    )
                )
                throw try JobExecutionFailure(
                    code: "retryable_chunk_failure",
                    safeSummary: "The synthetic chunk failed after a durable checkpoint.",
                    retryable: true
                )
            }
            await observation.record(
                resumedAtUnit: context.job.progress.completedUnitCount,
                checkpoint: context.job.checkpoint
            )
            _ = try await context.writeTemporaryFile(
                Data("continued".utf8),
                to: WorkspaceRelativePath("checkpoint/continued.bin")
            )
            return try JobExecutionResult()
        }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(),
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try makeTaskRequest(
            suffix: 72,
            jobType: jobType,
            resumeCapability: .checkpointed,
            maximumRetryCount: 1,
            totalUnitCount: 4
        )
        _ = try await manager.enqueue(request)
        let failed = try await waitForJob(manager, jobID: request.jobID, state: .failed)
        #expect(failed.progress.completedUnitCount == 2)
        #expect(failed.checkpoint?.payload == Data("resume-chunk-2".utf8))
        #expect(try await workspace.temporaryStorage.usage(of: failed.temporaryDirectory).byteSize > 0)

        _ = try await manager.retry(jobID: request.jobID)
        _ = try await waitForJob(manager, jobID: request.jobID, state: .succeeded)
        #expect(await observation.resumedAtUnit == 2)
        #expect(await observation.checkpointPayload == Data("resume-chunk-2".utf8))
        let directory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)"
        )
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func startupRecoveryCleansAnInterruptedJobWithNoRetryAuthority() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let request = try makeTaskRequest(
            suffix: 83,
            jobType: JobType("nonretryable-crash-recovery")
        )
        let lease = try await workspace.temporaryStorage.allocateDirectory(
            for: request.jobID,
            diskBudgetBytes: request.diskBudgetBytes
        )
        let queued = try JobRecord(
            request: request,
            lease: lease,
            createdAt: testInstant(1_800_000_650_000)
        )
        try await workspace.repository.create(queued)
        let running = try queued.transitioning(
            to: .running,
            at: testInstant(1_800_000_650_001)
        )
        try await workspace.repository.replace(
            running,
            expectedVersion: queued.recordVersion,
            changedAt: testInstant(1_800_000_650_001)
        )
        _ = try await workspace.temporaryStorage.write(
            Data("nonretryable-interrupted-data".utf8),
            to: WorkspaceRelativePath("intake/partial.bin"),
            in: lease
        )

        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(start: 1_800_000_700_000),
            executors: []
        )
        let report = try await manager.recoverAtStartup(
            policy: StartupRecoveryPolicy(
                maximumOrphansToInspect: 16,
                maximumOrphansToRemove: 4,
                orphanGracePeriodMilliseconds: 0,
                minimumAvailableCapacityBytes: 0,
                maximumManagedAssetOperations: 16
            )
        )
        #expect(report.interruptedJobIDs == [request.jobID])
        let interrupted = try #require(await manager.job(id: request.jobID))
        #expect(interrupted.state == .interrupted)
        #expect(interrupted.errorRecord?.retryable == false)
        let directory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func startupRecoveryMarksInterruptedWorkAndRetainsItsCheckpointDirectory() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let request = try makeTaskRequest(
            suffix: 81,
            jobType: JobType("crash-recovery"),
            resumeCapability: .checkpointed,
            maximumRetryCount: 1,
            totalUnitCount: 10
        )
        let lease = try await workspace.temporaryStorage.allocateDirectory(
            for: request.jobID,
            diskBudgetBytes: request.diskBudgetBytes
        )
        let queued = try JobRecord(
            request: request,
            lease: lease,
            createdAt: testInstant(1_800_000_600_000)
        )
        try await workspace.repository.create(queued)
        let running = try queued.transitioning(
            to: .running,
            at: testInstant(1_800_000_600_001)
        )
        try await workspace.repository.replace(
            running,
            expectedVersion: queued.recordVersion,
            changedAt: testInstant(1_800_000_600_001)
        )
        let checkpointed = try running.updatingProgress(
            JobProgress(completedUnitCount: 4, totalUnitCount: 10),
            checkpoint: JobCheckpoint(formatVersion: 1, payload: Data("durable".utf8))
        )
        try await workspace.repository.replace(
            checkpointed,
            expectedVersion: running.recordVersion,
            changedAt: testInstant(1_800_000_600_002)
        )
        _ = try await workspace.temporaryStorage.write(
            Data("recoverable-checkpoint-data".utf8),
            to: WorkspaceRelativePath("checkpoint/data.bin"),
            in: lease
        )

        let retryableRequest = try makeTaskRequest(
            suffix: 82,
            jobType: JobType("checkpointed-failure-recovery"),
            resumeCapability: .checkpointed,
            maximumRetryCount: 1,
            totalUnitCount: 10
        )
        let retryableLease = try await workspace.temporaryStorage.allocateDirectory(
            for: retryableRequest.jobID,
            diskBudgetBytes: retryableRequest.diskBudgetBytes
        )
        let retryableQueued = try JobRecord(
            request: retryableRequest,
            lease: retryableLease,
            createdAt: testInstant(1_800_000_600_010)
        )
        try await workspace.repository.create(retryableQueued)
        let retryableRunning = try retryableQueued.transitioning(
            to: .running,
            at: testInstant(1_800_000_600_011)
        )
        try await workspace.repository.replace(
            retryableRunning,
            expectedVersion: retryableQueued.recordVersion,
            changedAt: testInstant(1_800_000_600_011)
        )
        let retryableCheckpointed = try retryableRunning.updatingProgress(
            JobProgress(completedUnitCount: 6, totalUnitCount: 10),
            checkpoint: JobCheckpoint(formatVersion: 1, payload: Data("retry-node".utf8))
        )
        try await workspace.repository.replace(
            retryableCheckpointed,
            expectedVersion: retryableRunning.recordVersion,
            changedAt: testInstant(1_800_000_600_012)
        )
        let retryableFailed = try retryableCheckpointed.transitioning(
            to: .failed,
            at: testInstant(1_800_000_600_013),
            failure: JobFailureRecord(
                code: "retryable_node_failure",
                safeSummary: "The durable node can be retried.",
                retryable: true,
                occurredAt: testInstant(1_800_000_600_013)
            )
        )
        try await workspace.repository.replace(
            retryableFailed,
            expectedVersion: retryableCheckpointed.recordVersion,
            changedAt: testInstant(1_800_000_600_013)
        )
        _ = try await workspace.temporaryStorage.write(
            Data("retryable-checkpoint-data".utf8),
            to: WorkspaceRelativePath("checkpoint/retry.bin"),
            in: retryableLease
        )
        let assetRecovery = ManagedAssetRecoveryProbe()

        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            managedAssetRecovery: assetRecovery,
            clock: SteppingTaskClock(start: 1_800_000_700_000),
            maximumConcurrentJobs: 1,
            executors: []
        )
        let report = try await manager.recoverAtStartup(
            policy: StartupRecoveryPolicy(
                maximumOrphansToInspect: 16,
                maximumOrphansToRemove: 4,
                orphanGracePeriodMilliseconds: 0,
                minimumAvailableCapacityBytes: 0,
                maximumManagedAssetOperations: 16
            )
        )
        #expect(report.interruptedJobIDs == [request.jobID])
        #expect(report.databaseHealth.isHealthy)
        #expect(report.availableCapacityBytes != nil)
        #expect(report.isHealthy)
        #expect(report.managedAssetRecovery.reconciledOperationCount == 1)
        #expect(await assetRecovery.requestedMaximum == 16)
        let truncatedRecovery = StartupHealthReport(
            checkedAt: report.checkedAt,
            databaseHealth: report.databaseHealth,
            interruptedJobIDs: report.interruptedJobIDs,
            orphanScan: report.orphanScan,
            orphanCleanup: report.orphanCleanup,
            managedAssetRecovery: ManagedAssetRecoveryReport(
                reconciledOperationCount: 0,
                rolledBackOperationCount: 0,
                repairRequiredOperationCount: 0,
                truncated: true
            ),
            logRotation: report.logRotation,
            availableCapacityBytes: report.availableCapacityBytes,
            capacityIsSufficient: true
        )
        #expect(!truncatedRecovery.isHealthy)
        let interrupted = try #require(await manager.job(id: request.jobID))
        #expect(interrupted.state == .interrupted)
        #expect(interrupted.checkpoint == checkpointed.checkpoint)
        #expect(try await workspace.temporaryStorage.usage(of: lease).byteSize > 0)
        let retainedFailure = try #require(await manager.job(id: retryableRequest.jobID))
        #expect(retainedFailure.state == .failed)
        #expect(retainedFailure.checkpoint == retryableFailed.checkpoint)
        #expect(
            try await workspace.temporaryStorage.usage(of: retryableLease).byteSize > 0
        )
    }

    @Test
    func historicalIndexRebuildRunsOnlyThroughTheLocalTaskManagerRoute() async throws {
        let workspace = try TaskTestWorkspace(suffix: "historical-index")
        defer { workspace.cleanup() }
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            clock: SteppingTaskClock(start: 1_800_000_800_000),
            maximumConcurrentJobs: 1,
            executors: [HistoricalIndexRebuildJobExecutor(repository: workspace.store)]
        )
        let plan = try HistoricalIndexRebuildJobPlan(
            requestedAt: testInstant(1_800_000_800_100)
        )
        let request = try HistoricalIndexRebuildJobFactory().request(
            plan: plan,
            jobID: testJobID(810),
            requestedBy: JobRequester("task010-test")
        )
        #expect(request.jobType == HistoricalReviewJobTypes.indexRebuild)
        #expect(request.privacyRoute == .localOnly)
        #expect(request.dataClassification == .restricted)
        #expect(request.inputRevisionIDs.isEmpty)
        #expect(request.meetingID == nil)

        _ = try await manager.enqueue(request)
        let succeeded = try await waitForJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        #expect(succeeded.progress.completedUnitCount == 1)
        #expect(succeeded.progress.currentNode == "historical-index-ready")
        let index = try workspace.store.historicalIndexStatus()
        #expect(index.availability == .ready)
        #expect(index.generation == 1)
        #expect(index.indexedPositionCount == 0)
    }
}

private actor ConcurrencyProbe {
    private(set) var active = 0
    private(set) var maximumActive = 0

    func enter() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func leave() {
        active -= 1
    }
}

private actor AttemptCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private actor ManagedAssetRecoveryProbe: ManagedAssetRecoveryService {
    private(set) var requestedMaximum: UInt32?

    func reconcileInterruptedOperations(
        at _: UTCInstant,
        maximumOperations: UInt32
    ) async throws -> ManagedAssetRecoveryReport {
        requestedMaximum = maximumOperations
        return ManagedAssetRecoveryReport(
            reconciledOperationCount: 1,
            rolledBackOperationCount: 0,
            repairRequiredOperationCount: 0,
            truncated: false
        )
    }
}

private actor ExecutionRelease {
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor ResumeObservation {
    private(set) var resumedAtUnit: UInt64?
    private(set) var checkpointPayload: Data?

    func record(resumedAtUnit: UInt64, checkpoint: JobCheckpoint?) {
        self.resumedAtUnit = resumedAtUnit
        checkpointPayload = checkpoint?.payload
    }
}
