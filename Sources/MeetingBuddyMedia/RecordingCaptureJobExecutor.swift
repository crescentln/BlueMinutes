import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct RecordingCaptureExecutionAuthority: Sendable {
    public let preparedCapture: PreparedCapture
    public let epoch: RecordingEpoch
    public let provider: any AuthorizedAudioCaptureProvider

    public init(
        preparedCapture: PreparedCapture,
        epoch: RecordingEpoch,
        provider: any AuthorizedAudioCaptureProvider
    ) {
        self.preparedCapture = preparedCapture
        self.epoch = epoch
        self.provider = provider
    }
}

public actor TransientRecordingCaptureRegistry {
    private var authorities: [JobID: RecordingCaptureExecutionAuthority] = [:]

    public init() {}

    public func register(
        _ authority: RecordingCaptureExecutionAuthority,
        for jobID: JobID
    ) throws {
        guard authorities[jobID] == nil else {
            throw RecordingContractError.integrityFailure("A capture job already has process-local authority.")
        }
        authorities[jobID] = authority
    }

    public func consume(jobID: JobID) throws -> RecordingCaptureExecutionAuthority {
        guard let authority = authorities.removeValue(forKey: jobID) else {
            throw CaptureProviderError.authorizationExpired
        }
        return authority
    }

    public func discard(jobID: JobID) {
        authorities.removeValue(forKey: jobID)
    }
}

public struct RecordingCaptureJobFactory: Sendable {
    public init() {}

    public func request(
        plan: RecordingCaptureJobPlan,
        requestedBy: JobRequester
    ) throws -> JobRequest {
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }.joined()
        return try JobRequest(
            jobID: plan.intent.jobID,
            jobType: MediaJobTypes.recordingCapture,
            meetingID: plan.intent.meetingID,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            inputRevisionIDs: [
                plan.intent.policy.sensitivityLabelRevision,
                plan.intent.policy.accessPolicyRevision
            ],
            privacyRoute: .localOnly,
            dataClassification: plan.intent.policy.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .checkpointed,
            maximumRetryCount: 1,
            totalUnitCount: 1,
            diskBudgetBytes: plan.intent.diskBudgetBytes
        )
    }
}

