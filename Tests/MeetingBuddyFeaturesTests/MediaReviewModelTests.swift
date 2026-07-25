import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
import UniformTypeIdentifiers
@testable import MeetingBuddyFeatures

@Suite
struct MediaReviewModelTests {
    @Test
    func oneFileImporterRoutesWorkspaceAndMediaSelections() {
        #expect(LocalFileImporterPurpose.workspace.allowedContentTypes == [.folder])
        #expect(LocalFileImporterPurpose.media.allowedContentTypes == [.audio, .movie])
    }

    @Test
    func classificationAndSpeechChoicesExposeEveryTask005APolicyValue() {
        #expect(ClassificationChoice.all.map(\.value) == [
            .public, .internal, .sensitive, .restricted
        ])
        #expect(SpeechKindChoice.all.map(\.value) == [
            .originalSpeakerAudio,
            .simultaneousInterpretation,
            .translatedAudioTrack,
            .unknown
        ])
    }

    @Test
    func analysisBriefingAndHistoryAreIndependentNavigationSections() {
        #expect(
            Set<MediaReviewSection>([
                .intake, .transcript, .analysis, .briefing, .history, .storage
            ]).count == 6
        )
        #expect(MediaReviewSection.analysis != .transcript)
        #expect(MediaReviewSection.briefing != .analysis)
        #expect(MediaReviewSection.history != .briefing)
    }

    @Test @MainActor
    func storageActionsRequireVisibleDeletionConfirmationAndRefreshTheReport() async throws {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/selected-workspace"),
            using: sceneState
        )
        await store.loadStorageReport()
        let item = try #require(store.storageReport?.trashItems.first)

        await store.permanentlyDeleteTrashItem(
            item.storageObjectID,
            confirmedByVisibleDialog: false
        )
        #expect(store.safeErrorMessage == "Permanent deletion requires visible confirmation.")
        #expect(workflow.permanentDeletionCallCount == 0)

        await store.permanentlyDeleteTrashItem(
            item.storageObjectID,
            confirmedByVisibleDialog: true
        )
        #expect(workflow.permanentDeletionCallCount == 1)
        #expect(workflow.lastDeletionConfirmed == true)
        #expect(workflow.lastUnlinkAcknowledged == true)
        #expect(store.storageReport?.trashItems.isEmpty == true)
    }

    @Test @MainActor
    func multipleAudioTracksRequireAnExplicitSelection() async throws {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/selected-workspace"),
            using: sceneState
        )
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/selected-source.wav"),
            using: sceneState
        )
        sceneState.meetingTitle = "Review fixture"

        #expect(sceneState.selectedTrack == nil)
        await store.importAndProcess(using: sceneState)
        #expect(store.safeErrorMessage == "Select one audio track before processing this media.")
        #expect(workflow.importCallCount == 0)
    }

    @Test @MainActor
    func aSecondLongOperationCannotReplaceAnActiveWorkspaceRuntime() async throws {
        let gate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(openGate: gate)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        let opening = Task {
            await store.openOrCreateWorkspace(
                at: URL(fileURLWithPath: "/selected-workspace"),
                using: sceneState
            )
        }
        await gate.waitUntilEntered()

        await store.inspectMedia(
            at: URL(fileURLWithPath: "/selected-source.wav"),
            using: sceneState
        )
        #expect(store.safeErrorMessage == "Wait for the current local operation to finish.")
        #expect(workflow.inspectCallCount == 0)

        await gate.release()
        await opening.value
        #expect(store.workspace?.displayName == "Synthetic Workspace")
    }

    @Test @MainActor
    func workspaceRestoreIsIdempotentForSingletonWindowReentry() async throws {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        await store.restoreWorkspace(using: sceneState)
        await store.restoreWorkspace(using: sceneState)

        #expect(workflow.restoreCallCount == 1)
    }

    @Test @MainActor
    func cancelledWorkspaceRestoreCanRetryWithoutAllowingOverlap() async throws {
        let restoreGate = AsyncGate()
        let restoredWorkspace = WorkspaceReview(
            workspaceID: featureID(3_001, WorkspaceID.self),
            displayName: "Restored Workspace"
        )
        let workflow = try MediaReviewWorkflowProbe(
            restoreGate: restoreGate,
            restoredWorkspace: restoredWorkspace
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        let restoration = Task {
            await store.restoreWorkspace(using: sceneState)
        }
        await restoreGate.waitUntilEntered()

        await store.restoreWorkspace(using: sceneState)
        #expect(workflow.restoreCallCount == 1)

        restoration.cancel()
        await restoreGate.release()
        await restoration.value

        #expect(store.workspace == nil)

        await store.restoreWorkspace(using: sceneState)

        #expect(workflow.restoreCallCount == 2)
        #expect(store.workspace == restoredWorkspace)
    }

    @Test @MainActor
    func transientWorkspaceRestoreFailureCanRetry() async throws {
        let restoredWorkspace = WorkspaceReview(
            workspaceID: featureID(3_002, WorkspaceID.self),
            displayName: "Restored Workspace"
        )
        let workflow = try MediaReviewWorkflowProbe(
            restoredWorkspace: restoredWorkspace,
            restoreFailuresRemaining: 1
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        await store.restoreWorkspace(using: sceneState)
        #expect(workflow.restoreCallCount == 1)
        #expect(store.workspace == nil)

        await store.restoreWorkspace(using: sceneState)
        await store.restoreWorkspace(using: sceneState)

        #expect(workflow.restoreCallCount == 2)
        #expect(store.workspace == restoredWorkspace)
        #expect(store.safeErrorMessage == nil)
    }

    @Test @MainActor
    func workspaceSwitchClearsPendingPreImportSourceAndSceneAuthorization() async throws {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-a"),
            using: sceneState
        )
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source.wav"),
            using: sceneState
        )
        sceneState.meetingTitle = "Workspace A"
        sceneState.selectedTrack = try MediaTrackIdentifier(2)
        sceneState.recordingAcknowledged = true
        sceneState.unWebTVNetworkAuthorized = true

        #expect(store.pendingMedia != nil)
        #expect(sceneState.selectedTrack != nil)

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-b"),
            using: sceneState
        )

        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.pendingMedia == nil)
        #expect(store.importedSource == nil)
        #expect(store.job == nil)
        #expect(sceneState.selectedTrack == nil)
        #expect(sceneState.meetingTitle.isEmpty)
        #expect(!sceneState.recordingAcknowledged)
        #expect(!sceneState.unWebTVNetworkAuthorized)
    }

    @Test @MainActor
    func workspaceSwitchClearsNonemptyTranscriptAnalysisBriefingAndHistoryState() async throws {
        let workflow = try MediaReviewWorkflowProbe(seededReviewState: true)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-a"),
            using: sceneState
        )
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source.wav"),
            using: sceneState
        )
        sceneState.meetingTitle = "Synthetic review state"
        sceneState.selectedTrack = try MediaTrackIdentifier(1)
        await store.importAndProcess(using: sceneState)
        await store.loadTranscriptReview()
        await store.loadAnalysisReview()
        await store.loadBriefingReview()
        await store.loadHistoricalReview(using: sceneState)
        await store.loadStorageReport()
        sceneState.transcript.reconcile(with: store.transcriptReview)
        sceneState.analysis.reconcile(with: store.analysisReview)
        sceneState.briefing.reconcile(with: store.briefingReview)
        let analysisPosition = try #require(
            store.analysisReview?.positions.first
        )
        let briefingSection = try #require(
            store.briefingReview?.publication.sections.first
        )
        let briefingItem = try #require(briefingSection.items.first)
        sceneState.analysis.statement += " — unpublished A draft"
        sceneState.briefing.itemTexts[briefingItem.itemID]
            = "Workspace A unpublished briefing draft"

        #expect(
            store.transcriptReview?.transcriptSegments.first?.text
                == "Workspace A transcript fixture"
        )
        #expect(
            analysisPosition.statement.text
                == "Workspace A analysis fixture position"
        )
        #expect(
            briefingItem.claim.text
                == "Workspace A overview fixture"
        )
        #expect(
            sceneState.analysis.selectedPositionID
                == analysisPosition.positionID
        )
        #expect(
            sceneState.briefing.selectedSectionType
                == briefingSection.sectionType
        )
        #expect(sceneState.analysis.isDirty)
        #expect(sceneState.briefing.isDirty)
        #expect(store.historicalIndex != nil)
        #expect(store.learnedPreferences != nil)
        #expect(store.storageReport != nil)

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-b"),
            using: sceneState
        )

        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.transcriptReview == nil)
        #expect(store.analysisReview == nil)
        #expect(store.briefingReview == nil)
        #expect(store.historicalIndex == nil)
        #expect(store.learnedPreferences == nil)
        #expect(store.storageReport == nil)
        #expect(sceneState.transcript.selectedSegmentID == nil)
        #expect(sceneState.analysis.selectedPositionID == nil)
        #expect(sceneState.analysis.statement.isEmpty)
        #expect(sceneState.briefing.selectedSectionType == nil)
        #expect(sceneState.briefing.itemTexts.isEmpty)
        #expect(!sceneState.hasUnsavedEditorChanges)
    }

    @Test @MainActor
    func acceptingNewMediaPreservesPreflightThenClearsOnlyTheOldReviewChain() async throws {
        let workflow = try MediaReviewWorkflowProbe(seededReviewState: true)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadAnalysisReview()
        await store.loadBriefingReview()
        await store.loadHistoricalReview(using: sceneState)
        await store.loadStorageReport()
        sceneState.transcript.reconcile(with: store.transcriptReview)
        sceneState.analysis.reconcile(with: store.analysisReview)
        sceneState.briefing.reconcile(with: store.briefingReview)
        sceneState.selectedSection = .briefing
        sceneState.historyTopic = "preserved history filter"
        let workspaceID = try #require(store.workspace?.workspaceID)
        let priorJobID = try #require(store.job?.jobID)
        let priorTranscriptManifestID = try #require(
            store.transcriptReview?.manifest.manifestID
        )

        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source-b.wav"),
            using: sceneState
        )

        #expect(workflow.inspectCallCount == 2)
        #expect(store.pendingMedia != nil)
        #expect(store.job?.jobID == priorJobID)
        #expect(
            store.transcriptReview?.manifest.manifestID
                == priorTranscriptManifestID
        )
        #expect(store.analysisReview != nil)
        #expect(store.briefingReview != nil)
        #expect(sceneState.selectedSection == .briefing)

        sceneState.meetingTitle = "Synthetic review state B"
        let acceptedTrack = try MediaTrackIdentifier(1)
        sceneState.selectedTrack = acceptedTrack
        #expect(sceneState.requestMediaImport() == .importPendingMedia)
        await store.importAndProcess(using: sceneState)

        #expect(workflow.importCallCount == 2)
        #expect(store.workspace?.workspaceID == workspaceID)
        #expect(store.pendingMedia == nil)
        #expect(store.importedSource != nil)
        #expect(store.job != nil)
        #expect(store.transcriptJob == nil)
        #expect(store.routeReview == nil)
        #expect(store.transcriptReview == nil)
        #expect(store.analysisJob == nil)
        #expect(store.analysisRouteReview == nil)
        #expect(store.analysisReview == nil)
        #expect(store.briefingJob == nil)
        #expect(store.briefingRouteReview == nil)
        #expect(store.briefingReview == nil)
        #expect(store.lastBriefingExport == nil)
        #expect(store.historicalIndex != nil)
        #expect(store.learnedPreferences != nil)
        #expect(store.storageReport != nil)
        #expect(sceneState.selectedSection == .intake)
        #expect(sceneState.transcript.selectedSegmentID == nil)
        #expect(sceneState.analysis.selectedPositionID == nil)
        #expect(sceneState.briefing.selectedSectionType == nil)
        #expect(!sceneState.hasUnsavedEditorChanges)
        #expect(sceneState.meetingTitle == "Synthetic review state B")
        #expect(sceneState.selectedTrack == acceptedTrack)
        #expect(sceneState.historyTopic == "preserved history filter")
    }

    @Test @MainActor
    func directMediaReplacementFailsBeforeImportWhenAnEditorDraftIsDirty() async throws {
        let workflow = try MediaReviewWorkflowProbe(seededReviewState: true)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let priorJobID = try #require(store.job?.jobID)
        sceneState.transcript.transcriptText = "unpublished correction"
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source-b.wav"),
            using: sceneState
        )
        sceneState.selectedTrack = try MediaTrackIdentifier(1)

        await store.importAndProcess(using: sceneState)

        #expect(workflow.importCallCount == 1)
        #expect(store.job?.jobID == priorJobID)
        #expect(store.transcriptReview != nil)
        #expect(store.pendingMedia != nil)
        #expect(sceneState.transcript.transcriptIsDirty)
        #expect(
            store.safeErrorMessage
                == "Save or discard every unpublished editor draft before replacing the current media workflow."
        )
    }

    @Test @MainActor
    func nonterminalMediaWorkBlocksReplacementBeforeASecondImport() async throws {
        let pollGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(pollGate: pollGate)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-a"),
            using: sceneState
        )
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source-a.wav"),
            using: sceneState
        )
        sceneState.meetingTitle = "Synthetic running workflow"
        sceneState.selectedTrack = try MediaTrackIdentifier(1)
        await store.importAndProcess(using: sceneState)
        await pollGate.waitUntilEntered()

        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source-b.wav"),
            using: sceneState
        )
        sceneState.selectedTrack = try MediaTrackIdentifier(1)
        await store.importAndProcess(using: sceneState)

        #expect(store.blocksMediaReplacement)
        #expect(workflow.importCallCount == 1)
        #expect(store.pendingMedia != nil)
        #expect(
            store.safeErrorMessage
                == "Wait for the current media workflow to finish before replacing its source."
        )

        await pollGate.release()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-b"),
            using: sceneState
        )
    }

    @Test @MainActor
    func lateWorkspaceAPollCannotWriteIntoWorkspaceBAfterReset() async throws {
        let pollGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(pollGate: pollGate)
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-a"),
            using: sceneState
        )
        await store.inspectMedia(
            at: URL(fileURLWithPath: "/synthetic-source.wav"),
            using: sceneState
        )
        sceneState.meetingTitle = "Workspace A"
        sceneState.selectedTrack = try MediaTrackIdentifier(1)
        sceneState.manualTranscriptText = "Workspace A private draft"
        sceneState.unWebTVNetworkAuthorized = true
        sceneState.selectedSection = .transcript

        #expect(store.pendingMedia != nil)
        await store.importAndProcess(using: sceneState)
        await pollGate.waitUntilEntered()
        #expect(store.job != nil)
        #expect(store.importedSource != nil)
        #expect(store.pendingMedia == nil)

        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-b"),
            using: sceneState
        )
        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.job == nil)
        #expect(store.pendingMedia == nil)
        #expect(store.importedSource == nil)
        #expect(store.transcriptJob == nil)
        #expect(store.routeReview == nil)
        #expect(store.transcriptReview == nil)
        #expect(store.analysisJob == nil)
        #expect(store.analysisRouteReview == nil)
        #expect(store.analysisReview == nil)
        #expect(store.briefingJob == nil)
        #expect(store.briefingRouteReview == nil)
        #expect(store.briefingReview == nil)
        #expect(store.historicalIndex == nil)
        #expect(store.historicalIndexJob == nil)
        #expect(store.historicalSearchPage == nil)
        #expect(store.historicalComparison == nil)
        #expect(sceneState.selectedSection == .intake)
        #expect(sceneState.meetingTitle.isEmpty)
        #expect(sceneState.manualTranscriptText.isEmpty)
        #expect(!sceneState.unWebTVNetworkAuthorized)

        await pollGate.release()
        for _ in 0..<10 { await Task.yield() }

        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.job == nil)
        #expect(store.safeErrorMessage != "Processing status is temporarily unavailable.")
    }

    @Test @MainActor
    func historyRebuildRestoresTheAcceptedAutomaticSearchRefresh() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-workspace-a"),
            using: sceneState
        )
        sceneState.historyActorOrCountry = "Synthetic actor"

        await store.rebuildHistoricalIndex(using: sceneState)
        for _ in 0..<20 { await Task.yield() }

        #expect(workflow.historicalRebuildCallCount == 1)
        #expect(workflow.historicalSearchCallCount == 1)
        #expect(workflow.lastHistoricalSearchQuery?.actorOrCountry == "Synthetic actor")
        #expect(store.historicalIndexJob?.state == .succeeded)
        #expect(store.historicalIndex != nil)
        #expect(store.historicalSearchPage?.indexGeneration == 7)
    }

    @Test @MainActor
    func simultaneousTranscriptDraftsPersistThroughTheStoreInExplicitOrder() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let initialTranscriptRevisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        let initialTranslationRevisionID = try #require(
            sceneState.transcript.translationRevisionID
        )
        sceneState.transcript.transcriptText = "Transcript saved last"
        sceneState.transcript.translationText = "Translation saved first"
        sceneState.transcript.speakerName = "Synthetic Speaker"

        let translationOperation = try #require(
            sceneState.beginDirectTranslationSave()
        )
        let translationSucceeded = await store.saveEditorDraft(
            translationOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                translationOperation,
                succeeded: translationSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.transcript.translationIsDirty)
        #expect(sceneState.transcript.transcriptIsDirty)
        #expect(sceneState.transcript.speakerIsDirty)
        #expect(
            sceneState.transcript.translationRevisionID
                != initialTranslationRevisionID
        )

        let speakerOperation = try #require(
            sceneState.beginDirectSpeakerSave()
        )
        let speakerSucceeded = await store.saveEditorDraft(
            speakerOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                speakerOperation,
                succeeded: speakerSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.transcript.speakerIsDirty)
        #expect(sceneState.transcript.transcriptIsDirty)

        let transcriptOperation = try #require(
            sceneState.beginDirectTranscriptSave()
        )
        let transcriptSucceeded = await store.saveEditorDraft(
            transcriptOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                transcriptOperation,
                succeeded: transcriptSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.transcript.isDirty)
        #expect(
            sceneState.transcript.transcriptRevisionID
                != initialTranscriptRevisionID
        )
        #expect(workflow.editorSaveCalls == [
            .translation(
                initialTranslationRevisionID,
                "Translation saved first"
            ),
            .speaker(initialTranscriptRevisionID, "Synthetic Speaker"),
            .transcript(initialTranscriptRevisionID, "Transcript saved last")
        ])
    }

    @Test @MainActor
    func transcriptFirstRefreshesItsRevisionAndPreservesAStaleTranslationDraft() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let initialTranscriptRevisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        let initialTranslationRevisionID = try #require(
            sceneState.transcript.translationRevisionID
        )
        sceneState.transcript.transcriptText = "First transcript correction"
        sceneState.transcript.translationText = "Retained translation draft"
        sceneState.transcript.speakerName = "Retained speaker draft"

        let firstTranscriptOperation = try #require(
            sceneState.beginDirectTranscriptSave()
        )
        let firstTranscriptSucceeded = await store.saveEditorDraft(
            firstTranscriptOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                firstTranscriptOperation,
                succeeded: firstTranscriptSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        let refreshedTranscriptRevisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        #expect(refreshedTranscriptRevisionID != initialTranscriptRevisionID)
        #expect(sceneState.transcript.translationIsDirty)
        #expect(
            sceneState.transcript.translationText
                == "Retained translation draft"
        )
        #expect(sceneState.transcript.speakerName == "Retained speaker draft")

        let staleTranslationOperation = try #require(
            sceneState.beginDirectTranslationSave()
        )
        let staleTranslationSucceeded = await store.saveEditorDraft(
            staleTranslationOperation.request
        )
        #expect(!staleTranslationSucceeded)
        #expect(
            !sceneState.completeDirectEditorSave(
                staleTranslationOperation,
                succeeded: staleTranslationSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(sceneState.transcript.translationIsDirty)
        #expect(
            sceneState.transcript.translationText
                == "Retained translation draft"
        )

        let speakerOperation = try #require(
            sceneState.beginDirectSpeakerSave()
        )
        guard case let .speaker(speakerRevisionID, _) =
            speakerOperation.request
        else {
            Issue.record("Expected a Speaker save operation.")
            return
        }
        #expect(speakerRevisionID == refreshedTranscriptRevisionID)
        let speakerSucceeded = await store.saveEditorDraft(
            speakerOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                speakerOperation,
                succeeded: speakerSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )

        sceneState.transcript.transcriptText = "Second transcript correction"
        let secondTranscriptOperation = try #require(
            sceneState.beginDirectTranscriptSave()
        )
        guard case let .transcript(secondRevisionID, _) =
            secondTranscriptOperation.request
        else {
            Issue.record("Expected a second Transcript save operation.")
            return
        }
        #expect(secondRevisionID == refreshedTranscriptRevisionID)
        let secondTranscriptSucceeded = await store.saveEditorDraft(
            secondTranscriptOperation.request
        )
        #expect(
            sceneState.completeDirectEditorSave(
                secondTranscriptOperation,
                succeeded: secondTranscriptSucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(sceneState.transcript.translationIsDirty)
        #expect(workflow.editorSaveCalls == [
            .transcript(
                initialTranscriptRevisionID,
                "First transcript correction"
            ),
            .translation(
                initialTranslationRevisionID,
                "Retained translation draft"
            ),
            .speaker(
                refreshedTranscriptRevisionID,
                "Retained speaker draft"
            ),
            .transcript(
                refreshedTranscriptRevisionID,
                "Second transcript correction"
            )
        ])
    }

    @Test @MainActor
    func transcriptWorkspaceNavigationWaitsForTheStoreBackedSave() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let revisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        let workspaceB = URL(
            fileURLWithPath: "/synthetic-workspace-b"
        )
        sceneState.transcript.transcriptText =
            "Persist Transcript A before B"

        #expect(sceneState.requestWorkspaceChange(to: workspaceB) == nil)
        let saveOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let resolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                saveOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        #expect(workflow.openCallCount == 1)
        #expect(store.workspace?.displayName == "Synthetic Workspace")
        #expect(sceneState.isEditorSaveInFlight)
        await saveGate.release()
        let effect = await resolution.value
        #expect(effect == .openWorkspace(workspaceB))
        #expect(workflow.editorSaveCalls == [
            .transcript(
                revisionID,
                "Persist Transcript A before B"
            )
        ])

        let workspaceOperation = try #require(
            sceneState.beginWorkspaceChange(to: workspaceB)
        )
        await sceneState.resolveWorkspaceChange(workspaceOperation) { url in
            await store.openOrCreateWorkspace(
                at: url,
                using: sceneState
            )
        }
        #expect(workflow.openCallCount == 2)
        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.transcriptReview == nil)
        #expect(sceneState.transcript.selectedSegmentID == nil)
        #expect(sceneState.transcript.transcriptText.isEmpty)
    }

    @Test @MainActor
    func analysisWorkspaceNavigationWaitsForTheStoreBackedSave() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadAnalysisReview()
        sceneState.analysis.reconcile(with: store.analysisReview)
        let position = try #require(store.analysisReview?.positions.first)
        let workspaceB = URL(
            fileURLWithPath: "/synthetic-workspace-b"
        )
        sceneState.analysis.statement = "Persist Analysis A before B"

        #expect(sceneState.requestWorkspaceChange(to: workspaceB) == nil)
        let saveOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let resolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                saveOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        #expect(workflow.openCallCount == 1)
        #expect(store.workspace?.displayName == "Synthetic Workspace")
        #expect(sceneState.isEditorSaveInFlight)
        await saveGate.release()
        let effect = await resolution.value
        #expect(effect == .openWorkspace(workspaceB))
        #expect(workflow.editorSaveCalls == [
            .position(
                position.revision.revisionID,
                position.positionType,
                "Persist Analysis A before B",
                [],
                []
            )
        ])

        let workspaceOperation = try #require(
            sceneState.beginWorkspaceChange(to: workspaceB)
        )
        await sceneState.resolveWorkspaceChange(workspaceOperation) { url in
            await store.openOrCreateWorkspace(
                at: url,
                using: sceneState
            )
        }
        #expect(workflow.openCallCount == 2)
        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.analysisReview == nil)
        #expect(sceneState.analysis.selectedPositionID == nil)
        #expect(sceneState.analysis.statement.isEmpty)
    }

    @Test @MainActor
    func briefingWorkspaceNavigationWaitsForTheStoreBackedSave() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadBriefingReview()
        sceneState.briefing.reconcile(with: store.briefingReview)
        let section = try #require(
            store.briefingReview?.publication.sections.first
        )
        let item = try #require(section.items.first)
        let workspaceB = URL(
            fileURLWithPath: "/synthetic-workspace-b"
        )
        sceneState.briefing.itemTexts[item.itemID]
            = "Persist Briefing A before B"

        #expect(sceneState.requestWorkspaceChange(to: workspaceB) == nil)
        let saveOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let resolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                saveOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        #expect(workflow.openCallCount == 1)
        #expect(store.workspace?.displayName == "Synthetic Workspace")
        #expect(sceneState.isEditorSaveInFlight)
        await saveGate.release()
        let effect = await resolution.value
        #expect(effect == .openWorkspace(workspaceB))
        #expect(workflow.editorSaveCalls == [
            .briefing(
                section.sectionType,
                section.revision.revisionID,
                [item.itemID: "Persist Briefing A before B"],
                false
            )
        ])

        let workspaceOperation = try #require(
            sceneState.beginWorkspaceChange(to: workspaceB)
        )
        await sceneState.resolveWorkspaceChange(workspaceOperation) { url in
            await store.openOrCreateWorkspace(
                at: url,
                using: sceneState
            )
        }
        #expect(workflow.openCallCount == 2)
        #expect(store.workspace?.displayName == "Synthetic Workspace B")
        #expect(store.briefingReview == nil)
        #expect(sceneState.briefing.selectedSectionType == nil)
        #expect(sceneState.briefing.itemTexts.isEmpty)
    }

    @Test @MainActor
    func transcriptSaveRebasesANewerDraftForStoreBackedRetry() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let initialRevisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        sceneState.transcript.transcriptText = "Submitted transcript value"
        #expect(
            sceneState.requestWorkspaceChange(
                to: URL(fileURLWithPath: "/synthetic-workspace-b")
            ) == nil
        )
        let firstOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let firstResolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                firstOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        sceneState.transcript.transcriptText = "Newer transcript value"
        await saveGate.release()

        #expect(await firstResolution.value == nil)
        let refreshedRevisionID = try #require(
            sceneState.transcript.transcriptRevisionID
        )
        #expect(refreshedRevisionID != initialRevisionID)
        #expect(sceneState.transcript.transcriptIsDirty)
        #expect(
            sceneState.transcript.transcriptText == "Newer transcript value"
        )
        #expect(sceneState.isNavigationConfirmationPresented)

        sceneState.cancelPendingNavigation()
        let retry = try #require(sceneState.beginDirectTranscriptSave())
        guard case let .transcript(retryRevisionID, retryText) =
            retry.request
        else {
            Issue.record("Expected a Transcript retry.")
            return
        }
        #expect(retryRevisionID == refreshedRevisionID)
        #expect(retryText == "Newer transcript value")
        let retrySucceeded = await store.saveEditorDraft(retry.request)
        #expect(
            sceneState.completeDirectEditorSave(
                retry,
                succeeded: retrySucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.transcript.transcriptIsDirty)
    }

    @Test @MainActor
    func analysisSaveRebasesANewerDraftForStoreBackedRetry() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadAnalysisReview()
        sceneState.analysis.reconcile(with: store.analysisReview)
        let initialRevisionID = try #require(
            sceneState.analysis.positionRevisionID
        )
        sceneState.analysis.statement = "Submitted analysis value"
        #expect(
            sceneState.requestWorkspaceChange(
                to: URL(fileURLWithPath: "/synthetic-workspace-b")
            ) == nil
        )
        let firstOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let firstResolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                firstOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        sceneState.analysis.statement = "Newer analysis value"
        await saveGate.release()

        #expect(await firstResolution.value == nil)
        let refreshedRevisionID = try #require(
            sceneState.analysis.positionRevisionID
        )
        #expect(refreshedRevisionID != initialRevisionID)
        #expect(sceneState.analysis.isDirty)
        #expect(sceneState.analysis.statement == "Newer analysis value")
        #expect(sceneState.isNavigationConfirmationPresented)

        sceneState.cancelPendingNavigation()
        let retry = try #require(sceneState.beginDirectAnalysisSave())
        guard case let .position(
            retryRevisionID,
            _,
            retryStatement,
            _,
            _
        ) = retry.request
        else {
            Issue.record("Expected an Analysis retry.")
            return
        }
        #expect(retryRevisionID == refreshedRevisionID)
        #expect(retryStatement == "Newer analysis value")
        let retrySucceeded = await store.saveEditorDraft(retry.request)
        #expect(
            sceneState.completeDirectEditorSave(
                retry,
                succeeded: retrySucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.analysis.isDirty)
    }

    @Test @MainActor
    func briefingSaveRebasesANewerDraftForStoreBackedRetry() async throws {
        let saveGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            editorSaveGate: saveGate,
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadBriefingReview()
        sceneState.briefing.reconcile(with: store.briefingReview)
        let section = try #require(
            store.briefingReview?.publication.sections.first
        )
        let item = try #require(section.items.first)
        let initialRevisionID = section.revision.revisionID
        sceneState.briefing.itemTexts[item.itemID] =
            "Submitted briefing value"
        #expect(
            sceneState.requestWorkspaceChange(
                to: URL(fileURLWithPath: "/synthetic-workspace-b")
            ) == nil
        )
        let firstOperation = try #require(
            sceneState.beginPendingNavigationSave()
        )
        let firstResolution = Task { @MainActor in
            await sceneState.resolvePendingNavigationSave(
                firstOperation,
                updatedReviews: { store.editorReviewSnapshot }
            ) { request in
                await store.saveEditorDraft(request)
            }
        }

        await saveGate.waitUntilEntered()
        sceneState.briefing.itemTexts[item.itemID] =
            "Newer briefing value"
        await saveGate.release()

        #expect(await firstResolution.value == nil)
        let refreshedRevisionID = try #require(
            sceneState.briefing.sectionRevisionID
        )
        #expect(refreshedRevisionID != initialRevisionID)
        #expect(sceneState.briefing.isSourceRevisionCurrent)
        #expect(sceneState.briefing.isDirty)
        #expect(
            sceneState.briefing.itemTexts[item.itemID]
                == "Newer briefing value"
        )
        #expect(sceneState.isNavigationConfirmationPresented)

        sceneState.cancelPendingNavigation()
        let retry = try #require(sceneState.beginDirectBriefingSave())
        guard case let .briefing(
            retrySectionType,
            retryRevisionID,
            retryTexts,
            _
        ) = retry.request
        else {
            Issue.record("Expected a Briefing retry.")
            return
        }
        #expect(retrySectionType == section.sectionType)
        #expect(retryRevisionID == refreshedRevisionID)
        #expect(retryTexts[item.itemID] == "Newer briefing value")
        let retrySucceeded = await store.saveEditorDraft(retry.request)
        #expect(
            sceneState.completeDirectEditorSave(
                retry,
                succeeded: retrySucceeded,
                updatedReviews: store.editorReviewSnapshot
            )
        )
        #expect(!sceneState.briefing.isDirty)
    }

    @Test @MainActor
    func applicationTerminationFailsClosedBeforePersistingMultipleEditorDrafts() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadAnalysisReview()
        await store.loadBriefingReview()
        sceneState.transcript.reconcile(with: store.transcriptReview)
        sceneState.analysis.reconcile(with: store.analysisReview)
        sceneState.briefing.reconcile(with: store.briefingReview)

        let section = try #require(
            store.briefingReview?.publication.sections.first
        )
        let item = try #require(section.items.first)

        sceneState.transcript.translationText = " Saved translation "
        sceneState.transcript.speakerName = " Saved speaker "
        sceneState.transcript.transcriptText = " Saved transcript "
        sceneState.analysis.statement = "Saved analysis"
        sceneState.briefing.itemTexts[item.itemID] = "Saved briefing"

        let didSave = await store.saveAllEditorDrafts(in: sceneState)
        #expect(!didSave)

        #expect(workflow.editorSaveCalls.isEmpty)
        #expect(sceneState.hasUnsavedEditorChanges)
        #expect(sceneState.transcript.translationText == " Saved translation ")
        #expect(sceneState.transcript.speakerName == " Saved speaker ")
        #expect(sceneState.transcript.transcriptText == " Saved transcript ")
        #expect(sceneState.analysis.statement == "Saved analysis")
        #expect(
            sceneState.briefing.itemTexts[item.itemID]
                == "Saved briefing"
        )
        #expect(
            store.safeErrorMessage
                == "Save each unpublished editor draft separately before quitting. BlueMinutes will not partially save drafts whose revisions depend on one another."
        )
    }

    @Test @MainActor
    func applicationTerminationSavesOneRevisionBoundDraft() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        sceneState.transcript.reconcile(with: store.transcriptReview)
        let translationRevisionID = try #require(
            sceneState.transcript.translationRevisionID
        )
        sceneState.transcript.translationText = " Saved translation "

        #expect(await store.saveAllEditorDrafts(in: sceneState))

        #expect(!sceneState.hasUnsavedEditorChanges)
        #expect(sceneState.transcript.translationText == "Saved translation")
        #expect(workflow.editorSaveCalls == [
            .translation(translationRevisionID, "Saved translation")
        ])
    }

    @Test @MainActor
    func staleBriefingDraftFailsBeforeTheApplicationAction() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        try await loadSeededReviewState(
            store: store,
            sceneState: sceneState
        )
        await store.loadBriefingReview()
        let section = try #require(
            store.briefingReview?.publication.sections.first
        )
        let item = try #require(section.items.first)
        let staleRevisionID = featureID(2_500, RevisionID.self)
        sceneState.briefing.hydrateSelection(
            sectionType: section.sectionType,
            revisionID: staleRevisionID,
            itemTexts: [item.itemID: item.claim.text],
            isLocked: false
        )
        sceneState.briefing.itemTexts[item.itemID] = "Stale draft"

        sceneState.briefing.reconcile(with: store.briefingReview)

        #expect(!sceneState.briefing.isSourceRevisionCurrent)
        #expect(sceneState.beginDirectBriefingSave()?.id == nil)
        let succeeded = await store.saveEditorDraft(
            .briefing(
                sectionType: section.sectionType,
                expectedRevisionID: staleRevisionID,
                editedTextByItemID: [item.itemID: "Stale draft"],
                locked: false
            )
        )
        #expect(!succeeded)
        #expect(workflow.editorSaveCalls.isEmpty)
        #expect(
            store.safeErrorMessage
                == "The Briefing section changed after this draft was opened. Keep the draft, review the new revision, and apply the edit again."
        )
    }
}

