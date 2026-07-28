import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

@MainActor
@Observable
public final class MediaReviewSceneState {
    public var selectedSection: MediaReviewSection? = .intake
    public var meetingTitle = ""
    public var dataClassification: DataClassification = .internal
    public var codexTextProcessingAllowed = false
    public var transcriptionSelection:
        ProviderModelSelectionRecord?
    public var remoteSpeechToTextAllowed = false
    public var remoteAudioUploadAcknowledged = false
    public var approvedRemoteSTTProviderIdentifier:
        String?
    public var selectedTrack: MediaTrackIdentifier?
    public var speechSourceKind: SpeechSourceKind = .unknown
    public var languageTag = ""
    public var transcriptSourceLanguageTag = "en"
    public var transcriptTargetLanguageTag = ""
    public var manualTranscriptText = ""
    public var manualTranslationText = ""
    public var manualCoverageConfirmed = false
    public var analysisClaimsConfirmed = false
    public var briefingExportFileName = "meeting-briefing"
    public var captureMode: CaptureMode = .microphoneOnly
    public var selectedMicrophoneDeviceID: String?
    public var microphoneSpeechSourceKind: SpeechSourceKind = .originalSpeakerAudio
    public var applicationSpeechSourceKind: SpeechSourceKind = .originalSpeakerAudio
    public var recordingAcknowledged = false
    public var unWebTVURL = "" {
        didSet {
            guard unWebTVURL != oldValue else { return }
            unWebTVAuthorizedCanonicalURL = nil
        }
    }
    private var unWebTVAuthorizedCanonicalURL: String?
    public var reviewedUNTitle = ""
    public var reviewedUNDescription = ""
    public var reviewedUNProductionDate = ""
    public var reviewedUNLanguageAvailability = ""
    public var historyActorOrCountry = ""
    public var historyTopic = ""
    public var historyBody = ""
    public var historyMeetingType = ""
    public var historyStartDate = ""
    public var historyEndDate = ""
    public var selectedCurrentHistoryRevisionID: RevisionID?
    public var selectedPriorHistoryRevisionID: RevisionID?
    public let learnedPreferenceEditor = LearnedPreferenceEditorState()
    public var pendingPermanentDeletion: WorkspaceTrashItem?
    public var confirmHistoricalChange = false

    public internal(set) var transcript = TranscriptEditorDraft()
    public internal(set) var analysis = AnalysisEditorDraft()
    public internal(set) var briefing = BriefingEditorDraft()

    var pendingNavigation: MediaReviewPendingNavigation?
    private(set) var isResolvingPendingSave = false
    private(set) var editorSaveInFlight: MediaReviewEditorSaveOperation?
    private(set) var workspaceChangeInFlight: MediaReviewWorkspaceChangeOperation?
    private var destinationAvailability = MediaReviewDestinationAvailability()

    public init() {}

    public var learnedPreferenceKind: LearnedPreferenceKind {
        get { learnedPreferenceEditor.kind }
        set { learnedPreferenceEditor.kind = newValue }
    }

    public var learnedPreferenceValue: String {
        get { learnedPreferenceEditor.value }
        set { learnedPreferenceEditor.value = newValue }
    }

    public var editingLearnedPreferenceID: LearnedPreferenceID? {
        get { learnedPreferenceEditor.editingPreferenceID }
        set {
            learnedPreferenceEditor.editingPreferenceID =
                newValue
        }
    }

    public var editingLearnedPreferenceVersion: UInt64? {
        get { learnedPreferenceEditor.editingPreferenceVersion }
        set {
            learnedPreferenceEditor.editingPreferenceVersion =
                newValue
        }
    }

    public var confirmPreferenceReset: Bool {
        get {
            learnedPreferenceEditor
                .isResetConfirmationPresented
        }
        set {
            learnedPreferenceEditor
                .isResetConfirmationPresented = newValue
        }
    }

    public var validatedUNWebTVURL: URL? {
        validatedUNWebTVAssetURL?.url
    }

    public var unWebTVNetworkAuthorized: Bool {
        get {
            guard let validated = validatedUNWebTVAssetURL else { return false }
            return unWebTVAuthorizedCanonicalURL == validated.absoluteString
        }
        set {
            guard newValue,
                  let validated = validatedUNWebTVAssetURL
            else {
                unWebTVAuthorizedCanonicalURL = nil
                return
            }
            unWebTVAuthorizedCanonicalURL = validated.absoluteString
        }
    }

