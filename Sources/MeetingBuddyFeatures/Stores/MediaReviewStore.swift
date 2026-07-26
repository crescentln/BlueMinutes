import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

@MainActor
@Observable
public final class MediaReviewStore {
    public private(set) var workspace: WorkspaceReview?
    public private(set) var pendingMedia: PendingMediaReview?
    public private(set) var importedSource: ImportedSourceReview?
    public private(set) var job: MediaJobReview?
    public private(set) var transcriptJob: MediaJobReview?
    public private(set) var routeReview: TranscriptRouteReview?
    public private(set) var transcriptReview: TranscriptReviewBundle?
    public private(set) var analysisJob: MediaJobReview?
    public private(set) var analysisRouteReview: AnalysisRouteReview?
    public private(set) var analysisReview: AnalysisReviewBundle?
    public private(set) var briefingJob: MediaJobReview?
    public private(set) var briefingRouteReview: BriefingRouteReview?
    public private(set) var briefingReview: BriefingReviewBundle?
    public private(set) var lastBriefingExport: BriefingExportRecord?
    public private(set) var historicalIndex: HistoricalIndexStatus?
    public private(set) var historicalIndexJob: MediaJobReview?
    public private(set) var historicalSearchPage: HistoricalSearchPage?
    public private(set) var historicalComparison: HistoricalComparisonV1?
    public private(set) var learnedPreferences: LearnedPreferenceState?
    public private(set) var storageReport: WorkspaceStorageReport?
    public private(set) var recordingSetup: RecordingSetupReview?
    public private(set) var recordingSession: RecordingSessionReview?
    public private(set) var webMetadataCandidate: UNWebTVMetadataCandidate?
    public private(set) var isWorking = false
    public private(set) var isStoppingRecording = false
    public private(set) var safeErrorMessage: String?
    public private(set) var workspaceSession: UInt64 = 0

    @ObservationIgnored
    private let workflow: any MediaReviewWorkflow
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var recordingPollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasCompletedWorkspaceRestore = false
    @ObservationIgnored
    private var isWorkspaceRestoreInFlight = false

    public var blocksWorkspaceSwitch: Bool {
        recordingSession?.blocksWorkspaceSwitch == true
    }

    public var recordingIndicatorIsVisible: Bool {
        guard let recordingSession else { return false }
        return !recordingSession.state.isTerminal
    }

    public var blocksMediaReplacement: Bool {
        [job, transcriptJob, analysisJob, briefingJob]
            .compactMap { $0 }
            .contains { !$0.state.isTerminal }
    }

    var editorReviewSnapshot: MediaReviewEditorReviewSnapshot {
        MediaReviewEditorReviewSnapshot(
            transcript: transcriptReview,
            analysis: analysisReview,
            briefing: briefingReview
        )
    }

    public init(workflow: any MediaReviewWorkflow) {
        self.workflow = workflow
    }

    public func restoreWorkspace(using sceneState: MediaReviewSceneState) async {
        guard !hasCompletedWorkspaceRestore,
              !isWorkspaceRestoreInFlight,
              workspace == nil
        else { return }
        isWorkspaceRestoreInFlight = true
        defer { isWorkspaceRestoreInFlight = false }
        let completed = await perform {
            let restoredWorkspace = try await workflow.restoreWorkspace()
            try Task.checkCancellation()
            if let restoredWorkspace {
                let setup = try await workflow.recordingSetup()
                try Task.checkCancellation()
                advanceWorkspaceSession()
                workspace = restoredWorkspace
                resetMediaState()
                sceneState.resetForWorkspaceChange()
                recordingSetup = setup
                recordingSession = setup.recoverableSession
                sceneState.selectedMicrophoneDeviceID = setup.microphones.first?.id
                if let session = setup.recoverableSession, !session.state.isTerminal {
                    beginRecordingPolling(jobID: session.jobID)
                }
            }
        }
        if completed {
            hasCompletedWorkspaceRestore = true
        }
    }

    public func openOrCreateWorkspace(
        at url: URL,
        using sceneState: MediaReviewSceneState
    ) async {
        guard !blocksWorkspaceSwitch else {
            safeErrorMessage = "Finish or retain the current recording before switching workspaces."
            return
        }
        await perform {
            let openedWorkspace = try await workflow.openOrCreateWorkspace(at: url)
            advanceWorkspaceSession()
            workspace = openedWorkspace
            resetMediaState()
            sceneState.resetForWorkspaceChange()
            let setup = try await workflow.recordingSetup()
            recordingSetup = setup
            recordingSession = setup.recoverableSession
            sceneState.selectedMicrophoneDeviceID = setup.microphones.first?.id
        }
    }

