import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import MeetingBuddyPersistence
import MeetingBuddyTasks
import Testing

@Suite(.serialized)
struct TranscriptPipelineIntegrationTests {
    @Test
    func deterministicPipelinePublishesExactCoverageAndSurvivesReopen() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 600_000)
        let speech = DeterministicSpeechProvider(noSpeechIndices: [1])
        let translation = DeterministicTranslationProvider()
        let processor = SyntheticTranscriptMediaProcessor()
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: 600_000,
            targetLanguage: LanguageTag("zh-hans")
        )
        let manager = try workspace.manager(
            executor: TranscriptPipelineJobExecutor(
                transcriptionProvider: speech,
                translationProvider: translation,
                processor: processor,
                catalog: workspace.store,
                fileAccess: workspace.fileAccess,
                repository: workspace.store
            )
        )
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(30, JobID.self),
            requestedBy: JobRequester("task005b-test")
        )
        _ = try await manager.enqueue(request)
        let succeeded = try await waitForAIJob(manager, request.jobID, state: .succeeded)

        #expect(succeeded.privacyRoute == .localOnly)
        #expect(succeeded.providerUsage.count == 2)
        #expect(succeeded.outputRevisionIDs.count == 2)
        let loadedReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        let review = try #require(loadedReview)
        #expect(review.manifest.status == .published)
        #expect(review.manifest.canonicalSourceRevision == source)
        #expect(review.manifest.chunks.map(\.disposition) == [.transcribed, .noSpeech])
        #expect(review.transcriptSegments.map(\.text) == ["chunk-0-speech"])
        #expect(review.translations.map(\.translatedText) == ["zh:chunk-0-speech"])
        #expect(review.translations.first?.sourceSegmentRevision.revisionID
            == review.transcriptSegments.first?.revision.revisionID)
        #expect(await speech.callCount(index: 0) == 1)
        #expect(await speech.callCount(index: 1) == 1)
        #expect(await processor.callCount == 2)
        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))

        try workspace.store.close()
        let reopened = try SQLitePersistenceStore(workspace: workspace.descriptor)
        let loadedReopenedReview = try reopened.activeTranscriptReview(meetingID: workspace.meetingID)
        let reopenedReview = try #require(loadedReopenedReview)
        #expect(reopenedReview.manifest == review.manifest)
        #expect(reopenedReview.transcriptSegments == review.transcriptSegments)
        #expect(reopenedReview.translations == review.translations)
        try reopened.close()
    }

    @Test
    func retryReusesVerifiedChunkArtifactsAndStableSegmentIDs() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 1_000_000)
        let speech = DeterministicSpeechProvider(failOnceIndex: 1)
        let processor = SyntheticTranscriptMediaProcessor()
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: 1_000_000,
            targetLanguage: nil
        )
        let manager = try workspace.manager(
            executor: TranscriptPipelineJobExecutor(
                transcriptionProvider: speech,
                translationProvider: nil,
                processor: processor,
                catalog: workspace.store,
                fileAccess: workspace.fileAccess,
                repository: workspace.store
            )
        )
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(31, JobID.self),
            requestedBy: JobRequester("task005b-test")
        )
        _ = try await manager.enqueue(request)
        let failed = try await waitForAIJob(manager, request.jobID, state: .failed)
        #expect(failed.errorRecord?.retryable == true)
        #expect(try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID) == nil)
        #expect(await speech.callCount(index: 0) == 1)
        #expect(await speech.callCount(index: 1) == 1)
        #expect(await speech.callCount(index: 2) == 0)
        let incompleteHistory = try workspace.store.transcriptCoverageManifests(
            meetingID: workspace.meetingID
        )
        let incomplete = try #require(incompleteHistory.first)
        #expect(incomplete.status == .incomplete)
        #expect(incomplete.chunks.map(\.disposition) == [.transcribed, .failed, .missing])

        _ = try await manager.retry(jobID: request.jobID)
        let succeeded = try await waitForAIJob(manager, request.jobID, state: .succeeded)
        #expect(succeeded.retryCount == 1)
        #expect(await speech.callCount(index: 0) == 1)
        #expect(await speech.callCount(index: 1) == 2)
        #expect(await speech.callCount(index: 2) == 1)
        #expect(await processor.callCount == 4)
        let loadedReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        let review = try #require(loadedReview)
        #expect(review.transcriptSegments.map(\.segmentID).sorted()
            == plan.chunkIdentities.map(\.transcriptID).sorted())
    }

    @Test
    func threeHourRetryAcrossManagerRestartPreservesExactCoverageAndTraceability() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let threeHourFrames: UInt64 = 3 * 60 * 60 * 16_000
        let source = try workspace.installCanonicalSource(totalFrames: threeHourFrames)
        let failedIndex: UInt32 = 180
        let speech = DeterministicSpeechProvider(failOnceIndex: failedIndex)
        let processor = SyntheticTranscriptMediaProcessor()
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: threeHourFrames,
            targetLanguage: nil
        )
        #expect(plan.chunkIdentities.count == 360)
        let executor = TranscriptPipelineJobExecutor(
            transcriptionProvider: speech,
            translationProvider: nil,
            processor: processor,
            catalog: workspace.store,
            fileAccess: workspace.fileAccess,
            repository: workspace.store
        )
        let manager = try workspace.manager(executor: executor)
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(35, JobID.self),
            requestedBy: JobRequester("task007-long-meeting")
        )
        let clock = ContinuousClock()
        let started = clock.now
        _ = try await manager.enqueue(request)
        let failed = try await waitForAIJob(manager, request.jobID, state: .failed)
        #expect(failed.progress.completedUnitCount == UInt64(failedIndex))
        #expect(failed.checkpoint != nil)
        let incomplete = try #require(
            try workspace.store.transcriptCoverageManifests(
                meetingID: workspace.meetingID
            ).first
        )
        #expect(incomplete.chunks.count == 360)
        #expect(incomplete.chunks[Int(failedIndex)].disposition == .failed)
        #expect(incomplete.chunks.suffix(from: Int(failedIndex) + 1).allSatisfy {
            $0.disposition == .missing
        })

        let restartedManager = try workspace.manager(executor: executor)
        let startup = try await restartedManager.recoverAtStartup(
            policy: StartupRecoveryPolicy(
                maximumOrphansToInspect: 8,
                maximumOrphansToRemove: 0,
                orphanGracePeriodMilliseconds: 0,
                minimumAvailableCapacityBytes: 0,
                maximumManagedAssetOperations: 8
            )
        )
        #expect(startup.databaseHealth.isHealthy)
        _ = try await restartedManager.retry(jobID: request.jobID)
        _ = try await waitForAIJob(restartedManager, request.jobID, state: .succeeded)
        #expect(clock.now - started < .seconds(30))

        let review = try #require(
            try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        )
        #expect(review.manifest.canonicalFrameCount == threeHourFrames)
        #expect(review.manifest.chunks.count == 360)
        #expect(review.manifest.chunks.allSatisfy { $0.disposition == .transcribed })
        #expect(review.manifest.chunks.prefix(Int(failedIndex)).allSatisfy {
            $0.attemptCount == 1
        })
        #expect(review.manifest.chunks.suffix(from: Int(failedIndex)).allSatisfy {
            $0.attemptCount == 2
        })
        #expect(Set(review.manifest.transcriptRevisionReferences).count == 360)
        #expect(Set(review.transcriptSegments.map(\.revision.revisionID)).count == 360)
        #expect(await speech.callCount(index: 0) == 1)
        #expect(await speech.callCount(index: failedIndex) == 2)
        #expect(await processor.callCount == 361)

        #expect(throws: TranscriptCoverageError.self) {
            _ = try TranscriptCoverageManifest(
                transcriptSetID: review.manifest.transcriptSetID,
                meetingID: review.manifest.meetingID,
                canonicalSourceRevision: review.manifest.canonicalSourceRevision,
                canonicalFrameCount: review.manifest.canonicalFrameCount,
                transcriptionRoute: review.manifest.transcriptionRoute,
                status: .published,
                chunks: Array(review.manifest.chunks.dropLast()) + [review.manifest.chunks[0]],
                createdAt: aiInstant(1_900_000_000_200)
            )
        }
        let first = review.manifest.chunks[0]
        let second = review.manifest.chunks[1]
        let overlappedSecond = try TranscriptChunkCoverage(
            index: second.index,
            coreRange: first.coreRange,
            physicalRange: first.physicalRange,
            disposition: second.disposition,
            attemptCount: second.attemptCount,
            provider: second.provider,
            machineSegmentRevision: second.machineSegmentRevision,
            reviewedSegmentRevision: second.reviewedSegmentRevision,
            translationRevision: second.translationRevision,
            safeFailureCode: second.safeFailureCode
        )
        var overlap = review.manifest.chunks
        overlap[1] = overlappedSecond
        #expect(throws: TranscriptCoverageError.self) {
            _ = try TranscriptCoverageManifest(
                transcriptSetID: review.manifest.transcriptSetID,
                meetingID: review.manifest.meetingID,
                canonicalSourceRevision: review.manifest.canonicalSourceRevision,
                canonicalFrameCount: review.manifest.canonicalFrameCount,
                transcriptionRoute: review.manifest.transcriptionRoute,
                status: .published,
                chunks: overlap,
                createdAt: aiInstant(1_900_000_000_201)
            )
        }
    }

    @Test
    func overlapOwnershipIsDeterministicAndAnUnusedTranslationAdapterIsNotCalled() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 600_000)
        let speech = BoundaryOverlapSpeechProvider()
        let translation = DeterministicTranslationProvider()
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: 600_000,
            targetLanguage: nil
        )
        let manager = try workspace.manager(
            executor: TranscriptPipelineJobExecutor(
                transcriptionProvider: speech,
                translationProvider: translation,
                processor: SyntheticTranscriptMediaProcessor(),
                catalog: workspace.store,
                fileAccess: workspace.fileAccess,
                repository: workspace.store
            )
        )
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(32, JobID.self),
            requestedBy: JobRequester("task005b-test")
        )
        _ = try await manager.enqueue(request)
        let succeeded = try await waitForAIJob(manager, request.jobID, state: .succeeded)
        let loadedReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        let review = try #require(loadedReview)

        #expect(succeeded.progress.completedUnitCount == succeeded.progress.totalUnitCount)
        #expect(succeeded.providerUsage.count == 1)
        #expect(review.manifest.chunks.map(\.disposition) == [.noSpeech, .transcribed])
        #expect(review.transcriptSegments.map(\.text) == ["one-boundary-utterance"])
        #expect(review.translations.isEmpty)
        #expect(await translation.callCount == 0)
    }

    @Test
    func cancellationPublishesNothingAndRemovesTranscriptTaskArtifacts() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 600_000)
        let speech = DelayedSpeechProvider(delay: .seconds(5))
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: 600_000,
            targetLanguage: nil
        )
        let manager = try workspace.manager(
            executor: TranscriptPipelineJobExecutor(
                transcriptionProvider: speech,
                translationProvider: nil,
                processor: SyntheticTranscriptMediaProcessor(),
                catalog: workspace.store,
                fileAccess: workspace.fileAccess,
                repository: workspace.store
            )
        )
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(33, JobID.self),
            requestedBy: JobRequester("task005b-test")
        )
        _ = try await manager.enqueue(request)
        try await waitForProviderStart(speech)
        _ = try await manager.cancel(jobID: request.jobID)
        _ = try await waitForAIJob(manager, request.jobID, state: .cancelled)

        #expect(try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID) == nil)
        #expect(try workspace.store.transcriptCoverageManifests(
            meetingID: workspace.meetingID
        ).isEmpty)
        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))
    }

    @Test
    func staleCanonicalInputBlocksAtomicTranscriptPublication() async throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 600_000)
        let speech = DelayedSpeechProvider(delay: .milliseconds(150))
        let plan = try transcriptPlan(
            workspace: workspace,
            source: source,
            totalFrames: 600_000,
            targetLanguage: nil
        )
        let manager = try workspace.manager(
            executor: TranscriptPipelineJobExecutor(
                transcriptionProvider: speech,
                translationProvider: nil,
                processor: SyntheticTranscriptMediaProcessor(),
                catalog: workspace.store,
                fileAccess: workspace.fileAccess,
                repository: workspace.store
            )
        )
        let request = try TranscriptPipelineJobFactory().request(
            plan: plan,
            jobID: aiID(34, JobID.self),
            requestedBy: JobRequester("task005b-test")
        )
        _ = try await manager.enqueue(request)
        try await waitForProviderStart(speech)
        try workspace.supersedeCanonicalSource(source)
        let failed = try await waitForAIJob(manager, request.jobID, state: .failed)

        #expect(failed.errorRecord?.code == "stale_input")
        #expect(try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID) == nil)
        #expect(try workspace.store.transcriptCoverageManifests(
            meetingID: workspace.meetingID
        ).isEmpty)
    }

    @Test
    func manualReviewCorrectionsStaleDependentsAndConfirmSpeaker() throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try workspace.installCanonicalSource(totalFrames: 600_000)
        let route = try ModelPolicyRouter().decide(
            try ModelRouteRequest(
                capability: .transcription,
                dataClassification: .internal,
                offlineMode: true,
                organizationAllowsExternalProcessing: false,
                deploymentEnvironment: .production,
                destination: .localDevice,
                retentionPolicy: .localWorkspaceOnly,
                dataCategories: [.canonicalAudio],
                visibleUserAuthorization: false,
                localModelAvailable: false
            )
        )
        let translationRoute = try ModelPolicyRouter().decide(
            ModelRouteRequest(
                capability: .translation,
                dataClassification: .internal,
                offlineMode: true,
                organizationAllowsExternalProcessing: false,
                deploymentEnvironment: .production,
                destination: .localDevice,
                retentionPolicy: .localWorkspaceOnly,
                dataCategories: [.transcriptText],
                visibleUserAuthorization: false,
                localModelAvailable: false
            )
        )
        #expect(throws: TranscriptCoverageError.self) {
            _ = try TranscriptSemanticFactory.manualPublication(
                meetingID: workspace.meetingID,
                canonicalSource: source,
                canonicalFrameCount: 600_000,
                speechSourceKind: .originalSpeakerAudio,
                sourceLanguage: LanguageTag("en"),
                transcriptText: "Unconfirmed manual text.",
                targetLanguage: nil,
                translatedText: nil,
                confirmsCompleteCoverage: false,
                classification: .internal,
                transcriptionRoute: route,
                translationRoute: nil,
                createdAt: aiInstant(1_900_000_000_099)
            )
        }
        let publication = try TranscriptSemanticFactory.manualPublication(
            meetingID: workspace.meetingID,
            canonicalSource: source,
            canonicalFrameCount: 600_000,
            speechSourceKind: .originalSpeakerAudio,
            sourceLanguage: LanguageTag("en"),
            transcriptText: "Human-entered synthetic transcript.",
            targetLanguage: LanguageTag("fr"),
            translatedText: "Transcription synthetique saisie par un humain.",
            confirmsCompleteCoverage: true,
            classification: .internal,
            transcriptionRoute: route,
            translationRoute: translationRoute,
            createdAt: aiInstant(1_900_000_000_100)
        )
        try workspace.store.publishTranscript(publication)
        let loadedInitialReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        var review = try #require(loadedInitialReview)
        #expect(review.manifest.transcriptionRoute.request.capability == .transcription)
        #expect(review.manifest.transcriptionRoute.request.dataCategories == [.canonicalAudio])
        #expect(review.manifest.translationRoute?.request.capability == .translation)
        #expect(review.manifest.translationRoute?.request.dataCategories == [.transcriptText])
        #expect(review.manifest.chunks.allSatisfy { $0.reviewedSegmentRevision
            == review.manifest.chunks.first?.reviewedSegmentRevision })

        let priorTranslation = try #require(review.translations.first)
        let translationChangedAt = aiInstant(1_900_000_000_110)
        let correctedTranslation = try TranscriptSemanticFactory.correctedTranslation(
            prior: priorTranslation,
            sourceTranscript: try #require(review.transcriptSegments.first),
            text: "Traduction humaine corrigee.",
            changedAt: translationChangedAt
        )
        let translationManifest = try TranscriptSemanticFactory.replacingTranslation(
            in: review.manifest,
            oldRevisionID: priorTranslation.revision.revisionID,
            with: correctedTranslation,
            at: translationChangedAt
        )
        try workspace.store.saveTranslationCorrection(
            correctedTranslation,
            replacing: priorTranslation.revision.revisionID,
            updatedManifest: translationManifest,
            changedAt: translationChangedAt
        )
        let loadedTranslationReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        review = try #require(loadedTranslationReview)
        #expect(review.translations.first?.translatedText == "Traduction humaine corrigee.")

        let priorTranscript = try #require(review.transcriptSegments.first)
        let transcriptChangedAt = aiInstant(1_900_000_000_120)
        let correctedTranscript = try TranscriptSemanticFactory.correctedTranscript(
            prior: priorTranscript,
            text: "Human-confirmed corrected transcript.",
            changedAt: transcriptChangedAt
        )
        let transcriptManifest = try TranscriptSemanticFactory.replacingTranscript(
            in: review.manifest,
            oldRevisionID: priorTranscript.revision.revisionID,
            with: correctedTranscript,
            at: transcriptChangedAt
        )
        try workspace.store.saveTranscriptCorrection(
            correctedTranscript,
            replacing: priorTranscript.revision.revisionID,
            updatedManifest: transcriptManifest,
            changedAt: transcriptChangedAt
        )
        let correctedTranslationReference = try SemanticRevisionReference(
            logicalID: correctedTranslation.translationID,
            revisionID: correctedTranslation.revision.revisionID
        )
        #expect(try !workspace.store.staleMarks(for: correctedTranslationReference).isEmpty)
        let loadedTranscriptReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        review = try #require(loadedTranscriptReview)
        #expect(review.transcriptSegments.first?.text == "Human-confirmed corrected transcript.")
        #expect(review.translations.isEmpty)

        let confirmedTranscript = try #require(review.transcriptSegments.first)
        let confirmation = try TranscriptSemanticFactory.speakerConfirmation(
            transcript: confirmedTranscript,
            displayName: "Synthetic Speaker",
            changedAt: aiInstant(1_900_000_000_130)
        )
        try workspace.store.publishSpeakerConfirmation(
            actor: confirmation.0,
            capacity: confirmation.1,
            evidence: confirmation.2,
            assignment: confirmation.3,
            changedAt: aiInstant(1_900_000_000_130)
        )
        let loadedSpeakerReview = try workspace.store.activeTranscriptReview(meetingID: workspace.meetingID)
        review = try #require(loadedSpeakerReview)
        #expect(review.speakerAssignments.count == 1)
        #expect(review.speakerAssignments.first?.certainty == .confirmed)
        #expect(review.speakerAssignments.first?.userConfirmed == true)
    }
}