    func consumeUNWebTVNetworkAuthorization(
        for validatedURL: ValidatedUNWebTVAssetURL
    ) -> Bool {
        guard unWebTVAuthorizedCanonicalURL == validatedURL.absoluteString
        else { return false }
        unWebTVAuthorizedCanonicalURL = nil
        return true
    }

    private var validatedUNWebTVAssetURL: ValidatedUNWebTVAssetURL? {
        let normalized = unWebTVURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return try? ValidatedUNWebTVAssetURL(normalized)
    }

    public var hasUnsavedEditorChanges: Bool {
        transcript.isDirty || analysis.isDirty || briefing.isDirty
    }

    public var applicationTerminationRequirement:
        MediaReviewApplicationTerminationRequirement
    {
        if isInteractionLocked {
            return .operationInFlight
        }
        return hasUnsavedEditorChanges ? .unsavedEditorChanges : .none
    }

    var isEditorSaveInFlight: Bool {
        editorSaveInFlight != nil
    }

    public var isInteractionLocked: Bool {
        editorSaveInFlight != nil || workspaceChangeInFlight != nil
    }

    var isNavigationConfirmationPresented: Bool {
        pendingNavigation != nil && !isResolvingPendingSave
    }

    var canSavePendingChanges: Bool {
        pendingSaveRequest != nil
    }

    var navigationConfirmationMessage: String {
        if transcript.dirtyOperationCount > 1 {
            return "More than one independent Transcript draft is unsaved. Keep editing and save each draft separately in Transcript Review, or discard all unpublished drafts before leaving."
        }
        return "Save the current unpublished editor draft, discard it, or keep editing before continuing."
    }

    func requestSection(_ section: MediaReviewSection?) {
        guard destinationAvailability.includes(section),
              section != selectedSection,
              pendingNavigation == nil,
              !isInteractionLocked
        else { return }
        guard hasUnsavedEditorChanges else {
            selectedSection = section
            return
        }
        pendingNavigation = .section(section)
    }

    func requestWorkspaceChange(to url: URL) -> MediaReviewNavigationEffect? {
        guard pendingNavigation == nil, !isInteractionLocked else { return nil }
        guard hasUnsavedEditorChanges else { return .openWorkspace(url) }
        pendingNavigation = .workspace(url)
        return nil
    }

    func requestMediaImport() -> MediaReviewNavigationEffect? {
        guard pendingNavigation == nil, !isInteractionLocked else { return nil }
        guard hasUnsavedEditorChanges else { return .importPendingMedia }
        pendingNavigation = .mediaImport
        return nil
    }

    func requestTranscriptSelection(_ segmentID: TranscriptSegmentID?) {
        guard segmentID != transcript.selectedSegmentID,
              pendingNavigation == nil,
              !isInteractionLocked
        else {
            return
        }
        guard !transcript.isDirty else {
            pendingNavigation = .transcript(segmentID)
            return
        }
        transcript.select(segmentID)
    }

    func requestAnalysisSelection(_ positionID: PositionID?) {
        guard positionID != analysis.selectedPositionID,
              pendingNavigation == nil,
              !isInteractionLocked
        else {
            return
        }
        guard !analysis.isDirty else {
            pendingNavigation = .analysis(positionID)
            return
        }
        analysis.select(positionID)
    }

    func requestBriefingSelection(_ sectionType: BriefingSectionType?) {
        guard sectionType != briefing.selectedSectionType,
              pendingNavigation == nil,
              !isInteractionLocked
        else {
            return
        }
        guard !briefing.isDirty else {
            pendingNavigation = .briefing(sectionType)
            return
        }
        briefing.select(sectionType)
    }

    func cancelPendingNavigation() {
        guard !isInteractionLocked else { return }
        isResolvingPendingSave = false
        pendingNavigation = nil
    }

    func navigationConfirmationPresentationChanged(
        isPresented: Bool
    ) {
        if !isPresented, !isResolvingPendingSave {
            cancelPendingNavigation()
        }
    }

