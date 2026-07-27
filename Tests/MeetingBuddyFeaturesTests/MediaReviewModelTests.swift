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
        #expect(store.storageFailureMessage == nil)
        #expect(
            StorageDashboardPresentation.state(
                report: store.storageReport,
                operation: store.storageOperation,
                failureMessage: store.storageFailureMessage
            ) == .ready(try #require(store.storageReport))
        )
        #expect(workflow.permanentDeletionCallCount == 0)

        await store.permanentlyDeleteTrashItem(
            item.storageObjectID,
            confirmedByVisibleDialog: true
        )
        #expect(workflow.permanentDeletionCallCount == 1)
        #expect(workflow.lastDeletionConfirmed == true)
        #expect(workflow.lastUnlinkAcknowledged == true)
        #expect(store.storageReport?.trashItems.isEmpty == true)
        #expect(store.storageFailureMessage == nil)
        #expect(store.safeErrorMessage == nil)
    }

    @Test @MainActor
    func storageRefreshPublishesLoadingThenRetainsOnlyAnExplicitlyStaleReport()
        async throws
    {
        let gate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            storageReportGate: gate,
            storageReportFailureCall: 2
        )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/selected-workspace"
            ),
            using: sceneState
        )

        let initialLoad = Task {
            await store.loadStorageReport()
        }
        await gate.waitUntilEntered()
        #expect(
            store.storageOperation
                == .refreshing
        )
        #expect(store.storageReport == nil)
        #expect(
            StorageDashboardPresentation
                .state(
                    report: store.storageReport,
                    operation:
                        store.storageOperation,
                    failureMessage:
                        store.storageFailureMessage
                ) == .loading(previous: nil)
        )
        await gate.release()
        await initialLoad.value

        let accepted = try #require(
            store.storageReport
        )
        #expect(store.storageOperation == nil)
        #expect(store.storageFailureMessage == nil)
        #expect(
            workflow.storageReportCallCount == 1
        )

        await store.loadStorageReport()
        #expect(
            store.storageReport == accepted
        )
        #expect(
            store.storageFailureMessage
                == "The exact local storage ledger could not be refreshed. The last successful report, if any, remains read-only."
        )
        #expect(store.safeErrorMessage == nil)
        #expect(
            StorageDashboardPresentation
                .state(
                    report: store.storageReport,
                    operation:
                        store.storageOperation,
                    failureMessage:
                        store.storageFailureMessage
                ) == .staleLastSuccess(
                    accepted,
                    message:
                        "The exact local storage ledger could not be refreshed. The last successful report, if any, remains read-only."
                )
        )
        #expect(
            workflow.storageReportCallCount == 2
        )
    }

    @Test @MainActor
    func rejectedOverlappingStorageRefreshCannotStaleTheOwningSuccess()
        async throws
    {
        let gate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            storageReportGate: gate
        )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/selected-workspace"
            ),
            using: sceneState
        )

        let owningRefresh = Task {
            await store.loadStorageReport()
        }
        await gate.waitUntilEntered()

        await store.loadStorageReport()
        #expect(store.safeErrorMessage == nil)
        #expect(store.storageFailureMessage == nil)
        #expect(
            workflow.storageReportCallCount == 1
        )

        await gate.release()
        await owningRefresh.value

        let accepted = try #require(
            store.storageReport
        )
        #expect(store.storageOperation == nil)
        #expect(store.storageFailureMessage == nil)
        #expect(store.safeErrorMessage == nil)
        #expect(
            StorageDashboardPresentation
                .state(
                    report: store.storageReport,
                    operation:
                        store.storageOperation,
                    failureMessage:
                        store.storageFailureMessage
                ) == .ready(accepted)
        )
        #expect(
            workflow.storageReportCallCount == 1
        )
    }

    @Test @MainActor
    func storageMutationFailurePreservesTheReportAndWorkspaceSwitchClearsIt()
        async throws
    {
        let workflow =
            try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/selected-workspace"
            ),
            using: sceneState
        )
        await store.loadStorageReport()
        let accepted = try #require(
            store.storageReport
        )
        let item = try #require(
            accepted.trashItems.first
        )

        await store.restoreTrashItem(
            item.storageObjectID
        )
        #expect(
            store.storageReport == accepted
        )
        #expect(
            store.storageFailureMessage
                == "The restore result could not be verified. Refresh the exact ledger before retrying; do not assume the item remains in Workspace Trash."
        )
        #expect(store.safeErrorMessage == nil)

        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/replacement-workspace"
            ),
            using: sceneState
        )
        #expect(store.storageReport == nil)
        #expect(store.storageOperation == nil)
        #expect(store.storageFailureMessage == nil)
    }

    @Test @MainActor
    func storageMutationAndRefreshAmbiguityNeverClaimsTheOppositeResult()
        async throws
    {
        let restoreWorkflow =
            try MediaReviewWorkflowProbe(
                restoreReportFailsAfterMutation:
                    true
            )
        let restoreStore = MediaReviewStore(
            workflow: restoreWorkflow
        )
        let restoreSceneState =
            MediaReviewSceneState()
        await restoreStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/restore-ambiguity-workspace"
            ),
            using: restoreSceneState
        )
        await restoreStore.loadStorageReport()
        let restoreItem = try #require(
            restoreStore.storageReport?
                .trashItems.first
        )

        await restoreStore.restoreTrashItem(
            restoreItem.storageObjectID
        )

        #expect(
            restoreWorkflow
                .restoreMutationCallCount == 1
        )
        #expect(
            restoreStore.storageFailureMessage
                == "The restore result could not be verified. Refresh the exact ledger before retrying; do not assume the item remains in Workspace Trash."
        )
        #expect(
            restoreStore.storageReport?
                .trashItems.first?
                .storageObjectID
                == restoreItem.storageObjectID
        )

        let deletionWorkflow =
            try MediaReviewWorkflowProbe(
                permanentDeletionReportFailsAfterMutation:
                    true
            )
        let deletionStore = MediaReviewStore(
            workflow: deletionWorkflow
        )
        let deletionSceneState =
            MediaReviewSceneState()
        await deletionStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/deletion-ambiguity-workspace"
            ),
            using: deletionSceneState
        )
        await deletionStore.loadStorageReport()
        let deletionItem = try #require(
            deletionStore.storageReport?
                .trashItems.first
        )

        await deletionStore
            .permanentlyDeleteTrashItem(
                deletionItem.storageObjectID,
                confirmedByVisibleDialog: true
            )

        #expect(
            deletionWorkflow
                .permanentDeletionMutationCallCount
                == 1
        )
        #expect(
            deletionStore.storageFailureMessage
                == "The permanent-deletion result could not be verified. Refresh the exact ledger before retrying; do not assume the item remains in Workspace Trash."
        )
        #expect(
            deletionStore.storageReport?
                .trashItems.first?
                .storageObjectID
                == deletionItem.storageObjectID
        )
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
        sceneState.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/synthetic-id"
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
        await store.loadLearnedPreferences()
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
        await store.loadLearnedPreferences()
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
        sceneState.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/synthetic-id"
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
        let filter = HistoricalSearchFilterSnapshot(
            sceneState: sceneState
        )
        #expect(
            store.historicalSearchFilterSnapshot
                == filter
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: store.historicalSearchPage,
                isLoading: false,
                searchFailureMessage:
                    store
                    .historicalSearchFailureMessage,
                pageStaleReason:
                    store
                    .historicalSearchPageStaleReason,
                lastSuccessfulFilter:
                    store
                    .historicalSearchFilterSnapshot,
                currentFilter: filter
            ) == .empty(generation: 7)
        )
    }

    @Test @MainActor
    func settingsReadinessWaitsWithoutHidingTheWorkflowWorkspaceSwitch()
        async throws
    {
        let setupGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            recordingSetupGate: setupGate
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()

        let openTask = Task {
            await store.openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-atomic-workspace"
                ),
                using: sceneState
            )
        }
        while workflow.openCallCount == 0 {
            await Task.yield()
        }

        #expect(store.workspace != nil)
        #expect(store.workspaceSession == 1)
        #expect(store.workspaceReadySession == 0)
        await store.loadLearnedPreferences()
        #expect(
            workflow.learnedPreferenceStateCallCount
                == 0
        )

        await setupGate.release()
        await openTask.value

        #expect(store.workspace != nil)
        #expect(store.workspaceSession == 1)
        #expect(store.workspaceReadySession == 1)
        #expect(store.recordingSetup != nil)
    }

    @Test @MainActor
    func setupFailureKeepsStoreAndWorkflowOnTheSameVisibleWorkspace()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            recordingSetupFailureCall: 2
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-workspace-a"
            ),
            using: sceneState
        )
        #expect(
            store.workspace?.displayName
                == "Synthetic Workspace"
        )
        #expect(store.workspaceReadySession == 1)

        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-workspace-b"
            ),
            using: sceneState
        )

        #expect(
            store.workspace?.displayName
                == "Synthetic Workspace B"
        )
        #expect(
            store.workspace?.displayName
                == workflow
                .workflowWorkspaceDisplayName
        )
        #expect(store.workspaceSession == 2)
        #expect(store.workspaceReadySession == 1)
        #expect(store.recordingSetup == nil)
        #expect(store.safeErrorMessage != nil)
        await store.loadLearnedPreferences()
        #expect(
            workflow.learnedPreferenceStateCallCount
                == 0
        )
    }

    @Test @MainActor
    func historyLoadDoesNotDependOnTheSettingsPreferenceRepository()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            learnedPreferenceFailureCall: 1,
            historicalIndexAvailability: .ready
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-independent-history-workspace"
            ),
            using: sceneState
        )

        await store.loadHistoricalReview(
            using: sceneState
        )

        #expect(workflow.historicalIndexCallCount == 1)
        #expect(workflow.historicalSearchCallCount == 1)
        #expect(
            workflow.learnedPreferenceStateCallCount
                == 0
        )
        #expect(store.historicalSearchPage != nil)
        #expect(
            store.historicalIndexFailureMessage == nil
        )
        #expect(
            store.historicalSearchFailureMessage == nil
        )
    }

    @Test @MainActor
    func historyPaginationUsesTheAcceptedGenerationFilterAndCursor()
        async throws
    {
        let firstResult =
            try makeFeatureHistoricalResult(
                suffix: 1
            )
        let nextResult =
            try makeFeatureHistoricalResult(
                suffix: 2
            )
        let cursor =
            firstResult.cursor(
                indexGeneration: 7
            )
        let firstPage = HistoricalSearchPage(
            results: [firstResult],
            nextCursor: cursor,
            indexGeneration: 7
        )
        let finalPage = HistoricalSearchPage(
            results: [nextResult],
            nextCursor: nil,
            indexGeneration: 7
        )
        let workflow = try MediaReviewWorkflowProbe(
            historicalSearchPages: [
                firstPage,
                finalPage
            ],
            historicalIndexAvailability: .ready
        )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-paginated-history-workspace"
            ),
            using: sceneState
        )
        sceneState.historyActorOrCountry =
            "Synthetic actor"

        await store.searchMeetingHistory(
            using: sceneState
        )
        #expect(
            store.historicalSearchPage
                == firstPage
        )
        #expect(
            workflow.historicalSearchCallCount
                == 1
        )

        sceneState.historyTopic =
            "Changed after the accepted page"
        await store.loadMoreHistoricalResults(
            using: sceneState
        )
        #expect(
            workflow.historicalSearchCallCount
                == 1
        )
        #expect(
            store.historicalSearchPage
                == firstPage
        )

        sceneState.historyTopic = ""
        await store.loadMoreHistoricalResults(
            using: sceneState
        )

        #expect(
            workflow.historicalSearchCallCount
                == 2
        )
        #expect(
            workflow.lastHistoricalSearchQuery?
                .actorOrCountry
                == "Synthetic actor"
        )
        #expect(
            workflow.lastHistoricalSearchQuery?
                .cursor
                == cursor
        )
        #expect(
            store.historicalSearchPage
                == HistoricalSearchPage(
                    results: [
                        firstResult,
                        nextResult
                    ],
                    nextCursor: nil,
                    indexGeneration: 7
                )
        )
        #expect(
            !store
                .historicalSearchIsLoadingNextPage
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )
        #expect(
            store.historicalPaginationFailureMessage
                == nil
        )
    }

    @Test @MainActor
    func historyPaginationRejectsMalformedCursorsAndDuplicateRevisions()
        async throws
    {
        let firstResult =
            try makeFeatureHistoricalResult(
                suffix: 3
            )
        let nextResult =
            try makeFeatureHistoricalResult(
                suffix: 4
            )
        let firstPage = HistoricalSearchPage(
            results: [firstResult],
            nextCursor:
                firstResult.cursor(
                    indexGeneration: 7
                ),
            indexGeneration: 7
        )
        let wrongGenerationWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    firstPage,
                    HistoricalSearchPage(
                        results: [nextResult],
                        nextCursor: nil,
                        indexGeneration: 8
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let wrongGenerationStore =
            MediaReviewStore(
                workflow:
                    wrongGenerationWorkflow
            )
        let wrongGenerationScene =
            MediaReviewSceneState()
        await wrongGenerationStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-wrong-generation-workspace"
                ),
                using: wrongGenerationScene
            )
        await wrongGenerationStore
            .searchMeetingHistory(
                using: wrongGenerationScene
            )
        await wrongGenerationStore
            .loadMoreHistoricalResults(
                using: wrongGenerationScene
            )
        #expect(
            wrongGenerationStore
                .historicalSearchPage
                == firstPage
        )
        #expect(
            wrongGenerationStore
                .historicalPaginationFailureMessage
                != nil
        )
        #expect(
            wrongGenerationStore
                .historicalSearchFailureMessage
                == nil
        )
        #expect(
            wrongGenerationStore
                .historicalResultsAreCurrent(
                    using:
                        wrongGenerationScene
                )
        )

        let malformedCursor =
            HistoricalSearchCursor(
                indexGeneration: 7,
                effectiveDate: nil,
                mediaStartMilliseconds: nil,
                positionRevisionID:
                    featureID(
                        1_042,
                        RevisionID.self
                    )
            )
        let malformedWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    firstPage,
                    HistoricalSearchPage(
                        results: [nextResult],
                        nextCursor:
                            malformedCursor,
                        indexGeneration: 7
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let malformedStore =
            MediaReviewStore(
                workflow:
                    malformedWorkflow
            )
        let malformedScene =
            MediaReviewSceneState()
        await malformedStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-malformed-cursor-workspace"
                ),
                using: malformedScene
            )
        await malformedStore
            .searchMeetingHistory(
                using: malformedScene
            )
        await malformedStore
            .loadMoreHistoricalResults(
                using: malformedScene
            )
        #expect(
            malformedStore
                .historicalSearchPage
                == firstPage
        )
        #expect(
            malformedStore
                .historicalPaginationFailureMessage
                != nil
        )
        #expect(
            malformedStore
                .historicalSearchFailureMessage
                == nil
        )

        let duplicateWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    firstPage,
                    HistoricalSearchPage(
                        results: [firstResult],
                        nextCursor: nil,
                        indexGeneration: 7
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let duplicateStore =
            MediaReviewStore(
                workflow:
                    duplicateWorkflow
            )
        let duplicateScene =
            MediaReviewSceneState()
        await duplicateStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-duplicate-page-workspace"
                ),
                using: duplicateScene
            )
        await duplicateStore
            .searchMeetingHistory(
                using: duplicateScene
            )
        await duplicateStore
            .loadMoreHistoricalResults(
                using: duplicateScene
            )
        #expect(
            duplicateStore
                .historicalSearchPage
                == firstPage
        )
        #expect(
            duplicateStore
                .historicalPaginationFailureMessage
                != nil
        )
        #expect(
            duplicateStore
                .historicalSearchFailureMessage
                == nil
        )
    }

    @Test @MainActor
    func failedIndexReloadRetainsOnlyAnExplicitlyStaleSnapshot()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            historicalIndexFailureCall: 2,
            historicalIndexAvailability: .ready
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-index-reload-workspace"
            ),
            using: sceneState
        )
        await store.loadHistoricalReview(
            using: sceneState
        )
        let firstIndex = try #require(
            store.historicalIndex
        )
        let firstPage = try #require(
            store.historicalSearchPage
        )

        await store.loadHistoricalReview(
            using: sceneState
        )

        #expect(store.historicalIndex == firstIndex)
        #expect(store.historicalSearchPage == firstPage)
        #expect(workflow.historicalIndexCallCount == 2)
        #expect(workflow.historicalSearchCallCount == 1)
        #expect(
            store.historicalIndexFailureMessage != nil
        )
        #expect(
            store.historicalSearchFailureMessage == nil
        )
    }

    @Test @MainActor
    func indexFailureAndSearchFreshnessRecoverIndependently()
        async throws
    {
        let page7 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 5
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let page8 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 6
                )
            ],
            nextCursor: nil,
            indexGeneration: 8
        )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    page7,
                    page7,
                    page8
                ],
                historicalIndexFailureCall: 2,
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    ),
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    ),
                    makeFeatureHistoricalIndexStatus(
                        generation: 8
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-independent-status-page-workspace"
            ),
            using: sceneState
        )

        await store.loadHistoricalReview(
            using: sceneState
        )
        #expect(store.historicalIndex?.generation == 7)
        #expect(store.historicalSearchPage == page7)
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )

        await store.loadHistoricalReview(
            using: sceneState
        )
        #expect(store.historicalSearchPage == page7)
        #expect(
            store.historicalIndexFailureMessage
                != nil
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalSearchPageStaleReason
                != nil
        )

        await store.searchMeetingHistory(
            using: sceneState
        )
        #expect(store.historicalSearchPage == page7)
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalIndexFailureMessage
                != nil
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )

        await store.loadHistoricalReview(
            using: sceneState
        )
        #expect(store.historicalIndex?.generation == 8)
        #expect(store.historicalSearchPage == page8)
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalIndexFailureMessage
                == nil
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )
    }

    @Test @MainActor
    func generationDriftNeverPresentsStatusAndPageAsJointlyCurrent()
        async throws
    {
        let page7 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 7
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let page8 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 8
                )
            ],
            nextCursor: nil,
            indexGeneration: 8
        )
        let cachedWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    page7,
                    page8
                ],
                historicalIndexFailureCall: 2,
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let cachedStore = MediaReviewStore(
            workflow: cachedWorkflow
        )
        let cachedScene =
            MediaReviewSceneState()
        await cachedStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-cached-generation-workspace"
            ),
            using: cachedScene
        )
        await cachedStore.loadHistoricalReview(
            using: cachedScene
        )
        await cachedStore.searchMeetingHistory(
            using: cachedScene
        )

        #expect(
            cachedStore.historicalIndex?
                .generation == 7
        )
        #expect(
            cachedStore.historicalSearchPage
                == page8
        )
        #expect(
            cachedStore.historicalResultsAreCurrent(
                using: cachedScene
            )
        )
        #expect(
            cachedStore
                .historicalIndexFailureMessage?
                .contains("generation 7")
                == true
        )
        #expect(
            cachedStore
                .historicalIndexFailureMessage?
                .contains("generation 8")
                == true
        )

        await cachedStore.loadHistoricalReview(
            using: cachedScene
        )
        #expect(
            cachedStore.historicalSearchPage
                == page8
        )
        #expect(
            !cachedStore.historicalResultsAreCurrent(
                using: cachedScene
            )
        )
        #expect(
            cachedStore
                .historicalSearchPageStaleReason
                != nil
        )

        let freshWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    page8
                ],
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let freshStore = MediaReviewStore(
            workflow: freshWorkflow
        )
        let freshScene =
            MediaReviewSceneState()
        await freshStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-fresh-generation-workspace"
            ),
            using: freshScene
        )
        await freshStore.loadHistoricalReview(
            using: freshScene
        )

        #expect(
            freshStore.historicalIndex?
                .generation == 7
        )
        #expect(
            freshStore.historicalSearchPage
                == page8
        )
        #expect(
            freshStore.historicalResultsAreCurrent(
                using: freshScene
            )
        )
        #expect(
            freshStore.historicalIndexFailureMessage
                != nil
        )
    }

    @Test @MainActor
    func historyLoadFreezesItsQueryAndRejectsInterveningFilterDrift()
        async throws
    {
        let indexGate = AsyncGate()
        let searchGate = AsyncGate()
        let page = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 5
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalIndexGate:
                    indexGate,
                historicalSearchGate:
                    searchGate,
                historicalSearchGateCall: 1,
                historicalSearchPages: [
                    page
                ],
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-frozen-history-query-workspace"
            ),
            using: sceneState
        )
        sceneState.historyActorOrCountry =
            "Frozen actor A"
        let loading = Task {
            await store.loadHistoricalReview(
                using: sceneState
            )
        }
        await indexGate.waitUntilEntered()

        sceneState.historyActorOrCountry =
            "Transient actor B"
        store.historicalFilterDidChange(
            using: sceneState
        )
        await indexGate.release()
        await searchGate.waitUntilEntered()
        sceneState.historyActorOrCountry =
            "Frozen actor A"
        store.historicalFilterDidChange(
            using: sceneState
        )
        await searchGate.release()
        await loading.value

        #expect(
            workflow.lastHistoricalSearchQuery?
                .actorOrCountry
                == "Frozen actor A"
        )
        #expect(
            store.historicalSearchFilterSnapshot
                == nil
        )
        #expect(
            store.historicalSearchPage == nil
        )
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalSearchFailureMessage?
                .contains(
                    "filters changed"
                ) == true
        )
    }

    @Test @MainActor
    func cancelledSecondStageSearchCannotLeaveANewStatusWithAnOldCurrentPage()
        async throws
    {
        let searchGate = AsyncGate()
        let page7 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 6
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let page8 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 7
                )
            ],
            nextCursor: nil,
            indexGeneration: 8
        )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    searchGate,
                historicalSearchGateCall: 2,
                historicalSearchPages: [
                    page7,
                    page8
                ],
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    ),
                    makeFeatureHistoricalIndexStatus(
                        generation: 8
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-two-stage-cancellation-workspace"
            ),
            using: sceneState
        )
        await store.loadHistoricalReview(
            using: sceneState
        )
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )

        let reloading = Task {
            await store.loadHistoricalReview(
                using: sceneState
            )
        }
        await searchGate.waitUntilEntered()

        #expect(store.historicalIndex?.generation == 8)
        #expect(store.historicalSearchPage == page7)
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalSearchPageStaleReason?
                .contains("generation 8")
                == true
        )
        #expect(
            store.historicalSearchPageStaleReason?
                .contains("generation 7")
                == true
        )

        reloading.cancel()
        await searchGate.release()
        await reloading.value

        #expect(store.historicalIndex?.generation == 8)
        #expect(store.historicalSearchPage == page7)
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalIndexFailureMessage
                == nil
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )
        #expect(
            !store.historicalReviewIsLoading
        )
        #expect(
            !store.historicalSearchIsLoading
        )
    }

    @Test @MainActor
    func indexStatusLoadDoesNotClaimASearchBeforeReadinessIsKnown()
        async throws
    {
        let indexGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            historicalIndexGate: indexGate
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-index-loading-workspace"
            ),
            using: sceneState
        )

        let loadTask = Task {
            await store.loadHistoricalReview(
                using: sceneState
            )
        }
        while workflow.historicalIndexCallCount == 0 {
            await Task.yield()
        }

        #expect(store.historicalReviewIsLoading)
        #expect(!store.historicalSearchIsLoading)

        await indexGate.release()
        await loadTask.value

        #expect(!store.historicalReviewIsLoading)
        #expect(!store.historicalSearchIsLoading)
        #expect(workflow.historicalSearchCallCount == 0)
    }

    @Test @MainActor
    func activeHistoryRebuildRejectsADuplicateEnqueue()
        async throws
    {
        let pollGate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(
            pollGate: pollGate,
            historicalRebuildCompletesImmediately:
                false
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-rebuild-gate-workspace"
            ),
            using: sceneState
        )

        await store.rebuildHistoricalIndex(
            using: sceneState
        )
        await store.rebuildHistoricalIndex(
            using: sceneState
        )

        #expect(workflow.historicalRebuildCallCount == 1)
        #expect(
            store.historicalIndexJob?.state
                == .running
        )

        await pollGate.release()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-rebuild-gate-workspace-b"
            ),
            using: sceneState
        )
    }

    @Test @MainActor
    func rebuildClearsTheAcceptedBundleOnlyAfterEnqueueSucceeds()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 9
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 10
            )
        let firstPage = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor:
                current.cursor(
                    indexGeneration: 7
                ),
            indexGeneration: 7
        )
        let comparison =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical
            )
        let pollGate = AsyncGate()
        let workflow =
            try MediaReviewWorkflowProbe(
                pollGate: pollGate,
                historicalSearchFailureCall: 2,
                historicalSearchPages: [
                    firstPage
                ],
                historicalRebuildFailureCall: 1,
                historicalComparisonResult:
                    comparison,
                historicalIndexAvailability:
                    .ready,
                historicalRebuildCompletesImmediately:
                    false
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-rebuild-preservation-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        await store.loadMoreHistoricalResults(
            using: sceneState
        )

        let acceptedPage = try #require(
            store.historicalSearchPage
        )
        let acceptedFilter = try #require(
            store.historicalSearchFilterSnapshot
        )
        let acceptedComparison = try #require(
            store.historicalComparison
        )
        let paginationFailure = try #require(
            store
                .historicalPaginationFailureMessage
        )
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )

        await store.rebuildHistoricalIndex(
            using: sceneState
        )

        #expect(
            workflow.historicalRebuildCallCount
                == 1
        )
        #expect(
            store.historicalSearchPage
                == acceptedPage
        )
        #expect(
            store.historicalSearchFilterSnapshot
                == acceptedFilter
        )
        #expect(
            store.historicalComparison
                == acceptedComparison
        )
        #expect(
            store
                .historicalPaginationFailureMessage
                == paginationFailure
        )
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            sceneState
                .selectedCurrentHistoryRevisionID
                == current.position.revision
                .revisionID
        )
        #expect(
            sceneState
                .selectedPriorHistoryRevisionID
                == historical.position.revision
                .revisionID
        )

        await store.rebuildHistoricalIndex(
            using: sceneState
        )
        await pollGate.waitUntilEntered()

        #expect(
            workflow.historicalRebuildCallCount
                == 2
        )
        #expect(store.historicalSearchPage == nil)
        #expect(store.historicalComparison == nil)
        #expect(
            store
                .historicalPaginationFailureMessage
                == nil
        )
        #expect(
            sceneState
                .selectedCurrentHistoryRevisionID
                == nil
        )
        #expect(
            sceneState
                .selectedPriorHistoryRevisionID
                == nil
        )

        await pollGate.release()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-rebuild-preservation-workspace-b"
            ),
            using: sceneState
        )
    }

    @Test @MainActor
    func paginationFailurePreservesPrefixComparisonAndRetryCapability()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 11
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 12
            )
        let next =
            try makeFeatureHistoricalResult(
                suffix: 13
            )
        let firstPage = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor:
                current.cursor(
                    indexGeneration: 7
                ),
            indexGeneration: 7
        )
        let nextPage = HistoricalSearchPage(
            results: [next],
            nextCursor: nil,
            indexGeneration: 7
        )
        let comparison =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 2
            )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalSearchFailureCall: 2,
                historicalSearchPages: [
                    firstPage,
                    HistoricalSearchPage(
                        results: [],
                        nextCursor: nil,
                        indexGeneration: 7
                    ),
                    nextPage
                ],
                historicalComparisonResult:
                    comparison,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-pagination-retry-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        #expect(
            store.historicalComparison
                == comparison
        )

        await store.loadMoreHistoricalResults(
            using: sceneState
        )

        #expect(
            store.historicalSearchPage
                == firstPage
        )
        #expect(
            store.historicalComparison
                == comparison
        )
        #expect(
            store
                .historicalPaginationFailureMessage
                != nil
        )
        #expect(
            store.historicalSearchFailureMessage
                == nil
        )
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )

        await store.loadMoreHistoricalResults(
            using: sceneState
        )

        #expect(
            workflow.historicalSearchCallCount
                == 3
        )
        #expect(
            store.historicalSearchPage
                == HistoricalSearchPage(
                    results: [
                        historical,
                        current,
                        next
                    ],
                    nextCursor: nil,
                    indexGeneration: 7
                )
        )
        #expect(
            store.historicalComparison
                == comparison
        )
        #expect(
            store
                .historicalPaginationFailureMessage
                == nil
        )
        #expect(
            store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
    }

    @Test @MainActor
    func changingHistoryFiltersStalesTheBundleAndClearsComparison()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 14
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 15
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let comparison =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 3
            )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    comparison,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-history-filter-change-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        sceneState.confirmHistoricalChange =
            true

        sceneState.historyTopic =
            "changed after search"
        store.historicalFilterDidChange(
            using: sceneState
        )

        #expect(
            store.historicalSearchPage == page
        )
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalSearchPageStaleReason
                != nil
        )
        #expect(
            store.historicalComparison == nil
        )
        #expect(
            !sceneState.confirmHistoricalChange
        )

        sceneState.historyTopic = ""
        store.historicalFilterDidChange(
            using: sceneState
        )

        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(
            store.historicalSearchPageStaleReason
                != nil
        )
        #expect(
            store.historicalComparison == nil
        )
    }

    @Test @MainActor
    func completedManualAndRebuildSearchesRejectFilterRevisionDrift()
        async throws
    {
        let page = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 16
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )

        let manualGate = AsyncGate()
        let manualWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    manualGate,
                historicalSearchGateCall: 1,
                historicalSearchPages: [
                    page
                ],
                historicalIndexAvailability:
                    .ready
            )
        let manualStore =
            MediaReviewStore(
                workflow: manualWorkflow
            )
        let manualScene =
            MediaReviewSceneState()
        await manualStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-manual-filter-revision-workspace"
            ),
            using: manualScene
        )
        manualScene.historyActorOrCountry =
            "Captured actor"
        let manualSearch = Task {
            await manualStore
                .searchMeetingHistory(
                    using: manualScene
                )
        }
        await manualGate.waitUntilEntered()
        manualScene.historyActorOrCountry =
            "Transient actor"
        manualStore.historicalFilterDidChange(
            using: manualScene
        )
        manualScene.historyActorOrCountry =
            "Captured actor"
        manualStore.historicalFilterDidChange(
            using: manualScene
        )
        await manualGate.release()
        await manualSearch.value

        #expect(
            manualWorkflow
                .lastHistoricalSearchQuery?
                .actorOrCountry
                == "Captured actor"
        )
        #expect(
            manualStore.historicalSearchPage
                == nil
        )
        #expect(
            manualStore
                .historicalSearchFailureMessage?
                .contains(
                    "filters changed"
                ) == true
        )

        let rebuildSearchGate = AsyncGate()
        let rebuildWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    rebuildSearchGate,
                historicalSearchGateCall: 1,
                seededReviewState: true,
                historicalSearchPages: [
                    page
                ],
                historicalIndexAvailability:
                    .ready
            )
        let rebuildStore =
            MediaReviewStore(
                workflow: rebuildWorkflow
            )
        let rebuildScene =
            MediaReviewSceneState()
        await rebuildStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-rebuild-filter-revision-workspace"
            ),
            using: rebuildScene
        )
        rebuildScene.historyActorOrCountry =
            "Captured rebuild actor"
        await rebuildStore.rebuildHistoricalIndex(
            using: rebuildScene
        )
        await rebuildSearchGate.waitUntilEntered()
        rebuildScene.historyActorOrCountry =
            "Transient rebuild actor"
        rebuildStore.historicalFilterDidChange(
            using: rebuildScene
        )
        rebuildScene.historyActorOrCountry =
            "Captured rebuild actor"
        rebuildStore.historicalFilterDidChange(
            using: rebuildScene
        )
        await rebuildSearchGate.release()
        for _ in 0..<200
            where rebuildStore
                .historicalIndexFinalizationIsWorking
        {
            await Task.yield()
        }

        #expect(
            rebuildWorkflow
                .lastHistoricalSearchQuery?
                .actorOrCountry
                == "Captured rebuild actor"
        )
        #expect(
            rebuildStore.historicalSearchPage
                == nil
        )
        #expect(
            rebuildStore
                .historicalSearchFailureMessage?
                .contains(
                    "filters changed"
                ) == true
        )
        #expect(
            !rebuildStore
                .historicalIndexFinalizationIsWorking
        )
    }

    @Test @MainActor
    func cancelledReturnedComparisonAndConfirmationReconcileInSameWorkspace()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 16
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 17
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let candidate =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 5
            )
        let confirmed =
            try makeFeatureConfirmedHistoricalComparison(
                candidate: candidate,
                suffix: 5
            )
        let comparisonGate = AsyncGate()
        let confirmationGate = AsyncGate()
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalComparisonGate:
                    comparisonGate,
                historicalConfirmationGate:
                    confirmationGate,
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    candidate,
                historicalConfirmedComparisonResult:
                    confirmed,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-cancelled-comparison-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )

        let cancelledComparison = Task {
            await store
                .compareSelectedHistoricalPositions(
                    using: sceneState
                )
        }
        await comparisonGate.waitUntilEntered()
        cancelledComparison.cancel()
        await comparisonGate.release()
        await cancelledComparison.value

        #expect(
            store.historicalComparison
                == candidate
        )
        #expect(
            workflow.historicalCompareCallCount
                == 1
        )
        #expect(
            !store.historicalComparisonIsWorking
        )

        sceneState.confirmHistoricalChange =
            true
        let cancelledConfirmation = Task {
            await store.confirmHistoricalChange(
                using: sceneState
            )
        }
        await confirmationGate.waitUntilEntered()
        cancelledConfirmation.cancel()
        await confirmationGate.release()
        await cancelledConfirmation.value

        #expect(
            store.historicalComparison
                == confirmed
        )
        #expect(
            workflow.historicalConfirmCallCount
                == 1
        )
        #expect(
            !sceneState.confirmHistoricalChange
        )
        #expect(
            !store.historicalComparisonIsWorking
        )
        #expect(store.safeErrorMessage == nil)
    }

    @Test @MainActor
    func returnedComparisonInvalidatesAChangedVisibleContext()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 16
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 17
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let candidate =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 6
            )
        let comparisonGate = AsyncGate()
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalComparisonGate:
                    comparisonGate,
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    candidate,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-changed-comparison-context-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        let comparisonTask = Task {
            await store
                .compareSelectedHistoricalPositions(
                    using: sceneState
                )
        }
        await comparisonGate.waitUntilEntered()

        sceneState.historyTopic =
            "changed during comparison"
        store.historicalFilterDidChange(
            using: sceneState
        )
        await comparisonGate.release()
        await comparisonTask.value

        #expect(
            store.historicalComparison == nil
        )
        #expect(
            store.historicalSearchPageStaleReason?
                .contains(
                    "comparison was saved locally"
                ) == true
        )
        #expect(
            store.safeErrorMessage?
                .contains(
                    "comparison was saved locally"
                ) == true
        )
        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
    }

    @Test @MainActor
    func returnedConfirmationInvalidatesAChangedVisibleContext()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 16
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 17
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let candidate =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 7
            )
        let confirmed =
            try makeFeatureConfirmedHistoricalComparison(
                candidate: candidate,
                suffix: 7
            )
        let confirmationGate = AsyncGate()
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalConfirmationGate:
                    confirmationGate,
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    candidate,
                historicalConfirmedComparisonResult:
                    confirmed,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-changed-confirmation-context-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        sceneState.confirmHistoricalChange =
            true
        let confirmationTask = Task {
            await store.confirmHistoricalChange(
                using: sceneState
            )
        }
        await confirmationGate.waitUntilEntered()

        sceneState.historyMeetingType =
            "changed during confirmation"
        store.historicalFilterDidChange(
            using: sceneState
        )
        await confirmationGate.release()
        await confirmationTask.value

        #expect(
            store.historicalComparison == nil
        )
        #expect(
            store.historicalSearchPageStaleReason?
                .contains(
                    "confirmation was saved locally"
                ) == true
        )
        #expect(
            store.safeErrorMessage?
                .contains(
                    "confirmation was saved locally"
                ) == true
        )
        #expect(
            !sceneState.confirmHistoricalChange
        )
        #expect(
            workflow.historicalConfirmCallCount
                == 1
        )
    }

    @Test @MainActor
    func staleResultBundleRejectsDirectSelectionComparisonAndConfirmation()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 14
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 15
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let comparison =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 3
            )
        let workflow =
            try MediaReviewWorkflowProbe(
                historicalSearchPages: [
                    page
                ],
                historicalIndexFailureCall: 1,
                historicalComparisonResult:
                    comparison,
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-direct-history-guard-workspace"
            ),
            using: sceneState
        )
        await store.searchMeetingHistory(
            using: sceneState
        )
        store.selectHistoricalCurrentRevision(
            current.position.revision.revisionID,
            using: sceneState
        )
        store.selectHistoricalPreviousRevision(
            historical.position.revision.revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        #expect(
            workflow.historicalCompareCallCount
                == 1
        )
        #expect(
            store.historicalComparison
                == comparison
        )
        sceneState.confirmHistoricalChange =
            true

        await store.loadHistoricalReview(
            using: sceneState
        )

        #expect(
            !store.historicalResultsAreCurrent(
                using: sceneState
            )
        )
        #expect(store.historicalComparison == nil)
        #expect(
            !sceneState.confirmHistoricalChange
        )

        store.selectHistoricalCurrentRevision(
            historical.position.revision
                .revisionID,
            using: sceneState
        )
        await store
            .compareSelectedHistoricalPositions(
                using: sceneState
            )
        await store.confirmHistoricalChange(
            using: sceneState
        )

        #expect(
            sceneState
                .selectedCurrentHistoryRevisionID
                == current.position.revision
                .revisionID
        )
        #expect(
            workflow.historicalCompareCallCount
                == 1
        )
        #expect(
            workflow.historicalConfirmCallCount
                == 0
        )
    }

    @Test @MainActor
    func terminalHistoryPollFinalizationBlocksCompetingManualLoads()
        async throws
    {
        let initialPage = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 20
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let rebuiltPage = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 21
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let pollGate = AsyncGate()
        let statusGate = AsyncGate()
        let workflow =
            try MediaReviewWorkflowProbe(
                pollGate:
                    pollGate,
                historicalIndexGate:
                    statusGate,
                historicalIndexGateCall: 2,
                seededReviewState: true,
                historicalSearchPages: [
                    initialPage,
                    rebuiltPage
                ],
                historicalIndexAvailability:
                    .ready
            )
        let store = MediaReviewStore(
            workflow: workflow
        )
        let sceneState =
            MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-terminal-finalization-workspace"
            ),
            using: sceneState
        )
        sceneState.historyActorOrCountry =
            "Captured before rebuild"
        await store.loadHistoricalReview(
            using: sceneState
        )
        #expect(
            store.historicalSearchPage
                == initialPage
        )

        await store.rebuildHistoricalIndex(
            using: sceneState
        )
        await pollGate.waitUntilEntered()

        #expect(
            store.historicalIndexJob?.state
                == .succeeded
        )
        #expect(
            store
                .historicalIndexFinalizationIsWorking
        )
        #expect(
            store.historicalControlsAreBusy
        )
        #expect(
            HistoricalReviewPresentation
                .indexState(
                    status:
                        store.historicalIndex,
                    job:
                        store.historicalIndexJob,
                    isLoading:
                        store
                        .historicalIndexIsLoading,
                    failureMessage:
                        store
                        .historicalIndexFailureMessage
                ) == .loading
        )

        await store.searchMeetingHistory(
            using: sceneState
        )
        await store.loadHistoricalReview(
            using: sceneState
        )

        #expect(
            workflow.historicalIndexCallCount
                == 1
        )
        #expect(
            workflow.historicalSearchCallCount
                == 1
        )

        await pollGate.release()
        await statusGate.waitUntilEntered()

        #expect(
            store.historicalIndexJob?.state
                == .succeeded
        )
        #expect(
            store
                .historicalIndexFinalizationIsWorking
        )
        #expect(
            store.historicalControlsAreBusy
        )
        #expect(
            HistoricalReviewPresentation
                .indexState(
                    status:
                        store.historicalIndex,
                    job:
                        store.historicalIndexJob,
                    isLoading:
                        store
                        .historicalIndexIsLoading,
                    failureMessage:
                        store
                        .historicalIndexFailureMessage
                ) == .loading
        )

        await store.searchMeetingHistory(
            using: sceneState
        )
        await store.loadHistoricalReview(
            using: sceneState
        )

        #expect(
            workflow.historicalIndexCallCount
                == 2
        )
        #expect(
            workflow.historicalSearchCallCount
                == 1
        )
        #expect(
            store.historicalIndexJob?.state
                == .succeeded
        )

        await statusGate.release()
        for _ in 0..<200
            where store
                .historicalIndexFinalizationIsWorking
        {
            await Task.yield()
        }

        #expect(
            !store
                .historicalIndexFinalizationIsWorking
        )
        #expect(
            workflow.historicalIndexCallCount
                == 2
        )
        #expect(
            workflow.historicalSearchCallCount
                == 2
        )
        #expect(
            store.historicalSearchPage
                == rebuiltPage
        )
        #expect(
            HistoricalReviewPresentation
                .indexState(
                    status:
                        store.historicalIndex,
                    job:
                        store.historicalIndexJob,
                    isLoading:
                        store
                        .historicalIndexIsLoading,
                    failureMessage:
                        store
                        .historicalIndexFailureMessage
                ) == .ready
        )
        #expect(
            workflow.lastHistoricalSearchQuery?
                .actorOrCountry
                == "Captured before rebuild"
        )
    }

    @Test @MainActor
    func terminalHistoryPollKeepsStatusAndAutomaticPageGenerationHonest()
        async throws
    {
        let page8 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 16
                )
            ],
            nextCursor: nil,
            indexGeneration: 8
        )
        let matchingWorkflow =
            try MediaReviewWorkflowProbe(
                seededReviewState: true,
                historicalSearchPages: [
                    page8
                ],
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 8
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let matchingStore =
            MediaReviewStore(
                workflow: matchingWorkflow
            )
        let matchingScene =
            MediaReviewSceneState()
        await matchingStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-matching-poll-workspace"
                ),
                using: matchingScene
            )
        await matchingStore
            .rebuildHistoricalIndex(
                using: matchingScene
            )
        for _ in 0..<200
            where matchingWorkflow
                .historicalSearchCallCount == 0
        {
            await Task.yield()
        }

        #expect(
            matchingStore.historicalIndexJob?
                .state == .succeeded
        )
        #expect(
            matchingStore.historicalIndex?
                .generation == 8
        )
        #expect(
            matchingStore.historicalSearchPage
                == page8
        )
        #expect(
            matchingStore
                .historicalIndexFailureMessage
                == nil
        )
        #expect(
            matchingStore.historicalResultsAreCurrent(
                using: matchingScene
            )
        )

        let mismatchingWorkflow =
            try MediaReviewWorkflowProbe(
                seededReviewState: true,
                historicalSearchPages: [
                    page8
                ],
                historicalIndexStatuses: [
                    makeFeatureHistoricalIndexStatus(
                        generation: 7
                    )
                ],
                historicalIndexAvailability:
                    .ready
            )
        let mismatchingStore =
            MediaReviewStore(
                workflow: mismatchingWorkflow
            )
        let mismatchingScene =
            MediaReviewSceneState()
        await mismatchingStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-mismatching-poll-workspace"
                ),
                using: mismatchingScene
            )
        await mismatchingStore
            .rebuildHistoricalIndex(
                using: mismatchingScene
            )
        for _ in 0..<200
            where mismatchingWorkflow
                .historicalSearchCallCount == 0
        {
            await Task.yield()
        }

        #expect(
            mismatchingStore.historicalIndex?
                .generation == 7
        )
        #expect(
            mismatchingStore
                .historicalSearchPage == page8
        )
        #expect(
            mismatchingStore
                .historicalIndexFailureMessage
                != nil
        )
        #expect(
            mismatchingStore
                .historicalResultsAreCurrent(
                    using: mismatchingScene
                )
        )
    }

    @Test @MainActor
    func lateWorkspaceAHistoryOperationsCannotCommitIntoWorkspaceB()
        async throws
    {
        let firstResult =
            try makeFeatureHistoricalResult(
                suffix: 17
            )
        let nextResult =
            try makeFeatureHistoricalResult(
                suffix: 18
            )
        let firstPage = HistoricalSearchPage(
            results: [firstResult],
            nextCursor:
                firstResult.cursor(
                    indexGeneration: 7
                ),
            indexGeneration: 7
        )
        let nextPage = HistoricalSearchPage(
            results: [nextResult],
            nextCursor: nil,
            indexGeneration: 7
        )

        let indexGate = AsyncGate()
        let workspaceBSearchGate =
            AsyncGate()
        let loadWorkflow =
            try MediaReviewWorkflowProbe(
                historicalIndexGate: indexGate,
                historicalSearchGate:
                    workspaceBSearchGate,
                historicalSearchGateCall: 1,
                historicalSearchPages: [
                    firstPage
                ],
                historicalIndexAvailability:
                    .ready
            )
        let loadStore = MediaReviewStore(
            workflow: loadWorkflow
        )
        let loadScene =
            MediaReviewSceneState()
        await loadStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-load-workspace-a"
            ),
            using: loadScene
        )
        let lateLoad = Task {
            await loadStore
                .loadHistoricalReview(
                    using: loadScene
                )
        }
        await indexGate.waitUntilEntered()
        await loadStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-load-workspace-b"
            ),
            using: loadScene
        )
        let workspaceBSearch = Task {
            await loadStore
                .searchMeetingHistory(
                    using: loadScene
                )
        }
        await workspaceBSearchGate
            .waitUntilEntered()
        await indexGate.release()
        await lateLoad.value

        #expect(
            loadStore.workspace?.displayName
                == "Synthetic Workspace B"
        )
        #expect(loadStore.historicalIndex == nil)
        #expect(loadStore.historicalSearchPage == nil)
        #expect(
            loadStore.historicalSearchIsLoading
        )
        #expect(
            loadStore.historicalIndexFailureMessage
                == nil
        )
        await workspaceBSearchGate.release()
        await workspaceBSearch.value
        #expect(
            loadStore.historicalSearchPage
                == firstPage
        )

        let searchGate = AsyncGate()
        let searchWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    searchGate,
                historicalSearchGateCall: 1,
                historicalSearchPages: [
                    firstPage
                ],
                historicalIndexAvailability:
                    .ready
            )
        let searchStore = MediaReviewStore(
            workflow: searchWorkflow
        )
        let searchScene =
            MediaReviewSceneState()
        await searchStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-search-workspace-a"
                ),
                using: searchScene
            )
        let lateSearch = Task {
            await searchStore
                .searchMeetingHistory(
                    using: searchScene
                )
        }
        await searchGate.waitUntilEntered()
        await searchStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-search-workspace-b"
                ),
                using: searchScene
            )
        await searchGate.release()
        await lateSearch.value
        #expect(
            searchStore.workspace?.displayName
                == "Synthetic Workspace B"
        )
        #expect(
            searchStore.historicalSearchPage
                == nil
        )
        #expect(
            searchStore
                .historicalSearchFailureMessage
                == nil
        )

        let paginationGate = AsyncGate()
        let paginationWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    paginationGate,
                historicalSearchGateCall: 2,
                historicalSearchPages: [
                    firstPage,
                    nextPage
                ],
                historicalIndexAvailability:
                    .ready
            )
        let paginationStore =
            MediaReviewStore(
                workflow:
                    paginationWorkflow
            )
        let paginationScene =
            MediaReviewSceneState()
        await paginationStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-pagination-workspace-a"
                ),
                using: paginationScene
            )
        await paginationStore
            .searchMeetingHistory(
                using: paginationScene
            )
        let latePagination = Task {
            await paginationStore
                .loadMoreHistoricalResults(
                    using: paginationScene
                )
        }
        await paginationGate.waitUntilEntered()
        await paginationStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-pagination-workspace-b"
                ),
                using: paginationScene
            )
        await paginationGate.release()
        await latePagination.value
        #expect(
            paginationStore.workspace?
                .displayName
                == "Synthetic Workspace B"
        )
        #expect(
            paginationStore
                .historicalSearchPage == nil
        )
        #expect(
            paginationStore
                .historicalPaginationFailureMessage
                == nil
        )

        let rebuildGate = AsyncGate()
        let rebuildWorkflow =
            try MediaReviewWorkflowProbe(
                historicalRebuildGate:
                    rebuildGate,
                historicalIndexAvailability:
                    .ready
            )
        let rebuildStore = MediaReviewStore(
            workflow: rebuildWorkflow
        )
        let rebuildScene =
            MediaReviewSceneState()
        await rebuildStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-rebuild-workspace-a"
                ),
                using: rebuildScene
            )
        let lateRebuild = Task {
            await rebuildStore
                .rebuildHistoricalIndex(
                    using: rebuildScene
                )
        }
        await rebuildGate.waitUntilEntered()
        await rebuildStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-rebuild-workspace-b"
                ),
                using: rebuildScene
            )
        await rebuildGate.release()
        await lateRebuild.value
        #expect(
            rebuildStore.workspace?
                .displayName
                == "Synthetic Workspace B"
        )
        #expect(
            rebuildStore.historicalIndexJob
                == nil
        )
        #expect(
            !rebuildStore
                .historicalIndexRebuildIsEnqueuing
        )

        let pollGate = AsyncGate()
        let pollWorkflow =
            try MediaReviewWorkflowProbe(
                pollGate: pollGate,
                historicalRebuildCompletesImmediately:
                    false
            )
        let pollStore = MediaReviewStore(
            workflow: pollWorkflow
        )
        let pollScene =
            MediaReviewSceneState()
        await pollStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-poll-workspace-a"
            ),
            using: pollScene
        )
        await pollStore
            .rebuildHistoricalIndex(
                using: pollScene
            )
        await pollGate.waitUntilEntered()
        await pollStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-poll-workspace-b"
            ),
            using: pollScene
        )
        await pollGate.release()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(
            pollStore.workspace?.displayName
                == "Synthetic Workspace B"
        )
        #expect(pollStore.historicalIndex == nil)
        #expect(
            pollStore.historicalIndexJob == nil
        )
        #expect(
            pollStore.historicalSearchPage == nil
        )
        #expect(
            pollStore.historicalIndexFailureMessage
                == nil
        )
    }

    @Test @MainActor
    func lateWorkspaceAComparisonSideEffectsNeverAttachToWorkspaceB()
        async throws
    {
        let historical =
            try makeFeatureHistoricalResult(
                suffix: 18
            )
        let current =
            try makeFeatureHistoricalResult(
                suffix: 19
            )
        let page = HistoricalSearchPage(
            results: [
                historical,
                current
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let candidate =
            try makeFeatureHistoricalComparison(
                current: current,
                historical: historical,
                suffix: 8
            )
        let confirmed =
            try makeFeatureConfirmedHistoricalComparison(
                candidate: candidate,
                suffix: 8
            )

        let comparisonGate = AsyncGate()
        let comparisonWorkflow =
            try MediaReviewWorkflowProbe(
                historicalComparisonGate:
                    comparisonGate,
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    candidate,
                historicalIndexAvailability:
                    .ready
            )
        let comparisonStore =
            MediaReviewStore(
                workflow:
                    comparisonWorkflow
            )
        let comparisonScene =
            MediaReviewSceneState()
        await comparisonStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-comparison-workspace-a"
            ),
            using: comparisonScene
        )
        await comparisonStore.searchMeetingHistory(
            using: comparisonScene
        )
        comparisonStore
            .selectHistoricalCurrentRevision(
                current.position.revision.revisionID,
                using: comparisonScene
            )
        comparisonStore
            .selectHistoricalPreviousRevision(
                historical.position.revision.revisionID,
                using: comparisonScene
            )
        let lateComparison = Task {
            await comparisonStore
                .compareSelectedHistoricalPositions(
                    using: comparisonScene
                )
        }
        await comparisonGate.waitUntilEntered()
        await comparisonStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-late-comparison-workspace-b"
            ),
            using: comparisonScene
        )
        await comparisonGate.release()
        await lateComparison.value

        #expect(
            comparisonStore.workspace?
                .displayName
                == "Synthetic Workspace B"
        )
        #expect(
            comparisonStore
                .historicalSearchPage == nil
        )
        #expect(
            comparisonStore
                .historicalComparison == nil
        )
        #expect(
            comparisonStore.safeErrorMessage
                == nil
        )

        let confirmationGate = AsyncGate()
        let confirmationWorkflow =
            try MediaReviewWorkflowProbe(
                historicalConfirmationGate:
                    confirmationGate,
                historicalSearchPages: [
                    page
                ],
                historicalComparisonResult:
                    candidate,
                historicalConfirmedComparisonResult:
                    confirmed,
                historicalIndexAvailability:
                    .ready
            )
        let confirmationStore =
            MediaReviewStore(
                workflow:
                    confirmationWorkflow
            )
        let confirmationScene =
            MediaReviewSceneState()
        await confirmationStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-confirmation-workspace-a"
                ),
                using: confirmationScene
            )
        await confirmationStore
            .searchMeetingHistory(
                using: confirmationScene
            )
        confirmationStore
            .selectHistoricalCurrentRevision(
                current.position.revision.revisionID,
                using: confirmationScene
            )
        confirmationStore
            .selectHistoricalPreviousRevision(
                historical.position.revision.revisionID,
                using: confirmationScene
            )
        await confirmationStore
            .compareSelectedHistoricalPositions(
                using: confirmationScene
            )
        let lateConfirmation = Task {
            await confirmationStore
                .confirmHistoricalChange(
                    using: confirmationScene
                )
        }
        await confirmationGate.waitUntilEntered()
        await confirmationStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-late-confirmation-workspace-b"
                ),
                using: confirmationScene
            )
        await confirmationGate.release()
        await lateConfirmation.value

        #expect(
            confirmationStore.workspace?
                .displayName
                == "Synthetic Workspace B"
        )
        #expect(
            confirmationStore
                .historicalSearchPage == nil
        )
        #expect(
            confirmationStore
                .historicalComparison == nil
        )
        #expect(
            confirmationStore.safeErrorMessage
                == nil
        )
    }

    @Test @MainActor
    func cancelledSearchPreservesTheBundleButReturnedRebuildReconciles()
        async throws
    {
        let page7 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 19
                )
            ],
            nextCursor: nil,
            indexGeneration: 7
        )
        let page8 = HistoricalSearchPage(
            results: [
                try makeFeatureHistoricalResult(
                    suffix: 20
                )
            ],
            nextCursor: nil,
            indexGeneration: 8
        )
        let searchGate = AsyncGate()
        let searchWorkflow =
            try MediaReviewWorkflowProbe(
                historicalSearchGate:
                    searchGate,
                historicalSearchGateCall: 2,
                historicalSearchPages: [
                    page7,
                    page8
                ],
                historicalIndexAvailability:
                    .ready
            )
        let searchStore = MediaReviewStore(
            workflow: searchWorkflow
        )
        let searchScene =
            MediaReviewSceneState()
        await searchStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-cancelled-search-workspace"
                ),
                using: searchScene
            )
        await searchStore.searchMeetingHistory(
            using: searchScene
        )
        let cancelledSearch = Task {
            await searchStore
                .searchMeetingHistory(
                    using: searchScene
                )
        }
        await searchGate.waitUntilEntered()
        cancelledSearch.cancel()
        await searchGate.release()
        await cancelledSearch.value

        #expect(
            searchStore.historicalSearchPage
                == page7
        )
        #expect(
            searchStore.historicalResultsAreCurrent(
                using: searchScene
            )
        )
        #expect(
            searchStore
                .historicalSearchFailureMessage
                == nil
        )
        #expect(
            !searchStore
                .historicalSearchIsLoading
        )

        let rebuildGate = AsyncGate()
        let pollGate = AsyncGate()
        let rebuildWorkflow =
            try MediaReviewWorkflowProbe(
                pollGate:
                    pollGate,
                historicalRebuildGate:
                    rebuildGate,
                historicalSearchPages: [
                    page7
                ],
                historicalIndexAvailability:
                    .ready,
                historicalRebuildCompletesImmediately:
                    false
            )
        let rebuildStore = MediaReviewStore(
            workflow: rebuildWorkflow
        )
        let rebuildScene =
            MediaReviewSceneState()
        await rebuildStore
            .openOrCreateWorkspace(
                at: URL(
                    fileURLWithPath:
                        "/synthetic-cancelled-rebuild-workspace"
                ),
                using: rebuildScene
            )
        await rebuildStore
            .searchMeetingHistory(
                using: rebuildScene
            )
        rebuildStore
            .selectHistoricalCurrentRevision(
                page7.results[0]
                    .position.revision.revisionID,
                using: rebuildScene
            )
        let cancelledRebuild = Task {
            await rebuildStore
                .rebuildHistoricalIndex(
                    using: rebuildScene
                )
        }
        await rebuildGate.waitUntilEntered()
        cancelledRebuild.cancel()
        await rebuildGate.release()
        await cancelledRebuild.value
        await pollGate.waitUntilEntered()

        #expect(
            rebuildStore.historicalSearchPage
                == nil
        )
        #expect(
            !rebuildStore.historicalResultsAreCurrent(
                using: rebuildScene
            )
        )
        #expect(
            rebuildStore.historicalIndexJob?.state
                == .running
        )
        #expect(
            rebuildScene
                .selectedCurrentHistoryRevisionID
                == nil
        )
        #expect(
            !rebuildStore
                .historicalIndexRebuildIsEnqueuing
        )

        await pollGate.release()
        await rebuildStore.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-cancelled-rebuild-workspace-b"
            ),
            using: rebuildScene
        )
    }

    @Test @MainActor
    func failedHistoryPollRetriesTheSameJobWithoutDuplicateRebuild()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true,
            jobReviewFailureCall: 1,
            historicalRebuildCompletesImmediately:
                false
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-poll-retry-workspace"
            ),
            using: sceneState
        )

        await store.rebuildHistoricalIndex(
            using: sceneState
        )
        for _ in 0..<100
            where store
                .historicalIndexFailureMessage == nil
        {
            await Task.yield()
        }

        #expect(
            store.historicalIndexJob?.state
                == .running
        )
        #expect(
            store.historicalIndexFailureMessage
                != nil
        )
        #expect(workflow.historicalRebuildCallCount == 1)
        #expect(
            HistoricalReviewPresentation.indexState(
                status: store.historicalIndex,
                job: store.historicalIndexJob,
                isLoading: false,
                failureMessage:
                    store
                    .historicalIndexFailureMessage
            ) == .failed(
                "Meeting History index status is temporarily unavailable."
            )
        )

        await store.loadHistoricalReview(
            using: sceneState
        )
        for _ in 0..<100
            where store.historicalIndexJob?.state
                != .succeeded
        {
            await Task.yield()
        }

        #expect(
            store.historicalIndexJob?.state
                == .succeeded
        )
        #expect(
            store.historicalIndexFailureMessage == nil
        )
        #expect(workflow.jobReviewCallCount == 2)
        #expect(workflow.historicalRebuildCallCount == 1)
    }

    @Test @MainActor
    func invalidSearchDatesDoNotBlockAnIndependentIndexRebuild()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            seededReviewState: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-invalid-filter-workspace"
            ),
            using: sceneState
        )
        sceneState.historyStartDate = "not-a-date"

        await store.rebuildHistoricalIndex(
            using: sceneState
        )
        for _ in 0..<20 { await Task.yield() }

        #expect(workflow.historicalRebuildCallCount == 1)
        #expect(workflow.historicalSearchCallCount == 0)
        #expect(store.historicalIndexJob?.state == .succeeded)
        #expect(store.historicalIndex != nil)
        #expect(
            store.historicalIndexFailureMessage == nil
        )
        #expect(
            store.historicalSearchFailureMessage != nil
        )
    }

    @Test @MainActor
    func successfulHistorySearchClearsSelectionsMissingFromTheNewPage()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-selection-workspace"
            ),
            using: sceneState
        )
        sceneState.selectedCurrentHistoryRevisionID =
            featureID(7_001, RevisionID.self)
        sceneState.selectedPriorHistoryRevisionID =
            featureID(7_002, RevisionID.self)

        await store.searchMeetingHistory(
            using: sceneState
        )

        #expect(
            sceneState
                .selectedCurrentHistoryRevisionID == nil
        )
        #expect(
            sceneState
                .selectedPriorHistoryRevisionID == nil
        )
    }

    @Test @MainActor
    func settingsPreferenceEditorPreservesVersionedRepositorySemantics()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe()
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        let editorState = LearnedPreferenceEditorState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-preference-workspace"
            ),
            using: sceneState
        )
        await store.loadLearnedPreferences()

        editorState.kind = .briefingLength
        editorState.value = "800"
        await store.saveLearnedPreference(
            using: editorState
        )

        let created = try #require(
            store.learnedPreferences?
                .preferences.first
        )
        #expect(created.value == .briefingLength(800))
        #expect(created.version == 1)
        #expect(
            created.sourceAction
                == "explicit-history-preferences-form"
        )
        #expect(
            workflow.lastPreferenceExpectedVersion
                == nil
        )
        #expect(editorState.value.isEmpty)
        #expect(editorState.editingPreferenceID == nil)

        store.editLearnedPreference(
            created,
            using: editorState
        )
        editorState.value = "900"
        await store.saveLearnedPreference(
            using: editorState
        )

        let edited = try #require(
            store.learnedPreferences?
                .preferences.first
        )
        #expect(
            edited.preferenceID
                == created.preferenceID
        )
        #expect(edited.value == .briefingLength(900))
        #expect(edited.version == 2)
        #expect(
            workflow.lastPreferenceExpectedVersion
                == 1
        )
        #expect(workflow.preferenceSaveCallCount == 2)
    }

    @Test @MainActor
    func settingsPreferenceFailureStaysOutOfTheMainWindowErrorChannel()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            learnedPreferenceFailureCall: 1
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-preference-failure-workspace"
            ),
            using: sceneState
        )

        await store.loadLearnedPreferences()

        #expect(
            store.learnedPreferencesFailureMessage
                != nil
        )
        #expect(store.safeErrorMessage == nil)
    }

    @Test @MainActor
    func failedHistoryRefreshRetainsOnlyExplicitlyStalePriorResults()
        async throws
    {
        let workflow = try MediaReviewWorkflowProbe(
            historicalSearchFailureCall: 2
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-history-failure-workspace"
            ),
            using: sceneState
        )

        sceneState.historyTopic = "first"
        await store.searchMeetingHistory(
            using: sceneState
        )
        let firstPage = try #require(
            store.historicalSearchPage
        )
        let firstFilter = try #require(
            store.historicalSearchFilterSnapshot
        )

        sceneState.historyTopic = "second"
        await store.searchMeetingHistory(
            using: sceneState
        )

        #expect(
            store.historicalSearchPage == firstPage
        )
        #expect(
            store.historicalSearchFilterSnapshot
                == firstFilter
        )
        #expect(
            store.historicalSearchFailureMessage
                != nil
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: store.historicalSearchPage,
                isLoading:
                    store.historicalSearchIsLoading,
                searchFailureMessage:
                    store
                    .historicalSearchFailureMessage,
                pageStaleReason:
                    store
                    .historicalSearchPageStaleReason,
                lastSuccessfulFilter:
                    store
                    .historicalSearchFilterSnapshot,
                currentFilter:
                    HistoricalSearchFilterSnapshot(
                        sceneState: sceneState
                    )
            ) == .staleResults(
                count: 0,
                generation: 7,
                reason:
                    "The latest search failed. These are the last successful authorized results. The local operation could not be completed."
            )
        )
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

    @Test @MainActor
    func successfulRecordingStartConsumesTheSessionAcknowledgement()
        async throws
    {
        let setup = RecordingSetupReview(
            capability: CaptureCapabilitySnapshot(
                microphonePermission: .authorized,
                applicationAudioAvailable: true,
                systemPickerAvailable: true,
                checkedAt: featureInstant(1_950_000_000_002)
            ),
            microphones: []
        )
        let completed = RecordingSessionReview(
            sessionID: featureID(81, RecordingSessionID.self),
            jobID: featureID(82, JobID.self),
            state: .completed,
            stateVersion: 1,
            activeTrackKinds: [.applicationAudio],
            durableThroughNanoseconds: 5_000_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
        let workflow = try MediaReviewWorkflowProbe(
            recordingSetupReview: setup,
            startedRecordingReview: completed
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-recording-workspace"),
            using: sceneState
        )
        sceneState.meetingTitle = "Synthetic recording"
        sceneState.captureMode = .applicationAudioOnly
        sceneState.recordingAcknowledged = true

        await store.startRecording(using: sceneState)

        #expect(workflow.recordingStartCallCount == 1)
        #expect(store.recordingSession?.state == .completed)
        #expect(!sceneState.recordingAcknowledged)
    }

    @Test @MainActor
    func recordingStopRemainsAvailableWhileAnotherLocalOperationIsWorking()
        async throws
    {
        let storageReportGate = AsyncGate()
        let active = RecordingSessionReview(
            sessionID: featureID(83, RecordingSessionID.self),
            jobID: featureID(84, JobID.self),
            state: .recording,
            stateVersion: 1,
            activeTrackKinds: [.applicationAudio],
            durableThroughNanoseconds: 1_000_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
        let stopped = RecordingSessionReview(
            sessionID: active.sessionID,
            jobID: active.jobID,
            state: .completed,
            stateVersion: 2,
            activeTrackKinds: [.applicationAudio],
            durableThroughNanoseconds: 2_000_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
        let workflow = try MediaReviewWorkflowProbe(
            storageReportGate: storageReportGate,
            startedRecordingReview: active,
            stoppedRecordingReview: stopped
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-recording-workspace"),
            using: sceneState
        )
        sceneState.meetingTitle = "Synthetic recording"
        sceneState.captureMode = .applicationAudioOnly
        sceneState.recordingAcknowledged = true
        await store.startRecording(using: sceneState)

        let reportTask = Task { @MainActor in
            await store.loadStorageReport()
        }
        await storageReportGate.waitUntilEntered()
        #expect(store.isWorking)

        await store.stopRecording()

        #expect(workflow.recordingStopCallCount == 1)
        #expect(store.recordingSession?.state == .completed)
        #expect(!store.isStoppingRecording)

        await storageReportGate.release()
        await reportTask.value
    }

    @Test @MainActor
    func storageOperationsCannotStartWhileRecordingStopIsSealing()
        async throws
    {
        let recordingStopGate = AsyncGate()
        let active = RecordingSessionReview(
            sessionID: featureID(85, RecordingSessionID.self),
            jobID: featureID(86, JobID.self),
            state: .recording,
            stateVersion: 1,
            activeTrackKinds: [.applicationAudio],
            durableThroughNanoseconds: 1_000_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
        let stopped = RecordingSessionReview(
            sessionID: active.sessionID,
            jobID: active.jobID,
            state: .completed,
            stateVersion: 2,
            activeTrackKinds: [.applicationAudio],
            durableThroughNanoseconds: 2_000_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
        let workflow = try MediaReviewWorkflowProbe(
            recordingStopGate: recordingStopGate,
            restoreReportFailsAfterMutation: true,
            permanentDeletionReportFailsAfterMutation: true,
            startedRecordingReview: active,
            stoppedRecordingReview: stopped
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(fileURLWithPath: "/synthetic-recording-workspace"),
            using: sceneState
        )
        sceneState.meetingTitle = "Synthetic recording"
        sceneState.captureMode = .applicationAudioOnly
        sceneState.recordingAcknowledged = true
        await store.startRecording(using: sceneState)

        let stopTask = Task { @MainActor in
            await store.stopRecording()
        }
        await recordingStopGate.waitUntilEntered()
        #expect(store.isStoppingRecording)

        let storageObjectID = featureID(87, StorageObjectID.self)
        await store.loadStorageReport()
        await store.restoreTrashItem(storageObjectID)
        await store.permanentlyDeleteTrashItem(
            storageObjectID,
            confirmedByVisibleDialog: true
        )

        #expect(workflow.storageReportCallCount == 0)
        #expect(workflow.restoreMutationCallCount == 0)
        #expect(workflow.permanentDeletionCallCount == 0)
        #expect(store.storageReport == nil)
        #expect(store.storageOperation == nil)
        #expect(store.storageFailureMessage == nil)
        #expect(store.safeErrorMessage == nil)
        #expect(!store.isWorking)
        #expect(store.isStoppingRecording)

        await recordingStopGate.release()
        await stopTask.value

        #expect(workflow.recordingStopCallCount == 1)
        #expect(store.recordingSession?.state == .completed)
        #expect(!store.isStoppingRecording)
    }

    @Test @MainActor
    func failedUNWebTVRequestConsumesExactURLAuthorization() async throws {
        let workflow = try MediaReviewWorkflowProbe(
            webMetadataShouldFail: true
        )
        let store = MediaReviewStore(workflow: workflow)
        let sceneState = MediaReviewSceneState()
        sceneState.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/synthetic-id"
        sceneState.unWebTVNetworkAuthorized = true

        await store.fetchUNWebTVMetadata(using: sceneState)

        #expect(workflow.webMetadataFetchCallCount == 1)
        #expect(!sceneState.unWebTVNetworkAuthorized)

        await store.fetchUNWebTVMetadata(using: sceneState)

        #expect(workflow.webMetadataFetchCallCount == 1)
        #expect(
            store.safeErrorMessage
                == "Authorize this one foreground official-page metadata request."
        )

        sceneState.unWebTVNetworkAuthorized = true
        await store.fetchUNWebTVMetadata(using: sceneState)

        #expect(workflow.webMetadataFetchCallCount == 2)
        #expect(!sceneState.unWebTVNetworkAuthorized)
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
func makeFeatureStoreForHostedSettingsTests(
    seededLearnedPreferenceID:
        LearnedPreferenceID? = nil
)
    throws -> MediaReviewStore
{
    MediaReviewStore(
        workflow: try MediaReviewWorkflowProbe(
            seededLearnedPreferenceID:
                seededLearnedPreferenceID
        )
    )
}

@MainActor
func makeFeatureStoreForHostedStorageTests(
    report: WorkspaceStorageReport? = nil,
    storageReportGate: AsyncGate? = nil,
    storageReportFailureCall: Int? = nil
) throws -> MediaReviewStore {
    MediaReviewStore(
        workflow: try MediaReviewWorkflowProbe(
            storageReportGate:
                storageReportGate,
            storageReportOverride:
                report,
            storageReportFailureCall:
                storageReportFailureCall
        )
    )
}

@MainActor
func makeFeatureOpenedVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let store =
        try makeFeatureStoreForHostedSettingsTests()
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-visual-workspace"
            ),
        using: sceneState
    )
    return (store, sceneState)
}

@MainActor
func makeFeatureRecordingLoadingVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState,
        setupGate: AsyncGate,
        openTask: Task<Void, Never>
    )
{
    let setupGate =
        AsyncGate()
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    recordingSetupGate:
                        setupGate
                )
        )
    let sceneState =
        MediaReviewSceneState()
    let openTask =
        Task { @MainActor in
            await store
                .openOrCreateWorkspace(
                    at:
                        URL(
                            fileURLWithPath:
                                "/synthetic-recording-loading-workspace"
                        ),
                    using:
                        sceneState
                )
        }
    await setupGate
        .waitUntilEntered()
    return (
        store,
        sceneState,
        setupGate,
        openTask
    )
}

