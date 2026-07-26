import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct MediaReviewSceneStateTests {
    @Test @MainActor
    func unWebTVAuthorizationIsBoundToOneExactVisibleURL() {
        let state = MediaReviewSceneState()
        state.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/first"
        state.unWebTVNetworkAuthorized = true

        #expect(state.unWebTVNetworkAuthorized)

        state.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/second"

        #expect(!state.unWebTVNetworkAuthorized)
    }

    @Test @MainActor
    func workspaceChangeResetsEverySceneOwnedDraftAndTransientAuthorization() throws {
        let state = MediaReviewSceneState()
        state.selectedSection = .briefing
        state.meetingTitle = "Workspace A"
        state.dataClassification = .restricted
        state.selectedTrack = try MediaTrackIdentifier(7)
        state.speechSourceKind = .simultaneousInterpretation
        state.languageTag = "fr"
        state.transcriptSourceLanguageTag = "fr"
        state.transcriptTargetLanguageTag = "en"
        state.manualTranscriptText = "private draft"
        state.manualTranslationText = "translation draft"
        state.manualCoverageConfirmed = true
        state.analysisClaimsConfirmed = true
        state.briefingExportFileName = "workspace-a"
        state.captureMode = .microphoneAndApplicationAudio
        state.selectedMicrophoneDeviceID = "workspace-a-microphone"
        state.microphoneSpeechSourceKind = .simultaneousInterpretation
        state.applicationSpeechSourceKind = .translatedAudioTrack
        state.recordingAcknowledged = true
        state.unWebTVURL = "https://webtv.un.org/en/asset/a/b"
        state.unWebTVNetworkAuthorized = true
        state.reviewedUNTitle = "Workspace A title"
        state.reviewedUNDescription = "Workspace A description"
        state.reviewedUNProductionDate = "2026-07-24"
        state.reviewedUNLanguageAvailability = "English"
        state.historyActorOrCountry = "Workspace A actor"
        state.historyTopic = "Workspace A topic"
        state.historyBody = "Workspace A body"
        state.historyMeetingType = "Workspace A meeting type"
        state.historyStartDate = "2026-07-01"
        state.historyEndDate = "2026-07-24"
        state.selectedCurrentHistoryRevisionID = stateID(4, RevisionID.self)
        state.selectedPriorHistoryRevisionID = stateID(5, RevisionID.self)
        state.learnedPreferenceKind = .grouping
        state.learnedPreferenceValue = "Workspace A preference"
        state.editingLearnedPreferenceID = stateID(6, LearnedPreferenceID.self)
        state.editingLearnedPreferenceVersion = 9
        state.pendingPermanentDeletion = try WorkspaceTrashItem(
            storageObjectID: stateID(7, StorageObjectID.self),
            byteSize: 128,
            trashedAt: UTCInstant(millisecondsSinceUnixEpoch: 1_950_000_000_000),
            purgeEligibleAt: UTCInstant(
                millisecondsSinceUnixEpoch: 1_950_086_400_000
            ),
            dataClassification: .sensitive,
            retentionClass: .workspaceManaged
        )
        state.confirmHistoricalChange = true
        state.confirmPreferenceReset = true
        state.transcript.hydrateSelection(
            segmentID: stateID(1, TranscriptSegmentID.self),
            transcriptRevisionID: stateID(8, RevisionID.self),
            translationRevisionID: stateID(9, RevisionID.self),
            transcriptText: "Workspace A published transcript",
            translationText: "Workspace A published translation"
        )
        state.transcript.transcriptText = "Workspace A transcript correction"
        state.transcript.translationText = "Workspace A translation correction"
        state.transcript.speakerName = "Workspace A speaker"
        state.analysis.hydrateSelection(
            positionID: stateID(2, PositionID.self),
            revisionID: stateID(10, RevisionID.self),
            positionType: .supports,
            statement: "Workspace A published position",
            reservations: "Workspace A published reservation",
            conditions: "Workspace A published condition"
        )
        state.analysis.positionType = .opposes
        state.analysis.statement = "Workspace A position correction"
        state.analysis.reservations = "Workspace A reservation correction"
        state.analysis.conditions = "Workspace A condition correction"
        let briefingItemID = stateID(3, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .majorIssues,
            revisionID: stateID(11, RevisionID.self),
            itemTexts: [briefingItemID: "Workspace A published briefing"],
            isLocked: false
        )
        state.briefing.itemTexts[briefingItemID] = "Workspace A briefing"
        state.briefing.isLocked = true

        state.resetForWorkspaceChange()

        #expect(state.selectedSection == .intake)
        #expect(state.meetingTitle.isEmpty)
        #expect(state.dataClassification == .internal)
        #expect(state.selectedTrack == nil)
        #expect(state.speechSourceKind == .unknown)
        #expect(state.languageTag.isEmpty)
        #expect(state.transcriptSourceLanguageTag == "en")
        #expect(state.transcriptTargetLanguageTag.isEmpty)
        #expect(state.manualTranscriptText.isEmpty)
        #expect(state.manualTranslationText.isEmpty)
        #expect(!state.manualCoverageConfirmed)
        #expect(!state.analysisClaimsConfirmed)
        #expect(state.briefingExportFileName == "meeting-briefing")
        #expect(state.captureMode == .microphoneOnly)
        #expect(state.selectedMicrophoneDeviceID == nil)
        #expect(
            state.microphoneSpeechSourceKind == .originalSpeakerAudio
        )
        #expect(
            state.applicationSpeechSourceKind == .originalSpeakerAudio
        )
        #expect(!state.recordingAcknowledged)
        #expect(state.unWebTVURL.isEmpty)
        #expect(!state.unWebTVNetworkAuthorized)
        #expect(state.reviewedUNTitle.isEmpty)
        #expect(state.reviewedUNDescription.isEmpty)
        #expect(state.reviewedUNProductionDate.isEmpty)
        #expect(state.reviewedUNLanguageAvailability.isEmpty)
        #expect(state.historyActorOrCountry.isEmpty)
        #expect(state.historyTopic.isEmpty)
        #expect(state.historyBody.isEmpty)
        #expect(state.historyMeetingType.isEmpty)
        #expect(state.historyStartDate.isEmpty)
        #expect(state.historyEndDate.isEmpty)
        #expect(state.selectedCurrentHistoryRevisionID == nil)
        #expect(state.selectedPriorHistoryRevisionID == nil)
        #expect(state.learnedPreferenceKind == .briefingLength)
        #expect(state.learnedPreferenceValue.isEmpty)
        #expect(state.editingLearnedPreferenceID == nil)
        #expect(state.editingLearnedPreferenceVersion == nil)
        #expect(state.pendingPermanentDeletion == nil)
        #expect(!state.confirmHistoricalChange)
        #expect(!state.confirmPreferenceReset)
        #expect(state.transcript.selectedSegmentID == nil)
        #expect(state.transcript.transcriptRevisionID == nil)
        #expect(state.transcript.translationRevisionID == nil)
        #expect(state.transcript.transcriptText.isEmpty)
        #expect(state.transcript.translationText.isEmpty)
        #expect(state.transcript.speakerName.isEmpty)
        #expect(state.analysis.selectedPositionID == nil)
        #expect(state.analysis.positionRevisionID == nil)
        #expect(state.analysis.positionType == .uncertain)
        #expect(state.analysis.statement.isEmpty)
        #expect(state.analysis.reservations.isEmpty)
        #expect(state.analysis.conditions.isEmpty)
        #expect(state.briefing.selectedSectionType == nil)
        #expect(state.briefing.sectionRevisionID == nil)
        #expect(state.briefing.itemTexts.isEmpty)
        #expect(!state.briefing.isLocked)
        #expect(!state.hasUnsavedEditorChanges)
    }

    @Test @MainActor
    func dirtyTranscriptSelectionSupportsKeepEditingAndDiscardOutcomes() {
        let state = MediaReviewSceneState()
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: true
        )
        let first = stateID(10, TranscriptSegmentID.self)
        let second = stateID(11, TranscriptSegmentID.self)

        state.transcript.select(first)
        state.transcript.transcriptText = "unsaved correction"
        state.requestTranscriptSelection(second)

        #expect(state.transcript.selectedSegmentID == first)
        #expect(state.isNavigationConfirmationPresented)

        state.cancelPendingNavigation()
        #expect(state.transcript.selectedSegmentID == first)
        #expect(state.transcript.transcriptText == "unsaved correction")

        state.requestTranscriptSelection(second)
        #expect(
            state.discardChangesAndResolvePending()
                == MediaReviewNavigationEffect.none
        )
        #expect(state.transcript.selectedSegmentID == second)
        #expect(state.transcript.transcriptText.isEmpty)
    }

    @Test @MainActor
    func dirtyAnalysisAndBriefingSelectionsDoNotChangeBeforeResolution() {
        let state = MediaReviewSceneState()
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: true
        )
        let firstPosition = stateID(20, PositionID.self)
        let secondPosition = stateID(21, PositionID.self)

        state.analysis.select(firstPosition)
        state.analysis.statement = "unsaved position"
        state.requestAnalysisSelection(secondPosition)
        #expect(state.analysis.selectedPositionID == firstPosition)
        state.cancelPendingNavigation()
        #expect(state.analysis.statement == "unsaved position")
        state.requestAnalysisSelection(secondPosition)
        _ = state.discardChangesAndResolvePending()
        #expect(state.analysis.selectedPositionID == secondPosition)

        state.briefing.select(.meetingOverview)
        state.briefing.itemTexts[stateID(22, BriefingItemID.self)] = "unsaved section"
        state.requestBriefingSelection(.majorDelegations)
        #expect(state.briefing.selectedSectionType == .meetingOverview)
        state.cancelPendingNavigation()
        #expect(!state.briefing.itemTexts.isEmpty)
        state.requestBriefingSelection(.majorDelegations)
        _ = state.discardChangesAndResolvePending()
        #expect(state.briefing.selectedSectionType == .majorDelegations)
        #expect(state.briefing.itemTexts.isEmpty)
    }

    @Test @MainActor
    func workspaceIntentWaitsForDirtyResolutionAndSaveFailurePreservesTheDraft() throws {
        let state = MediaReviewSceneState()
        let workspaceB = URL(fileURLWithPath: "/synthetic-workspace-b")
        let itemID = stateID(30, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(31, RevisionID.self),
            itemTexts: [itemID: "published briefing"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "workspace A draft"

        #expect(state.requestWorkspaceChange(to: workspaceB) == nil)
        let failedOperation = try #require(state.beginPendingNavigationSave())
        #expect(!state.isNavigationConfirmationPresented)
        #expect(
            state.completePendingNavigationAfterSave(
                failedOperation,
                succeeded: false
            ) == nil
        )
        #expect(state.briefing.itemTexts[itemID] == "workspace A draft")
        #expect(state.isNavigationConfirmationPresented)

        let successfulOperation = try #require(state.beginPendingNavigationSave())
        #expect(
            state.completePendingNavigationAfterSave(
                successfulOperation,
                succeeded: true
            )
                == .openWorkspace(workspaceB)
        )
        #expect(!state.briefing.isDirty)
    }

    @Test @MainActor
    func mediaImportIntentUsesSaveDiscardAndCancelBeforeReplacement() throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(35, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(36, RevisionID.self),
            itemTexts: [itemID: "published briefing"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "unpublished briefing"

        #expect(state.requestMediaImport() == nil)
        #expect(state.isNavigationConfirmationPresented)
        state.cancelPendingNavigation()
        #expect(state.briefing.itemTexts[itemID] == "unpublished briefing")

        #expect(state.requestMediaImport() == nil)
        #expect(
            state.discardChangesAndResolvePending()
                == .importPendingMedia
        )
        #expect(!state.briefing.isDirty)

        state.briefing.itemTexts[itemID] = "saved before import"
        #expect(state.requestMediaImport() == nil)
        let operation = try #require(state.beginPendingNavigationSave())
        #expect(
            state.completePendingNavigationAfterSave(
                operation,
                succeeded: true
            ) == .importPendingMedia
        )
        #expect(!state.hasUnsavedEditorChanges)
        #expect(state.requestMediaImport() == .importPendingMedia)
    }

    @Test @MainActor
    func simultaneousTranscriptDraftsSaveIndependentlyWithoutDiscardingSiblings() throws {
        let state = MediaReviewSceneState()
        let transcriptRevisionID = stateID(41, RevisionID.self)
        let translationRevisionID = stateID(42, RevisionID.self)
        state.transcript.hydrateSelection(
            segmentID: stateID(40, TranscriptSegmentID.self),
            transcriptRevisionID: transcriptRevisionID,
            translationRevisionID: translationRevisionID,
            transcriptText: "published transcript",
            translationText: "published translation"
        )
        state.transcript.transcriptText = "transcript correction"
        state.transcript.translationText = "translation correction"
        state.transcript.speakerName = "Speaker draft"
        state.requestSection(.analysis)

        #expect(state.transcript.dirtyOperationCount == 3)
        #expect(state.pendingSaveRequest == nil)
        #expect(!state.canSavePendingChanges)
        #expect(state.selectedSection == .intake)

        state.cancelPendingNavigation()
        let transcriptOperation = try #require(
            state.beginDirectTranscriptSave()
        )
        guard case let .transcript(revisionID, text) =
            transcriptOperation.request
        else {
            Issue.record("Expected a captured Transcript correction.")
            return
        }
        #expect(revisionID == transcriptRevisionID)
        #expect(text == "transcript correction")
        #expect(
            state.completeDirectEditorSave(
                transcriptOperation,
                succeeded: true
            )
        )
        #expect(!state.transcript.transcriptIsDirty)
        #expect(state.transcript.translationIsDirty)
        #expect(state.transcript.translationText == "translation correction")
        #expect(state.transcript.speakerIsDirty)
        #expect(state.transcript.speakerName == "Speaker draft")

        let translationOperation = try #require(
            state.beginDirectTranslationSave()
        )
        guard case let .translation(translationID, translationText) =
            translationOperation.request
        else {
            Issue.record("Expected a captured Translation correction.")
            return
        }
        #expect(translationID == translationRevisionID)
        #expect(translationText == "translation correction")
        #expect(
            state.completeDirectEditorSave(
                translationOperation,
                succeeded: true
            )
        )
        #expect(!state.transcript.translationIsDirty)
        #expect(state.transcript.speakerIsDirty)

        let speakerOperation = try #require(
            state.beginDirectSpeakerSave()
        )
        guard case let .speaker(speakerRevisionID, displayName) =
            speakerOperation.request
        else {
            Issue.record("Expected a captured Speaker confirmation.")
            return
        }
        #expect(speakerRevisionID == transcriptRevisionID)
        #expect(displayName == "Speaker draft")
        #expect(
            state.completeDirectEditorSave(
                speakerOperation,
                succeeded: true
            )
        )
        #expect(!state.transcript.isDirty)
    }

    @Test @MainActor
    func unavailableWorkflowDestinationFallsBackToIntake() {
        let state = MediaReviewSceneState()

        state.selectedSection = .transcript
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: false,
            hasTranscriptReview: false,
            hasHumanConfirmedAnalysis: false
        )
        #expect(state.selectedSection == .intake)

        state.selectedSection = .analysis
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: false,
            hasHumanConfirmedAnalysis: false
        )
        #expect(state.selectedSection == .intake)

        state.selectedSection = .briefing
        state.briefing.select(.meetingOverview)
        let itemID = stateID(45, BriefingItemID.self)
        state.briefing.itemTexts[itemID] = "retain unavailable draft"
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: false
        )
        #expect(state.selectedSection == .intake)
        #expect(state.briefing.itemTexts[itemID] == "retain unavailable draft")
        #expect(state.briefing.isDirty)
    }

    @Test @MainActor
    func destinationPrerequisitesCascadeAndRejectUnavailableRequests() {
        let state = MediaReviewSceneState()

        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: false,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: true
        )
        state.requestSection(.transcript)
        state.requestSection(.analysis)
        state.requestSection(.briefing)
        #expect(state.selectedSection == .intake)

        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: false,
            hasHumanConfirmedAnalysis: true
        )
        state.requestSection(.transcript)
        #expect(state.selectedSection == .transcript)
        state.requestSection(.analysis)
        state.requestSection(.briefing)
        #expect(state.selectedSection == .transcript)

        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: false
        )
        state.requestSection(.analysis)
        #expect(state.selectedSection == .analysis)
        state.requestSection(.briefing)
        #expect(state.selectedSection == .analysis)

        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: true
        )
        state.requestSection(.briefing)
        #expect(state.selectedSection == .briefing)
    }

    @Test @MainActor
    func pendingDestinationIsRevalidatedAfterItsDraftSaveCompletes() throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(145, BriefingItemID.self)
        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: true,
            hasHumanConfirmedAnalysis: true
        )
        state.selectedSection = .briefing
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(146, RevisionID.self),
            itemTexts: [itemID: "published value"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "pending save"
        state.requestSection(.analysis)
        let operation = try #require(state.beginPendingNavigationSave())

        state.reconcileDestinationAvailability(
            canonicalJobSucceeded: true,
            hasTranscriptReview: false,
            hasHumanConfirmedAnalysis: true
        )
        let effect = state.completePendingNavigationAfterSave(
            operation,
            succeeded: true
        )

        #expect(effect == MediaReviewNavigationEffect.none)
        #expect(state.selectedSection == .intake)
        #expect(!state.briefing.isDirty)
        #expect(!state.isNavigationConfirmationPresented)
    }

    @Test @MainActor
    func inFlightSaveCapturesItsSnapshotAndBlocksNavigationUntilCompletion() async throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(46, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(146, RevisionID.self),
            itemTexts: [itemID: "published value"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "submitted value"

        let operation = try #require(state.beginDirectBriefingSave())
        let gate = SceneStateAsyncGate()
        let completion = Task { @MainActor in
            await gate.block()
            return state.completeDirectEditorSave(
                operation,
                succeeded: true
            )
        }

        await gate.waitUntilEntered()
        #expect(state.isEditorSaveInFlight)
        state.requestSection(.history)
        #expect(state.selectedSection == .intake)

        // Even an out-of-band mutation cannot be falsely marked as part of
        // the captured save operation.
        state.briefing.itemTexts[itemID] = "newer unpublished value"
        await gate.release()
        #expect(await completion.value)
        #expect(!state.isEditorSaveInFlight)
        #expect(state.briefing.isDirty)
        #expect(
            state.briefing.itemTexts[itemID] == "newer unpublished value"
        )
    }

    @Test @MainActor
    func applicationSaveCompletesPendingNavigationOnlyAfterAsyncSuccess() async throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(47, BriefingItemID.self)
        let revisionID = stateID(147, RevisionID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: revisionID,
            itemTexts: [itemID: "published value"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "persist through application action"
        state.requestSection(.history)
        let operation = try #require(state.beginPendingNavigationSave())
        let gate = SceneStateAsyncGate()

        let resolution = Task { @MainActor in
            await state.resolvePendingNavigationSave(operation) { request in
                guard case let .briefing(
                    sectionType,
                    expectedRevisionID,
                    values,
                    locked
                ) = request
                else { return false }
                #expect(sectionType == .meetingOverview)
                #expect(expectedRevisionID == revisionID)
                #expect(values[itemID] == "persist through application action")
                #expect(!locked)
                await gate.block()
                return true
            }
        }

        await gate.waitUntilEntered()
        #expect(state.selectedSection == .intake)
        #expect(state.isEditorSaveInFlight)
        await gate.release()
        let effect = await resolution.value

        #expect(effect == MediaReviewNavigationEffect.none)
        #expect(state.selectedSection == .history)
        #expect(!state.briefing.isDirty)
        #expect(!state.isEditorSaveInFlight)
    }

    @Test @MainActor
    func newerEditDuringPendingSavePreventsNavigationAndIsRePresented() throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(247, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(248, RevisionID.self),
            itemTexts: [itemID: "published value"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "submitted value"
        state.requestSection(.history)
        let operation = try #require(state.beginPendingNavigationSave())

        state.briefing.itemTexts[itemID] = "newer unpublished value"
        let effect = state.completePendingNavigationAfterSave(
            operation,
            succeeded: true
        )

        #expect(effect == nil)
        #expect(state.selectedSection == .intake)
        #expect(state.briefing.isDirty)
        #expect(
            state.briefing.itemTexts[itemID] == "newer unpublished value"
        )
        #expect(state.isNavigationConfirmationPresented)
    }

    @Test @MainActor
    func dialogAutoDismissCannotCancelAnInFlightSaveAndFailureRePresentsIt() throws {
        let state = MediaReviewSceneState()
        let itemID = stateID(48, BriefingItemID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(148, RevisionID.self),
            itemTexts: [itemID: "published value"],
            isLocked: false
        )
        state.briefing.itemTexts[itemID] = "unpublished"
        state.requestSection(.history)
        let operation = try #require(state.beginPendingNavigationSave())

        state.navigationConfirmationPresentationChanged(isPresented: false)
        #expect(state.isEditorSaveInFlight)
        #expect(!state.isNavigationConfirmationPresented)
        #expect(state.discardChangesAndResolvePending() == nil)
        state.cancelPendingNavigation()
        #expect(state.isEditorSaveInFlight)

        #expect(
            state.completePendingNavigationAfterSave(
                operation,
                succeeded: false
            ) == nil
        )
        #expect(state.isNavigationConfirmationPresented)
        #expect(state.selectedSection == .intake)
        #expect(state.briefing.itemTexts[itemID] == "unpublished")
    }

    @Test @MainActor
    func workspaceOpenLocksNavigationUntilTheApplicationActionCompletes() async throws {
        let state = MediaReviewSceneState()
        let workspaceB = URL(fileURLWithPath: "/synthetic-workspace-b")
        #expect(
            state.requestWorkspaceChange(to: workspaceB)
                == .openWorkspace(workspaceB)
        )
        let operation = try #require(
            state.beginWorkspaceChange(to: workspaceB)
        )
        let gate = SceneStateAsyncGate()

        let resolution = Task { @MainActor in
            await state.resolveWorkspaceChange(operation) { url in
                #expect(url == workspaceB)
                await gate.block()
            }
        }

        await gate.waitUntilEntered()
        #expect(state.isInteractionLocked)
        state.requestSection(.history)
        #expect(state.selectedSection == .intake)
        #expect(
            state.requestWorkspaceChange(
                to: URL(fileURLWithPath: "/synthetic-workspace-c")
            ) == nil
        )

        await gate.release()
        await resolution.value
        #expect(!state.isInteractionLocked)
        state.requestSection(.history)
        #expect(state.selectedSection == .history)
    }

    @Test @MainActor
    func cleanBriefingSectionStillProducesAnExplicitConfirmationAction() throws {
        let state = MediaReviewSceneState()
        let revisionID = stateID(149, RevisionID.self)
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: revisionID,
            itemTexts: [:],
            isLocked: false
        )
        #expect(!state.briefing.isDirty)

        let operation = try #require(state.beginDirectBriefingSave())
        #expect(state.isInteractionLocked)
        #expect(!state.hasUnsavedEditorChanges)
        guard case let .briefing(
            sectionType,
            expectedRevisionID,
            values,
            locked
        ) = operation.request
        else {
            Issue.record("Expected a briefing confirmation operation.")
            return
        }
        #expect(sectionType == .meetingOverview)
        #expect(expectedRevisionID == revisionID)
        #expect(values.isEmpty)
        #expect(!locked)
        #expect(
            state.completeDirectEditorSave(operation, succeeded: true)
        )
        #expect(!state.isEditorSaveInFlight)
    }

    @Test @MainActor
    func applicationDiscardClearsEveryEditorDraftWithoutChangingSelection() {
        let state = MediaReviewSceneState()
        let transcriptID = stateID(250, TranscriptSegmentID.self)
        let positionID = stateID(251, PositionID.self)
        let itemID = stateID(252, BriefingItemID.self)
        state.selectedSection = .history
        state.transcript.hydrateSelection(
            segmentID: transcriptID,
            transcriptRevisionID: stateID(253, RevisionID.self),
            translationRevisionID: nil,
            transcriptText: "published transcript",
            translationText: ""
        )
        state.analysis.hydrateSelection(
            positionID: positionID,
            revisionID: stateID(254, RevisionID.self),
            positionType: .supports,
            statement: "published position",
            reservations: "",
            conditions: ""
        )
        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(255, RevisionID.self),
            itemTexts: [itemID: "published briefing"],
            isLocked: false
        )
        state.transcript.transcriptText = "draft transcript"
        state.analysis.statement = "draft position"
        state.briefing.itemTexts[itemID] = "draft briefing"

        state.discardAllEditorChanges()

        #expect(state.selectedSection == .history)
        #expect(!state.hasUnsavedEditorChanges)
        #expect(state.transcript.transcriptText == "published transcript")
        #expect(state.analysis.statement == "published position")
        #expect(
            state.briefing.itemTexts[itemID] == "published briefing"
        )
    }

    @Test @MainActor
    func applicationTerminationPolicyPrioritizesEveryInFlightOperation() throws {
        let state = MediaReviewSceneState()
        #expect(state.applicationTerminationRequirement == .none)

        state.transcript.hydrateSelection(
            segmentID: stateID(260, TranscriptSegmentID.self),
            transcriptRevisionID: stateID(261, RevisionID.self),
            translationRevisionID: nil,
            transcriptText: "published transcript",
            translationText: ""
        )
        state.transcript.transcriptText = "dirty transcript"
        #expect(
            state.applicationTerminationRequirement == .unsavedEditorChanges
        )
        state.discardAllEditorChanges()

        let workspaceOperation = try #require(
            state.beginWorkspaceChange(
                to: URL(fileURLWithPath: "/synthetic-workspace-b")
            )
        )
        #expect(
            state.applicationTerminationRequirement == .operationInFlight
        )
        state.completeWorkspaceChange(workspaceOperation)

        state.briefing.hydrateSelection(
            sectionType: .meetingOverview,
            revisionID: stateID(262, RevisionID.self),
            itemTexts: [:],
            isLocked: false
        )
        let cleanSave = try #require(state.beginDirectBriefingSave())
        #expect(!state.hasUnsavedEditorChanges)
        #expect(
            state.applicationTerminationRequirement == .operationInFlight
        )
        #expect(
            state.completeDirectEditorSave(cleanSave, succeeded: true)
        )
        #expect(state.applicationTerminationRequirement == .none)
    }

    @Test @MainActor
    func transientlyMissingReviewDoesNotEraseAnUnpublishedEditorDraft() {
        let state = MediaReviewSceneState()
        let transcriptID = stateID(50, TranscriptSegmentID.self)
        let positionID = stateID(51, PositionID.self)
        let itemID = stateID(52, BriefingItemID.self)

        state.transcript.select(transcriptID)
        state.transcript.transcriptText = "retain transcript"
        state.transcript.reconcile(with: nil)
        #expect(state.transcript.selectedSegmentID == transcriptID)
        #expect(state.transcript.transcriptText == "retain transcript")

        state.analysis.select(positionID)
        state.analysis.statement = "retain position"
        state.analysis.reconcile(with: nil)
        #expect(state.analysis.selectedPositionID == positionID)
        #expect(state.analysis.statement == "retain position")

        state.briefing.select(.majorIssues)
        state.briefing.itemTexts[itemID] = "retain briefing"
        state.briefing.reconcile(with: nil)
        #expect(state.briefing.selectedSectionType == .majorIssues)
        #expect(state.briefing.itemTexts[itemID] == "retain briefing")
    }
}

private actor SceneStateAsyncGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        entered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters.removeAll()
    }
}

private func stateID<Tag>(
    _ suffix: Int,
    _ type: StableID<Tag>.Type
) -> StableID<Tag> {
    StableID<Tag>(
        UUID(uuidString: String(format: "52000000-0000-0000-0000-%012d", suffix))!
    )
}
