import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct CanonicalAudioJobFactory {
    public init() {}

    public func request(
        plan: CanonicalAudioJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester,
        maximumRetryCount: UInt32 = 2
    ) throws -> JobRequest {
        let input = try plan.jobInputPayload()
        let chunks = try CanonicalChunkPlanner.plan(
            totalFrameCount: plan.expectedDurationFrames
        )
        let totalUnits = UInt64(chunks.count) + 2
        let budget = try diskBudget(
            totalFrameCount: plan.expectedDurationFrames,
            chunks: chunks
        )
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }
            .joined()
        return try JobRequest(
            jobID: jobID,
            jobType: MediaJobTypes.canonicalAudio,
            meetingID: plan.meetingID,
            origin: .application,
            requestedBy: requestedBy,
            inputPayload: input,
            inputRevisionIDs: [plan.sourceRevision],
            privacyRoute: .localOnly,
            dataClassification: plan.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .checkpointed,
            maximumRetryCount: maximumRetryCount,
            totalUnitCount: totalUnits,
            diskBudgetBytes: budget
        )
    }

    private func diskBudget(
        totalFrameCount: UInt64,
        chunks: [MediaChunkPlanEntry]
    ) throws -> UInt64 {
        let canonicalBytes = try multiplied(totalFrameCount, by: 2)
        let chunkFrames = try chunks.reduce(UInt64(0)) { partial, chunk in
            let (next, overflow) = partial.addingReportingOverflow(
                chunk.physicalRange.frameCount
            )
            guard !overflow else { throw MediaContractError.invalidChunkPlan("Chunk size overflowed.") }
            return next
        }
        let chunkBytes = try multiplied(chunkFrames, by: 2)
        let (mediaBytes, mediaOverflow) = canonicalBytes.addingReportingOverflow(chunkBytes)
        let (budget, budgetOverflow) = mediaBytes.addingReportingOverflow(67_108_864)
        guard !mediaOverflow,
              !budgetOverflow,
              budget <= JobRequest.maximumDiskBudgetBytes
        else {
            throw JobContractError.invalidRequest(
                "The canonical media task exceeds the approved one-terabyte temporary budget."
            )
        }
        return max(budget, 67_108_864)
    }

    private func multiplied(_ value: UInt64, by multiplier: UInt64) throws -> UInt64 {
        let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
        guard !overflow else {
            throw MediaContractError.invalidChunkPlan("Media size overflowed.")
        }
        return result
    }
}