@MainActor
func makeFeatureLocalMediaVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let fixture =
        try await makeFeatureOpenedVisualFixture()
    await fixture.store.inspectMedia(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-visual-source.wav"
            ),
        using: fixture.sceneState
    )
    fixture.sceneState.meetingTitle =
        "Synthetic Policy Review"
    fixture.sceneState.selectedTrack =
        try MediaTrackIdentifier(1)
    return fixture
}

@MainActor
func makeFeatureLocalMediaWorkingVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    seededRunningJob: true
                )
        )
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-visual-workspace"
            ),
        using: sceneState
    )
    await store.inspectMedia(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-visual-source.wav"
            ),
        using: sceneState
    )
    sceneState.meetingTitle =
        "Synthetic Policy Review"
    sceneState.selectedTrack =
        try MediaTrackIdentifier(1)
    await store.importAndProcess(
        using: sceneState
    )
    return (store, sceneState)
}

@MainActor
func makeFeatureRecordingVisualFixture(
    active: Bool
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let activeSession =
        RecordingSessionReview(
            sessionID:
                featureID(
                    2_801,
                    RecordingSessionID.self
                ),
            jobID:
                featureID(
                    2_802,
                    JobID.self
                ),
            state: .recording,
            stateVersion: 4,
            activeTrackKinds: [
                .applicationAudio
            ],
            durableThroughNanoseconds:
                7_250_000_000,
            knownGapCount: 0,
            safeReason: nil
        )
    let setup =
        RecordingSetupReview(
            capability:
                CaptureCapabilitySnapshot(
                    microphonePermission:
                        .authorized,
                    applicationAudioAvailable:
                        true,
                    systemPickerAvailable:
                        true,
                    checkedAt:
                        featureInstant(
                            1_950_000_000_002
                        )
                ),
            microphones: [],
            recoverableSession:
                active
                ? activeSession
                : nil
        )
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    recordingSetupReview:
                        setup,
                    recordingReviewOverride:
                        active
                        ? activeSession
                        : nil
                )
        )
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-recording-visual-workspace"
            ),
        using: sceneState
    )
    sceneState.meetingTitle =
        "Synthetic Security Council Briefing"
    sceneState.captureMode =
        .applicationAudioOnly
    sceneState.recordingAcknowledged =
        !active
    await store.loadRecordingSetup(
        using: sceneState
    )
    return (store, sceneState)
}