final class AIWorkspace: @unchecked Sendable {
    let container: URL
    let root: URL
    let sourceURL: URL
    let descriptor: LocalWorkspaceDescriptor
    let store: SQLitePersistenceStore
    let storage: LocalStorageService
    let coordinator: ManagedAssetCoordinator
    let fileAccess: LocalManagedMediaFileAccess
    let temporaryStorage: LocalTaskTemporaryStorage
    let logStore: RotatingTaskLogStore
    let jobRepository: SQLiteJobRepository
    let workspaceID = aiID(10, WorkspaceID.self)
    let meetingID = aiID(11, MeetingID.self)

    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meetingbuddy-task005b-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        root = container.appendingPathComponent("workspace", isDirectory: true)
        sourceURL = container.appendingPathComponent("synthetic-canonical.caf")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        descriptor = try LocalWorkspaceService().createWorkspace(
            at: root,
            workspaceID: workspaceID,
            createdAt: aiInstant(1_900_000_000_000)
        )
        store = try SQLitePersistenceStore(
            workspace: descriptor,
            migrationTimestamp: aiInstant(1_900_000_000_001)
        )
        storage = LocalStorageService(workspace: descriptor)
        coordinator = ManagedAssetCoordinator(storage: storage, metadata: store)
        fileAccess = LocalManagedMediaFileAccess(storage: storage, metadata: store)
        temporaryStorage = LocalTaskTemporaryStorage(workspace: descriptor)
        logStore = RotatingTaskLogStore(
            workspace: descriptor,
            configuration: try TaskLogConfiguration()
        )
        jobRepository = SQLiteJobRepository(store: store)
        try installMeeting()
    }

    func installCanonicalSource(totalFrames: UInt64) throws -> SemanticRevisionReference {
        let bytes = Data(repeating: 0x5b, count: 2_048)
        try bytes.write(to: sourceURL, options: [.atomic])
        let createdAt = aiInstant(1_900_000_000_010)
        let record = try coordinator.importFile(
            from: sourceURL,
            meetingID: meetingID,
            storageObjectID: aiID(12, StorageObjectID.self),
            fileExtension: ManagedFileExtension("caf"),
            createdAt: createdAt,
            dataClassification: .internal,
            retentionClass: .workspaceManaged
        )
        let assetID = aiID(13, SourceAssetID.self)
        let revisionID = aiID(14, RevisionID.self)
        let media = try MediaProvenance(
            durationMilliseconds: totalFrames / 16,
            containerFormat: "caf",
            codec: "lpcm_s16le",
            sampleRateHertz: 16_000,
            channelLayout: "mono",
            languageTrack: LanguageTag("en"),
            speechSourceKind: .originalSpeakerAudio
        )
        let draft = try sourceAsset(
            assetID: assetID,
            revisionID: revisionID,
            record: record,
            media: media,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil
        )
        let source = try sourceAsset(
            assetID: assetID,
            revisionID: revisionID,
            record: record,
            media: media,
            lifecycle: .published,
            validation: .valid,
            publishedAt: createdAt,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
        try store.insert(source)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: source.assetID,
                revisionID: source.revision.revisionID
            ),
            as: SourceAssetV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: createdAt
        )
        return try SemanticRevisionReference(
            logicalID: source.assetID,
            revisionID: source.revision.revisionID
        )
    }

    func supersedeCanonicalSource(_ originalReference: SemanticRevisionReference) throws {
        guard let original = try store.sourceAsset(revisionID: originalReference.revisionID),
              let managedReference = original.managedStorageReference,
              let record = try store.managedAsset(storageObjectID: managedReference.storageObjectID),
              let media = original.media
        else { throw AIProviderContractError.invalidRequest("Synthetic source replacement failed.") }
        let replacementRevisionID = aiID(16, RevisionID.self)
        let changedAt = aiInstant(1_900_000_000_040)
        let draft = try sourceAsset(
            assetID: original.assetID,
            revisionID: replacementRevisionID,
            record: record,
            media: media,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil,
            supersedesRevisionID: original.revision.revisionID
        )
        let replacement = try sourceAsset(
            assetID: original.assetID,
            revisionID: replacementRevisionID,
            record: record,
            media: media,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            semanticHash: try draft.calculatedSemanticContentHash(),
            supersedesRevisionID: original.revision.revisionID
        )
        try store.insert(replacement)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: replacement.assetID,
                revisionID: replacement.revision.revisionID
            ),
            as: SourceAssetV1.self,
            expectedCurrentRevisionID: original.revision.revisionID,
            markedAt: changedAt
        )
    }

    func manager(executor: any TaskJobExecutor) throws -> LocalTaskManager {
        try LocalTaskManager(
            repository: jobRepository,
            temporaryStorage: temporaryStorage,
            logStore: logStore,
            managedAssetRecovery: coordinator,
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
    }

    func cleanup() {
        try? store.close()
        try? FileManager.default.removeItem(at: container)
    }

    private func installMeeting() throws {
        try store.insert(
            MeetingProfileV1(
                revision: RevisionEnvelope(
                    logicalID: meetingID,
                    revisionID: aiID(15, RevisionID.self),
                    schemaVersion: .v1,
                    lifecycleStatus: .draft,
                    validationState: .notValidated,
                    createdAt: aiInstant(1_900_000_000_005),
                    createdBy: .user,
                    dataClassification: .internal
                ),
                title: "Synthetic Task 005B Meeting",
                sourceLanguages: [LanguageTag("en")],
                outputLanguage: LanguageTag("en"),
                cloudProcessingPolicy: .localOnly,
                workspaceID: workspaceID,
                reviewStatus: .unreviewed,
                userConfirmed: false
            )
        )
    }

    private func sourceAsset(
        assetID: SourceAssetID,
        revisionID: RevisionID,
        record: ManagedAssetRecord,
        media: MediaProvenance,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        semanticHash: ContentDigest?,
        supersedesRevisionID: RevisionID? = nil
    ) throws -> SourceAssetV1 {
        try SourceAssetV1(
            revision: RevisionEnvelope(
                logicalID: assetID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: record.createdAt,
                createdBy: .application,
                publishedAt: publishedAt,
                supersedesRevisionID: supersedesRevisionID,
                dataClassification: .internal,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            assetType: .audio,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(
                storageObjectID: record.storageObjectID
            ),
            sourceContentHash: record.contentHash,
            mimeType: MIMEType("audio/x-caf"),
            byteSize: record.byteSize,
            language: LanguageTag("en"),
            acquisitionMethod: .userSelectedFile,
            acquiredAt: record.createdAt,
            retentionClass: record.retentionClass,
            media: media
        )
    }
}

private actor SyntheticTranscriptMediaProcessor: NativeMediaProcessing {
    private(set) var callCount = 0

    func inspect(_ sourceURL: URL) async throws -> MediaInspection {
        throw MediaContractError.unreadableMedia
    }

    func writeCanonicalAudio(
        from sourceURL: URL,
        selectedTrack: MediaTrackIdentifier,
        expectedTimelineFrameCount: UInt64,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws -> CanonicalAudioWriteResult {
        throw MediaContractError.processingFailed("Not used by the transcript fixture.")
    }

    func writeCanonicalChunk(
        from canonicalAudioURL: URL,
        range: MediaFrameRange,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws {
        callCount += 1
        try Data(repeating: UInt8(truncatingIfNeeded: range.startFrame / 16_000), count: 256)
            .write(to: destinationURL, options: [.atomic])
    }
}

private actor DeterministicSpeechProvider: TranscriptionProvider {
    nonisolated let metadata = try! providerMetadata()
    nonisolated let route: ModelExecutionRoute = .deterministicTest
    private let noSpeechIndices: Set<UInt32>
    private let failOnceIndex: UInt32?
    private var calls: [UInt32: Int] = [:]

    init(noSpeechIndices: Set<UInt32> = [], failOnceIndex: UInt32? = nil) {
        self.noSpeechIndices = noSpeechIndices
        self.failOnceIndex = failOnceIndex
    }

    func isModelInstalled(for language: LanguageTag) async -> Bool { true }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionChunkResult {
        let index = request.audio.plan.index
        calls[index, default: 0] += 1
        if failOnceIndex == index, calls[index] == 1 {
            throw AIProviderContractError.invalidResponse("Synthetic retryable failure.")
        }
        if noSpeechIndices.contains(index) { return .noSpeech }
        let relativeCoreStart = Int64(
            (request.audio.plan.coreRange.startFrame
                - request.audio.plan.physicalRange.startFrame) / 16
        )
        return try TranscriptionChunkResult(
            validatingSpans: [
                TranscriptionSpan(
                    startMilliseconds: relativeCoreStart + 100,
                    endMilliseconds: relativeCoreStart + 700,
                    text: "chunk-\(index)-speech",
                    confidence: ConfidenceScore(millionths: 900_000)
                )
            ]
        )
    }

    func callCount(index: UInt32) -> Int { calls[index, default: 0] }
}

private actor BoundaryOverlapSpeechProvider: TranscriptionProvider {
    nonisolated let metadata = try! providerMetadata()
    nonisolated let route: ModelExecutionRoute = .deterministicTest

    func isModelInstalled(for language: LanguageTag) async -> Bool { true }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionChunkResult {
        let globalStartFrame: UInt64 = 480_000
        let globalEndFrame: UInt64 = 488_000
        let physicalStart = request.audio.plan.physicalRange.startFrame
        guard globalStartFrame >= physicalStart,
              globalEndFrame <= request.audio.plan.physicalRange.endFrame
        else { return .noSpeech }
        return try TranscriptionChunkResult(
            validatingSpans: [
                TranscriptionSpan(
                    startMilliseconds: Int64((globalStartFrame - physicalStart) / 16),
                    endMilliseconds: Int64((globalEndFrame - physicalStart) / 16),
                    text: "one-boundary-utterance",
                    confidence: ConfidenceScore(millionths: 910_000)
                )
            ]
        )
    }
}

private actor DelayedSpeechProvider: TranscriptionProvider {
    nonisolated let metadata = try! providerMetadata()
    nonisolated let route: ModelExecutionRoute = .deterministicTest
    private let delay: Duration
    private var didStart = false

    init(delay: Duration) {
        self.delay = delay
    }

    func isModelInstalled(for language: LanguageTag) async -> Bool { true }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionChunkResult {
        didStart = true
        try await Task.sleep(for: delay)
        return .noSpeech
    }

    func hasStarted() -> Bool { didStart }
}

private actor DeterministicTranslationProvider: TranslationProvider {
    nonisolated let metadata = try! ProviderMetadata(
        providerIdentifier: "meetingbuddy-deterministic-translation",
        modelIdentifier: "fixture-v1"
    )
    nonisolated let route: ModelExecutionRoute = .deterministicTest
    private(set) var callCount = 0

    func isModelInstalled(source: LanguageTag, target: LanguageTag) async -> Bool { true }

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        callCount += 1
        return try TranslationResponse(
            translatedText: "zh:\(request.sourceText)",
            confidence: ConfidenceScore(millionths: 850_000)
        )
    }
}

private func waitForProviderStart(_ provider: DelayedSpeechProvider) async throws {
    for _ in 0..<3_000 {
        if await provider.hasStarted() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw AIProviderContractError.invalidResponse("Synthetic provider did not start.")
}

private func transcriptPlan(
    workspace: AIWorkspace,
    source: SemanticRevisionReference,
    totalFrames: UInt64,
    targetLanguage: LanguageTag?
) throws -> TranscriptPipelineJobPlan {
    let speechRequest = try ModelRouteRequest(
        capability: .transcription,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .test,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [.canonicalAudio],
        visibleUserAuthorization: false,
        localModelAvailable: true
    )
    let translationRequest = try ModelRouteRequest(
        capability: .translation,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .test,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [.transcriptText],
        visibleUserAuthorization: false,
        localModelAvailable: true
    )
    return try TranscriptPipelineJobPlan(
        meetingID: workspace.meetingID,
        canonicalSourceRevision: source,
        canonicalFrameCount: totalFrames,
        speechSourceKind: .originalSpeakerAudio,
        sourceLanguage: LanguageTag("en"),
        targetLanguage: targetLanguage,
        dataClassification: .internal,
        createdAt: aiInstant(1_900_000_000_020),
        transcriptionRoute: ModelPolicyRouter().decide(speechRequest),
        translationRoute: targetLanguage == nil
            ? nil
            : try ModelPolicyRouter().decide(translationRequest)
    )
}

private func waitForAIJob(
    _ manager: LocalTaskManager,
    _ jobID: JobID,
    state: JobState
) async throws -> JobRecord {
    for _ in 0..<500 {
        if let record = try await manager.job(id: jobID), record.state == state {
            return record
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw JobContractError.jobNotFound(jobID)
}
