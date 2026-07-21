import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct HistoricalIndexRebuildJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.historical-index-rebuild"
    public static let inputFormatVersion: UInt32 = 1

    public let requestedAt: UTCInstant
    public let normalizerVersion: UInt32

    public init(requestedAt: UTCInstant, normalizerVersion: UInt32 = 1) throws {
        guard normalizerVersion == 1 else {
            throw HistoricalReviewError.indexRebuildRequired
        }
        self.requestedAt = requestedAt
        self.normalizerVersion = normalizerVersion
    }

    public func jobInputPayload() throws -> JobInputPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JobInputPayload(
            formatIdentifier: Self.inputFormatIdentifier,
            formatVersion: Self.inputFormatVersion,
            payload: encoder.encode(self)
        )
    }

    public static func decode(from input: JobInputPayload?) throws -> Self {
        guard let input,
              input.formatIdentifier == inputFormatIdentifier,
              input.formatVersion == inputFormatVersion
        else { throw HistoricalReviewError.indexRebuildRequired }
        let decoded = try JSONDecoder().decode(Self.self, from: input.payload)
        guard decoded.normalizerVersion == 1 else {
            throw HistoricalReviewError.indexRebuildRequired
        }
        return decoded
    }
}

public struct HistoricalIndexRebuildJobFactory: Sendable {
    public init() {}

    public func request(
        plan: HistoricalIndexRebuildJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester
    ) throws -> JobRequest {
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }.joined()
        return try JobRequest(
            jobID: jobID,
            jobType: HistoricalReviewJobTypes.indexRebuild,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            privacyRoute: .localOnly,
            dataClassification: .restricted,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .restartOnly,
            maximumRetryCount: 1,
            totalUnitCount: 1,
            diskBudgetBytes: 1_048_576
        )
    }
}

public final class HistoricalIndexRebuildJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = HistoricalReviewJobTypes.indexRebuild
    private let repository: any HistoricalReviewRepository

    public init(repository: any HistoricalReviewRepository) {
        self.repository = repository
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        do {
            let plan = try HistoricalIndexRebuildJobPlan.decode(from: context.job.inputPayload)
            guard context.job.jobType == jobType,
                  context.job.meetingID == nil,
                  context.job.inputRevisionIDs.isEmpty,
                  context.job.privacyRoute == .localOnly,
                  context.job.dataClassification == .restricted,
                  context.job.progress.totalUnitCount == 1,
                  plan.normalizerVersion == 1
            else { throw HistoricalReviewError.indexRebuildRequired }
            try Task.checkCancellation()
            _ = try repository.rebuildHistoricalIndex(
                at: plan.requestedAt,
                cancellationCheck: { try Task.checkCancellation() }
            )
            try await context.checkpoint(
                progress: JobProgress(
                    completedUnitCount: 1,
                    totalUnitCount: 1,
                    currentNode: "historical-index-ready"
                )
            )
            return try JobExecutionResult()
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as JobExecutionFailure {
            throw failure
        } catch {
            throw try JobExecutionFailure(
                code: "historical_index_rebuild_failed",
                safeSummary: "The local meeting-history index could not be rebuilt. Existing semantic revisions were not changed.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
    }
}