@MainActor
func makeFeatureUNWebTVCandidateVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let candidate =
        try makeFeatureUNWebTVCandidate()
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    webMetadataCandidateOverride:
                        candidate
                )
        )
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-un-web-tv-visual-workspace"
            ),
        using: sceneState
    )
    sceneState.unWebTVURL =
        candidate.requestedURL
        .absoluteString
    sceneState.unWebTVNetworkAuthorized =
        true
    await store.fetchUNWebTVMetadata(
        using: sceneState
    )
    return (store, sceneState)
}

@MainActor
func makeFeatureReviewVisualFixture()
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    try await makeFeatureReviewVisualFixture(
        briefingHumanConfirmed: false
    )
}

@MainActor
func makeFeatureReviewVisualFixture(
    briefingHumanConfirmed: Bool
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    try await makeFeatureReviewVisualFixture(
        briefingHumanConfirmed:
            briefingHumanConfirmed,
        transcriptIncomplete: false,
        analysisStale: false
    )
}

@MainActor
func makeFeatureReviewVisualFixture(
    transcriptIncomplete: Bool
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    try await makeFeatureReviewVisualFixture(
        briefingHumanConfirmed: false,
        transcriptIncomplete:
            transcriptIncomplete,
        analysisStale: false
    )
}

@MainActor
func makeFeatureReviewVisualFixture(
    analysisStale: Bool
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    try await makeFeatureReviewVisualFixture(
        briefingHumanConfirmed: false,
        transcriptIncomplete: false,
        analysisStale:
            analysisStale
    )
}

