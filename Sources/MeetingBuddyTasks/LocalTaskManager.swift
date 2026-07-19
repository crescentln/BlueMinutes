import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public actor LocalTaskManager: TaskRuntimeManaging {
    private let repository: any JobRepository
    private let temporaryStorage: any TaskTemporaryStorage
    private let logStore: any TaskLogStore
    private let managedAssetRecovery: (any ManagedAssetRecoveryService)?
    private let clock: any TaskClock
    private let maximumConcurrentJobs: Int
    private let executors: [JobType: any TaskJobExecutor]

    private var runningTasks: [JobID: Task<Void, Never>] = [:]
    private var executionGates: [JobID: ExecutionGate] = [:]

    public init(
        repository: any JobRepository,
        temporaryStorage: any TaskTemporaryStorage,
        logStore: any TaskLogStore,
        managedAssetRecovery: (any ManagedAssetRecoveryService)? = nil,
        clock: any TaskClock = SystemTaskClock(),
        maximumConcurrentJobs: Int = 2,
        executors: [any TaskJobExecutor]
    ) throws {
        guard (1...16).contains(maximumConcurrentJobs) else {
            throw JobContractError.invalidRequest(
                "The Task Manager concurrency limit must be between 1 and 16."
            )
        }
        var executorMap: [JobType: any TaskJobExecutor] = [:]
        for executor in executors {
            guard executorMap[executor.jobType] == nil else {
                throw TaskRuntimeError.duplicateExecutor(executor.jobType)
            }
            executorMap[executor.jobType] = executor
        }
        self.repository = repository
        self.temporaryStorage = temporaryStorage
        self.logStore = logStore
        self.managedAssetRecovery = managedAssetRecovery
        self.clock = clock
        self.maximumConcurrentJobs = maximumConcurrentJobs
        self.executors = executorMap
    }

    deinit {
        for task in runningTasks.values {
            task.cancel()
        }
    }

    public func enqueue(_ request: JobRequest) async throws -> JobRecord {
        guard executors[request.jobType] != nil else {
            throw TaskRuntimeError.executorUnavailable(request.jobType)
        }
        if let existing = try await repository.job(
            jobType: request.jobType,
            idempotencyKey: request.idempotencyKey
        ) {
            return existing
        }
        let lease = try await temporaryStorage.allocateDirectory(
            for: request.jobID,
            diskBudgetBytes: request.diskBudgetBytes
        )
        let createdAt = clock.now()
        let record = try JobRecord(request: request, lease: lease, createdAt: createdAt)
        do {
            try await repository.create(record)
        } catch {
            try? await temporaryStorage.cleanupDirectory(lease)
            if case JobContractError.duplicateIdempotencyKey = error,
               let existing = try await repository.job(
                   jobType: request.jobType,
                   idempotencyKey: request.idempotencyKey
               )
            {
                return existing
            }
            throw error
        }
        await log(
            level: .info,
            category: "job-state",
            jobID: record.jobID,
            message: .publicValue("Job queued")
        )
        try await scheduleEligibleJobs()
        return record
    }

    public func job(id: JobID) async throws -> JobRecord? {
        try await repository.job(id: id)
    }

    public func jobs() async throws -> [JobRecord] {
        try await repository.jobs(states: nil)
    }

    public func pause(jobID: JobID) async throws -> JobRecord {
        guard let gate = executionGates[jobID] else {
            throw TaskRuntimeError.pauseUnsupported(jobID)
        }
        await gate.prepareToPause()
        do {
            for _ in 0..<8 {
                let current = try await requireJob(jobID)
                if current.state == .pauseRequested || current.state == .paused {
                    return current
                }
                guard current.state == .running,
                      current.resumeCapability == .checkpointed
                else {
                    throw TaskRuntimeError.pauseUnsupported(jobID)
                }
                let now = clock.now()
                let replacement = try current.transitioning(to: .pauseRequested, at: now)
                do {
                    try await repository.replace(
                        replacement,
                        expectedVersion: current.recordVersion,
                        changedAt: now
                    )
                    await log(
                        level: .notice,
                        category: "job-state",
                        jobID: jobID,
                        message: .publicValue("Pause requested")
                    )
                    return replacement
                } catch JobContractError.optimisticLockFailed {
                    continue
                }
            }
            throw JobContractError.optimisticLockFailed(jobID)
        } catch {
            await gate.resume()
            throw error
        }
    }

    public func resume(jobID: JobID) async throws -> JobRecord {
        let current = try await requireJob(jobID)
        guard current.state == .paused, let gate = executionGates[jobID] else {
            throw JobContractError.transitionNotAllowed(from: current.state, to: .running)
        }
        let now = clock.now()
        let replacement = try current.transitioning(to: .running, at: now)
        try await repository.replace(
            replacement,
            expectedVersion: current.recordVersion,
            changedAt: now
        )
        await gate.resume()
        await log(
            level: .notice,
            category: "job-state",
            jobID: jobID,
            message: .publicValue("Job resumed")
        )
        return replacement
    }

    public func cancel(jobID: JobID) async throws -> JobRecord {
        let current = try await requireJob(jobID)
        if current.state == .cancelled || current.state == .cancellationRequested {
            return current
        }
        let now = clock.now()
        switch current.state {
        case .queued, .failed, .interrupted:
            let replacement = try current.transitioning(to: .cancelled, at: now)
            try await repository.replace(
                replacement,
                expectedVersion: current.recordVersion,
                changedAt: now
            )
            try? await temporaryStorage.cleanupDirectory(current.temporaryDirectory)
            await log(
                level: .notice,
                category: "job-state",
                jobID: jobID,
                message: .publicValue("Job cancelled")
            )
            return replacement
        case .running, .pauseRequested, .paused:
            let replacement = try current.transitioning(
                to: .cancellationRequested,
                at: now
            )
            try await repository.replace(
                replacement,
                expectedVersion: current.recordVersion,
                changedAt: now
            )
            if let gate = executionGates[jobID] {
                await gate.cancel()
            }
            runningTasks[jobID]?.cancel()
            await log(
                level: .notice,
                category: "job-state",
                jobID: jobID,
                message: .publicValue("Cancellation requested")
            )
            return replacement
        default:
            throw JobContractError.transitionNotAllowed(from: current.state, to: .cancelled)
        }
    }

    public func retry(jobID: JobID) async throws -> JobRecord {
        let current = try await requireJob(jobID)
        let replacement = try current.retrying()
        if replacement.checkpoint != nil {
            try await temporaryStorage.reuseDirectory(current.temporaryDirectory)
        } else {
            try? await temporaryStorage.cleanupDirectory(current.temporaryDirectory)
            let newLease = try await temporaryStorage.allocateDirectory(
                for: current.jobID,
                diskBudgetBytes: current.temporaryDirectory.diskBudgetBytes
            )
            guard newLease == current.temporaryDirectory else {
                throw TaskRuntimeError.temporaryStorageConflict(jobID)
            }
        }
        let now = clock.now()
        try await repository.replace(
            replacement,
            expectedVersion: current.recordVersion,
            changedAt: now
        )
        await log(
            level: .notice,
            category: "job-state",
            jobID: jobID,
            message: .publicValue("Job queued for retry")
        )
        try await scheduleEligibleJobs()
        return replacement
    }

    public func runEligibleJobs() async throws {
        try await scheduleEligibleJobs()
    }

    public func recoverAtStartup(
        policy: StartupRecoveryPolicy
    ) async throws -> StartupHealthReport {
        guard runningTasks.isEmpty else {
            throw TaskRuntimeError.startupCheckFailed(
                "Startup recovery cannot run while this manager has active jobs."
            )
        }
        let checkedAt = clock.now()
        let activeStates: Set<JobState> = [
            .running,
            .pauseRequested,
            .paused,
            .cancellationRequested
        ]
        let unfinished = try await repository.jobs(states: activeStates)
        var interruptedIDs: [JobID] = []
        for record in unfinished {
            let canRetry = record.retryCount < record.maximumRetryCount
            let failure = try JobFailureRecord(
                code: "process_interrupted",
                safeSummary: "The previous process ended before the job reached a terminal state.",
                retryable: canRetry,
                occurredAt: checkedAt
            )
            let interrupted = try record.transitioning(
                to: .interrupted,
                at: checkedAt,
                failure: failure
            )
            try await repository.replace(
                interrupted,
                expectedVersion: record.recordVersion,
                changedAt: checkedAt
            )
            interruptedIDs.append(record.jobID)
            if !canRetry {
                try await temporaryStorage.cleanupDirectory(record.temporaryDirectory)
            }
        }

        let allJobs = try await repository.jobs(states: nil)
        let expectedDirectoryIDs = Set(
            allJobs.filter { record in
                record.state == .queued
                    || (record.state == .interrupted
                        && record.errorRecord?.retryable == true
                        && record.retryCount < record.maximumRetryCount)
                    || (record.state == .failed
                        && record.errorRecord?.retryable == true
                        && record.resumeCapability == .checkpointed
                        && record.checkpoint != nil
                        && record.retryCount < record.maximumRetryCount)
            }.map(\.jobID)
        )
        let orphanScan = try await temporaryStorage.scanOrphans(
            expectedJobIDs: expectedDirectoryIDs,
            maximumEntries: policy.maximumOrphansToInspect
        )
        let cutoffValue = max(
            checkedAt.millisecondsSinceUnixEpoch - policy.orphanGracePeriodMilliseconds,
            0
        )
        let orphanCleanup = try await temporaryStorage.cleanupOrphans(
            orphanScan.candidates,
            olderThan: UTCInstant(millisecondsSinceUnixEpoch: cutoffValue),
            maximumRemovals: policy.maximumOrphansToRemove
        )
        let assetRecovery = if let managedAssetRecovery {
            try await managedAssetRecovery.reconcileInterruptedOperations(
                at: checkedAt,
                maximumOperations: policy.maximumManagedAssetOperations
            )
        } else {
            ManagedAssetRecoveryReport.empty
        }
        let logRotation = try await logStore.rotate(at: checkedAt)
        let availableCapacity = try await temporaryStorage.availableCapacityBytes()
        let capacityIsSufficient = availableCapacity.map {
            $0 >= policy.minimumAvailableCapacityBytes
        } ?? false
        let databaseHealth = try await repository.databaseHealth()
        return StartupHealthReport(
            checkedAt: checkedAt,
            databaseHealth: databaseHealth,
            interruptedJobIDs: interruptedIDs,
            orphanScan: orphanScan,
            orphanCleanup: orphanCleanup,
            managedAssetRecovery: assetRecovery,
            logRotation: logRotation,
            availableCapacityBytes: availableCapacity,
            capacityIsSufficient: capacityIsSufficient
        )
    }

    private func scheduleEligibleJobs() async throws {
        var availableSlots = maximumConcurrentJobs - runningTasks.count
        guard availableSlots > 0 else { return }
        let queued = try await repository.jobs(states: [.queued])
        for record in queued where availableSlots > 0 {
            guard let executor = executors[record.jobType] else { continue }
            let dependencyState = try await dependencyReadiness(for: record)
            switch dependencyState {
            case .waiting:
                continue
            case let .failed(dependencyID):
                try await failBeforeStart(record, dependencyID: dependencyID)
                continue
            case .ready:
                break
            }
            do {
                try await temporaryStorage.reuseDirectory(record.temporaryDirectory)
            } catch {
                try await failBeforeStart(record, privateDiagnostic: String(describing: error))
                continue
            }
            let now = clock.now()
            let started = try record.transitioning(to: .running, at: now)
            try await repository.replace(
                started,
                expectedVersion: record.recordVersion,
                changedAt: now
            )
            let gate = ExecutionGate()
            executionGates[record.jobID] = gate
            let task = Task { [weak self] in
                guard let self else { return }
                await self.performExecution(started, executor: executor, gate: gate)
            }
            runningTasks[record.jobID] = task
            availableSlots -= 1
            await log(
                level: .info,
                category: "job-state",
                jobID: record.jobID,
                message: .publicValue("Job started")
            )
        }
    }

    private func performExecution(
        _ started: JobRecord,
        executor: any TaskJobExecutor,
        gate: ExecutionGate
    ) async {
        let context = JobExecutionContext(
            job: started,
            checkpointOperation: { [weak self] progress, checkpoint in
                guard let self else { throw CancellationError() }
                try await self.handleCheckpoint(
                    jobID: started.jobID,
                    progress: progress,
                    checkpoint: checkpoint,
                    gate: gate
                )
            },
            writeOperation: { [weak self] data, path in
                guard let self else { throw CancellationError() }
                return try await self.writeTemporaryFile(
                    data,
                    path: path,
                    lease: started.temporaryDirectory
                )
            },
            prepareWritableFileOperation: { [weak self] path in
                guard let self else { throw CancellationError() }
                return try await self.prepareWritableFile(
                    path: path,
                    lease: started.temporaryDirectory
                )
            },
            finalizeWritableFileOperation: { [weak self] writableFile in
                guard let self else { throw CancellationError() }
                return try await self.finalizeWritableFile(
                    writableFile,
                    lease: started.temporaryDirectory
                )
            },
            inspectFileOperation: { [weak self] path in
                guard let self else { throw CancellationError() }
                return try await self.inspectTemporaryFile(
                    path: path,
                    lease: started.temporaryDirectory
                )
            },
            verifiedFileURLOperation: { [weak self] descriptor in
                guard let self else { throw CancellationError() }
                return try await self.verifiedTemporaryFileURL(
                    descriptor: descriptor,
                    lease: started.temporaryDirectory
                )
            },
            discardWritableFileOperation: { [weak self] writableFile in
                guard let self else { throw CancellationError() }
                try await self.discardWritableFile(
                    writableFile,
                    lease: started.temporaryDirectory
                )
            },
            discardFileOperation: { [weak self] path in
                guard let self else { throw CancellationError() }
                try await self.discardTemporaryFile(
                    path: path,
                    lease: started.temporaryDirectory
                )
            }
        )
        do {
            let result = try await executor.execute(context)
            try await Task.detached { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.repository.validateInputRevisionsAreCurrent(
                    started.inputRevisionIDs
                )
                try await self.finishSucceeded(jobID: started.jobID, result: result)
            }.value
        } catch is CancellationError {
            await Task.detached { [weak self] in
                await self?.finishCancelled(jobID: started.jobID)
            }.value
        } catch let failure as JobExecutionFailure {
            await finishFailed(jobID: started.jobID, failure: failure)
        } catch let contract as JobContractError {
            let failure = try? JobExecutionFailure(
                code: "job_contract_failed",
                safeSummary: "The job stopped because an input or state contract was no longer valid.",
                retryable: true,
                privateDiagnostic: String(describing: contract)
            )
            if let failure {
                await finishFailed(jobID: started.jobID, failure: failure)
            }
        } catch {
            let failure = try? JobExecutionFailure(
                code: "operation_failed",
                safeSummary: "The operation failed without publishing output.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
            if let failure {
                await finishFailed(jobID: started.jobID, failure: failure)
            }
        }
        await executionFinished(jobID: started.jobID)
    }

    private func handleCheckpoint(
        jobID: JobID,
        progress: JobProgress,
        checkpoint: JobCheckpoint?,
        gate: ExecutionGate
    ) async throws {
        let lease = try await requireJob(jobID).temporaryDirectory
        _ = try await temporaryStorage.usage(of: lease)
        var persisted: JobRecord?
        for _ in 0..<8 {
            let current = try await requireJob(jobID)
            if current.state == .cancellationRequested {
                throw CancellationError()
            }
            let updated = try current.updatingProgress(progress, checkpoint: checkpoint)
            let now = clock.now()
            do {
                try await repository.replace(
                    updated,
                    expectedVersion: current.recordVersion,
                    changedAt: now
                )
                persisted = updated
                break
            } catch JobContractError.optimisticLockFailed {
                continue
            }
        }
        guard var current = persisted else {
            throw JobContractError.optimisticLockFailed(jobID)
        }
        if current.state == .pauseRequested {
            guard current.checkpoint != nil else {
                throw JobContractError.invalidCheckpoint(
                    "Pause was requested, but the executor did not provide a durable checkpoint."
                )
            }
            var pausedRecord: JobRecord?
            for _ in 0..<8 {
                current = try await requireJob(jobID)
                if current.state == .cancellationRequested {
                    throw CancellationError()
                }
                if current.state == .paused {
                    pausedRecord = current
                    break
                }
                guard current.state == .pauseRequested else { break }
                let now = clock.now()
                let paused = try current.transitioning(to: .paused, at: now)
                do {
                    try await repository.replace(
                        paused,
                        expectedVersion: current.recordVersion,
                        changedAt: now
                    )
                    pausedRecord = paused
                    break
                } catch JobContractError.optimisticLockFailed {
                    continue
                }
            }
            if pausedRecord != nil {
                await log(
                    level: .notice,
                    category: "job-state",
                    jobID: jobID,
                    message: .publicValue("Job paused at a durable checkpoint")
                )
                try await gate.suspendUntilResumed()
            }
        }
        let latest = try await requireJob(jobID)
        if latest.state == .cancellationRequested {
            throw CancellationError()
        }
    }

    private func writeTemporaryFile(
        _ data: Data,
        path: WorkspaceRelativePath,
        lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor {
        try await temporaryStorage.write(data, to: path, in: lease)
    }

    private func prepareWritableFile(
        path: WorkspaceRelativePath,
        lease: TaskDirectoryLease
    ) async throws -> TaskWritableFileLease {
        try await temporaryStorage.prepareWritableFile(at: path, in: lease)
    }

    private func finalizeWritableFile(
        _ writableFile: TaskWritableFileLease,
        lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor {
        try await temporaryStorage.finalizeWritableFile(writableFile, in: lease)
    }

    private func inspectTemporaryFile(
        path: WorkspaceRelativePath,
        lease: TaskDirectoryLease
    ) async throws -> TaskTemporaryFileDescriptor? {
        try await temporaryStorage.inspectFile(at: path, in: lease)
    }

    private func verifiedTemporaryFileURL(
        descriptor: TaskTemporaryFileDescriptor,
        lease: TaskDirectoryLease
    ) async throws -> URL {
        try await temporaryStorage.verifiedFileURL(for: descriptor, in: lease)
    }

    private func discardWritableFile(
        _ writableFile: TaskWritableFileLease,
        lease: TaskDirectoryLease
    ) async throws {
        try await temporaryStorage.discardWritableFile(writableFile, in: lease)
    }

    private func discardTemporaryFile(
        path: WorkspaceRelativePath,
        lease: TaskDirectoryLease
    ) async throws {
        try await temporaryStorage.discardFile(at: path, in: lease)
    }

    private func finishSucceeded(
        jobID: JobID,
        result: JobExecutionResult
    ) async throws {
        let current = try await requireJob(jobID)
        let now = clock.now()
        let succeeded = try current.transitioning(
            to: .succeeded,
            at: now,
            outputRevisionIDs: result.outputRevisionIDs,
            providerUsage: result.providerUsage
        )
        try await repository.replace(
            succeeded,
            expectedVersion: current.recordVersion,
            changedAt: now
        )
        try? await temporaryStorage.cleanupDirectory(current.temporaryDirectory)
        await log(
            level: .info,
            category: "job-state",
            jobID: jobID,
            message: .publicValue("Job succeeded")
        )
    }

    private func finishCancelled(jobID: JobID) async {
        guard let current = try? await requireJob(jobID),
              current.state != .cancelled,
              !current.state.isTerminal
        else {
            return
        }
        let now = clock.now()
        guard let cancelled = try? current.transitioning(to: .cancelled, at: now),
              (try? await repository.replace(
                  cancelled,
                  expectedVersion: current.recordVersion,
                  changedAt: now
              )) != nil
        else {
            return
        }
        try? await temporaryStorage.cleanupDirectory(current.temporaryDirectory)
        await log(
            level: .notice,
            category: "job-state",
            jobID: jobID,
            message: .publicValue("Job cancelled cooperatively")
        )
    }

    private func finishFailed(jobID: JobID, failure: JobExecutionFailure) async {
        guard let current = try? await requireJob(jobID), !current.state.isTerminal else {
            return
        }
        if current.state == .cancellationRequested {
            await finishCancelled(jobID: jobID)
            return
        }
        let now = clock.now()
        guard let errorRecord = try? JobFailureRecord(
            code: failure.code,
            safeSummary: failure.safeSummary,
            retryable: failure.retryable,
            occurredAt: now
        ),
            let failed = try? current.transitioning(
                to: .failed,
                at: now,
                failure: errorRecord
            ),
            (try? await repository.replace(
                failed,
                expectedVersion: current.recordVersion,
                changedAt: now
            )) != nil
        else {
            return
        }
        let retainCheckpoint = failure.retryable
            && current.resumeCapability == .checkpointed
            && current.checkpoint != nil
            && current.retryCount < current.maximumRetryCount
        if !retainCheckpoint {
            try? await temporaryStorage.cleanupDirectory(current.temporaryDirectory)
        }
        await log(
            level: .error,
            category: "job-state",
            jobID: jobID,
            message: .publicValue("Job failed"),
            metadata: [
                "error_code": .publicValue(failure.code),
                "diagnostic": .privateValue(failure.privateDiagnostic ?? "none")
            ]
        )
    }

    private func executionFinished(jobID: JobID) async {
        runningTasks.removeValue(forKey: jobID)
        executionGates.removeValue(forKey: jobID)
        try? await scheduleEligibleJobs()
    }

    private func failBeforeStart(
        _ record: JobRecord,
        dependencyID: JobID? = nil,
        privateDiagnostic: String? = nil
    ) async throws {
        let now = clock.now()
        let failure = try JobFailureRecord(
            code: dependencyID == nil ? "temporary_storage_unavailable" : "dependency_failed",
            safeSummary: dependencyID == nil
                ? "The job-owned temporary directory is unavailable."
                : "A required predecessor job did not succeed.",
            retryable: true,
            occurredAt: now
        )
        let running = try record.transitioning(to: .running, at: now)
        try await repository.replace(
            running,
            expectedVersion: record.recordVersion,
            changedAt: now
        )
        let failed = try running.transitioning(to: .failed, at: now, failure: failure)
        try await repository.replace(
            failed,
            expectedVersion: running.recordVersion,
            changedAt: now
        )
        try? await temporaryStorage.cleanupDirectory(record.temporaryDirectory)
        await log(
            level: .error,
            category: "job-state",
            jobID: record.jobID,
            message: .publicValue("Job failed"),
            metadata: [
                "dependency_job_id": dependencyID.map {
                    .publicValue($0.canonicalString)
                } ?? .publicValue("none"),
                "diagnostic": .privateValue(privateDiagnostic ?? "none")
            ]
        )
    }

    private func dependencyReadiness(for record: JobRecord) async throws -> DependencyReadiness {
        for dependencyID in record.dependencyJobIDs {
            guard let dependency = try await repository.job(id: dependencyID) else {
                return .failed(dependencyID)
            }
            if dependency.state == .succeeded { continue }
            if dependency.state.isTerminal {
                return .failed(dependencyID)
            }
            return .waiting
        }
        return .ready
    }

    private func requireJob(_ jobID: JobID) async throws -> JobRecord {
        guard let record = try await repository.job(id: jobID) else {
            throw JobContractError.jobNotFound(jobID)
        }
        return record
    }

    private func log(
        level: TaskLogLevel,
        category: String,
        jobID: JobID,
        message: TaskLogValue,
        metadata: [String: TaskLogValue] = [:]
    ) async {
        guard let event = try? TaskLogEvent(
            timestamp: clock.now(),
            level: level,
            category: category,
            jobID: jobID,
            message: message,
            metadata: metadata
        ) else {
            return
        }
        try? await logStore.record(event)
    }
}

private enum DependencyReadiness {
    case ready
    case waiting
    case failed(JobID)
}

private actor ExecutionGate {
    private var shouldSuspend = false
    private var cancelled = false
    private var continuation: CheckedContinuation<Void, any Error>?

    func prepareToPause() {
        shouldSuspend = true
    }

    func suspendUntilResumed() async throws {
        if cancelled { throw CancellationError() }
        guard shouldSuspend else { return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        shouldSuspend = false
        continuation?.resume()
        continuation = nil
    }

    func cancel() {
        cancelled = true
        shouldSuspend = false
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
