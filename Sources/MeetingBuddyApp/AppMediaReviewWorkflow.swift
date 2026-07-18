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
    case reviewFailed

    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "Choose a local MeetingBuddy workspace first."
        case .workspaceAuthorizationFailed:
            "MeetingBuddy could not retain access to the selected workspace."
        case .workspaceOpenFailed:
            "The selected folder is not an empty folder or a valid MeetingBuddy workspace."
        case .workspaceHealthFailed:
            "The workspace did not pass its local database and recovery health checks."
        case .sourceAuthorizationFailed:
            "MeetingBuddy could not read the user-selected source file."
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
        case .reviewFailed:
            "The transcript review change failed without replacing accepted content."
        }
    }
}

private final class WorkspaceRuntime: @unchecked Sendable {
    let descriptor: LocalWorkspaceDescriptor
    let store: SQLitePersistenceStore
    let storage: LocalStorageService
    let coordinator: ManagedAssetCoordinator
    let fileAccess: LocalManagedMediaFileAccess
    let processor: AVFoundationMediaProcessor
    let intake: LocalMediaIntakeService
    let transientSources: TransientMediaSourceRegistry
    let manager: LocalTaskManager
    let transcriptionProvider: (any TranscriptionProvider)?
    let translationProvider: (any TranslationProvider)?

    init(descriptor: LocalWorkspaceDescriptor) throws {
        self.descriptor = descriptor
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
        var executors: [any TaskJobExecutor] = [intakeExecutor, canonicalExecutor]
        if #available(macOS 26.0, *) {
            let speech = AppleOnDeviceTranscriptionProvider()
            let translation = AppleOnDeviceTranslationProvider()
            transcriptionProvider = speech
            translationProvider = translation
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
        } else {
            transcriptionProvider = nil
            translationProvider = nil
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
    }
}

@MainActor
final class AppMediaReviewWorkflow: MediaReviewWorkflow {
    private let workspaceService = LocalWorkspaceService()
    private let workspaceSecurityScope = WorkspaceSecurityScope()

    private var runtime: WorkspaceRuntime?
    private var workspaceDisplayName = ""
    private var pendingSourceURL: URL?
    private var pendingSourceDidStartScope = false
    private var pendingInspection: MediaInspection?

    deinit {
        if pendingSourceDidStartScope {
            pendingSourceURL?.stopAccessingSecurityScopedResource()
        }
    }

    func restoreWorkspace() async throws -> WorkspaceReview? {
        guard let url = try workspaceSecurityScope.restore() else { return nil }
        do {
            let descriptor = try workspaceService.openWorkspace(at: url)
            let nextRuntime = try WorkspaceRuntime(descriptor: descriptor)
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
            let nextRuntime = try WorkspaceRuntime(descriptor: descriptor)
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
                capability: .transcription,
                classification: context.plan.dataClassification,
                categories: [.canonicalAudio],
                localModelAvailable: false
            )
        )
        let translationRoute = try submission.targetLanguage.map { _ in
            try ModelPolicyRouter().decide(
                routeRequest(
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

    private func routeRequest(
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
            localModelAvailable: localModelAvailable
        )
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
        return name.isEmpty ? "MeetingBuddy Workspace" : name
    }
}