@MainActor
private func makeFeatureReviewVisualFixture(
    briefingHumanConfirmed: Bool,
    transcriptIncomplete: Bool,
    analysisStale: Bool
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    seededReviewState: true,
                    seededBriefingHumanConfirmed:
                        briefingHumanConfirmed,
                    seededTranscriptIncomplete:
                        transcriptIncomplete,
                    seededAnalysisStale:
                        analysisStale
                )
        )
    let sceneState =
        MediaReviewSceneState()
    try await loadSeededReviewState(
        store: store,
        sceneState: sceneState
    )
    await store.loadAnalysisReview()
    await store.loadBriefingReview()
    return (store, sceneState)
}

@MainActor
func makeFeatureHistoryVisualFixture(
    withResults: Bool = false
)
    async throws -> (
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState
    )
{
    let results =
        withResults
        ? [
            try
                HostedHistoryReviewAccessibilityFixture()
                .result
        ]
        : []
    let store =
        MediaReviewStore(
            workflow:
                try MediaReviewWorkflowProbe(
                    historicalSearchResults:
                        results,
                    historicalIndexAvailability:
                        .ready
                )
        )
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-history-visual-workspace"
            ),
        using: sceneState
    )
    await store
        .loadHistoricalReview(
            using: sceneState
        )
    return (store, sceneState)
}