    func beginPendingNavigationSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation != nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              let request = pendingSaveRequest
        else { return nil }
        isResolvingPendingSave = true
        return beginEditorSave(request)
    }

    func beginDirectTranscriptSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation == nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              transcript.transcriptIsDirty,
              let revisionID = transcript.transcriptRevisionID
        else { return nil }
        return beginEditorSave(
            .transcript(
                revisionID: revisionID,
                text: transcript.transcriptText
            )
        )
    }

    func beginDirectTranslationSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation == nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              transcript.translationIsDirty,
              let revisionID = transcript.translationRevisionID
        else { return nil }
        return beginEditorSave(
            .translation(
                revisionID: revisionID,
                text: transcript.translationText
            )
        )
    }

    func beginDirectSpeakerSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation == nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              transcript.speakerIsDirty,
              let revisionID = transcript.transcriptRevisionID
        else { return nil }
        return beginEditorSave(
            .speaker(
                transcriptRevisionID: revisionID,
                displayName: transcript.speakerName
            )
        )
    }

    func beginWorkspaceChange(
        to url: URL
    ) -> MediaReviewWorkspaceChangeOperation? {
        guard pendingNavigation == nil, !isInteractionLocked else { return nil }
        let operation = MediaReviewWorkspaceChangeOperation(url: url)
        workspaceChangeInFlight = operation
        return operation
    }

    func resolveWorkspaceChange(
        _ operation: MediaReviewWorkspaceChangeOperation,
        using open: @MainActor (URL) async -> Void
    ) async {
        guard workspaceChangeInFlight?.id == operation.id else { return }
        await open(operation.url)
        completeWorkspaceChange(operation)
    }

    func completeWorkspaceChange(
        _ operation: MediaReviewWorkspaceChangeOperation
    ) {
        guard workspaceChangeInFlight?.id == operation.id else { return }
        workspaceChangeInFlight = nil
    }

    func beginDirectAnalysisSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation == nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              analysis.isDirty,
              analysis.isSourceRevisionCurrent,
              let revisionID = analysis.positionRevisionID
        else { return nil }
        return beginEditorSave(
            .position(
                revisionID: revisionID,
                positionType: analysis.positionType,
                statement: analysis.statement,
                reservations: analysis.reservations,
                conditions: analysis.conditions
            )
        )
    }

    func beginDirectBriefingSave() -> MediaReviewEditorSaveOperation? {
        guard pendingNavigation == nil,
              editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              let sectionType = briefing.selectedSectionType,
              let revisionID = briefing.sectionRevisionID,
              briefing.isSourceRevisionCurrent
        else { return nil }
        return beginEditorSave(
            .briefing(
                sectionType: sectionType,
                expectedRevisionID: revisionID,
                editedTextByItemID: briefing.itemTexts,
                locked: briefing.isLocked
            )
        )
    }

    @discardableResult
    func completeDirectEditorSave(
        _ operation: MediaReviewEditorSaveOperation,
        succeeded: Bool,
        updatedReviews: MediaReviewEditorReviewSnapshot =
            MediaReviewEditorReviewSnapshot()
    ) -> Bool {
        guard editorSaveInFlight?.id == operation.id else { return false }
        editorSaveInFlight = nil
        guard succeeded else { return false }
        markEditorDraftSaved(
            for: operation.request,
            updatedReviews: updatedReviews
        )
        return true
    }

    func discardChangesAndResolvePending() -> MediaReviewNavigationEffect? {
        guard pendingNavigation != nil, !isInteractionLocked else { return nil }
        isResolvingPendingSave = false
        discardEditorDrafts()
        return applyPendingNavigation()
    }

    func completePendingNavigationAfterSave(
        _ operation: MediaReviewEditorSaveOperation,
        succeeded: Bool,
        updatedReviews: MediaReviewEditorReviewSnapshot =
            MediaReviewEditorReviewSnapshot()
    ) -> MediaReviewNavigationEffect? {
        guard editorSaveInFlight?.id == operation.id else { return nil }
        editorSaveInFlight = nil
        isResolvingPendingSave = false
        guard succeeded, pendingNavigation != nil else { return nil }
        markEditorDraftSaved(
            for: operation.request,
            updatedReviews: updatedReviews
        )
        guard !hasUnsavedEditorChanges else { return nil }
        return applyPendingNavigation()
    }

    func resolvePendingNavigationSave(
        _ operation: MediaReviewEditorSaveOperation,
        updatedReviews:
            @MainActor () -> MediaReviewEditorReviewSnapshot = {
                MediaReviewEditorReviewSnapshot()
            },
        using save: @MainActor (MediaReviewDraftSave) async -> Bool
    ) async -> MediaReviewNavigationEffect? {
        guard editorSaveInFlight?.id == operation.id else { return nil }
        let succeeded = await save(operation.request)
        return completePendingNavigationAfterSave(
            operation,
            succeeded: succeeded,
            updatedReviews: updatedReviews()
        )
    }

    func resetForWorkspaceChange() {
        selectedSection = .intake
        meetingTitle = ""
        dataClassification = .internal
        codexTextProcessingAllowed = false
        transcriptionSelection = nil
        remoteSpeechToTextAllowed = false
        remoteAudioUploadAcknowledged = false
        approvedRemoteSTTProviderIdentifier = nil
        selectedTrack = nil
        speechSourceKind = .unknown
        languageTag = ""
        transcriptSourceLanguageTag = "en"
        transcriptTargetLanguageTag = ""
        manualTranscriptText = ""
        manualTranslationText = ""
        manualCoverageConfirmed = false
        analysisClaimsConfirmed = false
        briefingExportFileName = "meeting-briefing"
        captureMode = .microphoneOnly
        selectedMicrophoneDeviceID = nil
        microphoneSpeechSourceKind = .originalSpeakerAudio
        applicationSpeechSourceKind = .originalSpeakerAudio
        recordingAcknowledged = false
        unWebTVURL = ""
        unWebTVAuthorizedCanonicalURL = nil
        reviewedUNTitle = ""
        reviewedUNDescription = ""
        reviewedUNProductionDate = ""
        reviewedUNLanguageAvailability = ""
        historyActorOrCountry = ""
        historyTopic = ""
        historyBody = ""
        historyMeetingType = ""
        historyStartDate = ""
        historyEndDate = ""
        selectedCurrentHistoryRevisionID = nil
        selectedPriorHistoryRevisionID = nil
        learnedPreferenceEditor.reset()
        pendingPermanentDeletion = nil
        confirmHistoricalChange = false
        pendingNavigation = nil
        isResolvingPendingSave = false
        editorSaveInFlight = nil
        destinationAvailability = MediaReviewDestinationAvailability()
        transcript.reset()
        analysis.reset()
        briefing.reset()
    }

    func resetForAcceptedMedia() {
        selectedSection = .intake
        transcriptSourceLanguageTag = "en"
        transcriptTargetLanguageTag = ""
        remoteAudioUploadAcknowledged = false
        manualTranscriptText = ""
        manualTranslationText = ""
        manualCoverageConfirmed = false
        analysisClaimsConfirmed = false
        briefingExportFileName = "meeting-briefing"
        pendingNavigation = nil
        isResolvingPendingSave = false
        editorSaveInFlight = nil
        destinationAvailability = MediaReviewDestinationAvailability()
        transcript.reset()
        analysis.reset()
        briefing.reset()
    }

    func isDestinationAvailable(_ section: MediaReviewSection?) -> Bool {
        destinationAvailability.includes(section)
    }

    func reconcileDestinationAvailability(
        canonicalJobSucceeded: Bool,
        hasTranscriptReview: Bool,
        hasHumanConfirmedAnalysis: Bool
    ) {
        destinationAvailability = MediaReviewDestinationAvailability(
            canonicalJobSucceeded: canonicalJobSucceeded,
            hasTranscriptReview: hasTranscriptReview,
            hasHumanConfirmedAnalysis: hasHumanConfirmedAnalysis
        )
        guard destinationAvailability.includes(selectedSection) else {
            selectedSection = .intake
            if !isInteractionLocked {
                pendingNavigation = nil
                isResolvingPendingSave = false
            }
            return
        }

        if let pendingNavigation,
           !destinationAvailability.includes(pendingNavigation),
           !isInteractionLocked
        {
            self.pendingNavigation = nil
            isResolvingPendingSave = false
        }
    }

    public func discardAllEditorChanges() {
        guard !isInteractionLocked else { return }
        pendingNavigation = nil
        isResolvingPendingSave = false
        discardEditorDrafts()
    }

    func prepareForApplicationTerminationSave() -> Bool {
        guard !isInteractionLocked else { return false }
        pendingNavigation = nil
        isResolvingPendingSave = false
        return true
    }

    func beginNextApplicationTerminationSave() -> MediaReviewEditorSaveOperation? {
        guard editorSaveInFlight == nil,
              workspaceChangeInFlight == nil,
              let request = pendingSaveRequest
        else { return nil }
        return beginEditorSave(request)
    }

    var pendingSaveRequest: MediaReviewDraftSave? {
        let dirtyEditorCount = [transcript.isDirty, analysis.isDirty, briefing.isDirty]
            .filter { $0 }.count
        guard dirtyEditorCount == 1 else { return nil }

        if transcript.isDirty {
            guard transcript.dirtyOperationCount == 1 else { return nil }
            if transcript.transcriptIsDirty,
               let revisionID = transcript.transcriptRevisionID
            {
                return .transcript(revisionID: revisionID, text: transcript.transcriptText)
            }
            if transcript.translationIsDirty,
               let revisionID = transcript.translationRevisionID
            {
                return .translation(revisionID: revisionID, text: transcript.translationText)
            }
            if transcript.speakerIsDirty,
               let revisionID = transcript.transcriptRevisionID
            {
                return .speaker(
                    transcriptRevisionID: revisionID,
                    displayName: transcript.speakerName
                )
            }
        }
        if analysis.isDirty,
           analysis.isSourceRevisionCurrent,
           let revisionID = analysis.positionRevisionID
        {
            return .position(
                revisionID: revisionID,
                positionType: analysis.positionType,
                statement: analysis.statement,
                reservations: analysis.reservations,
                conditions: analysis.conditions
            )
        }
        if briefing.isDirty,
           let sectionType = briefing.selectedSectionType,
           let revisionID = briefing.sectionRevisionID,
           briefing.isSourceRevisionCurrent
        {
            return .briefing(
                sectionType: sectionType,
                expectedRevisionID: revisionID,
                editedTextByItemID: briefing.itemTexts,
                locked: briefing.isLocked
            )
        }
        return nil
    }

    private func applyPendingNavigation() -> MediaReviewNavigationEffect? {
        guard let pendingNavigation else { return nil }
        self.pendingNavigation = nil
        guard destinationAvailability.includes(pendingNavigation) else {
            return MediaReviewNavigationEffect.none
        }
        switch pendingNavigation {
        case let .section(section):
            selectedSection = section
            return MediaReviewNavigationEffect.none
        case let .workspace(url):
            return .openWorkspace(url)
        case .mediaImport:
            return .importPendingMedia
        case let .transcript(segmentID):
            transcript.select(segmentID)
            return MediaReviewNavigationEffect.none
        case let .analysis(positionID):
            analysis.select(positionID)
            return MediaReviewNavigationEffect.none
        case let .briefing(sectionType):
            briefing.select(sectionType)
            return MediaReviewNavigationEffect.none
        }
    }

    private func discardEditorDrafts() {
        transcript.discardChanges()
        analysis.discardChanges()
        briefing.discardChanges()
    }

    private func beginEditorSave(
        _ request: MediaReviewDraftSave
    ) -> MediaReviewEditorSaveOperation {
        let operation = MediaReviewEditorSaveOperation(request: request)
        editorSaveInFlight = operation
        return operation
    }

    private func markEditorDraftSaved(
        for request: MediaReviewDraftSave,
        updatedReviews: MediaReviewEditorReviewSnapshot
    ) {
        switch request {
        case let .transcript(_, text):
            transcript.markTranscriptSaved(
                text,
                updatedReview: updatedReviews.transcript
            )
        case let .translation(_, text):
            transcript.markTranslationSaved(
                text,
                updatedReview: updatedReviews.transcript
            )
        case let .speaker(_, displayName):
            transcript.markSpeakerSaved(
                displayName,
                updatedReview: updatedReviews.transcript
            )
        case let .position(_, positionType, statement, reservations, conditions):
            analysis.markSaved(
                positionType: positionType,
                statement: statement,
                reservations: reservations,
                conditions: conditions,
                updatedReview: updatedReviews.analysis
            )
        case let .briefing(_, _, editedTextByItemID, locked):
            briefing.markSaved(
                itemTexts: editedTextByItemID,
                isLocked: locked,
                updatedReview: updatedReviews.briefing
            )
        }
    }

}

