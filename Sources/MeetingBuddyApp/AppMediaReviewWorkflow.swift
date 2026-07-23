import CryptoKit
import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import MeetingBuddyPersistence
import MeetingBuddyTasks

enum AppWorkflowError: LocalizedError {
    case workspaceRequired
    case workspaceAuthorizationFailed
    case workspaceOpenFailed
    case workspaceHealthFailed
    case sourceAuthorizationFailed
    case sourceSelectionExpired
    case sourceInspectionFailed
    case importFailed
    case jobUnavailable
    case canonicalAudioRequired
    case onDeviceModelUnavailable
    case transcriptUnavailable
    case analysisUnavailable
    case briefingUnavailable
    case recordingInProgress
    case recordingUnavailable
    case recordingAuthorizationRequired
    case webMetadataUnavailable
    case historicalReviewUnavailable
    case reviewFailed

    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "Choose a local BlueMinutes workspace first."
        case .workspaceAuthorizationFailed:
            "BlueMinutes could not retain access to the selected workspace."
        case .workspaceOpenFailed:
            "The selected folder is not an empty folder or a valid BlueMinutes workspace."
        case .workspaceHealthFailed:
            "The workspace did not pass its local database and recovery health checks."
        case .sourceAuthorizationFailed:
            "BlueMinutes could not read the user-selected source file."
        case .sourceSelectionExpired:
            "Choose the local source file again before importing it."
        case .sourceInspectionFailed:
            "The selected file is unsupported or contains no readable audio track."
        case .importFailed:
            "The source could not be copied, verified, and registered in the workspace."
        case .jobUnavailable:
            "The processing job is no longer available."
        case .canonicalAudioRequired:
            "Finish canonical local audio processing before starting transcription."
        case .onDeviceModelUnavailable:
            "The requested on-device model is unavailable. Use the manual local fallback or install the model in system settings."
        case .transcriptUnavailable:
            "No published transcript review is available for this meeting."
        case .analysisUnavailable:
            "Analysis requires a complete reviewed transcript with exactly one resolved speaker and capacity for every segment."
        case .briefingUnavailable:
            "A current, fully validated analysis is required before creating or changing the briefing."
        case .recordingInProgress:
            "Finish or retain the current recording before switching workspaces."
        case .recordingUnavailable:
            "The recording session is unavailable or cannot be changed safely."
        case .recordingAuthorizationRequired:
            "Recording requires a direct visible acknowledgement and explicit source selection."
        case .webMetadataUnavailable:
            "The official UN Web TV page metadata could not be read safely. Open the page and enter metadata manually."
        case .historicalReviewUnavailable:
            "Meeting History is unavailable until its local index and exact policy graph are current."
        case .reviewFailed:
            "The review change failed without replacing accepted content."
        }
    }
}

private final class WorkspaceRuntime: @unchecked Sendable {
    let descriptor: LocalWorkspaceDescriptor
    let capabilities: AppCapabilities
    let store: SQLitePersistenceStore
    let storage: LocalStorageService
    let coordinator: ManagedAssetCoordinator
    let fileAccess: LocalManagedMediaFileAccess
    let processor: AVFoundationMediaProcessor
    let intake: LocalMediaIntakeService
    let transientSources: TransientMediaSourceRegistry
    let manager: LocalTaskManager
    let telemetry: LocalTelemetryBuffer
    let storageReporter: LocalWorkspaceStorageReporter
    let recordingFileStore: LocalRecordingFileStore
    let recordingRecovery: LocalRecordingRecoveryService
    let captureProvider: MacOSAudioCaptureProvider
    let captureRegistry: TransientRecordingCaptureRegistry
    let metadataSource: URLSessionUNWebTVMetadataSource
    let transcriptionProvider: (any TranscriptionProvider)?
    let translationProvider: (any TranslationProvider)?
    let analysisProvider: (any AnalysisProvider)?
    let briefingProvider: (any BriefingSectionProvider)?
    private(set) var mostRecentRecoveredRecordingSession: RecordingSessionSnapshot? = nil

    init(
        descriptor: LocalWorkspaceDescriptor,
        capabilities: AppCapabilities
    ) throws {
        self.descriptor = descriptor
        self.capabilities = capabilities
        store = try SQLitePersistenceStore(workspace: descriptor)
        storage = LocalStorageService(workspace: descriptor)
        coordinator = ManagedAssetCoordinator(storage: storage, metadata: store)
        fileAccess = LocalManagedMediaFileAccess(storage: storage, metadata: store)
        processor = AVFoundationMediaProcessor()
        intake = LocalMediaIntakeService(
            processor: processor,
            storage: coordinator,
            catalog: store,
            fileAccess: fileAccess
        )
        transientSources = TransientMediaSourceRegistry()
        telemetry = LocalTelemetryBuffer(policy: try TelemetryPolicy())
        storageReporter = LocalWorkspaceStorageReporter(
            workspace: descriptor,
            store: store
        )
        recordingFileStore = LocalRecordingFileStore(workspace: descriptor)
        recordingRecovery = LocalRecordingRecoveryService(
            repository: store,
            fileStore: recordingFileStore
        )
        captureProvider = MacOSAudioCaptureProvider()
        captureRegistry = TransientRecordingCaptureRegistry()
        metadataSource = URLSessionUNWebTVMetadataSource()
        let intakeExecutor = LocalMediaIntakeJobExecutor(
            intake: intake,
            sources: transientSources
        )
        let canonicalExecutor = CanonicalAudioJobExecutor(
            processor: processor,
            storage: coordinator,
            catalog: store,
            fileAccess: fileAccess
        )
        let recordingExecutor = RecordingCaptureJobExecutor(
            repository: store,
            fileStore: recordingFileStore,
            assetStorage: coordinator,
            assetCatalog: store,
            assetFileAccess: fileAccess,
            registry: captureRegistry,
            recovery: recordingRecovery
        )
        var executors: [any TaskJobExecutor] = [
            intakeExecutor,
            canonicalExecutor,
            recordingExecutor,
            HistoricalIndexRebuildJobExecutor(repository: store)
        ]
        if #available(macOS 26.0, *) {
            let speech = AppleOnDeviceTranscriptionProvider()
            let translation = AppleOnDeviceTranslationProvider()
            let analysis = AppleFoundationModelsAnalysisProvider()
            let briefing = AppleFoundationModelsBriefingProvider()
            transcriptionProvider = speech
            translationProvider = translation
            analysisProvider = analysis
            briefingProvider = briefing
            executors.append(
                TranscriptPipelineJobExecutor(
                    transcriptionProvider: speech,
                    translationProvider: translation,
                    processor: processor,
                    catalog: store,
                    fileAccess: fileAccess,
                    repository: store
                )
            )
            executors.append(
                AnalysisPipelineJobExecutor(
                    provider: analysis,
                    repository: store
                )
            )
            executors.append(
                BriefingPipelineJobExecutor(
                    provider: briefing,
                    repository: store
                )
            )
        } else {
            transcriptionProvider = nil
            translationProvider = nil
            analysisProvider = nil
            briefingProvider = nil
        }
        manager = try LocalTaskManager(
            repository: SQLiteJobRepository(store: store),
            temporaryStorage: LocalTaskTemporaryStorage(workspace: descriptor),
            logStore: RotatingTaskLogStore(
                workspace: descriptor,
                configuration: try TaskLogConfiguration()
            ),
            managedAssetRecovery: coordinator,
            maximumConcurrentJobs: 2,
            executors: executors
        )
    }

    deinit {
        try? store.close()
    }

    func recover() async throws {
        let recordingOutcomes = try await recordingRecovery.recoverNonterminalSessions()
        mostRecentRecoveredRecordingSession = recordingOutcomes.last?.snapshot
        let report = try await manager.recoverAtStartup(
            policy: StartupRecoveryPolicy()
        )
        guard report.databaseHealth.isHealthy,
              report.managedAssetRecovery.repairRequiredOperationCount == 0,
              !report.managedAssetRecovery.truncated,
              !report.orphanScan.truncated
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        _ = await telemetry.record(
            try ContentFreeTelemetryEvent(
                name: .workspaceHealthChecked,
                counters: [TelemetryCounter(key: .successful, value: 1)]
            )
        )
    }
}