@MainActor
func makeFeatureStorageVisualFixture(
    destructiveDisabled: Bool = false,
    failure: Bool = false
)
    async throws -> MediaReviewStore {
    let store =
        try makeFeatureStoreForHostedStorageTests(
            report:
                failure
                ? nil
                : makeFeatureStorageVisualReport(
                    destructiveDisabled:
                        destructiveDisabled
                ),
            storageReportFailureCall:
                failure
                ? 1
                : nil
        )
    let sceneState =
        MediaReviewSceneState()
    await store.openOrCreateWorkspace(
        at:
            URL(
                fileURLWithPath:
                    "/synthetic-storage-visual-workspace"
            ),
        using: sceneState
    )
    await store.loadStorageReport()
    return store
}

private func makeFeatureStorageVisualReport(
    destructiveDisabled: Bool
) throws -> WorkspaceStorageReport {
    try WorkspaceStorageReport(
        calculatedAt:
            featureInstant(
                1_950_000_000_000
            ),
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
                storageObjectID:
                    featureID(
                        20,
                        StorageObjectID.self
                    ),
                byteSize: 128,
                trashedAt:
                    featureInstant(
                        1_940_000_000_000
                    ),
                purgeEligibleAt:
                    featureInstant(
                        destructiveDisabled
                        ? 1_960_000_000_000
                        : 1_949_000_000_000
                    ),
                dataClassification:
                    .sensitive,
                retentionClass:
                    .workspaceManaged
            )
        ],
        permissionIssueCount: 0,
        scanTruncated: false
    )
}