@MainActor
@Observable
public final class TranscriptEditorDraft {
    public private(set) var selectedSegmentID: TranscriptSegmentID?
    public private(set) var transcriptRevisionID: RevisionID?
    public private(set) var translationRevisionID: RevisionID?
    public var transcriptText = ""
    public var translationText = ""
    public var speakerName = ""

    private var savedTranscriptText = ""
    private var savedTranslationText = ""

    public var transcriptIsDirty: Bool { transcriptText != savedTranscriptText }
    public var translationIsDirty: Bool { translationText != savedTranslationText }
    public var speakerIsDirty: Bool {
        !speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var isDirty: Bool {
        transcriptIsDirty || translationIsDirty || speakerIsDirty
    }
    public var dirtyOperationCount: Int {
        [transcriptIsDirty, translationIsDirty, speakerIsDirty].filter { $0 }.count
    }

    func reconcile(with review: TranscriptReviewBundle?) {
        guard let review, !review.transcriptSegments.isEmpty else {
            if !isDirty { reset() }
            return
        }
        let selectedSegment = review.transcriptSegments.first {
            $0.segmentID == selectedSegmentID
        }
        if selectedSegment == nil, selectedSegmentID != nil, isDirty {
            return
        }
        let segment = selectedSegment ?? review.transcriptSegments[0]
        if selectedSegmentID != segment.segmentID {
            select(segment.segmentID)
        }
        guard !isDirty else { return }
        let translation = review.translations.first {
            $0.sourceSegmentRevision.revisionID == segment.revision.revisionID
        }
        load(segment: segment, translation: translation)
    }

    func select(_ segmentID: TranscriptSegmentID?) {
        selectedSegmentID = segmentID
        transcriptRevisionID = nil
        translationRevisionID = nil
        transcriptText = ""
        translationText = ""
        speakerName = ""
        savedTranscriptText = ""
        savedTranslationText = ""
    }

    func markSaved() {
        savedTranscriptText = transcriptText
        savedTranslationText = translationText
        speakerName = ""
    }

    func markTranscriptSaved(
        _ text: String,
        updatedReview: TranscriptReviewBundle?
    ) {
        guard let segment = selectedSegment(in: updatedReview) else {
            savedTranscriptText = text
            return
        }
        transcriptRevisionID = segment.revision.revisionID
        if transcriptText == text {
            transcriptText = segment.text
        }
        savedTranscriptText = segment.text
    }

    func markTranslationSaved(
        _ text: String,
        updatedReview: TranscriptReviewBundle?
    ) {
        guard let segment = selectedSegment(in: updatedReview),
              let translation = updatedReview?.translations.first(where: {
                  $0.sourceSegmentRevision.revisionID
                      == segment.revision.revisionID
              })
        else {
            savedTranslationText = text
            return
        }
        transcriptRevisionID = segment.revision.revisionID
        translationRevisionID = translation.revision.revisionID
        if translationText == text {
            translationText = translation.translatedText
        }
        savedTranslationText = translation.translatedText
    }

    func markSpeakerSaved(
        _ displayName: String,
        updatedReview: TranscriptReviewBundle?
    ) {
        if let segment = selectedSegment(in: updatedReview) {
            transcriptRevisionID = segment.revision.revisionID
        }
        if speakerName == displayName {
            speakerName = ""
        }
    }

    func discardTranscriptChanges() {
        transcriptText = savedTranscriptText
    }

    func discardTranslationChanges() {
        translationText = savedTranslationText
    }

    func discardSpeakerChanges() {
        speakerName = ""
    }

    func discardChanges() {
        transcriptText = savedTranscriptText
        translationText = savedTranslationText
        speakerName = ""
    }

    func reset() {
        select(nil)
    }

    private func load(
        segment: TranscriptSegmentV1,
        translation: TranslationSegmentV1?
    ) {
        hydrateSelection(
            segmentID: segment.segmentID,
            transcriptRevisionID: segment.revision.revisionID,
            translationRevisionID: translation?.revision.revisionID,
            transcriptText: segment.text,
            translationText: translation?.translatedText ?? ""
        )
    }

    func hydrateSelection(
        segmentID: TranscriptSegmentID,
        transcriptRevisionID: RevisionID,
        translationRevisionID: RevisionID?,
        transcriptText: String,
        translationText: String
    ) {
        selectedSegmentID = segmentID
        self.transcriptRevisionID = transcriptRevisionID
        self.translationRevisionID = translationRevisionID
        self.transcriptText = transcriptText
        self.translationText = translationText
        speakerName = ""
        savedTranscriptText = transcriptText
        savedTranslationText = translationText
    }

    private func selectedSegment(
        in review: TranscriptReviewBundle?
    ) -> TranscriptSegmentV1? {
        guard let selectedSegmentID else { return nil }
        return review?.transcriptSegments.first {
            $0.segmentID == selectedSegmentID
        }
    }
}

@MainActor
@Observable
public final class AnalysisEditorDraft {
    public private(set) var selectedPositionID: PositionID?
    public private(set) var positionRevisionID: RevisionID?
    public private(set) var isSourceRevisionCurrent = true
    public var positionType: PositionType = .uncertain
    public var statement = ""
    public var reservations = ""
    public var conditions = ""