@MainActor
private func loadSeededReviewState(
    store: MediaReviewStore,
    sceneState: MediaReviewSceneState
) async throws {
    await store.openOrCreateWorkspace(
        at: URL(fileURLWithPath: "/synthetic-workspace-a"),
        using: sceneState
    )
    await store.inspectMedia(
        at: URL(fileURLWithPath: "/synthetic-source.wav"),
        using: sceneState
    )
    sceneState.meetingTitle = "Synthetic review state"
    sceneState.selectedTrack = try MediaTrackIdentifier(1)
    await store.importAndProcess(using: sceneState)
    await store.loadTranscriptReview()
}

@MainActor
private final class MediaReviewWorkflowProbe: MediaReviewWorkflow {
    private let inspection: MediaInspection
    private let restoreGate: AsyncGate?
    private let restoredWorkspace: WorkspaceReview?
    private let openGate: AsyncGate?
    private let pollGate: AsyncGate?
    private let editorSaveGate: AsyncGate?
    private let pollingJob: MediaJobReview?
    private var restoreFailuresRemaining: Int
    private var currentTranscriptReview: TranscriptReviewBundle?
    private var currentAnalysisReview: AnalysisReviewBundle?
    private var currentBriefingReview: BriefingReviewBundle?
    private(set) var openCallCount = 0
    private(set) var inspectCallCount = 0
    private(set) var importCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var historicalRebuildCallCount = 0
    private(set) var historicalSearchCallCount = 0
    private(set) var lastHistoricalSearchQuery: HistoricalSearchQuery?
    private(set) var editorSaveCalls: [FeatureEditorSaveCall] = []
    private(set) var permanentDeletionCallCount = 0
    private(set) var lastDeletionConfirmed = false
    private(set) var lastUnlinkAcknowledged = false