private func makeFeatureUNWebTVCandidate()
    throws -> UNWebTVMetadataCandidate
{
    let url =
        try ValidatedUNWebTVAssetURL(
            "https://webtv.un.org/en/asset/security-council/synthetic-briefing"
        )
    let values: [
        (
            UNWebTVMetadataField,
            String,
            UNWebTVParserSource,
            String
        )
    ] = [
        (
            .title,
            "Synthetic Security Council Briefing",
            .htmlTitle,
            "title"
        ),
        (
            .description,
            "Synthetic, offline metadata used only to verify the local review surface.",
            .metaProperty,
            "og:description"
        )
    ]
    let fields =
        try values.enumerated().map {
            index,
            value in
            let (
                field,
                text,
                source,
                sourceKey
            ) = value
            return try UNWebTVFieldCandidate(
                id:
                    UUID(
                        uuidString:
                            String(
                                format:
                                    "51000000-0000-0000-0000-%012d",
                                2_900
                                    + index
                            )
                    )!,
                field: field,
                value: text,
                provenance:
                    UNWebTVFieldProvenance(
                        source: source,
                        sourceKey:
                            sourceKey,
                        normalizedValueDigest:
                            try ContentDigest
                            .sha256(
                                ofUTF8Text:
                                    text
                            ),
                        confidence: .high
                    )
            )
        }
    return try UNWebTVMetadataCandidate(
        requestedURL: url,
        finalURL: url,
        fields: fields,
        fetchedAt:
            featureInstant(
                1_950_000_000_300
            )
    )
}

@MainActor
private final class MediaReviewWorkflowProbe: MediaReviewWorkflow {
    private let inspection: MediaInspection
    private let restoreGate: AsyncGate?
    private let restoredWorkspace: WorkspaceReview?
    private let openGate: AsyncGate?
    private let pollGate: AsyncGate?
    private let editorSaveGate: AsyncGate?
    private let storageReportGate: AsyncGate?
    private let recordingSetupGate: AsyncGate?
    private let recordingStopGate: AsyncGate?
    private let historicalIndexGate: AsyncGate?
    private let historicalIndexGateCall: Int?
    private let historicalSearchGate: AsyncGate?
    private let historicalSearchGateCall: Int?
    private let historicalRebuildGate: AsyncGate?
    private let historicalComparisonGate: AsyncGate?
    private let historicalConfirmationGate: AsyncGate?
    private let storageReportOverride:
        WorkspaceStorageReport?
    private let restoreReportFailsAfterMutation:
        Bool
    private let permanentDeletionReportFailsAfterMutation:
        Bool
    private let recordingSetupFailureCall: Int?
    private let pollingJob: MediaJobReview?
    private let recordingSetupReview: RecordingSetupReview
    private let stoppedRecordingReview: RecordingSessionReview?
    private let webMetadataShouldFail: Bool
    private var currentRecordingReview: RecordingSessionReview?
    private let webMetadataCandidateOverride:
        UNWebTVMetadataCandidate?
    private let historicalSearchResults:
        [HistoricalPositionResult]
    private let historicalSearchFailureCall: Int?
    private let historicalSearchPages:
        [HistoricalSearchPage]
    private let historicalIndexFailureCall: Int?
    private let historicalIndexStatuses:
        [HistoricalIndexStatus]
    private let historicalRebuildFailureCall:
        Int?
    private let historicalComparisonResult:
        HistoricalComparisonV1?
    private let historicalConfirmedComparisonResult:
        HistoricalComparisonV1?
    private let learnedPreferenceFailureCall: Int?
    private let storageReportFailureCall: Int?
    private let jobReviewFailureCall: Int?
    private let historicalIndexAvailability:
        HistoricalIndexAvailability
    private let historicalRebuildCompletesImmediately: Bool
    private var restoreFailuresRemaining: Int
    private var currentTranscriptReview: TranscriptReviewBundle?
    private var currentAnalysisReview: AnalysisReviewBundle?
    private var currentBriefingReview: BriefingReviewBundle?
    private(set) var openCallCount = 0
    private(set) var inspectCallCount = 0
    private(set) var importCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var historicalRebuildCallCount = 0
    private(set) var historicalIndexCallCount = 0
    private(set) var historicalSearchCallCount = 0
    private(set) var historicalCompareCallCount = 0
    private(set) var historicalConfirmCallCount = 0
    private(set) var learnedPreferenceStateCallCount = 0
    private(set) var storageReportCallCount = 0
    private(set) var restoreMutationCallCount = 0
    private(set) var permanentDeletionMutationCallCount = 0
    private(set) var jobReviewCallCount = 0
    private(set) var lastHistoricalSearchQuery: HistoricalSearchQuery?
    private(set) var preferenceSaveCallCount = 0
    private(set) var lastPreferenceExpectedVersion:
        UInt64?
    private(set) var editorSaveCalls: [FeatureEditorSaveCall] = []
    private(set) var permanentDeletionCallCount = 0
    private(set) var recordingStartCallCount = 0
    private(set) var recordingStopCallCount = 0
    private(set) var webMetadataFetchCallCount = 0
    private(set) var recordingSetupCallCount = 0
    private(set) var lastDeletionConfirmed = false
    private(set) var lastUnlinkAcknowledged = false
    private(set) var workflowWorkspaceDisplayName:
        String?
    private var currentLearnedPreferenceState =
        LearnedPreferenceState(
            globallyEnabled: false,
            settingsVersion: 2,
            preferences: [],
            recentEvents: []
        )