public final class RecordingCaptureJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType: JobType = MediaJobTypes.recordingCapture

    private let repository: any RecordingSessionRepository
    private let fileStore: any RecordingSegmentFileStore
    private let assetStorage: any MediaIntakeStorage
    private let assetCatalog: any MediaAssetCatalog
    private let assetFileAccess: any ManagedMediaFileAccess
    private let registry: TransientRecordingCaptureRegistry
    private let recovery: (any RecordingRecoveryService)?
    private let clock: @Sendable () -> UTCInstant

    public init(
        repository: any RecordingSessionRepository,
        fileStore: any RecordingSegmentFileStore,
        assetStorage: any MediaIntakeStorage,
        assetCatalog: any MediaAssetCatalog,
        assetFileAccess: any ManagedMediaFileAccess,
        registry: TransientRecordingCaptureRegistry,
        recovery: (any RecordingRecoveryService)? = nil,
        clock: @escaping @Sendable () -> UTCInstant = {
            try! UTCInstant(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
            )
        }
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.assetStorage = assetStorage
        self.assetCatalog = assetCatalog
        self.assetFileAccess = assetFileAccess
        self.registry = registry
        self.recovery = recovery
        self.clock = clock
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        let plan = try RecordingCaptureJobPlan.decode(from: context.job.inputPayload)
        guard plan.intent.jobID == context.job.jobID else {
            throw RecordingContractError.integrityFailure("The capture job and recording intent IDs differ.")
        }
        let authority = try await registry.consume(jobID: context.job.jobID)
        guard authority.preparedCapture.sessionID == plan.intent.sessionID,
              authority.preparedCapture.epochID == authority.epoch.epochID,
              authority.preparedCapture.mode == plan.intent.mode,
              authority.epoch.sessionID == plan.intent.sessionID,
              Set(authority.epoch.sources.map(\.trackID))
                == Set(plan.intent.requestedTracks.map(\.trackID))
        else {
            throw CaptureProviderError.authorizationExpired
        }
        let coordinator = RecordingPersistenceCoordinator(
            repository: repository,
            fileStore: fileStore,
            assetStorage: assetStorage,
            assetCatalog: assetCatalog,
            assetFileAccess: assetFileAccess,
            clock: clock
        )
        if let existing = try await repository.session(plan.intent.sessionID) {
            guard existing.intent == plan.intent else {
                throw RecordingContractError.integrityFailure(
                    "A recording retry no longer matches its durable intent."
                )
            }
            if existing.state == .preparing {
                guard authority.epoch == plan.initialEpoch else {
                    throw CaptureProviderError.authorizationExpired
                }
                _ = try await coordinator.prepare(intent: plan.intent, epoch: plan.initialEpoch)
            } else {
                guard existing.state == .recovering,
                      authority.epoch.sequence > plan.initialEpoch.sequence,
                      let recovery
                else {
                    throw RecordingContractError.integrityFailure(
                        "A recording retry requires reconciled bytes and a newly authorized epoch."
                    )
                }
                let outcome = try await recovery.recover(plan.intent.sessionID)
                _ = try await coordinator.restore(
                    outcome: outcome,
                    epochs: try await repository.epochs(sessionID: plan.intent.sessionID)
                )
                _ = try await coordinator.prepareResume(epoch: authority.epoch)
            }
        } else {
            guard authority.epoch == plan.initialEpoch else {
                throw CaptureProviderError.authorizationExpired
            }
            _ = try await coordinator.prepare(intent: plan.intent, epoch: plan.initialEpoch)
        }
        var handle: CaptureHandle?
        do {
            handle = try await authority.provider.start(
                authority.preparedCapture,
                sink: coordinator
            )
            while true {
                try await Task.sleep(for: .milliseconds(500))
                guard let snapshot = await coordinator.snapshot() else {
                    throw RecordingContractError.integrityFailure("The capture session snapshot disappeared.")
                }
                if snapshot.state.isTerminal { break }
                if snapshot.state == .interrupted {
                    throw try JobExecutionFailure(
                        code: "recording_capture_interrupted",
                        safeSummary: "The selected recording source stopped. Verified local audio remains available to resume or finish.",
                        retryable: true
                    )
                }
                let recordingCheckpoint = try? await repository.latestCheckpoint(
                    sessionID: snapshot.intent.sessionID
                )
                let jobCheckpoint = try recordingCheckpoint.map {
                    try JobCheckpoint(formatVersion: 1, payload: $0.canonicalPayload())
                }
                try await context.checkpoint(
                    progress: JobProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 1,
                        currentNode: snapshot.state.rawValue
                    ),
                    durableCheckpoint: jobCheckpoint
                )
            }
        } catch let failure as JobExecutionFailure {
            if let handle { await authority.provider.stop(handle) }
            handle = nil
            throw failure
        } catch is CancellationError {
            let captureHandle = handle
            handle = nil
            _ = try await Task.detached {
                if let captureHandle {
                    await authority.provider.stop(captureHandle)
                }
                return try await coordinator.stop(reason: .taskCancellation)
            }.value
        } catch {
            if let handle { await authority.provider.stop(handle) }
            handle = nil
            _ = try? await coordinator.stop(reason: .taskCancellation)
            if let failure = error as? JobExecutionFailure { throw failure }
            throw try JobExecutionFailure(
                code: "recording_capture_failed",
                safeSummary: "The visible recording stopped without replacing verified local audio.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
        if let handle { await authority.provider.stop(handle) }
        guard let terminal = await coordinator.snapshot() else {
            throw RecordingContractError.integrityFailure("The recording finished without a durable terminal snapshot.")
        }
        switch terminal.state {
        case .completed:
            return try JobExecutionResult(outputRevisionIDs: plan.completedOutputRevisions)
        case .incomplete:
            return try JobExecutionResult()
        case .failed:
            throw try JobExecutionFailure(
                code: "recording_no_usable_audio",
                safeSummary: "No verified usable audio was available to publish.",
                retryable: false
            )
        default:
            throw RecordingContractError.integrityFailure("The recording executor stopped before a terminal state.")
        }
    }
}
