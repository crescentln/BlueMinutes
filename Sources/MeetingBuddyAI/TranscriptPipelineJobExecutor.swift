import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class TranscriptPipelineJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = TranscriptJobTypes.pipeline

    private let transcriptionProvider: any TranscriptionProvider
    private let translationProvider: (any TranslationProvider)?
    private let processor: any NativeMediaProcessing
    private let catalog: any MediaAssetCatalog
    private let fileAccess: any ManagedMediaFileAccess
    private let repository: any TranscriptReviewRepository
    private let noSpeechVerifier: any TranscriptNoSpeechVerifying

    public init(
        transcriptionProvider: any TranscriptionProvider,
        translationProvider: (any TranslationProvider)?,
        processor: any NativeMediaProcessing,
        catalog: any MediaAssetCatalog,
        fileAccess: any ManagedMediaFileAccess,
        repository: any TranscriptReviewRepository,
        noSpeechVerifier: any TranscriptNoSpeechVerifying = DigitalSilenceNoSpeechVerifier()
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.translationProvider = translationProvider
        self.processor = processor
        self.catalog = catalog
        self.fileAccess = fileAccess
        self.repository = repository
        self.noSpeechVerifier = noSpeechVerifier
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        do {
            return try await executePipeline(context)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as JobExecutionFailure {
            throw failure
        } catch let error as JobContractError {
            throw try JobExecutionFailure(
                code: "stale_input",
                safeSummary: "The canonical source changed before transcript publication. Nothing was published.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        } catch let error as AIProviderContractError {
            throw try JobExecutionFailure(
                code: failureCode(error),
                safeSummary: safeSummary(error),
                retryable: isRetryable(error),
                privateDiagnostic: String(describing: error)
            )
        } catch {
            throw try JobExecutionFailure(
                code: "transcript_pipeline_failed",
                safeSummary: "Local transcript processing failed without publishing partial output.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
    }

    private func executePipeline(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        let plan = try TranscriptPipelineJobPlan.decode(from: context.job.inputPayload)
        guard context.job.meetingID == plan.meetingID,
              context.job.inputRevisionIDs == [plan.canonicalSourceRevision],
              context.job.privacyRoute == .localOnly,
              context.job.dataClassification == plan.dataClassification,
              transcriptionProvider.route == plan.transcriptionRoute.route,
              transcriptionProvider.metadata.providerIdentifier
                == plan.transcriptionRoute.providerIdentifier,
              plan.targetLanguage == nil || translationProvider != nil,
              plan.translationRoute.map({ decision in
                  translationProvider.map({
                      $0.route == decision.route
                          && $0.metadata.providerIdentifier == decision.providerIdentifier
                  }) ?? false
              }) ?? true
        else { throw AIProviderContractError.invalidRequest("The executor does not match the approved model route.") }
        guard await transcriptionProvider.isModelInstalled(for: plan.sourceLanguage) else {
            throw AIProviderContractError.modelUnavailable("The approved speech model is not installed.")
        }
        if let target = plan.targetLanguage, let translationProvider {
            guard await translationProvider.isModelInstalled(source: plan.sourceLanguage, target: target) else {
                throw AIProviderContractError.modelUnavailable("The approved translation pair is not installed.")
            }
        }
        guard let source = try catalog.sourceAsset(
            revisionID: plan.canonicalSourceRevision.revisionID
        ),
            source.assetID.canonicalString == plan.canonicalSourceRevision.logicalID.canonicalString,
            source.meetingID == plan.meetingID,
            source.revision.dataClassification == plan.dataClassification,
            source.media?.sampleRateHertz == CanonicalAudioProfile.v1.sampleRateHertz,
            source.media?.channelLayout == "mono",
            let managedReference = source.managedStorageReference
        else { throw AIProviderContractError.invalidRequest("The exact canonical source is unavailable.") }
        let canonicalURL = try fileAccess.verifiedFileURL(for: managedReference)
        let chunkPlan = try CanonicalChunkPlanner.plan(totalFrameCount: plan.canonicalFrameCount)
        guard context.job.progress.totalUnitCount == UInt64(chunkPlan.count) else {
            throw AIProviderContractError.invalidRequest("The transcript progress contract does not match its chunk plan.")
        }

        var checkpoint = try TranscriptPipelineCheckpoint.decode(context.job.checkpoint)
        var outputs: [UInt32: TranscriptPipelineChunkOutput] = [:]
        for chunk in chunkPlan {
            if let descriptor = checkpoint.artifacts[chunk.index],
               let stored = try await restoredOutput(
                   chunk: chunk,
                   descriptor: descriptor,
                   context: context
               )
            {
                outputs[chunk.index] = stored
            }
        }

        for chunk in chunkPlan where outputs[chunk.index] == nil {
            try Task.checkCancellation()
            let output: TranscriptPipelineChunkOutput
            do {
                output = try await process(
                    chunk: chunk,
                    canonicalURL: canonicalURL,
                    plan: plan,
                    attemptCount: context.job.retryCount + 1,
                    context: context
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let code = (error as? AIProviderContractError).map(failureCode)
                    ?? "chunk_processing_failed"
                try repository.recordIncompleteCoverage(
                    incompleteManifest(
                        plan: plan,
                        chunkPlan: chunkPlan,
                        outputs: outputs,
                        failedIndex: chunk.index,
                        failureCode: code,
                        attemptCount: context.job.retryCount + 1
                    )
                )
                throw error
            }
            let descriptor = try await write(output: output, chunk: chunk, context: context)
            outputs[chunk.index] = output
            checkpoint = TranscriptPipelineCheckpoint(
                artifacts: checkpoint.artifacts.merging([chunk.index: descriptor]) { _, new in new }
            )
            try await context.checkpoint(
                progress: JobProgress(
                    completedUnitCount: UInt64(outputs.count),
                    totalUnitCount: context.job.progress.totalUnitCount,
                    currentNode: "transcript-chunk-\(chunk.index)"
                ),
                durableCheckpoint: checkpoint.jobCheckpoint()
            )
        }

        let publication = try publication(plan: plan, chunkPlan: chunkPlan, outputs: outputs)
        try repository.publishTranscript(
            publication,
            validatingInputRevisions: context.job.inputRevisionIDs
        )
        let outputReferences = try publication.transcriptSegments.map {
            try SemanticRevisionReference(logicalID: $0.segmentID, revisionID: $0.revision.revisionID)
        } + publication.translations.map {
            try SemanticRevisionReference(logicalID: $0.translationID, revisionID: $0.revision.revisionID)
        }
        var usage = [try ProviderUsageMetadata(
            provider: transcriptionProvider.metadata,
            inputUnitCount: plan.canonicalFrameCount,
            outputUnitCount: UInt64(publication.transcriptSegments.reduce(0) { $0 + $1.text.utf8.count })
        )]
        if plan.targetLanguage != nil, let translationProvider {
            usage.append(
                try ProviderUsageMetadata(
                    provider: translationProvider.metadata,
                    inputUnitCount: UInt64(publication.transcriptSegments.reduce(0) { $0 + $1.text.utf8.count }),
                    outputUnitCount: UInt64(publication.translations.reduce(0) { $0 + $1.translatedText.utf8.count })
                )
            )
        }
        return try JobExecutionResult(outputRevisionIDs: outputReferences, providerUsage: usage)
    }

    private func process(
        chunk: MediaChunkPlanEntry,
        canonicalURL: URL,
        plan: TranscriptPipelineJobPlan,
        attemptCount: UInt32,
        context: JobExecutionContext
    ) async throws -> TranscriptPipelineChunkOutput {
        let audioPath = try WorkspaceRelativePath(
            String(format: "transcript-audio/chunk-%06u.caf", chunk.index)
        )
        try? await context.discardTemporaryFile(at: audioPath)
        let writable = try await context.prepareWritableFile(at: audioPath)
        let descriptor: TaskTemporaryFileDescriptor
        do {
            try await processor.writeCanonicalChunk(
                from: canonicalURL,
                range: chunk.physicalRange,
                profile: .v1,
                to: writable.fileURL
            )
            descriptor = try await context.finalizeWritableFile(writable)
        } catch {
            try? await context.discardWritableFile(writable)
            throw error
        }
        defer { Task { try? await context.discardTemporaryFile(at: audioPath) } }
        let audioURL = try await context.verifiedTemporaryFileURL(for: descriptor)
        let taskAudio = try TaskOwnedAudioChunk(fileURL: audioURL, plan: chunk)
        let request = try TranscriptionRequest(
            audio: taskAudio,
            canonicalSourceRevision: plan.canonicalSourceRevision,
            language: plan.sourceLanguage,
            dataClassification: plan.dataClassification
        )
        let providerResult = try await transcriptionProvider.transcribe(request)
        let owned = try ownedSpeech(from: providerResult, chunk: chunk)
        guard let owned else {
            guard let confirmation = await noSpeechVerifier.confirmation(for: taskAudio),
                  confirmation.verifiedCoreRange == chunk.coreRange
            else {
                throw AIProviderContractError.invalidResponse(
                    "Provider-only no-speech cannot omit an unverified source range."
                )
            }
            return try TranscriptPipelineChunkOutput(
                index: chunk.index,
                disposition: .noSpeech,
                text: nil,
                confidence: nil,
                translation: nil,
                attemptCount: attemptCount,
                noSpeechConfirmation: confirmation
            )
        }
        let translation: TranslationResponse?
        if let target = plan.targetLanguage, let translationProvider {
            translation = try await translationProvider.translate(
                TranslationRequest(
                    sourceText: owned.text,
                    sourceLanguage: plan.sourceLanguage,
                    targetLanguage: target,
                    dataClassification: plan.dataClassification
                )
            )
        } else {
            translation = nil
        }
        return try TranscriptPipelineChunkOutput(
            index: chunk.index,
            disposition: .transcribed,
            text: owned.text,
            confidence: owned.confidence,
            translation: translation,
            attemptCount: attemptCount
        )
    }

    private func ownedSpeech(
        from result: TranscriptionChunkResult,
        chunk: MediaChunkPlanEntry
    ) throws -> (text: String, confidence: ConfidenceScore)? {
        guard case let .speech(spans) = result else { return nil }
        let physicalDurationMilliseconds = Int64(chunk.physicalRange.frameCount / 16)
        guard spans.allSatisfy({
            $0.startMilliseconds >= 0
                && $0.endMilliseconds <= physicalDurationMilliseconds + 100
        }) else { throw AIProviderContractError.invalidResponse("A provider span extends beyond its bounded audio chunk.") }

        let owned = spans.filter { span in
            let midpointMilliseconds = (span.startMilliseconds + span.endMilliseconds) / 2
            let globalMidpointFrame = chunk.physicalRange.startFrame
                + UInt64(max(midpointMilliseconds, 0)) * 16
            return globalMidpointFrame >= chunk.coreRange.startFrame
                && globalMidpointFrame < chunk.coreRange.endFrame
        }
        guard !owned.isEmpty else { return nil }
        let text = owned.map(\.text).joined(separator: " ")
        let confidence = UInt32(
            owned.reduce(UInt64(0)) { $0 + UInt64($1.confidence.millionths) }
                / UInt64(owned.count)
        )
        return (text, try ConfidenceScore(millionths: confidence))
    }

    private func write(
        output: TranscriptPipelineChunkOutput,
        chunk: MediaChunkPlanEntry,
        context: JobExecutionContext
    ) async throws -> TaskTemporaryFileDescriptor {
        let path = try outputPath(chunk.index)
        try? await context.discardTemporaryFile(at: path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try await context.writeTemporaryFile(encoder.encode(output), to: path)
    }

    private func restoredOutput(
        chunk: MediaChunkPlanEntry,
        descriptor: TaskTemporaryFileDescriptor,
        context: JobExecutionContext
    ) async throws -> TranscriptPipelineChunkOutput? {
        guard descriptor.relativePathWithinTask == (try outputPath(chunk.index)),
              let current = try await context.inspectTemporaryFile(
                  at: descriptor.relativePathWithinTask
              ),
              current == descriptor
        else { return nil }
        let url = try await context.verifiedTemporaryFileURL(for: descriptor)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let decoded = try JSONDecoder().decode(TranscriptPipelineChunkOutput.self, from: data)
        guard decoded.index == chunk.index else { return nil }
        return try? TranscriptPipelineChunkOutput(
            index: decoded.index,
            disposition: decoded.disposition,
            text: decoded.text,
            confidence: decoded.confidence,
            translation: decoded.translation,
            attemptCount: decoded.attemptCount,
            noSpeechConfirmation: decoded.noSpeechConfirmation
        )
    }

    private func outputPath(_ index: UInt32) throws -> WorkspaceRelativePath {
        try WorkspaceRelativePath(String(format: "transcript-results/chunk-%06u.json", index))
    }

    private func publication(
        plan: TranscriptPipelineJobPlan,
        chunkPlan: [MediaChunkPlanEntry],
        outputs: [UInt32: TranscriptPipelineChunkOutput]
    ) throws -> TranscriptPublication {
        let identities = Dictionary(uniqueKeysWithValues: plan.chunkIdentities.map { ($0.index, $0) })
        var transcripts: [TranscriptSegmentV1] = []
        var translations: [TranslationSegmentV1] = []
        var coverage: [TranscriptChunkCoverage] = []
        for chunk in chunkPlan {
            guard let output = outputs[chunk.index], let identity = identities[chunk.index] else {
                throw TranscriptCoverageError.invalidManifest("A completed job is missing a validated chunk result.")
            }
            switch output.disposition {
            case .noSpeech:
                coverage.append(
                    try TranscriptChunkCoverage(
                        index: chunk.index,
                        coreRange: chunk.coreRange,
                        physicalRange: chunk.physicalRange,
                        disposition: .noSpeech,
                        attemptCount: output.attemptCount,
                        provider: transcriptionProvider.metadata,
                        noSpeechConfirmation: output.noSpeechConfirmation
                    )
                )
            case .transcribed:
                guard let text = output.text, let confidence = output.confidence else {
                    throw TranscriptCoverageError.invalidManifest("A speech result lost its validated text.")
                }
                let transcript = try TranscriptSemanticFactory.providerTranscript(
                    logicalID: identity.transcriptID,
                    revisionID: identity.transcriptRevisionID,
                    meetingID: plan.meetingID,
                    canonicalSource: plan.canonicalSourceRevision,
                    speechSourceKind: plan.speechSourceKind,
                    coreRange: chunk.coreRange,
                    language: plan.sourceLanguage,
                    text: text,
                    confidence: confidence,
                    provider: transcriptionProvider.metadata,
                    createdAt: plan.createdAt,
                    classification: plan.dataClassification
                )
                transcripts.append(transcript)
                let transcriptReference = try SemanticRevisionReference(
                    logicalID: transcript.segmentID,
                    revisionID: transcript.revision.revisionID
                )
                var translationReference: SemanticRevisionReference?
                if let translated = output.translation,
                   let target = plan.targetLanguage,
                   let translationProvider,
                   let translationID = identity.translationID,
                   let translationRevisionID = identity.translationRevisionID
                {
                    let translation = try TranscriptSemanticFactory.providerTranslation(
                        logicalID: translationID,
                        revisionID: translationRevisionID,
                        transcript: transcript,
                        canonicalSource: plan.canonicalSourceRevision,
                        sourceLanguage: plan.sourceLanguage,
                        targetLanguage: target,
                        translatedText: translated.translatedText,
                        confidence: translated.confidence,
                        provider: translationProvider.metadata,
                        createdAt: plan.createdAt,
                        classification: plan.dataClassification
                    )
                    translations.append(translation)
                    translationReference = try SemanticRevisionReference(
                        logicalID: translation.translationID,
                        revisionID: translation.revision.revisionID
                    )
                } else if plan.targetLanguage != nil {
                    throw TranscriptCoverageError.invalidManifest("A translated pipeline result is incomplete.")
                }
                coverage.append(
                    try TranscriptChunkCoverage(
                        index: chunk.index,
                        coreRange: chunk.coreRange,
                        physicalRange: chunk.physicalRange,
                        disposition: .transcribed,
                        attemptCount: output.attemptCount,
                        provider: transcriptionProvider.metadata,
                        machineSegmentRevision: transcriptReference,
                        reviewedSegmentRevision: transcriptReference,
                        translationRevision: translationReference
                    )
                )
            case .failed, .missing:
                throw TranscriptCoverageError.invalidManifest("A failed or missing chunk cannot be published.")
            }
        }
        let manifest = try TranscriptCoverageManifest(
            manifestID: plan.manifestID,
            transcriptSetID: plan.transcriptSetID,
            meetingID: plan.meetingID,
            canonicalSourceRevision: plan.canonicalSourceRevision,
            canonicalFrameCount: plan.canonicalFrameCount,
            transcriptionRoute: plan.transcriptionRoute,
            translationRoute: plan.translationRoute,
            status: .published,
            chunks: coverage,
            createdAt: plan.createdAt
        )
        return try TranscriptPublication(
            manifest: manifest,
            transcriptSegments: transcripts,
            translations: translations
        )
    }

    private func incompleteManifest(
        plan: TranscriptPipelineJobPlan,
        chunkPlan: [MediaChunkPlanEntry],
        outputs: [UInt32: TranscriptPipelineChunkOutput],
        failedIndex: UInt32,
        failureCode: String,
        attemptCount: UInt32
    ) throws -> TranscriptCoverageManifest {
        let identities = Dictionary(uniqueKeysWithValues: plan.chunkIdentities.map { ($0.index, $0) })
        let coverage = try chunkPlan.map { chunk -> TranscriptChunkCoverage in
            if let output = outputs[chunk.index] {
                if output.disposition == .noSpeech {
                    return try TranscriptChunkCoverage(
                        index: chunk.index,
                        coreRange: chunk.coreRange,
                        physicalRange: chunk.physicalRange,
                        disposition: .noSpeech,
                        attemptCount: output.attemptCount,
                        provider: transcriptionProvider.metadata,
                        noSpeechConfirmation: output.noSpeechConfirmation
                    )
                }
                guard let identity = identities[chunk.index] else {
                    throw TranscriptCoverageError.invalidManifest("An incomplete manifest lost a stable chunk identity.")
                }
                let transcriptReference = try SemanticRevisionReference(
                    logicalID: identity.transcriptID,
                    revisionID: identity.transcriptRevisionID
                )
                let translationReference: SemanticRevisionReference? = try {
                    guard output.translation != nil,
                          let translationID = identity.translationID,
                          let translationRevisionID = identity.translationRevisionID
                    else { return nil }
                    return try SemanticRevisionReference(
                        logicalID: translationID,
                        revisionID: translationRevisionID
                    )
                }()
                return try TranscriptChunkCoverage(
                    index: chunk.index,
                    coreRange: chunk.coreRange,
                    physicalRange: chunk.physicalRange,
                    disposition: .transcribed,
                    attemptCount: output.attemptCount,
                    provider: transcriptionProvider.metadata,
                    machineSegmentRevision: transcriptReference,
                    reviewedSegmentRevision: transcriptReference,
                    translationRevision: translationReference
                )
            }
            if chunk.index == failedIndex {
                return try TranscriptChunkCoverage(
                    index: chunk.index,
                    coreRange: chunk.coreRange,
                    physicalRange: chunk.physicalRange,
                    disposition: .failed,
                    attemptCount: attemptCount,
                    provider: transcriptionProvider.metadata,
                    safeFailureCode: failureCode
                )
            }
            return try TranscriptChunkCoverage(
                index: chunk.index,
                coreRange: chunk.coreRange,
                physicalRange: chunk.physicalRange,
                disposition: .missing,
                attemptCount: 0
            )
        }
        return try TranscriptCoverageManifest(
            transcriptSetID: plan.transcriptSetID,
            meetingID: plan.meetingID,
            canonicalSourceRevision: plan.canonicalSourceRevision,
            canonicalFrameCount: plan.canonicalFrameCount,
            transcriptionRoute: plan.transcriptionRoute,
            translationRoute: plan.translationRoute,
            status: .incomplete,
            chunks: coverage,
            createdAt: UTCInstant(
                millisecondsSinceUnixEpoch: plan.createdAt.millisecondsSinceUnixEpoch
                    + Int64(attemptCount)
            )
        )
    }

    private func safeSummary(_ error: AIProviderContractError) -> String {
        switch error {
        case .modelUnavailable:
            "The approved on-device model is unavailable. Use the manual local fallback or install it in system settings."
        case .routeDenied:
            "The requested processing route is not authorized. No meeting content was sent."
        case .invalidResponse:
            "An on-device provider returned invalid structured output. Nothing was published."
        case .invalidRequest, .secretUnavailable:
            "The local transcript request failed validation. Nothing was published."
        }
    }

    private func failureCode(_ error: AIProviderContractError) -> String {
        switch error {
        case .modelUnavailable: "on_device_model_unavailable"
        case .routeDenied: "model_route_denied"
        case .invalidResponse: "provider_output_invalid"
        case .invalidRequest: "transcript_request_invalid"
        case .secretUnavailable: "secret_unavailable"
        }
    }

    private func isRetryable(_ error: AIProviderContractError) -> Bool {
        switch error {
        case .invalidResponse: true
        case .modelUnavailable, .routeDenied, .invalidRequest, .secretUnavailable: false
        }
    }
}