    init(
        restoreGate: AsyncGate? = nil,
        restoredWorkspace: WorkspaceReview? = nil,
        restoreFailuresRemaining: Int = 0,
        openGate: AsyncGate? = nil,
        pollGate: AsyncGate? = nil,
        editorSaveGate: AsyncGate? = nil,
        seededReviewState: Bool = false
    ) throws {
        self.restoreGate = restoreGate
        self.restoredWorkspace = restoredWorkspace
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.openGate = openGate
        self.pollGate = pollGate
        self.editorSaveGate = editorSaveGate
        pollingJob = try pollGate == nil && !seededReviewState
            ? nil
            : makeFeatureJobReview(succeeded: seededReviewState)
        currentTranscriptReview = try seededReviewState
            ? makeFeatureTranscriptReview()
            : nil
        currentAnalysisReview = try seededReviewState
            ? makeFeatureAnalysisReview()
            : nil
        currentBriefingReview = try seededReviewState
            ? makeFeatureBriefingReview()
            : nil
        inspection = try MediaInspection(
            format: .wav,
            durationFrameCount: 32_000,
            audioTracks: [
                AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(1),
                    durationFrameCount: 32_000,
                    sourceSampleRateHertz: 48_000,
                    sourceChannelCount: 1,
                    codec: "lpcm"
                ),
                AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(2),
                    durationFrameCount: 32_000,
                    sourceSampleRateHertz: 48_000,
                    sourceChannelCount: 1,
                    codec: "lpcm"
                )
            ]
        )
    }

    func restoreWorkspace() async throws -> WorkspaceReview? {
        restoreCallCount += 1
        if let restoreGate { await restoreGate.block() }
        if restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw ProbeError.transientRestore
        }
        return restoredWorkspace
    }

    func openOrCreateWorkspace(at _: URL) async throws -> WorkspaceReview {
        if let openGate { await openGate.block() }
        openCallCount += 1
        return WorkspaceReview(
            workspaceID: WorkspaceID(
                UUID(
                    uuidString: String(
                        format: "51000000-0000-0000-0000-%012d",
                        openCallCount
                    )
                )!
            ),
            displayName: openCallCount == 1
                ? "Synthetic Workspace" : "Synthetic Workspace B"
        )
    }

    func inspectSelectedMedia(at _: URL) async throws -> PendingMediaReview {
        inspectCallCount += 1
        return PendingMediaReview(displayName: "selected-source.wav", inspection: inspection)
    }

    func discardPendingMedia() {}

    func importAndProcess(_: MediaImportSubmission) async throws
        -> (ImportedSourceReview, MediaJobReview)
    {
        importCallCount += 1
        guard let pollingJob else { throw ProbeError.unexpectedCall }
        return (
            ImportedSourceReview(
                assetID: featureID(30, SourceAssetID.self),
                revisionID: featureID(31, RevisionID.self),
                sourceHash: try ContentDigest.sha256(ofUTF8Text: "synthetic-source"),
                byteSize: 128,
                format: .wav,
                durationFrameCount: 32_000,
                selectedTrack: try MediaTrackIdentifier(1),
                speechSourceKind: .originalSpeakerAudio
            ),
            pollingJob
        )
    }

    func jobReview(jobID _: JobID) async throws -> MediaJobReview {
        guard let pollingJob else { throw ProbeError.unexpectedCall }
        if let pollGate { await pollGate.block() }
        return pollingJob
    }

    func transcriptReview(
        canonicalJobID _: JobID
    ) async throws -> TranscriptReviewBundle? {
        guard let currentTranscriptReview else {
            throw ProbeError.unexpectedCall
        }
        return currentTranscriptReview
    }

    func correctTranscript(
        canonicalJobID _: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        editorSaveCalls.append(.transcript(revisionID, text))
        if let editorSaveGate { await editorSaveGate.block() }
        guard let currentTranscriptReview,
              let segment = currentTranscriptReview.transcriptSegments.first,
              segment.revision.revisionID == revisionID
        else {
            throw ProbeError.staleRevision
        }
        let updated = try makeFeatureTranscriptReview(
            transcriptRevisionID: featureID(
                600 + editorSaveCalls.count,
                RevisionID.self
            ),
            translationRevisionID: nil,
            transcriptText: text,
            translationText: nil
        )
        self.currentTranscriptReview = updated
        return updated
    }

    func correctTranslation(
        canonicalJobID _: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        editorSaveCalls.append(.translation(revisionID, text))
        guard let currentTranscriptReview,
              let segment = currentTranscriptReview.transcriptSegments.first,
              currentTranscriptReview.translations.first?.revision.revisionID
                  == revisionID
        else {
            throw ProbeError.staleRevision
        }
        let updated = try makeFeatureTranscriptReview(
            transcriptRevisionID: segment.revision.revisionID,
            translationRevisionID: featureID(
                700 + editorSaveCalls.count,
                RevisionID.self
            ),
            transcriptText: segment.text,
            translationText: text
        )
        self.currentTranscriptReview = updated
        return updated
    }

    func confirmSpeaker(
        canonicalJobID _: JobID,
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async throws -> TranscriptReviewBundle {
        editorSaveCalls.append(.speaker(transcriptRevisionID, displayName))
        guard let currentTranscriptReview,
              currentTranscriptReview.transcriptSegments.first?
                  .revision.revisionID == transcriptRevisionID
        else {
            throw ProbeError.staleRevision
        }
        return currentTranscriptReview
    }

    func analysisReview(
        canonicalJobID _: JobID
    ) async throws -> AnalysisReviewBundle? {
        guard let currentAnalysisReview else {
            throw ProbeError.unexpectedCall
        }
        return currentAnalysisReview
    }

    func correctPosition(
        canonicalJobID _: JobID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async throws -> AnalysisReviewBundle {
        editorSaveCalls.append(
            .position(
                revisionID,
                positionType,
                statement,
                reservations,
                conditions
            )
        )
        if let editorSaveGate { await editorSaveGate.block() }
        guard let currentAnalysisReview,
              currentAnalysisReview.positions.first?.revision.revisionID
                  == revisionID
        else {
            throw ProbeError.staleRevision
        }
        let updated = try makeFeatureAnalysisReview(
            positionRevisionID: featureID(
                1_600 + editorSaveCalls.count,
                RevisionID.self
            ),
            statementText: statement
        )
        self.currentAnalysisReview = updated
        return updated
    }

    func briefingReview(
        canonicalJobID _: JobID
    ) async throws -> BriefingReviewBundle? {
        guard let currentBriefingReview else {
            throw ProbeError.unexpectedCall
        }
        return currentBriefingReview
    }

    func updateBriefingSection(
        canonicalJobID _: JobID,
        sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle {
        editorSaveCalls.append(
            .briefing(
                sectionType,
                expectedRevisionID,
                editedTextByItemID,
                locked
            )
        )
        if let editorSaveGate { await editorSaveGate.block() }
        guard let currentBriefingReview,
              let currentSection =
                  currentBriefingReview.publication.sections.first(where: {
                      $0.sectionType == sectionType
                  }),
              currentSection.revision.revisionID == expectedRevisionID,
              let updatedText = editedTextByItemID[
                  currentSection.items[0].itemID
              ]
        else {
            throw ProbeError.staleRevision
        }
        let updated = try makeFeatureBriefingReview(
            overviewRevisionID: featureID(
                1_700 + editorSaveCalls.count,
                RevisionID.self
            ),
            overviewText: updatedText
        )
        self.currentBriefingReview = updated
        return updated
    }

    func historicalIndexStatus() async throws -> HistoricalIndexStatus {
        HistoricalIndexStatus(
            availability: .rebuildRequired,
            generation: 7,
            normalizerVersion: 1,
            indexedPositionCount: 3,
            rebuiltAt: nil,
            sourceFingerprint: nil
        )
    }

    func learnedPreferenceState() async throws -> LearnedPreferenceState {
        LearnedPreferenceState(
            globallyEnabled: false,
            settingsVersion: 2,
            preferences: [],
            recentEvents: []
        )
    }

    func rebuildHistoricalIndex() async throws -> MediaJobReview {
        historicalRebuildCallCount += 1
        return try makeFeatureJobReview(succeeded: true)
    }

    func searchMeetingHistory(
        _ query: HistoricalSearchQuery
    ) async throws -> HistoricalSearchPage {
        historicalSearchCallCount += 1
        lastHistoricalSearchQuery = query
        return HistoricalSearchPage(
            results: [],
            nextCursor: nil,
            indexGeneration: 7
        )
    }

    func cancel(jobID _: JobID) async throws -> MediaJobReview {
        throw ProbeError.unexpectedCall
    }

    func retry(jobID _: JobID) async throws -> MediaJobReview {
        throw ProbeError.unexpectedCall
    }

    func storageReport() async throws -> WorkspaceStorageReport {
        try WorkspaceStorageReport(
            calculatedAt: featureInstant(1_950_000_000_000),
            totalByteCount: 128,
            categories: [
                WorkspaceStorageCategoryUsage(
                    category: .trash,
                    byteCount: 128,
                    fileCount: 1
                )
            ],
            trashItems: [
                WorkspaceTrashItem(
                    storageObjectID: featureID(20, StorageObjectID.self),
                    byteSize: 128,
                    trashedAt: featureInstant(1_940_000_000_000),
                    purgeEligibleAt: featureInstant(1_949_000_000_000),
                    dataClassification: .sensitive,
                    retentionClass: .workspaceManaged
                )
            ],
            permissionIssueCount: 0,
            scanTruncated: false
        )
    }

    func permanentlyDeleteTrashItem(
        storageObjectID _: StorageObjectID,
        confirmsPermanentDeletion: Bool,
        acknowledgesUnlinkIsNotSecureErasure: Bool
    ) async throws -> WorkspaceStorageReport {
        permanentDeletionCallCount += 1
        lastDeletionConfirmed = confirmsPermanentDeletion
        lastUnlinkAcknowledged = acknowledgesUnlinkIsNotSecureErasure
        return try WorkspaceStorageReport(
            calculatedAt: featureInstant(1_950_000_000_001),
            totalByteCount: 0,
            categories: [],
            trashItems: [],
            permissionIssueCount: 0,
            scanTruncated: false
        )
    }

    func recordingSetup() async throws -> RecordingSetupReview {
        guard restoredWorkspace != nil else {
            throw TranscriptWorkflowError.unavailable
        }
        return RecordingSetupReview(
            capability: CaptureCapabilitySnapshot(
                microphonePermission: .denied,
                applicationAudioAvailable: false,
                systemPickerAvailable: false,
                checkedAt: featureInstant(1_950_000_000_002)
            ),
            microphones: []
        )
    }
}

private func featureID<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
    StableID<Tag>(
        UUID(uuidString: String(format: "51000000-0000-0000-0000-%012d", suffix))!
    )
}

private func featureInstant(_ milliseconds: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
}

private func makeFeatureJobReview(
    succeeded: Bool = false
) throws -> MediaJobReview {
    let jobID = featureID(40, JobID.self)
    let request = try JobRequest(
        jobID: jobID,
        jobType: JobType("feature-workspace-poll"),
        origin: .application,
        requestedBy: JobRequester("meetingbuddy-feature-test"),
        dataClassification: .internal,
        idempotencyKey: JobIdempotencyKey(
            lowercaseHex: String(repeating: "a", count: 64)
        ),
        totalUnitCount: 2,
        diskBudgetBytes: 65_536
    )
    let lease = try TaskDirectoryLease(
        jobID: jobID,
        relativePath: WorkspaceRelativePath(".tasks/\(jobID.canonicalString)"),
        diskBudgetBytes: 65_536
    )
    let queued = try JobRecord(
        request: request,
        lease: lease,
        createdAt: featureInstant(1_950_000_000_100)
    )
    let running = try queued.transitioning(
        to: .running,
        at: featureInstant(1_950_000_000_101)
    )
    return MediaJobReview(
        record: try succeeded
            ? running.transitioning(
                to: .succeeded,
                at: featureInstant(1_950_000_000_102)
            )
            : running
    )
}

private func makeFeatureTranscriptReview(
    transcriptRevisionID: RevisionID = featureID(56, RevisionID.self),
    translationRevisionID: RevisionID? = featureID(58, RevisionID.self),
    transcriptText: String = "Workspace A transcript fixture",
    translationText: String? = "Workspace A translation fixture"
) throws -> TranscriptReviewBundle {
    let canonicalSourceRevision = try SemanticRevisionReference(
        logicalID: featureID(50, SourceAssetID.self),
        revisionID: featureID(51, RevisionID.self)
    )
    let meetingID = featureID(54, MeetingID.self)
    let transcript = try TranscriptSegmentV1(
        revision: RevisionEnvelope(
            logicalID: featureID(55, TranscriptSegmentID.self),
            revisionID: transcriptRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: featureInstant(1_950_000_000_103),
            createdBy: .application,
            inputRevisions: [canonicalSourceRevision],
            sourceAssetRevisions: [canonicalSourceRevision],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        sourceProvenance: .originalSpeakerAudio(
            sourceAssetRevision: canonicalSourceRevision
        ),
        timeRange: MediaTimeRange(
            startMilliseconds: 0,
            endMilliseconds: 1_000
        ),
        detectedLanguage: LanguageTag("en"),
        text: transcriptText,
        confidence: ConfidenceScore(millionths: 900_000),
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
    let transcriptReference = try SemanticRevisionReference(
        logicalID: transcript.segmentID,
        revisionID: transcript.revision.revisionID
    )
    let translation: TranslationSegmentV1? = try {
        guard let translationRevisionID, let translationText else { return nil }
        return try TranslationSegmentV1(
            revision: RevisionEnvelope(
                logicalID: featureID(57, TranslationSegmentID.self),
                revisionID: translationRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: featureInstant(1_950_000_000_104),
                createdBy: .application,
                inputRevisions: [transcriptReference],
                dataClassification: .internal
            ),
            meetingID: meetingID,
            sourceSegmentRevision: transcriptReference,
            sourceLanguage: LanguageTag("en"),
            targetLanguage: LanguageTag("fr"),
            sourceTextHash: try TranslationSegmentV1.calculateSourceTextHash(
                transcript.text
            ),
            translatedText: translationText,
            translationType: .humanTranslation,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 900_000),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }()
    let translationReference = try translation.map {
        try SemanticRevisionReference(
            logicalID: $0.translationID,
            revisionID: $0.revision.revisionID
        )
    }
    let transcriptionRequest = try ModelRouteRequest(
        capability: .transcription,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .test,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [.canonicalAudio],
        visibleUserAuthorization: true,
        localModelAvailable: true
    )
    let transcriptionRoute = try ModelPolicyRouter().decide(
        transcriptionRequest
    )
    let translationRoute = try translation.map { _ in
        try ModelPolicyRouter().decide(
            ModelRouteRequest(
                capability: .translation,
                dataClassification: .internal,
                offlineMode: true,
                organizationAllowsExternalProcessing: false,
                deploymentEnvironment: .test,
                destination: .localDevice,
                retentionPolicy: .localWorkspaceOnly,
                dataCategories: [.transcriptText],
                visibleUserAuthorization: true,
                localModelAvailable: true
            )
        )
    }
    guard let plan = try CanonicalChunkPlanner.plan(
        totalFrameCount: 16_000
    ).first else {
        throw ProbeError.unexpectedCall
    }
    let coverage = try TranscriptChunkCoverage(
        index: plan.index,
        coreRange: plan.coreRange,
        physicalRange: plan.physicalRange,
        disposition: .transcribed,
        attemptCount: 1,
        reviewedSegmentRevision: transcriptReference,
        translationRevision: translationReference
    )
    let manifest = try TranscriptCoverageManifest(
        manifestID: featureID(52, TranscriptCoverageManifestID.self),
        transcriptSetID: featureID(53, TranscriptSetID.self),
        meetingID: meetingID,
        canonicalSourceRevision: canonicalSourceRevision,
        canonicalFrameCount: 16_000,
        transcriptionRoute: transcriptionRoute,
        translationRoute: translationRoute,
        status: .published,
        chunks: [coverage],
        createdAt: featureInstant(1_950_000_000_105)
    )
    return TranscriptReviewBundle(
        manifest: manifest,
        transcriptSegments: [transcript],
        translations: [translation].compactMap { $0 }
    )
}

private func makeFeatureAnalysisReview(
    positionRevisionID: RevisionID = featureID(814, RevisionID.self),
    statementText: String = "Workspace A analysis fixture position"
) throws -> AnalysisReviewBundle {
    let transcript = try makeFeatureTranscriptReview()
    let segment = try #require(transcript.transcriptSegments.first)
    let segmentReference = try featureReference(
        segment.segmentID,
        segment.revision.revisionID
    )
    let analysisRequest = try ModelRouteRequest(
        capability: .analysis,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .test,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [
            .transcriptText,
            .speakerContext,
            .evidenceIdentifiers
        ],
        visibleUserAuthorization: true,
        localModelAvailable: false
    )
    let ledger = try AnalysisCoverageLedger(
        ledgerID: featureID(800, AnalysisCoverageLedgerID.self),
        meetingID: transcript.manifest.meetingID,
        transcriptManifestID: transcript.manifest.manifestID,
        transcriptManifestHash: transcript.manifest.contentHash,
        eligibleSegmentRevisions: [segmentReference],
        analysisRoute: ModelPolicyRouter().decide(analysisRequest),
        runtimeEvidence: AnalysisRuntimeEvidence(
            operatingSystemVersion: "synthetic-test-host",
            frameworkIdentifier: "meetingbuddy.synthetic.analysis",
            adapterVersion: "feature-fixture-v1",
            localeIdentifier: "en",
            modelAvailable: false,
            noOutboundMode: true
        ),
        promptModules: [
            VersionedComponent(
                identifier: "feature-analysis-fixture",
                version: "1.0.0"
            )
        ],
        protectedRulesDigest: try ContentDigest.sha256(
            ofUTF8Text: "feature-analysis-rules"
        ),
        inputPackageDigest: try ContentDigest.sha256(
            ofUTF8Text: "feature-analysis-input"
        ),
        status: .incomplete,
        segments: [
            AnalysisSegmentCoverage(
                segmentRevision: segmentReference,
                disposition: .missing,
                attemptCount: 0
            )
        ],
        createdAt: featureInstant(1_950_000_000_200)
    )
    let meetingReference = try featureReference(
        transcript.manifest.meetingID,
        featureID(802, RevisionID.self)
    )
    let actorReference = try featureReference(
        featureID(803, ActorID.self),
        featureID(804, RevisionID.self)
    )
    let organizationReference = try featureReference(
        featureID(805, OrganizationID.self),
        featureID(806, RevisionID.self)
    )
    let capacityReference = try featureReference(
        featureID(807, SpeakingCapacityID.self),
        featureID(808, RevisionID.self)
    )
    let issueReference = try featureReference(
        featureID(809, IssueID.self),
        featureID(810, RevisionID.self)
    )
    let evidenceReference = try featureReference(
        featureID(811, EvidenceID.self),
        featureID(812, RevisionID.self)
    )
    let position = try PositionV1(
        revision: RevisionEnvelope(
            logicalID: featureID(813, PositionID.self),
            revisionID: positionRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: featureInstant(1_950_000_000_201),
            createdBy: .application,
            inputRevisions: [
                meetingReference,
                actorReference,
                organizationReference,
                capacityReference,
                issueReference
            ],
            evidenceRevisions: [evidenceReference],
            dataClassification: .internal
        ),
        meetingID: transcript.manifest.meetingID,
        actorRevision: actorReference,
        representedEntityRevision: organizationReference,
        speakingCapacityRevision: capacityReference,
        issueRevision: issueReference,
        positionType: .supports,
        statement: EvidenceLinkedClaim(
            text: statementText,
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidenceReference],
            confidence: ConfidenceScore(millionths: 900_000)
        ),
        comparisonState: .unknown,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
    return AnalysisReviewBundle(
        ledger: ledger,
        evidence: [],
        participants: [],
        organizations: [],
        issues: [],
        positions: [position],
        commitments: [],
        decisions: [],
        interventionCards: [],
        delegationPositionCards: []
    )
}

private func makeFeatureBriefingReview(
    overviewRevisionID: RevisionID = featureID(930, RevisionID.self),
    overviewText: String = "Workspace A overview fixture"
) throws -> BriefingReviewBundle {
    let analysis = try makeFeatureAnalysisReview()
    let meetingID = featureID(54, MeetingID.self)
    let meetingReference = try featureReference(
        meetingID,
        featureID(850, RevisionID.self)
    )
    let segmentReference = try featureReference(
        featureID(55, TranscriptSegmentID.self),
        featureID(56, RevisionID.self)
    )
    let evidenceReference = try featureReference(
        featureID(811, EvidenceID.self),
        featureID(812, RevisionID.self)
    )
    let issueReference = try featureReference(
        featureID(809, IssueID.self),
        featureID(810, RevisionID.self)
    )
    let organizationReference = try featureReference(
        featureID(805, OrganizationID.self),
        featureID(806, RevisionID.self)
    )
    let positionReference = try featureReference(
        featureID(813, PositionID.self),
        featureID(814, RevisionID.self)
    )
    let createdAt = featureInstant(1_950_000_000_300)

    let templateDraft = try featureBriefingTemplate(
        revision: RevisionEnvelope(
            logicalID: featureID(900, BriefingTemplateID.self),
            revisionID: featureID(901, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            dataClassification: .public
        )
    )
    let template = try featureBriefingTemplate(
        revision: publishedFeatureEnvelope(
            templateDraft.revision,
            semanticContentHash: templateDraft.calculatedSemanticContentHash(),
            at: createdAt
        )
    )
    let templateReference = try featureReference(
        template.templateID,
        template.revision.revisionID
    )
    let claim = try EvidenceLinkedClaim(
        text: "Workspace A supports the synthetic proposal.",
        taxonomy: .delegationClaim,
        supportStatus: .supported,
        evidenceRevisions: [evidenceReference],
        confidence: ConfidenceScore(millionths: 900_000)
    )
    let graphCell = try IssuePositionMatrixCell(
        itemID: featureID(902, BriefingItemID.self),
        representedEntityRevision: organizationReference,
        positionRevisions: [positionReference],
        positionTypes: [.supports],
        statements: [claim]
    )
    let graphRow = try IssuePositionMatrixRow(
        issueRevision: issueReference,
        cells: [graphCell]
    )
    let graphDraft = try IssuePositionGraphV1(
        revision: RevisionEnvelope(
            logicalID: featureID(903, IssuePositionGraphID.self),
            revisionID: featureID(904, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: [
                meetingReference,
                templateReference,
                issueReference,
                organizationReference,
                positionReference
            ],
            evidenceRevisions: [evidenceReference],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        templateRevision: templateReference,
        analysisLedgerID: analysis.ledger.ledgerID,
        analysisLedgerHash: analysis.ledger.contentHash,
        rows: [graphRow],
        reviewStatus: .needsReview,
        userConfirmed: false
    )
    let graph = try IssuePositionGraphV1(
        revision: publishedFeatureEnvelope(
            graphDraft.revision,
            semanticContentHash: graphDraft.calculatedSemanticContentHash(),
            at: createdAt
        ),
        meetingID: graphDraft.meetingID,
        templateRevision: graphDraft.templateRevision,
        analysisLedgerID: graphDraft.analysisLedgerID,
        analysisLedgerHash: graphDraft.analysisLedgerHash,
        rows: graphDraft.rows,
        reviewStatus: graphDraft.reviewStatus,
        userConfirmed: graphDraft.userConfirmed
    )
    let graphReference = try featureReference(
        graph.graphID,
        graph.revision.revisionID
    )
    let sectionMarkers = [
        overviewText,
        "Workspace A major issues fixture",
        "Workspace A delegations fixture"
    ]
    let sections = try zip(template.sections, sectionMarkers)
        .enumerated()
        .map { index, value in
            let (definition, marker) = value
            let itemID = featureID(
                910 + index,
                BriefingItemID.self
            )
            let item = try BriefingSectionItem(
                itemID: itemID,
                claim: EvidenceLinkedClaim(
                    text: marker,
                    taxonomy: .meetingBuddyInference,
                    supportStatus: .supported,
                    evidenceRevisions: [evidenceReference],
                    confidence: ConfidenceScore(millionths: 850_000)
                ),
                sourceObjectRevisions: [positionReference]
            )
            let draft = try BriefingSectionV1(
                revision: RevisionEnvelope(
                    logicalID: featureID(
                        920 + index,
                        BriefingSectionID.self
                    ),
                    revisionID: index == 0
                        ? overviewRevisionID
                        : featureID(930 + index, RevisionID.self),
                    schemaVersion: .v1,
                    lifecycleStatus: .draft,
                    validationState: .notValidated,
                    createdAt: createdAt,
                    createdBy: .application,
                    inputRevisions: [
                        meetingReference,
                        templateReference,
                        graphReference,
                        positionReference
                    ],
                    evidenceRevisions: [evidenceReference],
                    dataClassification: .internal
                ),
                meetingID: meetingID,
                templateRevision: templateReference,
                graphRevision: graphReference,
                sectionType: definition.sectionType,
                order: definition.order,
                title: definition.title,
                outputLanguage: LanguageTag("en"),
                items: [item],
                generatorModules: definition.promptModules,
                manualEditStatus: .generated,
                locked: false,
                reviewStatus: .needsReview,
                userConfirmed: false
            )
            return try BriefingSectionV1(
                revision: publishedFeatureEnvelope(
                    draft.revision,
                    semanticContentHash: draft
                        .calculatedSemanticContentHash(),
                    at: createdAt
                ),
                meetingID: draft.meetingID,
                templateRevision: draft.templateRevision,
                graphRevision: draft.graphRevision,
                sectionType: draft.sectionType,
                order: draft.order,
                title: draft.title,
                outputLanguage: draft.outputLanguage,
                metadata: draft.metadata,
                items: draft.items,
                generatorModules: draft.generatorModules,
                manualEditStatus: draft.manualEditStatus,
                locked: draft.locked,
                reviewStatus: draft.reviewStatus,
                userConfirmed: draft.userConfirmed
            )
        }
    let sectionReferences = try sections.map {
        try featureReference(
            $0.sectionID,
            $0.revision.revisionID
        )
    }
    var conclusions = [
        try BriefingConclusionReference(
            outputRevision: graphReference,
            itemID: graphCell.itemID
        )
    ]
    conclusions += try zip(sections, sectionReferences).map {
        section, reference in
        try BriefingConclusionReference(
            outputRevision: reference,
            itemID: section.items[0].itemID
        )
    }
    let ledger = try BriefingCoverageLedger(
        ledgerID: featureID(940, BriefingCoverageLedgerID.self),
        meetingID: meetingID,
        transcriptManifestID: analysis.ledger.transcriptManifestID,
        transcriptManifestHash: analysis.ledger.transcriptManifestHash,
        analysisLedgerID: analysis.ledger.ledgerID,
        analysisLedgerHash: analysis.ledger.contentHash,
        eligibleSegmentRevisions: [segmentReference],
        templateRevision: templateReference,
        graphRevision: graphReference,
        sectionRevisions: sectionReferences,
        status: .published,
        segments: [
            BriefingSegmentCoverage(
                segmentRevision: segmentReference,
                analysisOutputRevisions: [positionReference],
                evidenceRevisions: [evidenceReference],
                conclusionReferences: conclusions,
                disposition: .represented
            )
        ],
        createdAt: createdAt
    )
    let validator = try VersionedComponent(
        identifier: "feature-briefing-validator",
        version: "1.0.0"
    )
    let checks = try [
        BriefingValidationCategory.templateCompatibility,
        .schema,
        .evidence,
        .entity,
        .sourceCoverage,
        .length,
        .provenance,
        .contradiction,
        .currentInputs,
        .classification
    ].map {
        try BriefingValidationCheck(
            category: $0,
            status: .passed,
            validator: validator
        )
    }
    let reportDraft = try ValidationReportV1(
        revision: RevisionEnvelope(
            logicalID: featureID(941, ValidationReportID.self),
            revisionID: featureID(942, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: [
                meetingReference,
                templateReference,
                graphReference
            ] + sectionReferences,
            evidenceRevisions: [evidenceReference],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        templateRevision: templateReference,
        graphRevision: graphReference,
        sectionRevisions: sectionReferences,
        coverageLedgerID: ledger.ledgerID,
        coverageLedgerHash: ledger.contentHash,
        checks: checks,
        overallStatus: .passed,
        reviewStatus: .needsReview,
        userConfirmed: false
    )
    let report = try ValidationReportV1(
        revision: publishedFeatureEnvelope(
            reportDraft.revision,
            semanticContentHash: reportDraft.calculatedSemanticContentHash(),
            at: createdAt
        ),
        meetingID: reportDraft.meetingID,
        templateRevision: reportDraft.templateRevision,
        graphRevision: reportDraft.graphRevision,
        sectionRevisions: reportDraft.sectionRevisions,
        coverageLedgerID: reportDraft.coverageLedgerID,
        coverageLedgerHash: reportDraft.coverageLedgerHash,
        checks: reportDraft.checks,
        findings: reportDraft.findings,
        overallStatus: reportDraft.overallStatus,
        reviewStatus: reportDraft.reviewStatus,
        userConfirmed: reportDraft.userConfirmed
    )
    let reportReference = try featureReference(
        report.reportID,
        report.revision.revisionID
    )
    let markdown = """
    # Workspace A Briefing

    - Workspace A overview fixture
    - Workspace A major issues fixture
    - Workspace A delegations fixture
    """
    let finalDraft = try FinalBriefingV1(
        revision: RevisionEnvelope(
            logicalID: featureID(943, FinalBriefingID.self),
            revisionID: featureID(944, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: [
                meetingReference,
                templateReference
            ] + sectionReferences + [reportReference],
            evidenceRevisions: [evidenceReference],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        templateRevision: templateReference,
        sectionRevisions: sectionReferences,
        validationReportRevision: reportReference,
        outputLanguage: LanguageTag("en"),
        documentTitle: "Workspace A Briefing",
        renderer: template.rendererModules[0],
        markdown: markdown,
        markdownDigest: try ContentDigest.sha256(ofUTF8Text: markdown),
        manualSectionCount: 0,
        reviewStatus: .needsReview,
        userConfirmed: false
    )
    let final = try FinalBriefingV1(
        revision: publishedFeatureEnvelope(
            finalDraft.revision,
            semanticContentHash: finalDraft.calculatedSemanticContentHash(),
            at: createdAt
        ),
        meetingID: finalDraft.meetingID,
        templateRevision: finalDraft.templateRevision,
        sectionRevisions: finalDraft.sectionRevisions,
        validationReportRevision: finalDraft.validationReportRevision,
        outputLanguage: finalDraft.outputLanguage,
        documentTitle: finalDraft.documentTitle,
        renderer: finalDraft.renderer,
        markdown: finalDraft.markdown,
        markdownDigest: finalDraft.markdownDigest,
        manualSectionCount: finalDraft.manualSectionCount,
        reviewStatus: finalDraft.reviewStatus,
        userConfirmed: finalDraft.userConfirmed
    )
    return BriefingReviewBundle(
        publication: try BriefingPublication(
            template: template,
            graph: graph,
            sections: sections,
            validationReport: report,
            finalBriefing: final,
            ledger: ledger
        ),
        staleMarks: []
    )
}

private func featureBriefingTemplate(
    revision: RevisionEnvelope<BriefingTemplateIDTag>
) throws -> MeetingTemplateV1 {
    let sectionTypes: [
        (
            BriefingSectionType,
            String,
            String,
            UInt16,
            [SemanticObjectType]
        )
    ] = [
        (
            .meetingOverview,
            "meeting-overview",
            "Meeting Overview",
            1,
            [.meetingProfile, .interventionCard]
        ),
        (
            .majorIssues,
            "major-issues",
            "Major Issues",
            2,
            [.issuePositionGraph, .issue]
        ),
        (
            .majorDelegations,
            "major-delegations",
            "Major Countries / Delegations",
            3,
            [.issuePositionGraph, .position, .participant, .organization]
        )
    ]
    let sections = try sectionTypes.map {
        sectionType, key, title, order, inputTypes in
        try TemplateSectionDefinition(
            key: key,
            sectionType: sectionType,
            order: order,
            title: title,
            targetLengthUTF8Bytes: 4_096,
            requiredInputObjectTypes: inputTypes,
            promptModules: [
                VersionedComponent(
                    identifier: "feature-\(key)-generator",
                    version: "1.0.0"
                )
            ]
        )
    }
    let ruleKinds: [BriefingValidationRuleKind] = [
        .evidenceClosure,
        .entityResolution,
        .sourceCoverage,
        .contradiction,
        .lengthLimit,
        .prohibitHistoricalChange,
        .prohibitGroupInference
    ]
    return try MeetingTemplateV1(
        revision: revision,
        templateKey: "feature-diplomatic-meeting-v1",
        displayName: "Feature Diplomatic Meeting",
        meetingType: .multilateralDiplomaticMeeting,
        requiredSemanticObjectTypes: [
            .meetingProfile,
            .evidenceRef,
            .issue,
            .position,
            .participant,
            .organization
        ],
        sections: sections,
        validationRules: ruleKinds.map {
            try BriefingValidationRule(kind: $0)
        },
        rendererModules: [
            VersionedComponent(
                identifier: "feature-markdown-renderer",
                version: "1.0.0"
            )
        ],
        reviewStatus: .needsReview,
        userConfirmed: false
    )
}

private func publishedFeatureEnvelope<Tag: LogicalObjectIDScope>(
    _ draft: RevisionEnvelope<Tag>,
    semanticContentHash: ContentDigest,
    at publishedAt: UTCInstant
) throws -> RevisionEnvelope<Tag> {
    try RevisionEnvelope(
        logicalID: draft.logicalID,
        revisionID: draft.revisionID,
        schemaVersion: draft.schemaVersion,
        lifecycleStatus: .published,
        validationState: .valid,
        createdAt: draft.createdAt,
        createdBy: draft.createdBy,
        publishedAt: publishedAt,
        supersedesRevisionID: draft.supersedesRevisionID,
        inputRevisions: draft.inputRevisions,
        sourceAssetRevisions: draft.sourceAssetRevisions,
        evidenceRevisions: draft.evidenceRevisions,
        dataClassification: draft.dataClassification,
        generationMetadata: draft.generationMetadata,
        semanticContentHash: semanticContentHash
    )
}

private func featureReference<Tag: LogicalObjectIDScope>(
    _ logicalID: StableID<Tag>,
    _ revisionID: RevisionID
) throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: logicalID,
        revisionID: revisionID
    )
}

private actor AsyncGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func block() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private enum FeatureEditorSaveCall: Equatable {
    case transcript(RevisionID, String)
    case translation(RevisionID, String)
    case speaker(RevisionID, String)
    case position(
        RevisionID,
        PositionType,
        String,
        [String],
        [String]
    )
    case briefing(
        BriefingSectionType,
        RevisionID,
        [BriefingItemID: String],
        Bool
    )
}

private enum ProbeError: Error {
    case unexpectedCall
    case staleRevision
    case transientRestore
}
