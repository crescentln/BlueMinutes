import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// Process-local authority for user-selected source URLs.
///
/// Entries are never encoded into jobs, logs, checkpoints, or bookmarks. A
/// launch-interrupted intake therefore requires the user to select the source
/// again instead of silently retaining broader file authority.
public final class TransientMediaSourceRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [JobID: URL] = [:]

    public init() {}

    public func register(_ sourceURL: URL, for jobID: JobID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard sources[jobID] == nil else {
            throw MediaContractError.invalidJobPayload
        }
        sources[jobID] = sourceURL.standardizedFileURL
    }

    public func consume(jobID: JobID) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return sources.removeValue(forKey: jobID)
    }

    public func discard(jobID: JobID) {
        lock.lock()
        sources.removeValue(forKey: jobID)
        lock.unlock()
    }
}

public struct LocalMediaIntakeJobFactory: Sendable {
    public init() {}

    public func request(
        plan: LocalMediaIntakeJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester
    ) throws -> JobRequest {
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }
            .joined()
        return try JobRequest(
            jobID: jobID,
            jobType: MediaJobTypes.localIntake,
            meetingID: plan.meetingID,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            privacyRoute: .localOnly,
            dataClassification: plan.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .restartOnly,
            maximumRetryCount: 0,
            totalUnitCount: 1,
            diskBudgetBytes: plan.expectedSourceByteSize
        )
    }
}

public final class LocalMediaIntakeJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = MediaJobTypes.localIntake

    private let intake: LocalMediaIntakeService
    private let sources: TransientMediaSourceRegistry

    public init(
        intake: LocalMediaIntakeService,
        sources: TransientMediaSourceRegistry
    ) {
        self.intake = intake
        self.sources = sources
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        do {
            let plan = try LocalMediaIntakeJobPlan.decode(from: context.job.inputPayload)
            guard context.job.meetingID == plan.meetingID,
                  context.job.inputRevisionIDs.isEmpty,
                  context.job.dataClassification == plan.dataClassification,
                  context.job.privacyRoute == .localOnly,
                  context.job.progress.totalUnitCount == 1
            else {
                throw MediaContractError.invalidJobPayload
            }
            guard let sourceURL = sources.consume(jobID: context.job.jobID) else {
                throw try JobExecutionFailure(
                    code: "source_authority_unavailable",
                    safeSummary: "Select the local source file again before importing it.",
                    retryable: false
                )
            }
            try Task.checkCancellation()
            let imported = try await intake.importSelectedMedia(
                from: sourceURL,
                initialInspection: plan.initialInspection,
                request: MediaIntakeRequest(
                    meetingID: plan.meetingID,
                    sourceAssetID: plan.sourceAssetID,
                    sourceRevisionID: plan.sourceRevisionID,
                    storageObjectID: plan.storageObjectID,
                    selectedTrack: plan.selectedTrack,
                    speechSourceKind: plan.speechSourceKind,
                    language: plan.language,
                    createdAt: plan.createdAt,
                    dataClassification: plan.dataClassification,
                    retentionClass: plan.retentionClass,
                    expectedSourceByteSize: plan.expectedSourceByteSize
                ),
                cancellationCheck: { try Task.checkCancellation() }
            )
            return try JobExecutionResult(
                outputRevisionIDs: [
                    SemanticRevisionReference(
                        logicalID: imported.sourceAsset.assetID,
                        revisionID: imported.sourceAsset.revision.revisionID
                    )
                ]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as JobExecutionFailure {
            throw failure
        } catch {
            throw try JobExecutionFailure(
                code: "local_media_intake_failed",
                safeSummary: "The selected source could not be copied, verified, and registered.",
                retryable: false,
                privateDiagnostic: String(describing: error)
            )
        }
    }
}