    init(
        restoreGate: AsyncGate? = nil,
        restoredWorkspace: WorkspaceReview? = nil,
        restoreFailuresRemaining: Int = 0,
        openGate: AsyncGate? = nil,
        pollGate: AsyncGate? = nil,
        editorSaveGate: AsyncGate? = nil,
        storageReportGate: AsyncGate? = nil,
        recordingSetupGate: AsyncGate? = nil,
        recordingStopGate: AsyncGate? = nil,
        historicalIndexGate: AsyncGate? = nil,
        historicalIndexGateCall: Int? = nil,
        historicalSearchGate: AsyncGate? = nil,
        historicalSearchGateCall: Int? = nil,
        historicalRebuildGate: AsyncGate? = nil,
        historicalComparisonGate:
            AsyncGate? = nil,
        historicalConfirmationGate:
            AsyncGate? = nil,
        storageReportOverride:
            WorkspaceStorageReport? = nil,
        restoreReportFailsAfterMutation:
            Bool = false,
        permanentDeletionReportFailsAfterMutation:
            Bool = false,
        recordingSetupFailureCall: Int? = nil,
        recordingSetupReview: RecordingSetupReview? = nil,
        startedRecordingReview: RecordingSessionReview? = nil,
        stoppedRecordingReview: RecordingSessionReview? = nil,
        webMetadataShouldFail: Bool = false,
        recordingReviewOverride:
            RecordingSessionReview? = nil,
        webMetadataCandidateOverride:
            UNWebTVMetadataCandidate? = nil,
        seededRunningJob: Bool = false,
        seededReviewState: Bool = false,
        seededLearnedPreferenceID:
            LearnedPreferenceID? = nil,
        seededBriefingHumanConfirmed:
            Bool = false,
        seededTranscriptIncomplete:
            Bool = false,
        seededAnalysisStale:
            Bool = false,
        historicalSearchResults:
            [HistoricalPositionResult] = [],
        historicalSearchFailureCall: Int? = nil,
        historicalSearchPages:
            [HistoricalSearchPage] = [],
        historicalIndexFailureCall: Int? = nil,
        historicalIndexStatuses:
            [HistoricalIndexStatus] = [],
        historicalRebuildFailureCall:
            Int? = nil,
        historicalComparisonResult:
            HistoricalComparisonV1? = nil,
        historicalConfirmedComparisonResult:
            HistoricalComparisonV1? = nil,
        learnedPreferenceFailureCall: Int? = nil,
        storageReportFailureCall: Int? = nil,
        jobReviewFailureCall: Int? = nil,
        historicalIndexAvailability:
            HistoricalIndexAvailability =
            .rebuildRequired,
        historicalRebuildCompletesImmediately:
            Bool = true
    ) throws {
        self.restoreGate = restoreGate
        self.restoredWorkspace = restoredWorkspace
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.openGate = openGate
        self.pollGate = pollGate
        self.editorSaveGate = editorSaveGate
        self.storageReportGate = storageReportGate
        self.recordingSetupGate = recordingSetupGate
        self.recordingStopGate = recordingStopGate
        self.historicalIndexGate = historicalIndexGate
        self.historicalIndexGateCall =
            historicalIndexGateCall
        self.historicalSearchGate =
            historicalSearchGate
        self.historicalSearchGateCall =
            historicalSearchGateCall
        self.historicalRebuildGate =
            historicalRebuildGate
        self.historicalComparisonGate =
            historicalComparisonGate
        self.historicalConfirmationGate =
            historicalConfirmationGate
        self.storageReportOverride =
            storageReportOverride
        self.restoreReportFailsAfterMutation =
            restoreReportFailsAfterMutation
        self.permanentDeletionReportFailsAfterMutation =
            permanentDeletionReportFailsAfterMutation
        self.recordingSetupFailureCall =
            recordingSetupFailureCall
        self.recordingSetupReview = recordingSetupReview
            ?? RecordingSetupReview(
                capability: CaptureCapabilitySnapshot(
                    microphonePermission: .denied,
                    applicationAudioAvailable: false,
                    systemPickerAvailable: false,
                    checkedAt: featureInstant(1_950_000_000_002)
                ),
                microphones: []
            )
        currentRecordingReview =
            recordingReviewOverride
            ?? startedRecordingReview
        self.stoppedRecordingReview = stoppedRecordingReview
        self.webMetadataShouldFail = webMetadataShouldFail
        self.webMetadataCandidateOverride =
            webMetadataCandidateOverride
        self.historicalSearchResults =
            historicalSearchResults
        self.historicalSearchFailureCall =
            historicalSearchFailureCall
        self.historicalSearchPages =
            historicalSearchPages
        self.historicalIndexFailureCall =
            historicalIndexFailureCall
        self.historicalIndexStatuses =
            historicalIndexStatuses
        self.historicalRebuildFailureCall =
            historicalRebuildFailureCall
        self.historicalComparisonResult =
            historicalComparisonResult
        self.historicalConfirmedComparisonResult =
            historicalConfirmedComparisonResult
        self.learnedPreferenceFailureCall =
            learnedPreferenceFailureCall
        self.storageReportFailureCall =
            storageReportFailureCall
        self.jobReviewFailureCall =
            jobReviewFailureCall
        self.historicalIndexAvailability =
            historicalIndexAvailability
        self.historicalRebuildCompletesImmediately =
            historicalRebuildCompletesImmediately
        pollingJob = try pollGate == nil
            && !seededRunningJob
            && !seededReviewState
            ? nil
            : makeFeatureJobReview(
                succeeded:
                    seededReviewState
            )
        currentTranscriptReview = try seededReviewState
            ? makeFeatureTranscriptReview(
                incomplete:
                    seededTranscriptIncomplete
            )
            : nil
        currentAnalysisReview = try seededReviewState
            ? makeFeatureAnalysisReview(
                staleCard:
                    seededAnalysisStale
            )
            : nil
        currentBriefingReview = try seededReviewState
            ? makeFeatureBriefingReview(
                humanConfirmed:
                    seededBriefingHumanConfirmed
            )
            : nil
        if let seededLearnedPreferenceID {
            let timestamp =
                featureInstant(
                    1_950_000_000_090
                )
            currentLearnedPreferenceState =
                LearnedPreferenceState(
                    globallyEnabled: true,
                    settingsVersion: 2,
                    preferences: [
                        try LearnedPreferenceRecord(
                            preferenceID:
                                seededLearnedPreferenceID,
                            value:
                                .briefingLength(
                                    240
                                ),
                            enabled: true,
                            version: 1,
                            sourceAction:
                                "synthetic-hosted-settings",
                            createdAt: timestamp,
                            updatedAt: timestamp
                        )
                    ],
                    recentEvents: []
                )
        }
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
        let displayName = openCallCount == 1
            ? "Synthetic Workspace"
            : "Synthetic Workspace B"
        workflowWorkspaceDisplayName = displayName
        return WorkspaceReview(
            workspaceID: WorkspaceID(
                UUID(
                    uuidString: String(
                        format: "51000000-0000-0000-0000-%012d",
                        openCallCount
                    )
                )!
            ),
            displayName: displayName
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
        jobReviewCallCount += 1
        if jobReviewCallCount == jobReviewFailureCall {
            throw ProbeError.unexpectedCall
        }
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
        historicalIndexCallCount += 1
        if let historicalIndexGate,
           historicalIndexGateCall == nil
            || historicalIndexCallCount
                == historicalIndexGateCall
        {
            await historicalIndexGate.block()
        }
        if historicalIndexCallCount
            == historicalIndexFailureCall
        {
            throw ProbeError.unexpectedCall
        }
        let statusIndex =
            historicalIndexCallCount - 1
        if historicalIndexStatuses.indices
            .contains(statusIndex)
        {
            return historicalIndexStatuses[
                statusIndex
            ]
        }
        return HistoricalIndexStatus(
            availability: historicalIndexAvailability,
            generation: 7,
            normalizerVersion: 1,
            indexedPositionCount: 3,
            rebuiltAt: nil,
            sourceFingerprint: nil
        )
    }

    func learnedPreferenceState() async throws -> LearnedPreferenceState {
        learnedPreferenceStateCallCount += 1
        if learnedPreferenceStateCallCount
            == learnedPreferenceFailureCall
        {
            throw ProbeError.unexpectedCall
        }
        return currentLearnedPreferenceState
    }

    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?
    ) async throws -> LearnedPreferenceRecord {
        preferenceSaveCallCount += 1
        lastPreferenceExpectedVersion = expectedVersion
        let prior =
            currentLearnedPreferenceState
            .preferences.first {
                $0.preferenceID == preferenceID
            }
        guard prior?.version == expectedVersion else {
            throw HistoricalReviewError
                .preferenceConflict(preferenceID)
        }
        let timestamp = featureInstant(
            1_950_000_000_100
                + Int64(preferenceSaveCallCount)
        )
        let record = try LearnedPreferenceRecord(
            preferenceID: preferenceID,
            value: value,
            enabled: enabled,
            version: (prior?.version ?? 0) + 1,
            sourceAction: sourceAction,
            createdAt: prior?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        let retained =
            currentLearnedPreferenceState
            .preferences.filter {
                $0.preferenceID != preferenceID
            }
        currentLearnedPreferenceState =
            LearnedPreferenceState(
                globallyEnabled:
                    currentLearnedPreferenceState
                    .globallyEnabled,
                settingsVersion:
                    currentLearnedPreferenceState
                    .settingsVersion,
                preferences: retained + [record],
                recentEvents:
                    currentLearnedPreferenceState
                    .recentEvents
            )
        return record
    }

    func rebuildHistoricalIndex() async throws -> MediaJobReview {
        historicalRebuildCallCount += 1
        if let historicalRebuildGate {
            await historicalRebuildGate.block()
        }
        if historicalRebuildCallCount
            == historicalRebuildFailureCall
        {
            throw ProbeError.unexpectedCall
        }
        return try makeFeatureJobReview(
            succeeded:
                historicalRebuildCompletesImmediately
        )
    }

    func searchMeetingHistory(
        _ query: HistoricalSearchQuery
    ) async throws -> HistoricalSearchPage {
        historicalSearchCallCount += 1
        if historicalSearchCallCount
            == historicalSearchGateCall,
           let historicalSearchGate
        {
            await historicalSearchGate.block()
        }
        if historicalSearchCallCount
            == historicalSearchFailureCall
        {
            throw HistoricalReviewError.invalidQuery(
                "Synthetic history search failure."
            )
        }
        lastHistoricalSearchQuery = query
        let pageIndex =
            historicalSearchCallCount - 1
        if historicalSearchPages.indices
            .contains(pageIndex)
        {
            return historicalSearchPages[
                pageIndex
            ]
        }
        return HistoricalSearchPage(
            results:
                historicalSearchResults,
            nextCursor: nil,
            indexGeneration: 7
        )
    }

    func compareHistoricalPositions(
        current _: HistoricalPositionResult,
        historical _: HistoricalPositionResult
    ) async throws -> HistoricalComparisonV1 {
        historicalCompareCallCount += 1
        if let historicalComparisonGate {
            await historicalComparisonGate.block()
        }
        guard let historicalComparisonResult
        else { throw ProbeError.unexpectedCall }
        return historicalComparisonResult
    }

    func confirmHistoricalChange(
        candidateRevisionID _: RevisionID
    ) async throws -> HistoricalComparisonV1 {
        historicalConfirmCallCount += 1
        if let historicalConfirmationGate {
            await historicalConfirmationGate
                .block()
        }
        guard let historicalConfirmedComparisonResult
        else { throw ProbeError.unexpectedCall }
        return historicalConfirmedComparisonResult
    }

    func cancel(jobID _: JobID) async throws -> MediaJobReview {
        throw ProbeError.unexpectedCall
    }

    func retry(jobID _: JobID) async throws -> MediaJobReview {
        throw ProbeError.unexpectedCall
    }

    func storageReport() async throws -> WorkspaceStorageReport {
        storageReportCallCount += 1
        if let storageReportGate {
            await storageReportGate.block()
        }
        if storageReportCallCount
            == storageReportFailureCall
        {
            throw ProbeError.unexpectedCall
        }
        if let storageReportOverride {
            return storageReportOverride
        }
        return try WorkspaceStorageReport(
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

    func restoreTrashItem(
        storageObjectID _:
            StorageObjectID
    ) async throws -> WorkspaceStorageReport {
        guard restoreReportFailsAfterMutation
        else {
            throw ProbeError.unexpectedCall
        }
        restoreMutationCallCount += 1
        throw ProbeError.unexpectedCall
    }

    func permanentlyDeleteTrashItem(
        storageObjectID _: StorageObjectID,
        confirmsPermanentDeletion: Bool,
        acknowledgesUnlinkIsNotSecureErasure: Bool
    ) async throws -> WorkspaceStorageReport {
        permanentDeletionCallCount += 1
        lastDeletionConfirmed = confirmsPermanentDeletion
        lastUnlinkAcknowledged = acknowledgesUnlinkIsNotSecureErasure
        if permanentDeletionReportFailsAfterMutation {
            permanentDeletionMutationCallCount += 1
            throw ProbeError.unexpectedCall
        }
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
        recordingSetupCallCount += 1
        if let recordingSetupGate {
            await recordingSetupGate.block()
        }
        if recordingSetupCallCount
            == recordingSetupFailureCall
        {
            throw ProbeError.unexpectedCall
        }
        return recordingSetupReview
    }

    func startRecording(
        _: RecordingStartSubmission
    ) async throws -> RecordingSessionReview {
        recordingStartCallCount += 1
        guard let currentRecordingReview else {
            throw TranscriptWorkflowError.unavailable
        }
        return currentRecordingReview
    }

    func recordingReview(
        jobID _: JobID
    ) async throws -> RecordingSessionReview {
        guard let currentRecordingReview else {
            throw TranscriptWorkflowError.unavailable
        }
        return currentRecordingReview
    }

    func stopRecording(
        jobID _: JobID
    ) async throws -> RecordingSessionReview {
        recordingStopCallCount += 1
        if let recordingStopGate {
            await recordingStopGate.block()
        }
        guard let stoppedRecordingReview else {
            throw TranscriptWorkflowError.unavailable
        }
        currentRecordingReview = stoppedRecordingReview
        return stoppedRecordingReview
    }

    func fetchUNWebTVMetadata(
        url _: String,
        explicitNetworkAuthorization:
            Bool
    ) async throws -> UNWebTVMetadataCandidate {
        webMetadataFetchCallCount += 1
        if webMetadataShouldFail {
            throw ProbeError.unexpectedCall
        }
        guard
            explicitNetworkAuthorization,
            let webMetadataCandidateOverride
        else {
            throw
                TranscriptWorkflowError
                .unavailable
        }
        return webMetadataCandidateOverride
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

private func makeFeatureHistoricalResult(
    suffix: Int
) throws -> HistoricalPositionResult {
    let base = 4_000 + suffix * 20
    let createdAt =
        featureInstant(
            1_950_000_100_000
                + Int64(suffix)
        )
    let meetingID =
        featureID(base, MeetingID.self)
    let meetingRevisionID =
        featureID(
            base + 1,
            RevisionID.self
        )
    let meetingReference =
        try featureReference(
            meetingID,
            meetingRevisionID
        )
    let meeting = try MeetingProfileV1(
        revision:
            featureDraftEnvelope(
                logicalID: meetingID,
                revisionID:
                    meetingRevisionID,
                createdAt: createdAt
            ),
        title:
            "Synthetic pagination meeting \(suffix)",
        meetingDate:
            try CalendarDate(
                year: 2026,
                month: 7,
                day: UInt8(10 + suffix)
            ),
        outputLanguage: LanguageTag("en"),
        cloudProcessingPolicy: .localOnly,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )

    let actorID =
        featureID(
            base + 2,
            ActorID.self
        )
    let actorRevisionID =
        featureID(
            base + 3,
            RevisionID.self
        )
    let actorReference =
        try featureReference(
            actorID,
            actorRevisionID
        )
    let actor = try ActorV1(
        revision:
            featureDraftEnvelope(
                logicalID: actorID,
                revisionID:
                    actorRevisionID,
                createdAt: createdAt
            ),
        identity:
            .other(
                displayName:
                    "Synthetic Pagination Actor \(suffix)"
            ),
        reviewStatus: .unreviewed,
        userConfirmed: false
    )

    let issueID =
        featureID(
            base + 4,
            IssueID.self
        )
    let issueRevisionID =
        featureID(
            base + 5,
            RevisionID.self
        )
    let issueReference =
        try featureReference(
            issueID,
            issueRevisionID
        )
    let issue = try IssueV1(
        revision:
            featureDraftEnvelope(
                logicalID: issueID,
                revisionID:
                    issueRevisionID,
                inputs: [
                    meetingReference
                ],
                createdAt: createdAt
            ),
        meetingID: meetingID,
        title:
            EvidenceLinkedClaim(
                text:
                    "Synthetic pagination issue \(suffix)",
                taxonomy:
                    .meetingBuddyExtraction,
                supportStatus:
                    .unsupported,
                evidenceRevisions: [],
                confidence:
                    ConfidenceScore(
                        millionths:
                            500_000
                    )
            ),
        reviewStatus: .unreviewed,
        userConfirmed: false
    )

    let organizationReference =
        try featureReference(
            featureID(
                base + 6,
                OrganizationID.self
            ),
            featureID(
                base + 7,
                RevisionID.self
            )
        )
    let capacityReference =
        try featureReference(
            featureID(
                base + 8,
                SpeakingCapacityID.self
            ),
            featureID(
                base + 9,
                RevisionID.self
            )
        )
    let positionID =
        featureID(
            base + 10,
            PositionID.self
        )
    let positionRevisionID =
        featureID(
            base + 11,
            RevisionID.self
        )
    let position = try PositionV1(
        revision:
            featureDraftEnvelope(
                logicalID: positionID,
                revisionID:
                    positionRevisionID,
                inputs: [
                    meetingReference,
                    actorReference,
                    organizationReference,
                    capacityReference,
                    issueReference
                ],
                createdAt: createdAt
            ),
        meetingID: meetingID,
        actorRevision: actorReference,
        representedEntityRevision:
            organizationReference,
        speakingCapacityRevision:
            capacityReference,
        issueRevision: issueReference,
        positionType: .supports,
        statement:
            EvidenceLinkedClaim(
                text:
                    "Synthetic pagination position \(suffix)",
                taxonomy:
                    .meetingBuddyExtraction,
                supportStatus:
                    .unsupported,
                evidenceRevisions: [],
                confidence:
                    ConfidenceScore(
                        millionths:
                            500_000
                    )
            ),
        comparisonState: .unknown,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
    return HistoricalPositionResult(
        position: position,
        meeting: meeting,
        actor: actor,
        issue: issue,
        evidence: [],
        sensitivityLabelRevision:
            try featureReference(
                featureID(
                    base + 12,
                    SensitivityLabelID.self
                ),
                featureID(
                    base + 13,
                    RevisionID.self
                )
            ),
        accessPolicyRevision:
            try featureReference(
                featureID(
                    base + 14,
                    AccessPolicyID.self
                ),
                featureID(
                    base + 15,
                    RevisionID.self
                )
            ),
        organizationLabel:
            "Synthetic Pagination Organization",
        meetingType: nil,
        effectiveClassification:
            .internal
    )
}

private func makeFeatureHistoricalIndexStatus(
    generation: UInt64,
    availability:
        HistoricalIndexAvailability = .ready
) -> HistoricalIndexStatus {
    HistoricalIndexStatus(
        availability: availability,
        generation: generation,
        normalizerVersion: 1,
        indexedPositionCount: 3,
        rebuiltAt: nil,
        sourceFingerprint: nil
    )
}

private func makeFeatureHistoricalComparison(
    current: HistoricalPositionResult,
    historical: HistoricalPositionResult,
    suffix: Int = 1
) throws -> HistoricalComparisonV1 {
    let base = 8_000 + suffix * 30
    let currentPositionReference =
        try featureReference(
            current.position.positionID,
            current.position.revision.revisionID
        )
    let historicalPositionReference =
        try featureReference(
            historical.position.positionID,
            historical.position.revision.revisionID
        )
    let currentMeetingReference =
        try featureReference(
            current.meeting.meetingID,
            current.meeting.revision.revisionID
        )
    let historicalMeetingReference =
        try featureReference(
            historical.meeting.meetingID,
            historical.meeting.revision.revisionID
        )
    let currentActorReference =
        try featureReference(
            current.actor.actorID,
            current.actor.revision.revisionID
        )
    let historicalActorReference =
        try featureReference(
            historical.actor.actorID,
            historical.actor.revision.revisionID
        )
    let currentIssueReference =
        try featureReference(
            current.issue.issueID,
            current.issue.revision.revisionID
        )
    let historicalIssueReference =
        try featureReference(
            historical.issue.issueID,
            historical.issue.revision.revisionID
        )
    let currentEvidenceReference =
        try featureReference(
            featureID(
                base + 2,
                EvidenceID.self
            ),
            featureID(
                base + 3,
                RevisionID.self
            )
        )
    let historicalEvidenceReference =
        try featureReference(
            featureID(
                base + 4,
                EvidenceID.self
            ),
            featureID(
                base + 5,
                RevisionID.self
            )
        )
    let inputs = [
        currentPositionReference,
        historicalPositionReference,
        currentMeetingReference,
        historicalMeetingReference,
        currentActorReference,
        historicalActorReference,
        currentIssueReference,
        historicalIssueReference,
        current.sensitivityLabelRevision,
        historical.sensitivityLabelRevision,
        current.accessPolicyRevision,
        historical.accessPolicyRevision
    ]
    return try HistoricalComparisonV1(
        revision:
            featureDraftEnvelope(
                logicalID:
                    featureID(
                        base,
                        HistoricalComparisonID.self
                    ),
                revisionID:
                    featureID(
                        base + 1,
                        RevisionID.self
                    ),
                inputs: inputs,
                evidence: [
                    currentEvidenceReference,
                    historicalEvidenceReference
                ],
                createdAt:
                    featureInstant(
                        1_950_000_200_000
                            + Int64(suffix)
                    )
            ),
        currentPositionRevision:
            currentPositionReference,
        historicalPositionRevision:
            historicalPositionReference,
        currentMeetingRevision:
            currentMeetingReference,
        historicalMeetingRevision:
            historicalMeetingReference,
        currentActorRevision:
            currentActorReference,
        historicalActorRevision:
            historicalActorReference,
        currentIssueRevision:
            currentIssueReference,
        historicalIssueRevision:
            historicalIssueReference,
        currentSensitivityLabelRevision:
            current.sensitivityLabelRevision,
        historicalSensitivityLabelRevision:
            historical.sensitivityLabelRevision,
        currentAccessPolicyRevision:
            current.accessPolicyRevision,
        historicalAccessPolicyRevision:
            historical.accessPolicyRevision,
        currentEffectiveDate:
            current.meeting.meetingDate,
        historicalEffectiveDate:
            historical.meeting.meetingDate,
        currentEffectiveTimeRange: nil,
        historicalEffectiveTimeRange: nil,
        currentConfidence:
            current.position.statement.confidence,
        historicalConfidence:
            historical.position.statement.confidence,
        currentEvidenceRevisions: [
            currentEvidenceReference
        ],
        historicalEvidenceRevisions: [
            historicalEvidenceReference
        ],
        differenceState: .possibleDifference,
        finding: .possibleChange,
        reviewStatus: .needsReview,
        userConfirmed: false
    )
}

private func makeFeatureConfirmedHistoricalComparison(
    candidate: HistoricalComparisonV1,
    suffix: Int = 1
) throws -> HistoricalComparisonV1 {
    try HistoricalComparisonFactory
        .confirmedChange(
            candidate: candidate,
            revisionID:
                featureID(
                    9_000 + suffix,
                    RevisionID.self
                ),
            confirmedAt:
                featureInstant(
                    1_950_000_300_000
                        + Int64(suffix)
                )
        )
}

private func featureDraftEnvelope<
    Tag: LogicalObjectIDScope
>(
    logicalID: StableID<Tag>,
    revisionID: RevisionID,
    inputs:
        [SemanticRevisionReference] = [],
    evidence:
        [SemanticRevisionReference] = [],
    createdAt: UTCInstant
) throws -> RevisionEnvelope<Tag> {
    try RevisionEnvelope(
        logicalID: logicalID,
        revisionID: revisionID,
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: createdAt,
        createdBy: .application,
        inputRevisions: inputs,
        evidenceRevisions: evidence,
        dataClassification: .internal
    )
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
    translationText: String? = "Workspace A translation fixture",
    incomplete: Bool = false
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
        disposition:
            incomplete
            ? .failed
            : .transcribed,
        attemptCount: 1,
        reviewedSegmentRevision:
            incomplete
            ? nil
            : transcriptReference,
        translationRevision:
            incomplete
            ? nil
            : translationReference,
        safeFailureCode:
            incomplete
            ? "synthetic-offline-provider-unavailable"
            : nil
    )
    let manifest = try TranscriptCoverageManifest(
        manifestID: featureID(52, TranscriptCoverageManifestID.self),
        transcriptSetID: featureID(53, TranscriptSetID.self),
        meetingID: meetingID,
        canonicalSourceRevision: canonicalSourceRevision,
        canonicalFrameCount: 16_000,
        transcriptionRoute: transcriptionRoute,
        translationRoute: translationRoute,
        status:
            incomplete
            ? .incomplete
            : .published,
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
    statementText: String = "Workspace A analysis fixture position",
    staleCard: Bool = false
) throws -> AnalysisReviewBundle {
    let transcript = try makeFeatureTranscriptReview()
    let segment = try #require(transcript.transcriptSegments.first)
    let segmentReference = try featureReference(
        segment.segmentID,
        segment.revision.revisionID
    )
    let evidenceID =
        featureID(
            811,
            EvidenceID.self
        )
    let evidenceRevisionID =
        featureID(
            812,
            RevisionID.self
        )
    let evidenceReference =
        try featureReference(
            evidenceID,
            evidenceRevisionID
        )
    let interventionReference =
        try featureReference(
            featureID(
                815,
                InterventionCardID.self
            ),
            featureID(
                816,
                RevisionID.self
            )
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
        localModelAvailable: !staleCard
    )
    let analysisProvider = try ProviderMetadata(
        providerIdentifier:
            "meetingbuddy-deterministic-analysis",
        modelIdentifier:
            "feature-analysis-fixture-v1",
        modelVersion: "1",
        clientVersion:
            "feature-fixture-v1"
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
            modelAvailable: !staleCard,
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
        status:
            staleCard
            ? .incomplete
            : .published,
        segments: [
            staleCard
                ? try AnalysisSegmentCoverage(
                    segmentRevision:
                        segmentReference,
                    disposition: .missing,
                    attemptCount: 0
                )
                : try AnalysisSegmentCoverage(
                    segmentRevision:
                        segmentReference,
                    disposition:
                        .substantive,
                    attemptCount: 1,
                    provider: analysisProvider,
                    evidenceRevisions: [
                        evidenceReference
                    ],
                    outputRevisions: [
                        interventionReference
                    ]
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
    let evidence =
        try EvidenceRefV1(
            revision:
                RevisionEnvelope(
                    logicalID:
                        evidenceID,
                    revisionID:
                        evidenceRevisionID,
                    schemaVersion:
                        .v1,
                    lifecycleStatus:
                        .draft,
                    validationState:
                        .notValidated,
                    createdAt:
                        featureInstant(
                            1_950_000_000_200
                        ),
                    createdBy:
                        .application,
                    inputRevisions: [
                        segmentReference
                    ],
                    dataClassification:
                        .internal
                ),
            location:
                .transcriptSegment(
                    source:
                        segmentReference,
                    textRange: nil
                ),
            excerpt:
                EvidenceExcerpt(
                    text:
                        "Synthetic exact analysis evidence.",
                    language:
                        LanguageTag("en"),
                    translationStatus:
                        .sourceOnly
                ),
            confidence:
                ConfidenceScore(
                    millionths:
                        900_000
                )
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
    let delegationPositionCards:
        [DelegationPositionCardV1]
    if staleCard {
        let stalePositionReference =
            try featureReference(
                position.positionID,
                featureID(
                    2_950,
                    RevisionID.self
                )
            )
        let card =
            try DelegationPositionCardV1(
                revision:
                    RevisionEnvelope(
                        logicalID:
                            featureID(
                                2_951,
                                DelegationPositionCardID
                                    .self
                            ),
                        revisionID:
                            featureID(
                                2_952,
                                RevisionID.self
                            ),
                        schemaVersion: .v1,
                        lifecycleStatus:
                            .draft,
                        validationState:
                            .notValidated,
                        createdAt:
                            featureInstant(
                                1_950_000_000_202
                            ),
                        createdBy:
                            .application,
                        inputRevisions: [
                            meetingReference,
                            organizationReference,
                            capacityReference,
                            issueReference,
                            stalePositionReference
                        ],
                        evidenceRevisions: [
                            evidenceReference
                        ],
                        dataClassification:
                            .internal
                    ),
                meetingID:
                    transcript.manifest.meetingID,
                representedEntityRevision:
                    organizationReference,
                speakingCapacityRevisions: [
                    capacityReference
                ],
                issueRevision:
                    issueReference,
                positionRevisions: [
                    stalePositionReference
                ],
                overallPosition:
                    position.statement,
                reviewStatus:
                    .needsReview,
                userConfirmed: false
            )
        delegationPositionCards = [
            card
        ]
    } else {
        delegationPositionCards = []
    }
    return AnalysisReviewBundle(
        ledger: ledger,
        evidence:
            staleCard
            ? []
            : [evidence],
        participants: [],
        organizations: [],
        issues: [],
        positions: [position],
        commitments: [],
        decisions: [],
        interventionCards: [],
        delegationPositionCards:
            delegationPositionCards
    )
}

private func makeFeatureBriefingReview(
    overviewRevisionID: RevisionID = featureID(930, RevisionID.self),
    overviewText: String = "Workspace A overview fixture",
    humanConfirmed: Bool = false
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
    let generatedSections =
        try zip(
            template.sections,
            sectionMarkers
        )
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
    let sections: [BriefingSectionV1]
    if humanConfirmed {
        sections =
            try generatedSections
            .enumerated()
            .map { index, prior in
                let priorReference =
                    try featureReference(
                        prior.sectionID,
                        prior.revision.revisionID
                    )
                let items =
                    try prior.items.map {
                        item in
                        try BriefingSectionItem(
                            itemID: item.itemID,
                            label: item.label,
                            claim:
                                EvidenceLinkedClaim(
                                    text:
                                        item.claim.text,
                                    taxonomy:
                                        .userConfirmedConclusion,
                                    supportStatus:
                                        item.claim.supportStatus,
                                    evidenceRevisions:
                                        item.claim
                                        .evidenceRevisions,
                                    confidence:
                                        item.claim.confidence
                                ),
                            sourceObjectRevisions:
                                item.sourceObjectRevisions
                        )
                    }
                let draft =
                    try BriefingSectionV1(
                        revision:
                            RevisionEnvelope(
                                logicalID:
                                    prior.sectionID,
                                revisionID:
                                    featureID(
                                        1_800 + index,
                                        RevisionID.self
                                    ),
                                schemaVersion: .v1,
                                lifecycleStatus: .draft,
                                validationState:
                                    .notValidated,
                                createdAt: createdAt,
                                createdBy: .user,
                                supersedesRevisionID:
                                    prior.revision
                                    .revisionID,
                                inputRevisions:
                                    prior.revision
                                    .inputRevisions
                                        + [priorReference],
                                sourceAssetRevisions:
                                    prior.revision
                                    .sourceAssetRevisions,
                                evidenceRevisions:
                                    prior.revision
                                    .evidenceRevisions,
                                dataClassification:
                                    prior.revision
                                    .dataClassification
                            ),
                        meetingID:
                            prior.meetingID,
                        templateRevision:
                            prior.templateRevision,
                        graphRevision:
                            prior.graphRevision,
                        sectionType:
                            prior.sectionType,
                        order: prior.order,
                        title: prior.title,
                        outputLanguage:
                            prior.outputLanguage,
                        metadata:
                            prior.metadata,
                        items: items,
                        generatorModules:
                            prior.generatorModules,
                        manualEditStatus:
                            .userEdited,
                        locked: prior.locked,
                        reviewStatus:
                            .confirmed,
                        userConfirmed: true
                    )
                return try BriefingSectionV1(
                    revision:
                        publishedFeatureEnvelope(
                            draft.revision,
                            semanticContentHash:
                                draft
                                .calculatedSemanticContentHash(),
                            at: createdAt
                        ),
                    meetingID: draft.meetingID,
                    templateRevision:
                        draft.templateRevision,
                    graphRevision:
                        draft.graphRevision,
                    sectionType:
                        draft.sectionType,
                    order: draft.order,
                    title: draft.title,
                    outputLanguage:
                        draft.outputLanguage,
                    metadata: draft.metadata,
                    items: draft.items,
                    generatorModules:
                        draft.generatorModules,
                    manualEditStatus:
                        draft.manualEditStatus,
                    locked: draft.locked,
                    reviewStatus:
                        draft.reviewStatus,
                    userConfirmed:
                        draft.userConfirmed
                )
            }
    } else {
        sections = generatedSections
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
            createdBy:
                humanConfirmed
                ? .user
                : .application,
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
        manualSectionCount:
            humanConfirmed
            ? 3
            : 0,
        reviewStatus:
            humanConfirmed
            ? .confirmed
            : .needsReview,
        userConfirmed:
            humanConfirmed
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

actor AsyncGate {
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