@MainActor
final class AppMediaReviewWorkflow: MediaReviewWorkflow {
    private let capabilities: AppCapabilities
    private let workspaceService = LocalWorkspaceService()
    private let workspaceSecurityScope = WorkspaceSecurityScope()

    private var runtime: WorkspaceRuntime?
    private var workspaceDisplayName = ""
    private var pendingSourceURL: URL?
    private var pendingSourceDidStartScope = false
    private var pendingInspection: MediaInspection?

    init(capabilities: AppCapabilities) {
        self.capabilities = capabilities
    }

    deinit {
        if pendingSourceDidStartScope {
            pendingSourceURL?.stopAccessingSecurityScopedResource()
        }
    }

    func restoreWorkspace() async throws -> WorkspaceReview? {
        guard let url = try workspaceSecurityScope.restore() else { return nil }
        do {
            let descriptor = try workspaceService.openWorkspace(at: url)
            let nextRuntime = try WorkspaceRuntime(
                descriptor: descriptor,
                capabilities: capabilities
            )
            try await nextRuntime.recover()
            runtime = nextRuntime
            workspaceDisplayName = displayName(for: url)
            return WorkspaceReview(
                workspaceID: descriptor.manifest.workspaceID,
                displayName: workspaceDisplayName
            )
        } catch let error as AppWorkflowError {
            workspaceSecurityScope.forget()
            throw error
        } catch {
            workspaceSecurityScope.forget()
            throw AppWorkflowError.workspaceOpenFailed
        }
    }

    func openOrCreateWorkspace(at selectedDirectory: URL) async throws -> WorkspaceReview {
        if let runtime, !(try await runtime.store.nonterminalSessions()).isEmpty {
            throw AppWorkflowError.recordingInProgress
        }
        let authorizedURL = try workspaceSecurityScope.activate(selectedDirectory)
        do {
            let descriptor: LocalWorkspaceDescriptor
            do {
                descriptor = try workspaceService.openWorkspace(at: authorizedURL)
            } catch WorkspaceContractError.workspaceManifestMissing {
                descriptor = try workspaceService.createWorkspace(
                    at: authorizedURL,
                    workspaceID: WorkspaceID(UUID()),
                    createdAt: try currentInstant()
                )
            }
            let nextRuntime = try WorkspaceRuntime(
                descriptor: descriptor,
                capabilities: capabilities
            )
            try await nextRuntime.recover()
            releasePendingSource()
            runtime = nextRuntime
            workspaceDisplayName = displayName(for: authorizedURL)
            return WorkspaceReview(
                workspaceID: descriptor.manifest.workspaceID,
                displayName: workspaceDisplayName
            )
        } catch let error as AppWorkflowError {
            workspaceSecurityScope.forget()
            throw error
        } catch {
            workspaceSecurityScope.forget()
            throw AppWorkflowError.workspaceOpenFailed
        }
    }