public final class CanonicalAudioJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = MediaJobTypes.canonicalAudio

    private static let canonicalPath = try! WorkspaceRelativePath("canonical/audio.caf")
    private static let durationToleranceFrames: UInt64 = 800

    private let processor: any NativeMediaProcessing
    private let storage: any MediaIntakeStorage
    private let catalog: any MediaAssetCatalog
    private let fileAccess: any ManagedMediaFileAccess

    public init(
        processor: any NativeMediaProcessing,
        storage: any MediaIntakeStorage,
        catalog: any MediaAssetCatalog,
        fileAccess: any ManagedMediaFileAccess
    ) {
        self.processor = processor
        self.storage = storage
        self.catalog = catalog
        self.fileAccess = fileAccess
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        do {
            return try await executeMedia(context)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as JobExecutionFailure {
            throw failure
        } catch let error as MediaContractError {
            throw try JobExecutionFailure(
                code: "media_contract_failed",
                safeSummary: safeSummary(for: error),
                retryable: isRetryable(error),
                privateDiagnostic: String(describing: error)
            )
        } catch {
            throw try JobExecutionFailure(
                code: "media_processing_failed",
                safeSummary: "Local media processing failed without publishing output.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
    }

    private func executeMedia(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        let plan = try CanonicalAudioJobPlan.decode(from: context.job.inputPayload)
        guard context.job.meetingID == plan.meetingID,
              context.job.inputRevisionIDs == [plan.sourceRevision],
              context.job.dataClassification == plan.dataClassification,
              context.job.privacyRoute == .localOnly
        else {
            throw MediaContractError.invalidJobPayload
        }
        guard let source = try catalog.sourceAsset(
            revisionID: plan.sourceRevision.revisionID
        ),
            source.assetID.canonicalString == plan.sourceRevision.logicalID.canonicalString,
            source.meetingID == plan.meetingID,
            source.revision.dataClassification == plan.dataClassification,
            let managedReference = source.managedStorageReference
        else {
            throw MediaContractError.sourceAssetUnavailable(plan.sourceRevision.revisionID)
        }
        let sourceURL = try fileAccess.verifiedFileURL(for: managedReference)
        let chunkPlan = try CanonicalChunkPlanner.plan(
            totalFrameCount: plan.expectedDurationFrames
        )
        guard context.job.progress.totalUnitCount == UInt64(chunkPlan.count) + 2 else {
            throw MediaContractError.invalidJobPayload
        }

        var checkpoint = try await restoredCheckpoint(context, plan: plan)
        if checkpoint == nil {
            try? await context.discardTemporaryFile(at: Self.canonicalPath)
            let writable = try await context.prepareWritableFile(at: Self.canonicalPath)
            do {
                let result = try await processor.writeCanonicalAudio(
                    from: sourceURL,
                    selectedTrack: plan.selectedTrack,
                    expectedTimelineFrameCount: plan.expectedDurationFrames,
                    profile: plan.profile,
                    to: writable.fileURL
                )
                try validateDuration(
                    expected: plan.expectedDurationFrames,
                    actual: result.frameCount
                )
                let descriptor = try await context.finalizeWritableFile(writable)
                var rangeIssues = result.rangeIssues
                if result.frameCount < plan.expectedDurationFrames {
                    rangeIssues.append(
                        try MediaRangeIssue(
                            kind: .missing,
                            range: MediaFrameRange(
                                startFrame: result.frameCount,
                                endFrame: plan.expectedDurationFrames
                            ),
                            safeSummary: "Canonical conversion ended before the approved source timeline."
                        )
                    )
                }
                checkpoint = try CanonicalAudioCheckpoint(
                    canonicalFile: descriptor,
                    canonicalFrameCount: plan.expectedDurationFrames,
                    completedChunks: [],
                    rangeIssues: rangeIssues
                )
            } catch {
                try? await context.discardWritableFile(writable)
                throw error
            }
            try await persist(
                checkpoint: checkpoint!,
                completedUnits: 1,
                currentNode: "canonical-audio",
                context: context
            )
        }
        guard var checkpoint else {
            throw MediaContractError.invalidJobPayload
        }

        var completed = Dictionary(
            uniqueKeysWithValues: checkpoint.completedChunks.map { ($0.plan.index, $0) }
        )
        for entry in chunkPlan {
            try Task.checkCancellation()
            if let artifact = completed[entry.index], artifact.plan == entry,
               let onDisk = try? await context.inspectTemporaryFile(at: entry.relativePath),
               onDisk == artifact.file
            {
                continue
            }
            completed.removeValue(forKey: entry.index)
            try? await context.discardTemporaryFile(at: entry.relativePath)
            let writable = try await context.prepareWritableFile(at: entry.relativePath)
            do {
                let canonicalFileURL = try await canonicalURL(
                    checkpoint: checkpoint,
                    context: context
                )
                try await processor.writeCanonicalChunk(
                    from: canonicalFileURL,
                    range: entry.physicalRange,
                    profile: plan.profile,
                    to: writable.fileURL
                )
                let file = try await context.finalizeWritableFile(writable)
                completed[entry.index] = try CanonicalChunkArtifact(plan: entry, file: file)
            } catch {
                try? await context.discardWritableFile(writable)
                if error is CancellationError { throw error }
                let issue = try MediaRangeIssue(
                    kind: .decodeFailed,
                    range: entry.physicalRange,
                    safeSummary: "A canonical audio chunk could not be generated."
                )
                checkpoint = try CanonicalAudioCheckpoint(
                    canonicalFile: checkpoint.canonicalFile,
                    canonicalFrameCount: checkpoint.canonicalFrameCount,
                    completedChunks: Array(completed.values),
                    rangeIssues: checkpoint.rangeIssues + [issue]
                )
                try await persist(
                    checkpoint: checkpoint,
                    completedUnits: UInt64(completed.count) + 1,
                    currentNode: "chunk-failed-\(entry.index)",
                    context: context
                )
                throw error
            }
            checkpoint = try CanonicalAudioCheckpoint(
                canonicalFile: checkpoint.canonicalFile,
                canonicalFrameCount: checkpoint.canonicalFrameCount,
                completedChunks: Array(completed.values),
                rangeIssues: checkpoint.rangeIssues.filter { $0.range != entry.physicalRange }
            )
            try await persist(
                checkpoint: checkpoint,
                completedUnits: UInt64(completed.count) + 1,
                currentNode: "chunk-\(entry.index)",
                context: context
            )
        }

        try Task.checkCancellation()
        let canonicalFileURL = try await canonicalURL(
            checkpoint: checkpoint,
            context: context
        )
        let canonicalSource = try publishCanonical(
            plan: plan,
            checkpoint: checkpoint,
            canonicalURL: canonicalFileURL,
            cancellationCheck: { try Task.checkCancellation() }
        )
        return try JobExecutionResult(
            outputRevisionIDs: [
                SemanticRevisionReference(
                    logicalID: canonicalSource.assetID,
                    revisionID: canonicalSource.revision.revisionID
                )
            ]
        )
    }

    private func restoredCheckpoint(
        _ context: JobExecutionContext,
        plan: CanonicalAudioJobPlan
    ) async throws -> CanonicalAudioCheckpoint? {
        guard let checkpoint = try CanonicalAudioCheckpoint.decode(
            from: context.job.checkpoint
        ) else { return nil }
        try validateDuration(
            expected: plan.expectedDurationFrames,
            actual: checkpoint.canonicalFrameCount
        )
        guard let current = try? await context.inspectTemporaryFile(
            at: Self.canonicalPath
        ),
            current == checkpoint.canonicalFile
        else {
            return nil
        }
        return checkpoint
    }

    private func canonicalURL(
        checkpoint: CanonicalAudioCheckpoint,
        context: JobExecutionContext
    ) async throws -> URL {
        guard let current = try await context.inspectTemporaryFile(
            at: Self.canonicalPath
        ), current == checkpoint.canonicalFile else {
            throw MediaContractError.processingFailed(
                "The verified canonical task artifact is unavailable."
            )
        }
        return try await context.verifiedTemporaryFileURL(
            for: checkpoint.canonicalFile
        )
    }

    private func publishCanonical(
        plan: CanonicalAudioJobPlan,
        checkpoint: CanonicalAudioCheckpoint,
        canonicalURL: URL,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> SourceAssetV1 {
        if let existing = try catalog.sourceAsset(revisionID: plan.outputRevisionID) {
            guard existing.assetID == plan.outputAssetID,
                  existing.meetingID == plan.meetingID,
                  existing.revision.dataClassification == plan.dataClassification,
                  let reference = existing.managedStorageReference
            else {
                throw MediaContractError.invalidJobPayload
            }
            _ = try fileAccess.verifiedFileURL(for: reference)
            return existing
        }

        let record: ManagedAssetRecord
        if let existing = try catalog.managedAsset(
            storageObjectID: plan.outputStorageObjectID
        ) {
            guard existing.state == .active,
                  existing.meetingID == plan.meetingID,
                  existing.contentHash == checkpoint.canonicalFile.contentHash,
                  existing.byteSize == checkpoint.canonicalFile.byteSize,
                  existing.dataClassification == plan.dataClassification
            else {
                throw MediaContractError.invalidJobPayload
            }
            _ = try fileAccess.verifiedFileURL(
                for: ManagedAssetReference(storageObjectID: existing.storageObjectID)
            )
            record = existing
        } else {
            record = try storage.importFile(
                from: canonicalURL,
                meetingID: plan.meetingID,
                storageObjectID: plan.outputStorageObjectID,
                fileExtension: ManagedFileExtension("caf"),
                createdAt: plan.createdAt,
                dataClassification: plan.dataClassification,
                retentionClass: .workspaceManaged,
                cancellationCheck: cancellationCheck
            )
            guard record.contentHash == checkpoint.canonicalFile.contentHash,
                  record.byteSize == checkpoint.canonicalFile.byteSize
            else {
                throw MediaContractError.processingFailed(
                    "The persisted canonical audio failed its task-artifact digest check."
                )
            }
        }
        let source = try MediaSourceAssetFactory.canonicalSource(
            record: record,
            plan: plan,
            frameCount: checkpoint.canonicalFrameCount
        )
        try catalog.insertSourceAsset(source)
        return source
    }

    private func persist(
        checkpoint: CanonicalAudioCheckpoint,
        completedUnits: UInt64,
        currentNode: String,
        context: JobExecutionContext
    ) async throws {
        try await context.checkpoint(
            progress: JobProgress(
                completedUnitCount: completedUnits,
                totalUnitCount: context.job.progress.totalUnitCount,
                currentNode: currentNode
            ),
            durableCheckpoint: checkpoint.jobCheckpoint()
        )
    }

    private func validateDuration(expected: UInt64, actual: UInt64) throws {
        let difference = expected > actual ? expected - actual : actual - expected
        guard difference <= Self.durationToleranceFrames else {
            throw MediaContractError.durationOutsideTolerance(
                expectedFrames: expected,
                actualFrames: actual
            )
        }
    }

    private func safeSummary(for error: MediaContractError) -> String {
        switch error {
        case .unsupportedFileType:
            "The selected file type is not supported."
        case .noAudioTrack:
            "The selected media contains no readable audio track."
        case .trackSelectionRequired:
            "Select one audio track before processing this media."
        case .selectedTrackUnavailable:
            "The selected audio track is no longer available."
        case .durationOutsideTolerance:
            "Canonical audio duration fell outside the accepted 50 ms tolerance."
        case .sourceAssetUnavailable, .managedSourceUnavailable:
            "The managed source is unavailable or failed verification."
        default:
            "Local media processing failed without publishing output."
        }
    }

    private func isRetryable(_ error: MediaContractError) -> Bool {
        switch error {
        case .processingFailed, .sourceAssetUnavailable, .managedSourceUnavailable:
            true
        default:
            false
        }
    }
}