    private var savedPositionType: PositionType = .uncertain
    private var savedStatement = ""
    private var savedReservations = ""
    private var savedConditions = ""

    public var isDirty: Bool {
        positionType != savedPositionType
            || statement != savedStatement
            || reservations != savedReservations
            || conditions != savedConditions
    }

    func reconcile(with review: AnalysisReviewBundle?) {
        guard let review, !review.positions.isEmpty else {
            if isDirty {
                isSourceRevisionCurrent = false
            } else {
                reset()
            }
            return
        }
        let selectedPosition = review.positions.first {
            $0.positionID == selectedPositionID
        }
        if selectedPosition == nil, selectedPositionID != nil, isDirty {
            isSourceRevisionCurrent = false
            return
        }
        let position = selectedPosition ?? review.positions[0]
        if selectedPositionID != position.positionID {
            select(position.positionID)
        }
        guard !isDirty else {
            isSourceRevisionCurrent =
                positionRevisionID
                    == position.revision.revisionID
            return
        }
        load(position)
    }

    func select(_ positionID: PositionID?) {
        selectedPositionID = positionID
        positionRevisionID = nil
        isSourceRevisionCurrent = true
        positionType = .uncertain
        statement = ""
        reservations = ""
        conditions = ""
        markSaved()
    }