    func inspectSelectedMedia(at sourceURL: URL) async throws -> PendingMediaReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        releasePendingSource()
        let url = sourceURL.standardizedFileURL
        let didStart = url.startAccessingSecurityScopedResource()
        pendingSourceURL = url
        pendingSourceDidStartScope = didStart
        do {
            let inspection = try await runtime.intake.inspect(url)
            pendingInspection = inspection
            return PendingMediaReview(
                displayName: url.lastPathComponent,
                inspection: inspection
            )
        } catch {
            releasePendingSource()
            if error is MediaContractError {
                throw AppWorkflowError.sourceInspectionFailed
            }
            throw AppWorkflowError.sourceAuthorizationFailed
        }
    }

    func discardPendingMedia() {
        releasePendingSource()
    }

    func importAndProcess(_ submission: MediaImportSubmission) async throws
        -> (ImportedSourceReview, MediaJobReview)
    {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let sourceURL = pendingSourceURL,
              let inspection = pendingInspection
        else {
            throw AppWorkflowError.sourceSelectionExpired
        }
        defer { releasePendingSource() }
        do {
            let createdAt = try currentInstant()
            let meeting = try meetingProfile(
                title: submission.meetingTitle,
                classification: submission.dataClassification,
                language: submission.language,
                workspaceID: runtime.descriptor.manifest.workspaceID,
                createdAt: createdAt
            )
            try runtime.store.insert(meeting)
            let meetingUUID = try requiredUUID(meeting.meetingID.canonicalString)
            let securityPolicy = try LocalSecurityPolicyFactory().makeDefault(
                meeting: meeting,
                sensitivityLabelID: SensitivityLabelID(meetingUUID),
                sensitivityLabelRevisionID: RevisionID(UUID()),
                accessPolicyID: AccessPolicyID(meetingUUID),
                accessPolicyRevisionID: RevisionID(UUID()),
                createdAt: createdAt
            )
            try runtime.store.insert(securityPolicy.sensitivityLabel)
            _ = try runtime.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: securityPolicy.sensitivityLabel.labelID,
                    revisionID: securityPolicy.sensitivityLabel.revision.revisionID
                ),
                as: SensitivityLabelV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: createdAt
            )
            try runtime.store.insert(securityPolicy.accessPolicy)
            _ = try runtime.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: securityPolicy.accessPolicy.policyID,
                    revisionID: securityPolicy.accessPolicy.revision.revisionID
                ),
                as: AccessPolicyV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: createdAt
            )
            let selectedTrack = try inspection.requireTrack(submission.selectedTrack)
            let expectedSourceByteSize = try sourceByteSize(sourceURL)
            let intakePlan = try LocalMediaIntakeJobPlan(
                meetingID: meeting.meetingID,
                initialInspection: inspection,
                selectedTrack: selectedTrack.trackIdentifier,
                speechSourceKind: submission.speechSourceKind,
                language: submission.language,
                createdAt: createdAt,
                dataClassification: submission.dataClassification,
                expectedSourceByteSize: expectedSourceByteSize
            )
            let intakeJobID = JobID(UUID())
            try runtime.transientSources.register(sourceURL, for: intakeJobID)
            defer { runtime.transientSources.discard(jobID: intakeJobID) }
            let intakeRequest = try LocalMediaIntakeJobFactory().request(
                plan: intakePlan,
                jobID: intakeJobID,
                requestedBy: JobRequester("meetingbuddy-app")
            )
            _ = try await runtime.manager.enqueue(intakeRequest)
            let completedIntake = try await terminalJob(
                intakeJobID,
                manager: runtime.manager
            )
            let intakeOutputRevision = try intakePlan.outputRevision
            guard completedIntake.state == .succeeded,
                  completedIntake.outputRevisionIDs == [intakeOutputRevision],
                  let sourceAsset = try runtime.store.sourceAsset(
                      revisionID: intakePlan.sourceRevisionID
                  )
            else {
                throw AppWorkflowError.importFailed
            }
            let sourceReference = try SemanticRevisionReference(
                logicalID: sourceAsset.assetID,
                revisionID: sourceAsset.revision.revisionID
            )
            let plan = try CanonicalAudioJobPlan(
                sourceRevision: sourceReference,
                selectedTrack: selectedTrack.trackIdentifier,
                speechSourceKind: submission.speechSourceKind,
                meetingID: meeting.meetingID,
                createdAt: try currentInstant(),
                dataClassification: submission.dataClassification,
                language: submission.language ?? selectedTrack.language,
                expectedDurationFrames: inspection.durationFrameCount
            )
            let record = try await runtime.manager.enqueue(
                CanonicalAudioJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
            return (
                ImportedSourceReview(
                    assetID: sourceAsset.assetID,
                    revisionID: sourceAsset.revision.revisionID,
                    sourceHash: sourceAsset.sourceContentHash,
                    byteSize: sourceAsset.byteSize,
                    format: inspection.format,
                    durationFrameCount: inspection.durationFrameCount,
                    selectedTrack: selectedTrack.trackIdentifier,
                    speechSourceKind: submission.speechSourceKind
                ),
                MediaJobReview(record: record)
            )
        } catch let error as AppWorkflowError {
            throw error
        } catch {
            throw AppWorkflowError.importFailed
        }
    }

    func jobReview(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let record = try await runtime.manager.job(id: jobID) else {
            throw AppWorkflowError.jobUnavailable
        }
        return MediaJobReview(record: record)
    }

    func cancel(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return MediaJobReview(record: try await runtime.manager.cancel(jobID: jobID))
    }

    func retry(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return MediaJobReview(record: try await runtime.manager.retry(jobID: jobID))
    }

    func transcriptRoute(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> TranscriptRouteReview {
        let context = try await canonicalContext(jobID: canonicalJobID)
        let speechInstalled = await runtime?.transcriptionProvider?.isModelInstalled(
            for: submission.sourceLanguage
        ) ?? false
        let speechRequest = try routeRequest(
            meetingID: context.plan.meetingID,
            capability: .transcription,
            classification: context.plan.dataClassification,
            categories: [.canonicalAudio],
            localModelAvailable: speechInstalled
        )
        let speechDecision = try ModelPolicyRouter().decide(speechRequest)
        let translationDecision: ModelRouteDecision?
        if let target = submission.targetLanguage {
            let translationInstalled = await runtime?.translationProvider?.isModelInstalled(
                    source: submission.sourceLanguage,
                    target: target
                ) ?? false
            let installed = speechDecision.route == .appleOnDevice && translationInstalled
            translationDecision = try ModelPolicyRouter().decide(
                routeRequest(
                    meetingID: context.plan.meetingID,
                    capability: .translation,
                    classification: context.plan.dataClassification,
                    categories: [.transcriptText],
                    localModelAvailable: installed
                )
            )
        } else {
            translationDecision = nil
        }
        return TranscriptRouteReview(
            transcription: speechDecision,
            translation: translationDecision
        )
    }

    func startTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        let route = try await transcriptRoute(
            canonicalJobID: canonicalJobID,
            submission: submission
        )
        guard route.isOnDeviceReady,
              runtime.transcriptionProvider != nil,
              submission.targetLanguage == nil || runtime.translationProvider != nil
        else { throw AppWorkflowError.onDeviceModelUnavailable }
        let plan = try TranscriptPipelineJobPlan(
            meetingID: context.plan.meetingID,
            canonicalSourceRevision: context.canonicalReference,
            canonicalFrameCount: context.plan.expectedDurationFrames,
            speechSourceKind: context.plan.speechSourceKind,
            sourceLanguage: submission.sourceLanguage,
            targetLanguage: submission.targetLanguage,
            dataClassification: context.plan.dataClassification,
            createdAt: try currentInstant(),
            transcriptionRoute: route.transcription,
            translationRoute: route.translation
        )
        let record = try await runtime.manager.enqueue(
            TranscriptPipelineJobFactory().request(
                plan: plan,
                requestedBy: JobRequester("meetingbuddy-app")
            )
        )
        return MediaJobReview(record: record)
    }

    func publishManualTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission,
        transcriptText: String,
        translatedText: String?,
        confirmsCompleteCoverage: Bool
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard confirmsCompleteCoverage else { throw AppWorkflowError.reviewFailed }
        let context = try await canonicalContext(jobID: canonicalJobID)
        let speechRoute = try ModelPolicyRouter().decide(
            routeRequest(
                meetingID: context.plan.meetingID,
                capability: .transcription,
                classification: context.plan.dataClassification,
                categories: [.canonicalAudio],
                localModelAvailable: false
            )
        )
        let translationRoute = try submission.targetLanguage.map { _ in
            try ModelPolicyRouter().decide(
                routeRequest(
                    meetingID: context.plan.meetingID,
                    capability: .translation,
                    classification: context.plan.dataClassification,
                    categories: [.transcriptText],
                    localModelAvailable: false
                )
            )
        }
        let publication = try TranscriptSemanticFactory.manualPublication(
            meetingID: context.plan.meetingID,
            canonicalSource: context.canonicalReference,
            canonicalFrameCount: context.plan.expectedDurationFrames,
            speechSourceKind: context.plan.speechSourceKind,
            sourceLanguage: submission.sourceLanguage,
            transcriptText: transcriptText,
            targetLanguage: submission.targetLanguage,
            translatedText: translatedText,
            confirmsCompleteCoverage: confirmsCompleteCoverage,
            classification: context.plan.dataClassification,
            transcriptionRoute: speechRoute,
            translationRoute: translationRoute,
            createdAt: try currentInstant()
        )
        try runtime.store.publishTranscript(
            publication,
            validatingInputRevisions: [context.canonicalReference]
        )
        guard let review = try runtime.store.activeTranscriptReview(
            meetingID: context.plan.meetingID
        ) else { throw AppWorkflowError.transcriptUnavailable }
        return review
    }

    func transcriptReview(canonicalJobID: JobID) async throws -> TranscriptReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID)
    }

    func correctTranscript(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let prior = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == revisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let correction = try TranscriptSemanticFactory.correctedTranscript(
            prior: prior,
            text: text,
            changedAt: changedAt
        )
        let manifest = try TranscriptSemanticFactory.replacingTranscript(
            in: review.manifest,
            oldRevisionID: revisionID,
            with: correction,
            at: changedAt
        )
        try runtime.store.saveTranscriptCorrection(
            correction,
            replacing: revisionID,
            updatedManifest: manifest,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func correctTranslation(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let prior = review.translations.first(where: { $0.revision.revisionID == revisionID }),
              let transcript = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == prior.sourceSegmentRevision.revisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let correction = try TranscriptSemanticFactory.correctedTranslation(
            prior: prior,
            sourceTranscript: transcript,
            text: text,
            changedAt: changedAt
        )
        let manifest = try TranscriptSemanticFactory.replacingTranslation(
            in: review.manifest,
            oldRevisionID: revisionID,
            with: correction,
            at: changedAt
        )
        try runtime.store.saveTranslationCorrection(
            correction,
            replacing: revisionID,
            updatedManifest: manifest,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func confirmSpeaker(
        canonicalJobID: JobID,
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let transcript = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == transcriptRevisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let confirmation = try TranscriptSemanticFactory.speakerConfirmation(
            transcript: transcript,
            displayName: displayName,
            changedAt: changedAt
        )
        try runtime.store.publishSpeakerConfirmation(
            actor: confirmation.0,
            capacity: confirmation.1,
            evidence: confirmation.2,
            assignment: confirmation.3,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func analysisRoute(canonicalJobID: JobID) async throws -> AnalysisRouteReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let source = try await analysisSource(canonicalJobID: canonicalJobID)
        let locale = source.meeting.outputLanguage.value
        let modelAvailable = await runtime.analysisProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let request = try analysisRouteRequest(
            source: source,
            modelAvailable: modelAvailable,
            visibleUserAuthorization: false
        )
        return AnalysisRouteReview(
            analysis: try ModelPolicyRouter().decide(request),
            runtimeEvidence: try analysisRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: modelAvailable
            )
        )
    }

    func startAnalysis(canonicalJobID: JobID) async throws -> MediaJobReview {
        guard let runtime,
              runtime.analysisProvider != nil
        else { throw AppWorkflowError.onDeviceModelUnavailable }
        let source = try await analysisSource(canonicalJobID: canonicalJobID)
        let locale = source.meeting.outputLanguage.value
        let modelAvailable = await runtime.analysisProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let decision = try ModelPolicyRouter().decide(
            analysisRouteRequest(
                source: source,
                modelAvailable: modelAvailable,
                visibleUserAuthorization: true
            )
        )
        guard decision.route == .appleOnDevice,
              decision.providerIdentifier == "apple-foundation-models",
              modelAvailable
        else { throw AppWorkflowError.onDeviceModelUnavailable }
        let plan = try AnalysisPipelineJobPlan(
            source: source,
            analysisRoute: decision,
            runtimeEvidence: analysisRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: true
            ),
            createdAt: try currentInstant()
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                AnalysisPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func analysisReview(canonicalJobID: JobID) async throws -> AnalysisReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeAnalysisReview(meetingID: context.plan.meetingID)
    }

    func confirmAnalysisReview(
        canonicalJobID: JobID,
        confirmsEveryClaim: Bool
    ) async throws -> AnalysisReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try AnalysisManualReviewService(repository: runtime.store).confirmCurrent(
            meetingID: context.plan.meetingID,
            confirmsEveryClaim: confirmsEveryClaim,
            confirmedAt: try currentInstant()
        )
    }

    func correctPosition(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async throws -> AnalysisReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ),
            review.isHumanConfirmed,
            let prior = review.positions.first(where: {
                $0.revision.revisionID == revisionID
            })
        else { throw AppWorkflowError.analysisUnavailable }
        let changedAt = try currentInstant()
        let correction = try AnalysisSemanticFactory.correctedPosition(
            prior: prior,
            positionType: positionType,
            statement: statement,
            reservations: reservations,
            conditions: conditions,
            changedAt: changedAt
        )
        try runtime.store.savePositionCorrection(
            correction,
            replacing: revisionID,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ) else { throw AppWorkflowError.reviewFailed }
        return updated
    }

    func briefingRoute(canonicalJobID: JobID) async throws -> BriefingRouteReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let template = try BriefingSemanticFactory.builtInTemplate(
            createdAt: try currentInstant()
        )
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: template
        )
        let locale = source.meeting.outputLanguage.value
        let available = await runtime.briefingProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        return BriefingRouteReview(
            briefing: try ModelPolicyRouter().decide(
                briefingRouteRequest(
                    source: source,
                    modelAvailable: available,
                    visibleUserAuthorization: false
                )
            ),
            runtimeEvidence: try briefingRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: available
            )
        )
    }

    func startBriefing(canonicalJobID: JobID) async throws -> MediaJobReview {
        guard let runtime, runtime.briefingProvider != nil else {
            throw AppWorkflowError.onDeviceModelUnavailable
        }
        let createdAt = try currentInstant()
        let template = try BriefingSemanticFactory.builtInTemplate(createdAt: createdAt)
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: template
        )
        guard try runtime.store.activeBriefingReview(meetingID: source.meeting.meetingID) == nil
        else { throw AppWorkflowError.reviewFailed }
        let decision = try await approvedBriefingRoute(
            source: source,
            visibleUserAuthorization: true
        )
        let plan = try BriefingPipelineJobPlan(
            source: source,
            sectionRoute: decision,
            createdAt: createdAt
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                BriefingPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func briefingReview(canonicalJobID: JobID) async throws -> BriefingReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeBriefingReview(meetingID: context.plan.meetingID)
    }

    func regenerateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType
    ) async throws -> MediaJobReview {
        guard let runtime, runtime.briefingProvider != nil else {
            throw AppWorkflowError.onDeviceModelUnavailable
        }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let active = try runtime.store.activeBriefingReview(
            meetingID: context.plan.meetingID
        ),
            active.isCurrent,
            let section = active.publication.sections.first(where: {
                $0.sectionType == sectionType
            }),
            !section.locked,
            section.manualEditStatus == .generated
        else { throw AppWorkflowError.briefingUnavailable }
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: active.publication.template
        )
        let createdAt = try currentInstant()
        let operation = BriefingJobOperation.regenerate(
            sectionType: sectionType,
            expectedSectionRevisionID: section.revision.revisionID,
            graphRevision: try semanticReference(active.publication.graph),
            sectionRevisions: try active.publication.sections.map(semanticReference),
            validationReportRevision: try semanticReference(
                active.publication.validationReport
            ),
            finalBriefingRevision: try semanticReference(
                active.publication.finalBriefing
            ),
            briefingLedgerID: active.publication.ledger.ledgerID
        )
        let plan = try BriefingPipelineJobPlan(
            source: source,
            sectionRoute: try await approvedBriefingRoute(
                source: source,
                visibleUserAuthorization: true
            ),
            operation: operation,
            createdAt: createdAt
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                BriefingPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func updateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try BriefingManualReviewService(repository: runtime.store).updateSection(
            meetingID: context.plan.meetingID,
            sectionType: sectionType,
            editedTextByItemID: editedTextByItemID,
            locked: locked,
            changedAt: try currentInstant()
        )
    }

    func exportBriefingMarkdown(
        canonicalJobID: JobID,
        fileName: String,
        expectedClassification: DataClassification
    ) async throws -> BriefingExportRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let active = try runtime.store.activeBriefingReview(
            meetingID: context.plan.meetingID
        ), active.isCurrent else { throw AppWorkflowError.briefingUnavailable }
        return try LocalMarkdownExportService(store: runtime.store).exportMarkdown(
            BriefingMarkdownExportRequest(
                meetingID: context.plan.meetingID,
                finalBriefingRevision: try semanticReference(
                    active.publication.finalBriefing
                ),
                fileName: fileName,
                expectedClassification: expectedClassification,
                explicitUserAuthorization: true,
                requestedAt: try currentInstant()
            )
        )
    }

    func storageReport() async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.storageReporter.storageReport(
            calculatedAt: currentInstant(),
            maximumEntries: 100_000
        )
    }

    func historicalIndexStatus() async throws -> HistoricalIndexStatus {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.historicalIndexStatus()
    }

    func rebuildHistoricalIndex() async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let plan = try HistoricalIndexRebuildJobPlan(requestedAt: currentInstant())
        let record = try await runtime.manager.enqueue(
            HistoricalIndexRebuildJobFactory().request(
                plan: plan,
                requestedBy: JobRequester("meetingbuddy-app")
            )
        )
        return MediaJobReview(record: record)
    }

    func searchMeetingHistory(
        _ query: HistoricalSearchQuery
    ) async throws -> HistoricalSearchPage {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        do {
            return try runtime.store.searchHistory(query)
        } catch let error as HistoricalReviewError {
            throw error
        } catch {
            throw AppWorkflowError.historicalReviewUnavailable
        }
    }

    func compareHistoricalPositions(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) async throws -> HistoricalComparisonV1 {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let evaluation = HistoricalComparisonEvaluator.evaluate(
            current: current,
            historical: historical
        )
        let candidate = try HistoricalComparisonFactory.candidate(
            evaluation: evaluation,
            createdAt: currentInstant()
        )
        try runtime.store.publishHistoricalComparison(
            candidate,
            expectedCurrentRevisionID: nil,
            changedAt: candidate.revision.createdAt
        )
        return candidate
    }

    func confirmHistoricalChange(
        candidateRevisionID: RevisionID
    ) async throws -> HistoricalComparisonV1 {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let candidate = try runtime.store.fetch(
            HistoricalComparisonV1.self,
            revisionID: candidateRevisionID
        ) else { throw HistoricalReviewError.sourceUnavailable(candidateRevisionID) }
        let confirmed = try HistoricalComparisonFactory.confirmedChange(
            candidate: candidate,
            confirmedAt: currentInstant()
        )
        try runtime.store.publishHistoricalComparison(
            confirmed,
            expectedCurrentRevisionID: candidate.revision.revisionID,
            changedAt: confirmed.revision.createdAt
        )
        return confirmed
    }

    func learnedPreferenceState() async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.learnedPreferenceState(maximumEvents: 100)
    }

    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?
    ) async throws -> LearnedPreferenceRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.saveLearnedPreference(
            preferenceID: preferenceID,
            value: value,
            enabled: enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.setLearnedPreferenceEnabled(
            preferenceID: preferenceID,
            enabled: enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        try runtime.store.removeLearnedPreference(
            preferenceID: preferenceID,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.setLearnedPreferencesGloballyEnabled(
            enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.resetLearnedPreferences(
            sourceAction: sourceAction,
            expectedSettingsVersion: expectedSettingsVersion,
            changedAt: currentInstant()
        )
    }

    func restoreTrashItem(
        storageObjectID: StorageObjectID
    ) async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        _ = try runtime.coordinator.restoreFromTrash(
            storageObjectID: storageObjectID,
            at: currentInstant()
        )
        return try await storageReport()
    }

    func permanentlyDeleteTrashItem(
        storageObjectID: StorageObjectID,
        confirmsPermanentDeletion: Bool,
        acknowledgesUnlinkIsNotSecureErasure: Bool
    ) async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let timestamp = try currentInstant()
        let method: ManagedAssetDeletionMethod = .filesystemUnlinkNoErasureGuarantee
        guard acknowledgesUnlinkIsNotSecureErasure else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Permanent deletion requires acknowledgment of filesystem unlink semantics."
            )
        }
        let authorization = try ManagedAssetPurgeAuthorization(
            purgeID: UUID(),
            storageObjectID: storageObjectID,
            confirmedAt: timestamp,
            visibleUserConfirmation: confirmsPermanentDeletion,
            acknowledgedDeletionMethod: method
        )
        _ = try runtime.coordinator.permanentlyDeleteFromTrash(
            storageObjectID: storageObjectID,
            authorization: authorization
        )
        return try await storageReport()
    }

    func recordingSetup() async throws -> RecordingSetupReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let sessions = try await runtime.store.nonterminalSessions()
        guard sessions.count <= 1 else { throw AppWorkflowError.workspaceHealthFailed }
        let recoveredSession: RecordingSessionSnapshot?
        if let recovered = runtime.mostRecentRecoveredRecordingSession {
            recoveredSession = try await runtime.store.session(recovered.intent.sessionID)
        } else {
            recoveredSession = nil
        }
        let visibleSession = sessions.first ?? recoveredSession
        let recoverable: RecordingSessionReview?
        if let session = visibleSession {
            recoverable = try await recordingReview(snapshot: session, runtime: runtime)
        } else {
            recoverable = nil
        }
        return RecordingSetupReview(
            capability: await runtime.captureProvider.snapshot(),
            microphones: try await runtime.captureProvider.microphones(),
            recoverableSession: recoverable
        )
    }

    func startRecording(
        _ submission: RecordingStartSubmission
    ) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard submission.directUserAcknowledgement else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }
        guard try await runtime.store.nonterminalSessions().isEmpty else {
            throw AppWorkflowError.recordingInProgress
        }
        let title = submission.meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 2_048 else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }

        let capability = await runtime.captureProvider.snapshot()
        if submission.mode.requestedTrackKinds.contains(.applicationAudio) {
            guard capability.applicationAudioAvailable, capability.systemPickerAvailable else {
                throw AppWorkflowError.recordingUnavailable
            }
        }
        let microphone: CaptureMicrophoneChoice?
        if submission.mode.requestedTrackKinds.contains(.microphone) {
            guard let microphoneID = submission.microphoneDeviceID,
                  let selected = try await runtime.captureProvider.microphones().first(where: {
                      $0.id == microphoneID
                  })
            else { throw AppWorkflowError.recordingAuthorizationRequired }
            microphone = selected
        } else {
            guard submission.microphoneDeviceID == nil else {
                throw AppWorkflowError.recordingAuthorizationRequired
            }
            microphone = nil
        }

        let sessionID = RecordingSessionID(UUID())
        let jobID = JobID(UUID())
        let epochID = RecordingEpochID(UUID())
        var trackRequests: [RecordingTrackRequest] = []
        if submission.mode.requestedTrackKinds.contains(.microphone) {
            trackRequests.append(
                try RecordingTrackRequest(
                    kind: .microphone,
                    speechSourceKind: submission.microphoneSpeechSourceKind,
                    language: submission.language
                )
            )
        }
        if submission.mode.requestedTrackKinds.contains(.applicationAudio) {
            trackRequests.append(
                try RecordingTrackRequest(
                    kind: .applicationAudio,
                    speechSourceKind: submission.applicationSpeechSourceKind,
                    language: submission.language
                )
            )
        }

        let selection = try await runtime.captureProvider.requestSelection(
            CaptureSelectionRequest(
                sessionID: sessionID,
                epochID: epochID,
                mode: submission.mode,
                microphoneDeviceID: microphone?.id
            )
        )
        let applicationFormat = try CaptureAudioFormat(
            sampleRateHertz: 48_000,
            channelCount: 2,
            channelLayout: "interleaved-pcm-s16le",
            formatRevision: 1
        )
        let epochSources = try trackRequests.map { request -> RecordingEpochSource in
            switch request.kind {
            case .microphone:
                guard let microphone else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: sessionScopedSourceToken(
                        sessionID: sessionID,
                        sourceClass: "microphone",
                        platformIdentifier: microphone.id,
                        selectedAt: selection.selectedAt,
                        format: microphone.audioFormat
                    ),
                    audioFormat: microphone.audioFormat
                )
            case .applicationAudio:
                guard let token = selection.applicationSourceToken else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: token,
                    audioFormat: applicationFormat
                )
            }
        }
        let epoch = try RecordingEpoch(
            epochID: epochID,
            sessionID: sessionID,
            sequence: 1,
            selectedAt: selection.selectedAt,
            sources: epochSources,
            sourceSetDigest: try sourceSetDigest(epochSources),
            startHostNanoseconds: DispatchTime.now().uptimeNanoseconds
        )

        let createdAt = try currentInstant()
        let meeting = try meetingProfile(
            title: title,
            classification: submission.dataClassification,
            language: submission.language,
            workspaceID: runtime.descriptor.manifest.workspaceID,
            createdAt: createdAt
        )
        let policy = try persistMeetingAndDefaultPolicy(
            meeting,
            createdAt: createdAt,
            runtime: runtime
        )
        let policySnapshot = try RecordingPolicySnapshot(
            sensitivityLabelRevision: semanticReference(policy.sensitivityLabel),
            accessPolicyRevision: semanticReference(policy.accessPolicy),
            dataClassification: policy.accessPolicy.effectiveClassification,
            localProcessingAllowed: policy.accessPolicy.localProcessingAllowed,
            noOutboundMode: policy.accessPolicy.noOutboundMode
        )
        let intent = try RecordingIntent(
            sessionID: sessionID,
            jobID: jobID,
            meetingID: meeting.meetingID,
            mode: submission.mode,
            requestedTracks: trackRequests,
            policy: policySnapshot,
            authorization: RecordingAuthorizationEvent(
                occurredAt: selection.selectedAt,
                directUserAction: true,
                visibleRecordingAcknowledged: true,
                participantAndPolicyResponsibilityAcknowledged: true
            ),
            diskBudgetBytes: 8 * 1_024 * 1_024 * 1_024,
            createdAt: createdAt
        )
        let plan = try RecordingCaptureJobPlan(intent: intent, initialEpoch: epoch)
        let initial = try await runtime.store.createIntent(intent)
        try await runtime.store.registerEpoch(epoch)

        let prepared: PreparedCapture
        do {
            prepared = try await runtime.captureProvider.prepare(
                PreparedCaptureRequest(
                    authorization: selection,
                    tracks: trackRequests
                )
            )
        } catch {
            let failureReason: RecordingTransitionReason
            if case CaptureProviderError.permissionDenied = error {
                failureReason = .permissionDenied
            } else {
                failureReason = .sourceUnavailable
            }
            _ = try? await runtime.store.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: initial.stateVersion,
                    from: .preparing,
                    to: .failed,
                    reason: failureReason,
                    actor: .captureProvider,
                    occurredAt: try currentInstant()
                )
            )
            throw error
        }

        try await runtime.captureRegistry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: prepared,
                epoch: epoch,
                provider: runtime.captureProvider
            ),
            for: jobID
        )
        do {
            _ = try await runtime.manager.enqueue(
                RecordingCaptureJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        } catch {
            await runtime.captureRegistry.discard(jobID: jobID)
            if let snapshot = try? await runtime.store.session(sessionID), snapshot.state == .preparing {
                _ = try? await runtime.store.transition(
                    RecordingTransition(
                        sessionID: sessionID,
                        expectedStateVersion: snapshot.stateVersion,
                        from: .preparing,
                        to: .failed,
                        reason: .sourceUnavailable,
                        actor: .taskManager,
                        occurredAt: try currentInstant()
                    )
                )
            }
            throw error
        }
        return try await recordingReview(jobID: jobID)
    }

    func recordingReview(jobID: JobID) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let snapshot = try await runtime.store.session(jobID: jobID) else {
            throw AppWorkflowError.recordingUnavailable
        }
        return try await recordingReview(snapshot: snapshot, runtime: runtime)
    }

    func resumeRecording(
        jobID: JobID,
        submission: RecordingResumeSubmission
    ) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard submission.directUserAcknowledgement else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }
        guard let snapshot = try await runtime.store.session(jobID: jobID),
              snapshot.state == .interrupted || snapshot.state == .recovering,
              let job = try await runtime.manager.job(id: jobID),
              job.state == .failed || job.state == .interrupted
        else {
            throw AppWorkflowError.recordingUnavailable
        }

        let mode = snapshot.intent.mode
        let capability = await runtime.captureProvider.snapshot()
        if mode.requestedTrackKinds.contains(.applicationAudio) {
            guard capability.applicationAudioAvailable, capability.systemPickerAvailable else {
                throw AppWorkflowError.recordingUnavailable
            }
        }
        let microphone: CaptureMicrophoneChoice?
        if mode.requestedTrackKinds.contains(.microphone) {
            guard let microphoneID = submission.microphoneDeviceID,
                  let selected = try await runtime.captureProvider.microphones().first(where: {
                      $0.id == microphoneID
                  })
            else { throw AppWorkflowError.recordingAuthorizationRequired }
            microphone = selected
        } else {
            guard submission.microphoneDeviceID == nil else {
                throw AppWorkflowError.recordingAuthorizationRequired
            }
            microphone = nil
        }

        let priorEpochs = try await runtime.store.epochs(sessionID: snapshot.intent.sessionID)
        guard let priorSequence = priorEpochs.map(\.sequence).max(),
              priorSequence < UInt32.max
        else { throw AppWorkflowError.recordingUnavailable }
        let epochID = RecordingEpochID(UUID())
        let selection = try await runtime.captureProvider.requestSelection(
            CaptureSelectionRequest(
                sessionID: snapshot.intent.sessionID,
                epochID: epochID,
                mode: mode,
                microphoneDeviceID: microphone?.id
            )
        )
        let applicationFormat = try CaptureAudioFormat(
            sampleRateHertz: 48_000,
            channelCount: 2,
            channelLayout: "interleaved-pcm-s16le",
            formatRevision: 1
        )
        let epochSources = try snapshot.intent.requestedTracks.map {
            request -> RecordingEpochSource in
            switch request.kind {
            case .microphone:
                guard let microphone else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: sessionScopedSourceToken(
                        sessionID: snapshot.intent.sessionID,
                        sourceClass: "microphone",
                        platformIdentifier: microphone.id,
                        selectedAt: selection.selectedAt,
                        format: microphone.audioFormat
                    ),
                    audioFormat: microphone.audioFormat
                )
            case .applicationAudio:
                guard let token = selection.applicationSourceToken else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: token,
                    audioFormat: applicationFormat
                )
            }
        }
        let epoch = try RecordingEpoch(
            epochID: epochID,
            sessionID: snapshot.intent.sessionID,
            sequence: priorSequence + 1,
            selectedAt: selection.selectedAt,
            sources: epochSources,
            sourceSetDigest: try sourceSetDigest(epochSources),
            startHostNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        let prepared = try await runtime.captureProvider.prepare(
            PreparedCaptureRequest(
                authorization: selection,
                tracks: snapshot.intent.requestedTracks
            )
        )

        if snapshot.state == .interrupted {
            _ = try await runtime.recordingRecovery.recover(snapshot.intent.sessionID)
        }
        try await runtime.captureRegistry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: prepared,
                epoch: epoch,
                provider: runtime.captureProvider
            ),
            for: jobID
        )
        do {
            _ = try await runtime.manager.retry(jobID: jobID)
        } catch {
            await runtime.captureRegistry.discard(jobID: jobID)
            throw error
        }
        return try await recordingReview(jobID: jobID)
    }

    func stopRecording(jobID: JobID) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let snapshot = try await runtime.store.session(jobID: jobID) else {
            throw AppWorkflowError.recordingUnavailable
        }
        if snapshot.state.isTerminal {
            return try await recordingReview(snapshot: snapshot, runtime: runtime)
        }

        let job = try await runtime.manager.job(id: jobID)
        if let job, job.state.isActiveExecution || job.state == .queued {
            _ = try await runtime.manager.cancel(jobID: jobID)
        } else {
            let outcome = try await runtime.recordingRecovery.recover(snapshot.intent.sessionID)
            let coordinator = RecordingPersistenceCoordinator(
                repository: runtime.store,
                fileStore: runtime.recordingFileStore,
                assetStorage: runtime.coordinator,
                assetCatalog: runtime.store,
                assetFileAccess: runtime.fileAccess
            )
            _ = try await coordinator.restore(
                outcome: outcome,
                epochs: try await runtime.store.epochs(sessionID: snapshot.intent.sessionID)
            )
            _ = try await coordinator.stop(reason: .recoveredWithoutResume)
        }

        for _ in 0..<100 {
            if let current = try await runtime.store.session(jobID: jobID), current.state.isTerminal {
                return try await recordingReview(snapshot: current, runtime: runtime)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AppWorkflowError.recordingUnavailable
    }

    func fetchUNWebTVMetadata(
        url: String,
        explicitNetworkAuthorization: Bool
    ) async throws -> UNWebTVMetadataCandidate {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        do {
            return try await runtime.metadataSource.metadataCandidate(
                for: ValidatedUNWebTVAssetURL(url),
                policy: UNWebTVMetadataRequestPolicy(
                    directUserAction: explicitNetworkAuthorization,
                    outboundEnabled: explicitNetworkAuthorization
                )
            )
        } catch {
            throw AppWorkflowError.webMetadataUnavailable
        }
    }

    private func recordingReview(
        snapshot: RecordingSessionSnapshot,
        runtime: WorkspaceRuntime
    ) async throws -> RecordingSessionReview {
        let checkpoint = try? await runtime.store.latestCheckpoint(
            sessionID: snapshot.intent.sessionID
        )
        let gaps = try await runtime.store.gaps(sessionID: snapshot.intent.sessionID)
        guard let gapCount = UInt32(exactly: gaps.count) else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        let safeReason: String?
        if let reason = snapshot.terminalReason {
            safeReason = reason.rawValue
        } else if snapshot.state == .recovering {
            safeReason = "Recovered sealed audio is retained. Finish to verify an incomplete result."
        } else if snapshot.state == .interrupted {
            safeReason = "Capture continuity was interrupted; no source was substituted."
        } else {
            safeReason = nil
        }
        return RecordingSessionReview(
            sessionID: snapshot.intent.sessionID,
            jobID: snapshot.intent.jobID,
            state: snapshot.state,
            stateVersion: snapshot.stateVersion,
            activeTrackKinds: snapshot.intent.requestedTracks.map(\.kind).sorted {
                $0.rawValue < $1.rawValue
            },
            durableThroughNanoseconds: checkpoint?.tracks
                .map(\.lastCoveredMediaRange.endNanoseconds).max(),
            knownGapCount: gapCount,
            safeReason: safeReason
        )
    }

    private func persistMeetingAndDefaultPolicy(
        _ meeting: MeetingProfileV1,
        createdAt: UTCInstant,
        runtime: WorkspaceRuntime
    ) throws -> LocalSecurityPolicyBundle {
        try runtime.store.insert(meeting)
        let meetingUUID = try requiredUUID(meeting.meetingID.canonicalString)
        let policy = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: SensitivityLabelID(meetingUUID),
            sensitivityLabelRevisionID: RevisionID(UUID()),
            accessPolicyID: AccessPolicyID(meetingUUID),
            accessPolicyRevisionID: RevisionID(UUID()),
            createdAt: createdAt
        )
        try runtime.store.insert(policy.sensitivityLabel)
        _ = try runtime.store.activate(
            ActivePublishedRevisionSelection(
                logicalID: policy.sensitivityLabel.labelID,
                revisionID: policy.sensitivityLabel.revision.revisionID
            ),
            as: SensitivityLabelV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: createdAt
        )
        try runtime.store.insert(policy.accessPolicy)
        _ = try runtime.store.activate(
            ActivePublishedRevisionSelection(
                logicalID: policy.accessPolicy.policyID,
                revisionID: policy.accessPolicy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: createdAt
        )
        return policy
    }

    private func sessionScopedSourceToken(
        sessionID: RecordingSessionID,
        sourceClass: String,
        platformIdentifier: String,
        selectedAt: UTCInstant,
        format: CaptureAudioFormat
    ) throws -> ContentDigest {
        let material = [
            sessionID.canonicalString,
            sourceClass,
            platformIdentifier,
            String(selectedAt.millisecondsSinceUnixEpoch),
            String(format.sampleRateHertz),
            String(format.channelCount),
            format.channelLayout,
            String(format.formatRevision)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func sourceSetDigest(
        _ sources: [RecordingEpochSource]
    ) throws -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(sources.sorted { $0.trackID < $1.trackID })
        let digest = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func releasePendingSource() {
        if pendingSourceDidStartScope {
            pendingSourceURL?.stopAccessingSecurityScopedResource()
        }
        pendingSourceURL = nil
        pendingSourceDidStartScope = false
        pendingInspection = nil
    }

    private func currentInstant() throws -> UTCInstant {
        try UTCInstant(
            millisecondsSinceUnixEpoch: Int64(
                max(Date().timeIntervalSince1970 * 1_000, 0).rounded(.down)
            )
        )
    }

    private func canonicalContext(jobID: JobID) async throws -> (
        plan: CanonicalAudioJobPlan,
        canonicalReference: SemanticRevisionReference
    ) {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let record = try await runtime.manager.job(id: jobID),
              record.jobType == MediaJobTypes.canonicalAudio,
              record.state == .succeeded,
              record.outputRevisionIDs.count == 1,
              let reference = record.outputRevisionIDs.first
        else { throw AppWorkflowError.canonicalAudioRequired }
        return (try CanonicalAudioJobPlan.decode(from: record.inputPayload), reference)
    }

    private func analysisSource(
        canonicalJobID: JobID
    ) async throws -> AnalysisSourceBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(
            meetingID: context.plan.meetingID
        ),
            review.manifest.status == .published
        else { throw AppWorkflowError.transcriptUnavailable }
        let activeMeeting = try runtime.store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: context.plan.meetingID
        )?.revision
        let meeting: MeetingProfileV1
        if let activeMeeting {
            meeting = activeMeeting
        } else {
            let revisions = try runtime.store.revisions(
                MeetingProfileV1.self,
                logicalID: context.plan.meetingID
            )
            guard revisions.count == 1, let only = revisions.first else {
                throw AppWorkflowError.analysisUnavailable
            }
            meeting = only
        }
        let meetingReference = try SemanticRevisionReference(
            logicalID: meeting.meetingID,
            revisionID: meeting.revision.revisionID
        )
        do {
            return try runtime.store.analysisSourceBundle(
                meetingRevision: meetingReference,
                transcriptManifestID: review.manifest.manifestID
            )
        } catch {
            throw AppWorkflowError.analysisUnavailable
        }
    }

    private func briefingSource(
        canonicalJobID: JobID,
        template: MeetingTemplateV1
    ) async throws -> BriefingSourceBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let analysis = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ), analysis.ledger.status == .published else {
            throw AppWorkflowError.briefingUnavailable
        }
        let meetingState = try runtime.store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: context.plan.meetingID
        )
        let meeting: MeetingProfileV1
        if let meetingState {
            meeting = meetingState.revision
        } else {
            let revisions = try runtime.store.revisions(
                MeetingProfileV1.self,
                logicalID: context.plan.meetingID
            )
            guard revisions.count == 1, let only = revisions.first else {
                throw AppWorkflowError.briefingUnavailable
            }
            meeting = only
        }
        do {
            return try runtime.store.briefingSourceBundle(
                meetingRevision: try semanticReference(meeting),
                template: template,
                analysisLedgerID: analysis.ledger.ledgerID
            )
        } catch {
            throw AppWorkflowError.briefingUnavailable
        }
    }

    private func approvedBriefingRoute(
        source: BriefingSourceBundle,
        visibleUserAuthorization: Bool
    ) async throws -> ModelRouteDecision {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let locale = source.meeting.outputLanguage.value
        let available = await runtime.briefingProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let decision = try ModelPolicyRouter().decide(
            briefingRouteRequest(
                source: source,
                modelAvailable: available,
                visibleUserAuthorization: visibleUserAuthorization
            )
        )
        guard decision.route == .appleOnDevice,
              decision.providerIdentifier == "apple-foundation-models",
              available else { throw AppWorkflowError.onDeviceModelUnavailable }
        return decision
    }

    private func briefingRouteRequest(
        source: BriefingSourceBundle,
        modelAvailable: Bool,
        visibleUserAuthorization: Bool
    ) throws -> ModelRouteRequest {
        let classification = DataClassification.mostRestrictive(
            [source.meeting.revision.dataClassification]
                + source.analysis.evidence.map(\.revision.dataClassification)
                + source.analysis.positions.map(\.revision.dataClassification)
                + source.analysis.interventionCards.map(\.revision.dataClassification)
                + source.analysis.delegationPositionCards.map(\.revision.dataClassification)
        ) ?? .restricted
        return try ModelRouteRequest(
            capability: .analysis,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: [.validatedIntelligenceClaims, .evidenceIdentifiers],
            visibleUserAuthorization: visibleUserAuthorization,
            localModelAvailable: modelAvailable,
            securityPolicy: try securityPolicySnapshot(
                meetingID: source.meeting.meetingID
            )
        )
    }

    private func briefingRuntimeEvidence(
        localeIdentifier: String,
        modelAvailable: Bool
    ) throws -> AnalysisRuntimeEvidence {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return try AnalysisRuntimeEvidence(
            operatingSystemVersion: "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            frameworkIdentifier: "com.apple.FoundationModels",
            adapterVersion: "meetingbuddy-task006b-v1",
            localeIdentifier: localeIdentifier,
            modelAvailable: modelAvailable,
            noOutboundMode: true
        )
    }

    private func semanticReference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    private func analysisRouteRequest(
        source: AnalysisSourceBundle,
        modelAvailable: Bool,
        visibleUserAuthorization: Bool
    ) throws -> ModelRouteRequest {
        let packages = try AnalysisPipelineJobPlan.requestPackages(from: source)
        let classification = DataClassification.mostRestrictive(
            packages.map(\.request.dataClassification)
                + [source.meeting.revision.dataClassification]
        ) ?? .restricted
        var categories: [ProviderDataCategory] = [
            .transcriptText,
            .speakerContext,
            .evidenceIdentifiers
        ]
        if !source.transcriptReview.translations.isEmpty {
            categories.append(.translationText)
        }
        return try ModelRouteRequest(
            capability: .analysis,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: categories,
            visibleUserAuthorization: visibleUserAuthorization,
            localModelAvailable: modelAvailable,
            securityPolicy: try securityPolicySnapshot(
                meetingID: source.meeting.meetingID
            )
        )
    }

    private func analysisRuntimeEvidence(
        localeIdentifier: String,
        modelAvailable: Bool
    ) throws -> AnalysisRuntimeEvidence {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return try AnalysisRuntimeEvidence(
            operatingSystemVersion: "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            frameworkIdentifier: "com.apple.FoundationModels",
            adapterVersion: "meetingbuddy-task006a-v1",
            localeIdentifier: localeIdentifier,
            modelAvailable: modelAvailable,
            noOutboundMode: true
        )
    }

    private func routeRequest(
        meetingID: MeetingID,
        capability: AIProcessingCapability,
        classification: DataClassification,
        categories: [ProviderDataCategory],
        localModelAvailable: Bool
    ) throws -> ModelRouteRequest {
        try ModelRouteRequest(
            capability: capability,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .localWorkspaceOnly,
            dataCategories: categories,
            visibleUserAuthorization: false,
            localModelAvailable: localModelAvailable,
            securityPolicy: try securityPolicySnapshot(meetingID: meetingID)
        )
    }

    private func securityPolicySnapshot(
        meetingID: MeetingID
    ) throws -> ModelSecurityPolicySnapshot? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let labelID = try SensitivityLabelID(validating: meetingID.canonicalString)
        let policyID = try AccessPolicyID(validating: meetingID.canonicalString)
        guard let label = try runtime.store.activeRevisionState(
            SensitivityLabelV1.self,
            logicalID: labelID
        )?.revision,
            let policy = try runtime.store.activeRevisionState(
                AccessPolicyV1.self,
                logicalID: policyID
            )?.revision
        else {
            // Accepted v5 jobs remain readable and local-only. Absence never
            // becomes external-processing authority.
            return nil
        }
        let labelReference = try semanticReference(label)
        guard policy.meetingID == meetingID,
              label.meetingID == meetingID,
              policy.sensitivityLabelRevision == labelReference,
              policy.effectiveClassification == label.effectiveClassification
        else { throw AppWorkflowError.workspaceHealthFailed }
        return try LocalSecurityPolicyBundle(
            sensitivityLabel: label,
            accessPolicy: policy
        ).modelSnapshot
    }

    private func requiredUUID(_ canonicalString: String) throws -> UUID {
        guard let value = UUID(uuidString: canonicalString) else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        return value
    }

    private func sourceByteSize(_ sourceURL: URL) throws -> UInt64 {
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0
        else {
            throw AppWorkflowError.sourceAuthorizationFailed
        }
        return UInt64(fileSize)
    }

    private func terminalJob(
        _ jobID: JobID,
        manager: LocalTaskManager
    ) async throws -> JobRecord {
        while true {
            try Task.checkCancellation()
            guard let record = try await manager.job(id: jobID) else {
                throw AppWorkflowError.jobUnavailable
            }
            if record.state.isTerminal { return record }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func meetingProfile(
        title: String,
        classification: DataClassification,
        language: LanguageTag?,
        workspaceID: WorkspaceID,
        createdAt: UTCInstant
    ) throws -> MeetingProfileV1 {
        try MeetingProfileV1(
            revision: RevisionEnvelope(
                logicalID: MeetingID(UUID()),
                revisionID: RevisionID(UUID()),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .user,
                dataClassification: classification
            ),
            title: title,
            sourceLanguages: language.map { [$0] } ?? [],
            outputLanguage: language ?? LanguageTag("en"),
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspaceID,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "BlueMinutes Workspace" : name
    }
}