    public func inspectMedia(
        at url: URL,
        using sceneState: MediaReviewSceneState
    ) async {
        await perform {
            let review = try await workflow.inspectSelectedMedia(at: url)
            pendingMedia = review
            sceneState.selectedTrack = review.inspection.audioTracks.count == 1
                ? review.inspection.audioTracks.first?.trackIdentifier
                : nil
        }
    }

    public func discardPendingMedia(using sceneState: MediaReviewSceneState) {
        workflow.discardPendingMedia()
        pendingMedia = nil
        sceneState.selectedTrack = nil
    }

    public func importAndProcess(using sceneState: MediaReviewSceneState) async {
        guard !sceneState.isInteractionLocked else {
            safeErrorMessage = "Wait for the current editor or workspace operation to finish."
            return
        }
        guard !sceneState.hasUnsavedEditorChanges else {
            safeErrorMessage = "Save or discard every unpublished editor draft before replacing the current media workflow."
            return
        }
        guard !blocksMediaReplacement else {
            safeErrorMessage = "Wait for the current media workflow to finish before replacing its source."
            return
        }
        let title = sceneState.meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 2_048 else {
            safeErrorMessage = "Enter a meeting title before importing media."
            return
        }
        guard let pendingMedia else {
            safeErrorMessage = "Choose a supported local audio or video file first."
            return
        }
        if pendingMedia.inspection.audioTracks.count > 1, sceneState.selectedTrack == nil {
            safeErrorMessage = "Select one audio track before processing this media."
            return
        }
        let language: LanguageTag?
        let trimmedLanguage = sceneState.languageTag.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmedLanguage.isEmpty {
            language = nil
        } else {
            do {
                language = try LanguageTag(trimmedLanguage)
            } catch {
                safeErrorMessage = "Use a valid language tag such as en, fr, or zh-hans."
                return
            }
        }
        await perform {
            let result = try await workflow.importAndProcess(
                MediaImportSubmission(
                    meetingTitle: title,
                    dataClassification: sceneState.dataClassification,
                    selectedTrack: sceneState.selectedTrack,
                    speechSourceKind: sceneState.speechSourceKind,
                    language: language
                )
            )
            resetAcceptedMediaReviewState(using: sceneState)
            importedSource = result.0
            job = result.1
            self.pendingMedia = nil
            beginPolling(jobID: result.1.jobID)
        }
    }

    public func cancelJob() async {
        guard let job else { return }
        await perform {
            self.job = try await workflow.cancel(jobID: job.jobID)
        }
    }

    public func retryJob() async {
        guard let job else { return }
        await perform {
            self.job = try await workflow.retry(jobID: job.jobID)
            beginPolling(jobID: job.jobID)
        }
    }

    public func loadRecordingSetup(using sceneState: MediaReviewSceneState) async {
        guard workspace != nil else { return }
        await perform {
            let setup = try await workflow.recordingSetup()
            recordingSetup = setup
            if let recoverable = setup.recoverableSession {
                recordingSession = recoverable
                if !recoverable.state.isTerminal {
                    beginRecordingPolling(jobID: recoverable.jobID)
                }
            }
            if sceneState.selectedMicrophoneDeviceID == nil {
                sceneState.selectedMicrophoneDeviceID = setup.microphones.first?.id
            }
        }
    }

    public func startRecording(using sceneState: MediaReviewSceneState) async {
        let title = sceneState.meetingTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty, title.utf8.count <= 2_048 else {
            safeErrorMessage = "Enter a meeting title before recording."
            return
        }
        guard sceneState.recordingAcknowledged else {
            safeErrorMessage = "A visible recording requires the participant, policy, and legal-responsibility acknowledgement."
            return
        }
        guard recordingSession?.blocksWorkspaceSwitch != true else {
            safeErrorMessage = "Finish the current recording before starting another one."
            return
        }
        let language: LanguageTag?
        let trimmedLanguage = sceneState.languageTag.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmedLanguage.isEmpty {
            language = nil
        } else {
            do {
                language = try LanguageTag(trimmedLanguage)
            } catch {
                safeErrorMessage = "Use a valid language tag such as en, fr, or zh-hans."
                return
            }
        }
        let microphoneID = sceneState.captureMode.requestedTrackKinds.contains(.microphone)
            ? sceneState.selectedMicrophoneDeviceID : nil
        guard !sceneState.captureMode.requestedTrackKinds.contains(.microphone)
            || microphoneID != nil
        else {
            safeErrorMessage = "Select one microphone for this recording session."
            return
        }
        await perform {
            recordingSession = try await workflow.startRecording(
                RecordingStartSubmission(
                    meetingTitle: title,
                    dataClassification: sceneState.dataClassification,
                    mode: sceneState.captureMode,
                    microphoneDeviceID: microphoneID,
                    microphoneSpeechSourceKind: sceneState.microphoneSpeechSourceKind,
                    applicationSpeechSourceKind: sceneState.applicationSpeechSourceKind,
                    language: language,
                    directUserAcknowledgement: true
                )
            )
            sceneState.recordingAcknowledged = false
            if let recordingSession {
                beginRecordingPolling(jobID: recordingSession.jobID)
            }
        }
    }