    func markSaved() {
        savedPositionType = positionType
        savedStatement = statement
        savedReservations = reservations
        savedConditions = conditions
    }

    func markSaved(
        positionType: PositionType,
        statement: String,
        reservations: String,
        conditions: String,
        updatedReview: AnalysisReviewBundle? = nil
    ) {
        if let selectedPositionID,
           let updatedPosition = updatedReview?.positions.first(where: {
               $0.positionID == selectedPositionID
           })
        {
            positionRevisionID = updatedPosition.revision.revisionID
            isSourceRevisionCurrent = true
        }
        savedPositionType = positionType
        savedStatement = statement
        savedReservations = reservations
        savedConditions = conditions
    }

    func discardChanges() {
        positionType = savedPositionType
        statement = savedStatement
        reservations = savedReservations
        conditions = savedConditions
    }

    func reset() {
        select(nil)
    }

    private func load(_ position: PositionV1) {
        hydrateSelection(
            positionID: position.positionID,
            revisionID: position.revision.revisionID,
            positionType: position.positionType,
            statement: position.statement.text,
            reservations: position.reservations.map(\.text).joined(separator: "\n"),
            conditions: position.conditions.map(\.text).joined(separator: "\n")
        )
    }

    func hydrateSelection(
        positionID: PositionID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: String,
        conditions: String
    ) {
        selectedPositionID = positionID
        positionRevisionID = revisionID
        isSourceRevisionCurrent = true
        self.positionType = positionType
        self.statement = statement
        self.reservations = reservations
        self.conditions = conditions
        markSaved()
    }
}

@MainActor
@Observable
public final class BriefingEditorDraft {
    public private(set) var selectedSectionType: BriefingSectionType?
    public private(set) var sectionRevisionID: RevisionID?
    public private(set) var isSourceRevisionCurrent = true
    public var itemTexts: [BriefingItemID: String] = [:]
    public var isLocked = false

    private var savedItemTexts: [BriefingItemID: String] = [:]
    private var savedIsLocked = false

    public var isDirty: Bool {
        itemTexts != savedItemTexts || isLocked != savedIsLocked
    }

    func reconcile(with review: BriefingReviewBundle?) {
        guard let sections = review?.publication.sections, !sections.isEmpty else {
            if isDirty {
                isSourceRevisionCurrent = false
            } else {
                reset()
            }
            return
        }
        let selectedSection = sections.first {
            $0.sectionType == selectedSectionType
        }
        if selectedSection == nil, selectedSectionType != nil, isDirty {
            isSourceRevisionCurrent = false
            return
        }
        let section = selectedSection ?? sections[0]
        if selectedSectionType != section.sectionType {
            select(section.sectionType)
        }
        guard !isDirty else {
            isSourceRevisionCurrent =
                sectionRevisionID == section.revision.revisionID
            return
        }
        load(section)
    }

    func select(_ sectionType: BriefingSectionType?) {
        selectedSectionType = sectionType
        sectionRevisionID = nil
        isSourceRevisionCurrent = true
        itemTexts = [:]
        isLocked = false
        markSaved()
    }

    func markSaved() {
        savedItemTexts = itemTexts
        savedIsLocked = isLocked
    }

    func markSaved(
        itemTexts: [BriefingItemID: String],
        isLocked: Bool,
        updatedReview: BriefingReviewBundle? = nil
    ) {
        if let selectedSectionType,
           let updatedSection =
               updatedReview?.publication.sections.first(where: {
                   $0.sectionType == selectedSectionType
               })
        {
            sectionRevisionID = updatedSection.revision.revisionID
            isSourceRevisionCurrent = true
        }
        savedItemTexts = itemTexts
        savedIsLocked = isLocked
    }