    public func stopRecording() async {
        guard let recordingSession, recordingSession.canStop else { return }
        guard !isStoppingRecording else { return }
        safeErrorMessage = nil
        isStoppingRecording = true
        defer { isStoppingRecording = false }
        do {
            self.recordingSession = try await workflow.stopRecording(
                jobID: recordingSession.jobID
            )
            recordingPollingTask?.cancel()
        } catch let error as LocalizedError {
            safeErrorMessage = error.errorDescription
                ?? "The local operation could not be completed."
        } catch {
            safeErrorMessage = "The local operation could not be completed."
        }
    }

    public func resumeRecording(using sceneState: MediaReviewSceneState) async {
        guard let recordingSession,
              recordingSession.state == .interrupted || recordingSession.state == .recovering
        else { return }
        guard sceneState.recordingAcknowledged else {
            safeErrorMessage = "Resuming requires a fresh visible recording acknowledgement and source selection."
            return
        }
        let microphoneID = recordingSession.activeTrackKinds.contains(.microphone)
            ? sceneState.selectedMicrophoneDeviceID : nil
        guard !recordingSession.activeTrackKinds.contains(.microphone) || microphoneID != nil else {
            safeErrorMessage = "Select one microphone before resuming this recording."
            return
        }
        await perform {
            self.recordingSession = try await workflow.resumeRecording(
                jobID: recordingSession.jobID,
                submission: RecordingResumeSubmission(
                    microphoneDeviceID: microphoneID,
                    directUserAcknowledgement: true
                )
            )
            sceneState.recordingAcknowledged = false
            beginRecordingPolling(jobID: recordingSession.jobID)
        }
    }

    public func fetchUNWebTVMetadata(using sceneState: MediaReviewSceneState) async {
        let value = sceneState.unWebTVURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validatedURL = try? ValidatedUNWebTVAssetURL(value) else {
            safeErrorMessage = "Use an exact official UN Web TV asset URL such as https://webtv.un.org/en/asset/abc/asset-id."
            return
        }
        guard !isWorking, !isStoppingRecording else {
            safeErrorMessage = "Wait for the current local operation to finish."
            return
        }
        guard sceneState.consumeUNWebTVNetworkAuthorization(
            for: validatedURL
        ) else {
            safeErrorMessage = "Authorize this one foreground official-page metadata request."
            return
        }
        await perform {
            let candidate = try await workflow.fetchUNWebTVMetadata(
                url: validatedURL.absoluteString,
                explicitNetworkAuthorization: true
            )
            webMetadataCandidate = candidate
            sceneState.reviewedUNTitle = firstMetadataValue(.title, in: candidate)
            sceneState.reviewedUNDescription = firstMetadataValue(.description, in: candidate)
            sceneState.reviewedUNProductionDate = firstMetadataValue(
                .productionDate,
                in: candidate
            )
            sceneState.reviewedUNLanguageAvailability = firstMetadataValue(
                .languageAvailability,
                in: candidate
            )
        }
    }