    func discardChanges() {
        itemTexts = savedItemTexts
        isLocked = savedIsLocked
    }

    func reset() {
        select(nil)
    }

    private func load(_ section: BriefingSectionV1) {
        hydrateSelection(
            sectionType: section.sectionType,
            revisionID: section.revision.revisionID,
            itemTexts: Dictionary(uniqueKeysWithValues: section.items.map {
                ($0.itemID, $0.claim.text)
            }),
            isLocked: section.locked
        )
    }

    func hydrateSelection(
        sectionType: BriefingSectionType,
        revisionID: RevisionID,
        itemTexts: [BriefingItemID: String],
        isLocked: Bool
    ) {
        selectedSectionType = sectionType
        sectionRevisionID = revisionID
        isSourceRevisionCurrent = true
        self.itemTexts = itemTexts
        self.isLocked = isLocked
        markSaved()
    }
}

enum MediaReviewPendingNavigation {
    case section(MediaReviewSection?)
    case workspace(URL)
    case mediaImport
    case transcript(TranscriptSegmentID?)
    case analysis(PositionID?)
    case briefing(BriefingSectionType?)
}

private struct MediaReviewDestinationAvailability {
    var canonicalJobSucceeded = false
    var hasTranscriptReview = false
    var hasHumanConfirmedAnalysis = false

    func includes(_ section: MediaReviewSection?) -> Bool {
        switch section {
        case .transcript, .assistant:
            canonicalJobSucceeded
                && (section == .transcript || hasTranscriptReview)
        case .analysis:
            canonicalJobSucceeded && hasTranscriptReview
        case .briefing:
            canonicalJobSucceeded
                && hasTranscriptReview
                && hasHumanConfirmedAnalysis
        case .intake, .recording, .webMetadata, .history, .storage, nil:
            true
        }
    }

    func includes(_ navigation: MediaReviewPendingNavigation) -> Bool {
        switch navigation {
        case let .section(section):
            includes(section)
        case .workspace:
            true
        case .mediaImport:
            true
        case .transcript:
            canonicalJobSucceeded
        case .analysis:
            canonicalJobSucceeded && hasTranscriptReview
        case .briefing:
            canonicalJobSucceeded
                && hasTranscriptReview
                && hasHumanConfirmedAnalysis
        }
    }
}

enum MediaReviewNavigationEffect: Equatable {
    case none
    case openWorkspace(URL)
    case importPendingMedia
}

public enum MediaReviewApplicationTerminationRequirement:
    Equatable,
    Sendable
{
    case none
    case operationInFlight
    case unsavedEditorChanges
}

struct MediaReviewEditorReviewSnapshot {
    let transcript: TranscriptReviewBundle?
    let analysis: AnalysisReviewBundle?
    let briefing: BriefingReviewBundle?

    init(
        transcript: TranscriptReviewBundle? = nil,
        analysis: AnalysisReviewBundle? = nil,
        briefing: BriefingReviewBundle? = nil
    ) {
        self.transcript = transcript
        self.analysis = analysis
        self.briefing = briefing
    }
}

struct MediaReviewEditorSaveOperation: Identifiable, Sendable {
    let id = UUID()
    let request: MediaReviewDraftSave
}

struct MediaReviewWorkspaceChangeOperation: Identifiable, Sendable {
    let id = UUID()
    let url: URL
}

enum MediaReviewDraftSave: Sendable {
    case transcript(revisionID: RevisionID, text: String)
    case translation(revisionID: RevisionID, text: String)
    case speaker(transcriptRevisionID: RevisionID, displayName: String)
    case position(
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: String,
        conditions: String
    )
    case briefing(
        sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    )
}