    public func refreshTranscriptRoute(using sceneState: MediaReviewSceneState) async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission(using: sceneState) else { return }
        await perform {
            routeReview = try await workflow.transcriptRoute(
                canonicalJobID: job.jobID,
                submission: submission
            )
        }
    }

    public func startTranscript(using sceneState: MediaReviewSceneState) async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission(using: sceneState) else { return }
        await perform {
            let route = try await workflow.transcriptRoute(
                canonicalJobID: job.jobID,
                submission: submission
            )
            routeReview = route
            guard route.isOnDeviceReady else {
                safeErrorMessage = "The selected installed models are unavailable. Use the manual local fallback."
                return
            }
            transcriptJob = try await workflow.startTranscript(
                canonicalJobID: job.jobID,
                submission: submission
            )
            if let transcriptJob { beginTranscriptPolling(jobID: transcriptJob.jobID) }
        }
    }

    public func publishManualTranscript(using sceneState: MediaReviewSceneState) async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission(using: sceneState) else { return }
        let transcript = sceneState.manualTranscriptText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty, transcript.utf8.count <= 65_536 else {
            safeErrorMessage = "Enter a manual transcript of at most 65,536 UTF-8 bytes."
            return
        }
        guard sceneState.manualCoverageConfirmed else {
            safeErrorMessage = "Confirm that the manual text accounts for the complete recording."
            return
        }
        let translation: String?
        if submission.targetLanguage == nil {
            translation = nil
        } else {
            let value = sceneState.manualTranslationText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty, value.utf8.count <= 65_536 else {
                safeErrorMessage = "Enter the manual translation for the selected target language."
                return
            }
            translation = value
        }
        await perform {
            transcriptReview = try await workflow.publishManualTranscript(
                canonicalJobID: job.jobID,
                submission: submission,
                transcriptText: transcript,
                translatedText: translation,
                confirmsCompleteCoverage: sceneState.manualCoverageConfirmed
            )
            sceneState.selectedSection = .transcript
        }
    }

    public func loadTranscriptReview() async {
        guard let job, job.state == .succeeded else { return }
        await perform {
            transcriptReview = try await workflow.transcriptReview(canonicalJobID: job.jobID)
        }
    }

    @discardableResult
    public func correctTranscript(revisionID: RevisionID, text: String) async -> Bool {
        guard let job else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 65_536 else {
            safeErrorMessage = "A corrected transcript segment must contain bounded text."
            return false
        }
        return await perform {
            transcriptReview = try await workflow.correctTranscript(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                text: trimmed
            )
        }
    }

    @discardableResult
    public func correctTranslation(revisionID: RevisionID, text: String) async -> Bool {
        guard let job else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 65_536 else {
            safeErrorMessage = "A corrected translation segment must contain bounded text."
            return false
        }
        return await perform {
            transcriptReview = try await workflow.correctTranslation(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                text: trimmed
            )
        }
    }

    @discardableResult
    public func confirmSpeaker(
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async -> Bool {
        guard let job else { return false }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 512 else {
            safeErrorMessage = "Enter a speaker name of at most 512 UTF-8 bytes."
            return false
        }
        return await perform {
            transcriptReview = try await workflow.confirmSpeaker(
                canonicalJobID: job.jobID,
                transcriptRevisionID: transcriptRevisionID,
                displayName: trimmed
            )
        }
    }

    @discardableResult
    func saveEditorDraft(_ request: MediaReviewDraftSave) async -> Bool {
        switch request {
        case let .transcript(revisionID, text):
            return await correctTranscript(
                revisionID: revisionID,
                text: text
            )
        case let .translation(revisionID, text):
            return await correctTranslation(
                revisionID: revisionID,
                text: text
            )
        case let .speaker(transcriptRevisionID, displayName):
            return await confirmSpeaker(
                transcriptRevisionID: transcriptRevisionID,
                displayName: displayName
            )
        case let .position(
            revisionID,
            positionType,
            statement,
            reservations,
            conditions
        ):
            return await correctPosition(
                revisionID: revisionID,
                positionType: positionType,
                statement: statement,
                reservations: Self.editorLines(reservations),
                conditions: Self.editorLines(conditions)
            )
        case let .briefing(
            sectionType,
            expectedRevisionID,
            editedTextByItemID,
            locked
        ):
            guard briefingReview?.publication.sections.first(where: {
                $0.sectionType == sectionType
            })?.revision.revisionID == expectedRevisionID else {
                safeErrorMessage = "The Briefing section changed after this draft was opened. Keep the draft, review the new revision, and apply the edit again."
                return false
            }
            return await updateBriefingSection(
                sectionType,
                expectedRevisionID: expectedRevisionID,
                editedTextByItemID: editedTextByItemID,
                locked: locked
            )
        }
    }

    public func saveAllEditorDrafts(
        in sceneState: MediaReviewSceneState
    ) async -> Bool {
        guard sceneState.prepareForApplicationTerminationSave() else {
            safeErrorMessage = "Wait for the current editor or workspace operation to finish before quitting."
            return false
        }

        guard sceneState.hasUnsavedEditorChanges else { return true }
        guard let operation = sceneState.beginNextApplicationTerminationSave()
        else {
            safeErrorMessage = "Save each unpublished editor draft separately before quitting. BlueMinutes will not partially save drafts whose revisions depend on one another."
            return false
        }

        let succeeded = await saveEditorDraft(operation.request)
        guard sceneState.completeDirectEditorSave(
            operation,
            succeeded: succeeded,
            updatedReviews: editorReviewSnapshot
        ) else {
            return false
        }
        guard !sceneState.hasUnsavedEditorChanges else {
            safeErrorMessage = "The editor changed while BlueMinutes was saving. Keep the app open and review the remaining draft."
            return false
        }
        return true
    }

    public func refreshAnalysisRoute() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            analysisRouteReview = try await workflow.analysisRoute(
                canonicalJobID: job.jobID
            )
        }
    }

    public func startAnalysis(using sceneState: MediaReviewSceneState) async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            let route = try await workflow.analysisRoute(canonicalJobID: job.jobID)
            analysisRouteReview = route
            guard route.isOnDeviceReady else {
                safeErrorMessage = "The Apple on-device analysis model is unavailable for this meeting language. Existing local review data remains available."
                return
            }
            sceneState.analysisClaimsConfirmed = false
            analysisJob = try await workflow.startAnalysis(canonicalJobID: job.jobID)
            if let analysisJob { beginAnalysisPolling(jobID: analysisJob.jobID) }
        }
    }

    public func loadAnalysisReview() async {
        guard let job, job.state == .succeeded else { return }
        await perform {
            analysisReview = try await workflow.analysisReview(canonicalJobID: job.jobID)
        }
    }

    public func confirmAnalysisReview(using sceneState: MediaReviewSceneState) async {
        guard let job, sceneState.analysisClaimsConfirmed else {
            safeErrorMessage = "Confirm that you reviewed every analysis claim before continuing."
            return
        }
        await perform {
            analysisReview = try await workflow.confirmAnalysisReview(
                canonicalJobID: job.jobID,
                confirmsEveryClaim: sceneState.analysisClaimsConfirmed
            )
        }
    }

    @discardableResult
    public func correctPosition(
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async -> Bool {
        guard let job else { return false }
        let trimmedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReservations = Self.cleanClaims(reservations)
        let cleanConditions = Self.cleanClaims(conditions)
        guard !trimmedStatement.isEmpty, trimmedStatement.utf8.count <= 16_384 else {
            safeErrorMessage = "A corrected position statement must contain at most 16,384 UTF-8 bytes."
            return false
        }
        guard cleanReservations.count == reservations.filter({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }).count,
            cleanConditions.count == conditions.filter({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }).count
        else {
            safeErrorMessage = "Reservations and conditions must be unique bounded statements."
            return false
        }
        return await perform {
            analysisReview = try await workflow.correctPosition(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                positionType: positionType,
                statement: trimmedStatement,
                reservations: cleanReservations,
                conditions: cleanConditions
            )
        }
    }

    public func refreshBriefingRoute() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            briefingRouteReview = try await workflow.briefingRoute(
                canonicalJobID: job.jobID
            )
        }
    }

    public func startBriefing() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            let route = try await workflow.briefingRoute(canonicalJobID: job.jobID)
            briefingRouteReview = route
            guard route.isOnDeviceReady else {
                safeErrorMessage = "The Apple on-device briefing model is unavailable. Existing validated analysis remains unchanged."
                return
            }
            briefingJob = try await workflow.startBriefing(
                canonicalJobID: job.jobID
            )
            if let briefingJob { beginBriefingPolling(jobID: briefingJob.jobID) }
        }
    }

    public func loadBriefingReview() async {
        guard let job, job.state == .succeeded else { return }
        await perform {
            briefingReview = try await workflow.briefingReview(
                canonicalJobID: job.jobID
            )
        }
    }

    public func regenerateBriefingSection(_ sectionType: BriefingSectionType) async {
        guard let job else { return }
        await perform {
            briefingJob = try await workflow.regenerateBriefingSection(
                canonicalJobID: job.jobID,
                sectionType: sectionType
            )
            if let briefingJob { beginBriefingPolling(jobID: briefingJob.jobID) }
        }
    }

    @discardableResult
    public func updateBriefingSection(
        _ sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async -> Bool {
        guard let job else { return false }
        return await perform {
            briefingReview = try await workflow.updateBriefingSection(
                canonicalJobID: job.jobID,
                sectionType: sectionType,
                expectedRevisionID: expectedRevisionID,
                editedTextByItemID: editedTextByItemID,
                locked: locked
            )
        }
    }

    public func exportBriefing(using sceneState: MediaReviewSceneState) async {
        guard let job, let briefingReview else { return }
        let fileName = sceneState.briefingExportFileName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !fileName.isEmpty else {
            safeErrorMessage = "Enter a local Markdown export name."
            return
        }
        await perform {
            lastBriefingExport = try await workflow.exportBriefingMarkdown(
                canonicalJobID: job.jobID,
                fileName: fileName,
                expectedClassification: briefingReview.publication.finalBriefing
                    .revision.dataClassification
            )
        }
    }

    public func loadStorageReport() async {
        guard workspace != nil else { return }
        await perform {
            storageReport = try await workflow.storageReport()
        }
    }

    public func loadHistoricalReview(using sceneState: MediaReviewSceneState) async {
        guard workspace != nil else { return }
        await perform {
            historicalIndex = try await workflow.historicalIndexStatus()
            learnedPreferences = try await workflow.learnedPreferenceState()
            if historicalIndex?.availability == .ready {
                historicalSearchPage = try await workflow.searchMeetingHistory(
                    try historicalQuery(using: sceneState)
                )
            }
        }
    }

    public func rebuildHistoricalIndex(
        using sceneState: MediaReviewSceneState
    ) async {
        guard workspace != nil else { return }
        await perform {
            historicalIndexJob = try await workflow.rebuildHistoricalIndex()
            historicalSearchPage = nil
            historicalComparison = nil
            if let historicalIndexJob {
                beginHistoricalIndexPolling(
                    jobID: historicalIndexJob.jobID,
                    using: sceneState
                )
            }
        }
    }

    public func searchMeetingHistory(using sceneState: MediaReviewSceneState) async {
        await perform {
            historicalSearchPage = try await workflow.searchMeetingHistory(
                try historicalQuery(using: sceneState)
            )
            historicalComparison = nil
        }
    }

    public func compareSelectedHistoricalPositions(
        using sceneState: MediaReviewSceneState
    ) async {
        guard let results = historicalSearchPage?.results,
              let currentID = sceneState.selectedCurrentHistoryRevisionID,
              let priorID = sceneState.selectedPriorHistoryRevisionID,
              currentID != priorID,
              let current = results.first(where: {
                  $0.position.revision.revisionID == currentID
              }),
              let prior = results.first(where: {
                  $0.position.revision.revisionID == priorID
              })
        else {
            safeErrorMessage = "Select two different evidence-linked history results."
            return
        }
        await perform {
            historicalComparison = try await workflow.compareHistoricalPositions(
                current: current,
                historical: prior
            )
        }
    }

    public func confirmHistoricalChange() async {
        guard let comparison = historicalComparison,
              comparison.differenceState == .possibleDifference
        else {
            safeErrorMessage = "Only a possible evidence-linked difference can be confirmed."
            return
        }
        await perform {
            historicalComparison = try await workflow.confirmHistoricalChange(
                candidateRevisionID: comparison.revision.revisionID
            )
        }
    }

    public func editLearnedPreference(
        _ record: LearnedPreferenceRecord,
        using sceneState: MediaReviewSceneState
    ) {
        sceneState.editingLearnedPreferenceID = record.preferenceID
        sceneState.editingLearnedPreferenceVersion = record.version
        sceneState.learnedPreferenceKind = record.kind
        sceneState.learnedPreferenceValue = editablePreferenceValue(record.value)
    }

    public func saveLearnedPreference(using sceneState: MediaReviewSceneState) async {
        do {
            let value = try parsedPreferenceValue(using: sceneState)
            let preferenceID = sceneState.editingLearnedPreferenceID
                ?? LearnedPreferenceID(UUID())
            await perform {
                _ = try await workflow.saveLearnedPreference(
                    preferenceID: preferenceID,
                    value: value,
                    enabled: true,
                    sourceAction: "explicit-history-preferences-form",
                    expectedVersion: sceneState.editingLearnedPreferenceVersion
                )
                learnedPreferences = try await workflow.learnedPreferenceState()
                clearLearnedPreferenceEditor(in: sceneState)
            }
        } catch {
            safeErrorMessage = "Enter a valid value for the selected learned-preference type."
        }
    }

    public func toggleLearnedPreference(_ record: LearnedPreferenceRecord) async {
        await perform {
            _ = try await workflow.setLearnedPreferenceEnabled(
                preferenceID: record.preferenceID,
                enabled: !record.enabled,
                sourceAction: "explicit-preference-toggle",
                expectedVersion: record.version
            )
            learnedPreferences = try await workflow.learnedPreferenceState()
        }
    }

    public func removeLearnedPreference(
        _ record: LearnedPreferenceRecord,
        using sceneState: MediaReviewSceneState
    ) async {
        await perform {
            try await workflow.removeLearnedPreference(
                preferenceID: record.preferenceID,
                sourceAction: "explicit-preference-remove",
                expectedVersion: record.version
            )
            learnedPreferences = try await workflow.learnedPreferenceState()
            if sceneState.editingLearnedPreferenceID == record.preferenceID {
                clearLearnedPreferenceEditor(in: sceneState)
            }
        }
    }

    public func setLearnedPreferencesGloballyEnabled(_ enabled: Bool) async {
        guard let state = learnedPreferences else { return }
        await perform {
            learnedPreferences = try await workflow.setLearnedPreferencesGloballyEnabled(
                enabled,
                sourceAction: "explicit-preference-global-toggle",
                expectedVersion: state.settingsVersion
            )
        }
    }

    public func resetLearnedPreferences(
        confirmedByVisibleDialog: Bool,
        using sceneState: MediaReviewSceneState
    ) async {
        guard confirmedByVisibleDialog, let state = learnedPreferences else {
            safeErrorMessage = "Reset All requires visible confirmation."
            return
        }
        await perform {
            learnedPreferences = try await workflow.resetLearnedPreferences(
                sourceAction: "explicit-preference-reset-all",
                expectedSettingsVersion: state.settingsVersion
            )
            clearLearnedPreferenceEditor(in: sceneState)
        }
    }

    public func restoreTrashItem(_ storageObjectID: StorageObjectID) async {
        await perform {
            storageReport = try await workflow.restoreTrashItem(
                storageObjectID: storageObjectID
            )
        }
    }

    public func permanentlyDeleteTrashItem(
        _ storageObjectID: StorageObjectID,
        confirmedByVisibleDialog: Bool
    ) async {
        guard confirmedByVisibleDialog else {
            safeErrorMessage = "Permanent deletion requires visible confirmation."
            return
        }
        await perform {
            storageReport = try await workflow.permanentlyDeleteTrashItem(
                storageObjectID: storageObjectID,
                confirmsPermanentDeletion: true,
                acknowledgesUnlinkIsNotSecureErasure: true
            )
        }
    }

    public func clearError() {
        safeErrorMessage = nil
    }

    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isWorking, !isStoppingRecording else {
            safeErrorMessage = "Wait for the current local operation to finish."
            return false
        }
        safeErrorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            return true
        } catch let error as LocalizedError {
            safeErrorMessage = error.errorDescription
                ?? "The local operation could not be completed."
            return false
        } catch {
            safeErrorMessage = "The local operation could not be completed."
            return false
        }
    }

    private func resetMediaState() {
        workflow.discardPendingMedia()
        pendingMedia = nil
        importedSource = nil
        job = nil
        transcriptJob = nil
        routeReview = nil
        transcriptReview = nil
        analysisJob = nil
        analysisRouteReview = nil
        analysisReview = nil
        briefingJob = nil
        briefingRouteReview = nil
        briefingReview = nil
        lastBriefingExport = nil
        historicalIndex = nil
        historicalIndexJob = nil
        historicalSearchPage = nil
        historicalComparison = nil
        learnedPreferences = nil
        storageReport = nil
        recordingSetup = nil
        recordingSession = nil
        isStoppingRecording = false
        webMetadataCandidate = nil
        safeErrorMessage = nil
    }

    private func resetAcceptedMediaReviewState(
        using sceneState: MediaReviewSceneState
    ) {
        pollingTask?.cancel()
        pollingTask = nil
        importedSource = nil
        job = nil
        transcriptJob = nil
        routeReview = nil
        transcriptReview = nil
        analysisJob = nil
        analysisRouteReview = nil
        analysisReview = nil
        briefingJob = nil
        briefingRouteReview = nil
        briefingReview = nil
        lastBriefingExport = nil
        sceneState.resetForAcceptedMedia()
    }

    private func advanceWorkspaceSession() {
        pollingTask?.cancel()
        pollingTask = nil
        recordingPollingTask?.cancel()
        recordingPollingTask = nil
        workspaceSession &+= 1
    }

    private func beginPolling(jobID: JobID) {
        pollingTask?.cancel()
        let session = workspaceSession
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    job = current
                    if current.state.isTerminal { return }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func beginRecordingPolling(jobID: JobID) {
        recordingPollingTask?.cancel()
        let session = workspaceSession
        recordingPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.recordingReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    recordingSession = current
                    if current.state.isTerminal { return }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Recording status is temporarily unavailable; sealed local audio remains retained."
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func beginTranscriptPolling(jobID: JobID) {
        pollingTask?.cancel()
        let session = workspaceSession
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    transcriptJob = current
                    if current.state.isTerminal {
                        if current.state == .succeeded, let canonicalJob = job {
                            let review = try await workflow.transcriptReview(
                                canonicalJobID: canonicalJob.jobID
                            )
                            guard !Task.isCancelled, session == workspaceSession else {
                                return
                            }
                            transcriptReview = review
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Transcript processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func beginAnalysisPolling(jobID: JobID) {
        pollingTask?.cancel()
        let session = workspaceSession
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    analysisJob = current
                    if current.state.isTerminal {
                        if current.state == .succeeded, let canonicalJob = job {
                            let review = try await workflow.analysisReview(
                                canonicalJobID: canonicalJob.jobID
                            )
                            guard !Task.isCancelled, session == workspaceSession else {
                                return
                            }
                            analysisReview = review
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Analysis processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func beginBriefingPolling(jobID: JobID) {
        pollingTask?.cancel()
        let session = workspaceSession
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    briefingJob = current
                    if current.state.isTerminal {
                        if current.state == .succeeded, let canonicalJob = job {
                            let review = try await workflow.briefingReview(
                                canonicalJobID: canonicalJob.jobID
                            )
                            guard !Task.isCancelled, session == workspaceSession else {
                                return
                            }
                            briefingReview = review
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Briefing processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func beginHistoricalIndexPolling(
        jobID: JobID,
        using sceneState: MediaReviewSceneState
    ) {
        pollingTask?.cancel()
        let session = workspaceSession
        pollingTask = Task { @MainActor [weak self, weak sceneState] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    historicalIndexJob = current
                    if current.state.isTerminal {
                        let index = try await workflow.historicalIndexStatus()
                        guard !Task.isCancelled, session == workspaceSession else {
                            return
                        }
                        historicalIndex = index
                        if current.state == .succeeded,
                           let sceneState
                        {
                            let page = try await workflow.searchMeetingHistory(
                                try historicalQuery(using: sceneState)
                            )
                            guard !Task.isCancelled,
                                  session == workspaceSession
                            else {
                                return
                            }
                            historicalSearchPage = page
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, session == workspaceSession else { return }
                    safeErrorMessage = "Meeting History index status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func historicalQuery(
        using sceneState: MediaReviewSceneState
    ) throws -> HistoricalSearchQuery {
        try HistoricalSearchQuery(
            actorOrCountry: optionalText(sceneState.historyActorOrCountry),
            topic: optionalText(sceneState.historyTopic),
            meetingBody: optionalText(sceneState.historyBody),
            meetingType: optionalText(sceneState.historyMeetingType),
            startDate: try optionalDate(sceneState.historyStartDate),
            endDate: try optionalDate(sceneState.historyEndDate),
            reviewStatus: .confirmed,
            maximumClassification: .restricted,
            pageSize: 100
        )
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalDate(_ value: String) throws -> CalendarDate? {
        guard let text = optionalText(value) else { return nil }
        let components = text.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = UInt16(components[0]),
              let month = UInt8(components[1]),
              let day = UInt8(components[2])
        else { throw HistoricalReviewError.invalidQuery("Dates must use YYYY-MM-DD.") }
        return try CalendarDate(year: year, month: month, day: day)
    }

    private func parsedPreferenceValue(
        using sceneState: MediaReviewSceneState
    ) throws -> LearnedPreferenceValue {
        let text = sceneState.learnedPreferenceValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let commaValues = text.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        switch sceneState.learnedPreferenceKind {
        case .actorCountryOrder:
            return .actorCountryOrder(commaValues)
        case .briefingLength:
            guard let value = UInt32(text) else {
                throw HistoricalReviewError.invalidPreference("A numeric word limit is required.")
            }
            return .briefingLength(value)
        case .sectionOrder:
            let sections = commaValues.map(BriefingSectionType.init(encodedValue:))
            guard sections.allSatisfy(\.isKnown) else {
                throw HistoricalReviewError.invalidPreference("A section type is unsupported.")
            }
            return .sectionOrder(sections)
        case .quotationPolicy:
            guard let value = LearnedQuotationPolicy(rawValue: text) else {
                throw HistoricalReviewError.invalidPreference("A quotation policy is unsupported.")
            }
            return .quotationPolicy(value)
        case .grouping:
            guard let value = LearnedGrouping(rawValue: text) else {
                throw HistoricalReviewError.invalidPreference("A grouping is unsupported.")
            }
            return .grouping(value)
        case .terminology:
            return .terminology(try commaValues.map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw HistoricalReviewError.invalidPreference("Terminology uses source=display.")
                }
                return try TerminologyPreference(sourceTerm: parts[0], displayTerm: parts[1])
            })
        case .frequentTemplates:
            return .frequentTemplates(try commaValues.map(BriefingTemplateID.init(validating:)))
        }
    }

    private func editablePreferenceValue(_ value: LearnedPreferenceValue) -> String {
        switch value {
        case let .actorCountryOrder(values): values.joined(separator: ", ")
        case let .briefingLength(value): String(value)
        case let .sectionOrder(values): values.map(\.encodedValue).joined(separator: ", ")
        case let .quotationPolicy(value): value.rawValue
        case let .grouping(value): value.rawValue
        case let .terminology(values): values.map { "\($0.sourceTerm)=\($0.displayTerm)" }.joined(separator: ", ")
        case let .frequentTemplates(values): values.map(\.canonicalString).joined(separator: ", ")
        }
    }

    private func clearLearnedPreferenceEditor(in sceneState: MediaReviewSceneState) {
        sceneState.editingLearnedPreferenceID = nil
        sceneState.editingLearnedPreferenceVersion = nil
        sceneState.learnedPreferenceValue = ""
    }

    private static func cleanClaims(_ values: [String]) -> [String] {
        let cleaned = values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty && $0.utf8.count <= 16_384 }
        guard Set(cleaned).count == cleaned.count else { return [] }
        return cleaned
    }

    private static func editorLines(_ value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func firstMetadataValue(
        _ field: UNWebTVMetadataField,
        in candidate: UNWebTVMetadataCandidate
    ) -> String {
        candidate.fields.first(where: { $0.field == field })?.value ?? ""
    }

    private func transcriptSubmission(
        using sceneState: MediaReviewSceneState
    ) -> TranscriptStartSubmission? {
        let source = sceneState.transcriptSourceLanguageTag.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let target = sceneState.transcriptTargetLanguageTag.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        do {
            let sourceLanguage = try LanguageTag(source)
            let targetLanguage = target.isEmpty ? nil : try LanguageTag(target)
            guard targetLanguage != sourceLanguage else {
                safeErrorMessage = "Source and target transcript languages must differ."
                return nil
            }
            return TranscriptStartSubmission(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        } catch {
            safeErrorMessage = "Use valid language tags such as en, fr, or zh-hans."
            return nil
        }
    }
}
