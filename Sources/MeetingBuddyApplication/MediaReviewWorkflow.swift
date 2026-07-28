import Foundation
import MeetingBuddyDomain

public struct WorkspaceReview: Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let displayName: String

    public init(workspaceID: WorkspaceID, displayName: String) {
        self.workspaceID = workspaceID
        self.displayName = displayName
    }
}

public struct PendingMediaReview: Hashable, Sendable {
    public let displayName: String
    public let inspection: MediaInspection

    public init(displayName: String, inspection: MediaInspection) {
        self.displayName = displayName
        self.inspection = inspection
    }
}

public struct ImportedSourceReview: Hashable, Sendable {
    public let assetID: SourceAssetID
    public let revisionID: RevisionID
    public let sourceHash: ContentDigest
    public let byteSize: UInt64
    public let format: ApprovedMediaFormat
    public let durationFrameCount: UInt64
    public let selectedTrack: MediaTrackIdentifier
    public let speechSourceKind: SpeechSourceKind

    public init(
        assetID: SourceAssetID,
        revisionID: RevisionID,
        sourceHash: ContentDigest,
        byteSize: UInt64,
        format: ApprovedMediaFormat,
        durationFrameCount: UInt64,
        selectedTrack: MediaTrackIdentifier,
        speechSourceKind: SpeechSourceKind
    ) {
        self.assetID = assetID
        self.revisionID = revisionID
        self.sourceHash = sourceHash
        self.byteSize = byteSize
        self.format = format
        self.durationFrameCount = durationFrameCount
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
    }
}

public struct MediaJobReview: Hashable, Sendable {
    public let jobID: JobID
    public let state: JobState
    public let completedUnitCount: UInt64
    public let totalUnitCount: UInt64
    public let currentNode: String?
    public let safeFailureSummary: String?
    public let canCancel: Bool
    public let canRetry: Bool
    public let outputRevisionIDs: [SemanticRevisionReference]
    public let privacyRoute: PrivacyRoute
    public let providerUsage: [ProviderUsageMetadata]

    public init(record: JobRecord) {
        jobID = record.jobID
        state = record.state
        completedUnitCount = record.progress.completedUnitCount
        totalUnitCount = record.progress.totalUnitCount
        currentNode = record.progress.currentNode
        safeFailureSummary = record.errorRecord?.safeSummary
        canCancel = !record.state.isTerminal
        canRetry = (record.state == .failed
            || record.state == .cancelled
            || record.state == .interrupted)
            && record.retryCount < record.maximumRetryCount
            && (record.state == .cancelled || record.errorRecord?.retryable == true)
        outputRevisionIDs = record.outputRevisionIDs
        privacyRoute = record.privacyRoute
        providerUsage = record.providerUsage
    }

    public var progressFraction: Double {
        guard totalUnitCount > 0 else { return 0 }
        return Double(completedUnitCount) / Double(totalUnitCount)
    }
}

/// A bounded application projection of the one media workflow that can be
/// resumed after reopening a workspace. It contains no source path, credential,
/// or one-time outbound authorization.
public struct RestoredMediaWorkflowReview: Sendable {
    public let meetingTitle: String
    public let dataClassification: DataClassification
    public let sourceLanguage: LanguageTag?
    public let codexTextProcessingAllowed: Bool
    public let speechToTextRoute:
        MeetingSpeechToTextRouteV1?
    public let importedSource: ImportedSourceReview?
    public let sourceReselectionJob: MediaJobReview?
    public let canonicalJob: MediaJobReview?
    public let transcriptJob: MediaJobReview?
    public let transcriptReview: TranscriptReviewBundle?
    public let analysisJob: MediaJobReview?
    public let analysisReview: AnalysisReviewBundle?
    public let briefingJob: MediaJobReview?
    public let briefingReview: BriefingReviewBundle?

    public init(
        meetingTitle: String,
        dataClassification: DataClassification,
        sourceLanguage: LanguageTag?,
        codexTextProcessingAllowed: Bool,
        speechToTextRoute:
            MeetingSpeechToTextRouteV1?,
        importedSource: ImportedSourceReview?,
        sourceReselectionJob:
            MediaJobReview? = nil,
        canonicalJob: MediaJobReview?,
        transcriptJob: MediaJobReview? = nil,
        transcriptReview: TranscriptReviewBundle? = nil,
        analysisJob: MediaJobReview? = nil,
        analysisReview: AnalysisReviewBundle? = nil,
        briefingJob: MediaJobReview? = nil,
        briefingReview: BriefingReviewBundle? = nil
    ) {
        self.meetingTitle = meetingTitle
        self.dataClassification = dataClassification
        self.sourceLanguage = sourceLanguage
        self.codexTextProcessingAllowed =
            codexTextProcessingAllowed
        self.speechToTextRoute =
            speechToTextRoute
        self.importedSource = importedSource
        self.sourceReselectionJob =
            sourceReselectionJob
        self.canonicalJob = canonicalJob
        self.transcriptJob = transcriptJob
        self.transcriptReview = transcriptReview
        self.analysisJob = analysisJob
        self.analysisReview = analysisReview
        self.briefingJob = briefingJob
        self.briefingReview = briefingReview
    }
}

public struct TranscriptRouteReview: Hashable, Sendable {
    public let transcription: ModelRouteDecision
    public let translation: ModelRouteDecision?
    public let selection: ProviderModelSelectionRecord?
    public let intelligenceConfigurationRevision: UInt64?
    public let remoteProviderConfiguration:
        RemoteProviderConfiguration?

    public init(
        transcription: ModelRouteDecision,
        translation: ModelRouteDecision?,
        selection: ProviderModelSelectionRecord? = nil,
        intelligenceConfigurationRevision: UInt64? = nil,
        remoteProviderConfiguration:
            RemoteProviderConfiguration? = nil
    ) {
        self.transcription = transcription
        self.translation = translation
        self.selection = selection
        self.intelligenceConfigurationRevision =
            intelligenceConfigurationRevision
        self.remoteProviderConfiguration =
            remoteProviderConfiguration
    }

    public var isOnDeviceReady: Bool {
        transcription.route == .appleOnDevice
            && (translation?.route == .appleOnDevice || translation == nil)
    }

    public var isReady: Bool {
        guard selection != nil else { return false }
        if remoteProviderConfiguration != nil {
            return transcription.route == .approvedExternal
                && transcription.providerIdentifier
                    == remoteProviderConfiguration?.identifier
                && remoteProviderConfiguration?
                    .connectionState == .ready
                && (
                    translation == nil
                        || translation?.route
                            == .appleOnDevice
                )
        }
        return isOnDeviceReady
    }

    public var sendsAudioOffDevice: Bool {
        remoteProviderConfiguration != nil
    }
}

public struct TranscriptStartSubmission: Sendable {
    public let sourceLanguage: LanguageTag
    public let targetLanguage: LanguageTag?
    public let transcriptionSelection:
        ProviderModelSelectionRecord?
    public let visibleRemoteAudioAuthorization: Bool

    public init(
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag?,
        transcriptionSelection:
            ProviderModelSelectionRecord? =
            ProviderModelSelectionRecord(
                providerIdentifier: "apple-speech",
                modelIdentifier:
                    "speech-analyzer-installed"
            ),
        visibleRemoteAudioAuthorization: Bool = false
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.transcriptionSelection =
            transcriptionSelection
        self.visibleRemoteAudioAuthorization =
            visibleRemoteAudioAuthorization
    }
}

public struct AnalysisRouteReview: Hashable, Sendable {
    public let analysis: ModelRouteDecision
    public let runtimeEvidence: AnalysisRuntimeEvidence

    public init(
        analysis: ModelRouteDecision,
        runtimeEvidence: AnalysisRuntimeEvidence
    ) {
        self.analysis = analysis
        self.runtimeEvidence = runtimeEvidence
    }

    public var isOnDeviceReady: Bool {
        analysis.route == .appleOnDevice
            && analysis.providerIdentifier == "apple-foundation-models"
            && runtimeEvidence.modelAvailable
            && runtimeEvidence.noOutboundMode
    }
}

public struct BriefingRouteReview: Hashable, Sendable {
    public let briefing: ModelRouteDecision
    public let runtimeEvidence: AnalysisRuntimeEvidence

    public init(
        briefing: ModelRouteDecision,
        runtimeEvidence: AnalysisRuntimeEvidence
    ) {
        self.briefing = briefing
        self.runtimeEvidence = runtimeEvidence
    }

    public var isOnDeviceReady: Bool {
        briefing.route == .appleOnDevice
            && briefing.providerIdentifier == "apple-foundation-models"
            && briefing.request.dataCategories
                == [.evidenceIdentifiers, .validatedIntelligenceClaims]
            && runtimeEvidence.modelAvailable
            && runtimeEvidence.noOutboundMode
    }
}

public enum TranscriptWorkflowError: Error, Sendable {
    case unavailable
}

public struct MediaImportSubmission: Sendable {
    public let meetingTitle: String
    public let dataClassification: DataClassification
    public let selectedTrack: MediaTrackIdentifier?
    public let speechSourceKind: SpeechSourceKind
    public let language: LanguageTag?
    public let codexTextProcessingAllowed: Bool
    public let transcriptionSelection:
        ProviderModelSelectionRecord?
    public let remoteSpeechToTextAllowed: Bool

    public init(
        meetingTitle: String,
        dataClassification: DataClassification,
        selectedTrack: MediaTrackIdentifier?,
        speechSourceKind: SpeechSourceKind,
        language: LanguageTag?,
        codexTextProcessingAllowed: Bool = false,
        transcriptionSelection:
            ProviderModelSelectionRecord? = nil,
        remoteSpeechToTextAllowed: Bool = false
    ) {
        self.meetingTitle = meetingTitle
        self.dataClassification = dataClassification
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
        self.language = language
        self.codexTextProcessingAllowed =
            codexTextProcessingAllowed
        self.transcriptionSelection =
            transcriptionSelection
        self.remoteSpeechToTextAllowed =
            remoteSpeechToTextAllowed
    }
}

public struct RecordingSetupReview: Hashable, Sendable {
    public let capability: CaptureCapabilitySnapshot
    public let microphones: [CaptureMicrophoneChoice]
    public let recoverableSession: RecordingSessionReview?

    public init(
        capability: CaptureCapabilitySnapshot,
        microphones: [CaptureMicrophoneChoice],
        recoverableSession: RecordingSessionReview? = nil
    ) {
        self.capability = capability
        self.microphones = microphones
        self.recoverableSession = recoverableSession
    }
}

public struct RecordingStartSubmission: Sendable {
    public let meetingTitle: String
    public let dataClassification: DataClassification
    public let mode: CaptureMode
    public let microphoneDeviceID: String?
    public let microphoneSpeechSourceKind: SpeechSourceKind
    public let applicationSpeechSourceKind: SpeechSourceKind
    public let language: LanguageTag?
    public let directUserAcknowledgement: Bool
    public let codexTextProcessingAllowed: Bool
    public let transcriptionSelection:
        ProviderModelSelectionRecord?
    public let remoteSpeechToTextAllowed: Bool

    public init(
        meetingTitle: String,
        dataClassification: DataClassification,
        mode: CaptureMode,
        microphoneDeviceID: String?,
        microphoneSpeechSourceKind: SpeechSourceKind,
        applicationSpeechSourceKind: SpeechSourceKind,
        language: LanguageTag?,
        directUserAcknowledgement: Bool,
        codexTextProcessingAllowed: Bool = false,
        transcriptionSelection:
            ProviderModelSelectionRecord? = nil,
        remoteSpeechToTextAllowed: Bool = false
    ) {
        self.meetingTitle = meetingTitle
        self.dataClassification = dataClassification
        self.mode = mode
        self.microphoneDeviceID = microphoneDeviceID
        self.microphoneSpeechSourceKind = microphoneSpeechSourceKind
        self.applicationSpeechSourceKind = applicationSpeechSourceKind
        self.language = language
        self.directUserAcknowledgement = directUserAcknowledgement
        self.codexTextProcessingAllowed =
            codexTextProcessingAllowed
        self.transcriptionSelection =
            transcriptionSelection
        self.remoteSpeechToTextAllowed =
            remoteSpeechToTextAllowed
    }
}

public struct RecordingResumeSubmission: Sendable {
    public let microphoneDeviceID: String?
    public let directUserAcknowledgement: Bool

    public init(
        microphoneDeviceID: String?,
        directUserAcknowledgement: Bool
    ) {
        self.microphoneDeviceID = microphoneDeviceID
        self.directUserAcknowledgement = directUserAcknowledgement
    }
}

public struct CompletedRecordingTrackReview:
    Hashable,
    Identifiable,
    Sendable
{
    public let trackID: RecordingTrackID
    public let kind: CaptureTrackKind
    public let sourceRevision:
        SemanticRevisionReference
    public let mediaTrackIdentifier:
        MediaTrackIdentifier
    public let durationFrameCount: UInt64
    public let speechSourceKind:
        SpeechSourceKind
    public let language: LanguageTag?

    public var id: RecordingTrackID {
        trackID
    }

    public init(
        trackID: RecordingTrackID,
        kind: CaptureTrackKind,
        sourceRevision:
            SemanticRevisionReference,
        mediaTrackIdentifier:
            MediaTrackIdentifier,
        durationFrameCount: UInt64,
        speechSourceKind:
            SpeechSourceKind,
        language: LanguageTag?
    ) {
        self.trackID = trackID
        self.kind = kind
        self.sourceRevision =
            sourceRevision
        self.mediaTrackIdentifier =
            mediaTrackIdentifier
        self.durationFrameCount =
            durationFrameCount
        self.speechSourceKind =
            speechSourceKind
        self.language = language
    }
}

public struct RecordingSessionReview: Hashable, Sendable {
    public let sessionID: RecordingSessionID
    public let jobID: JobID
    public let state: RecordingState
    public let stateVersion: UInt64
    public let activeTrackKinds: [CaptureTrackKind]
    public let durableThroughNanoseconds: UInt64?
    public let knownGapCount: UInt32
    public let safeReason: String?
    public let completedTracks:
        [CompletedRecordingTrackReview]

    public init(
        sessionID: RecordingSessionID,
        jobID: JobID,
        state: RecordingState,
        stateVersion: UInt64,
        activeTrackKinds: [CaptureTrackKind],
        durableThroughNanoseconds: UInt64?,
        knownGapCount: UInt32,
        safeReason: String?,
        completedTracks:
            [CompletedRecordingTrackReview] = []
    ) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.state = state
        self.stateVersion = stateVersion
        self.activeTrackKinds = activeTrackKinds
        self.durableThroughNanoseconds = durableThroughNanoseconds
        self.knownGapCount = knownGapCount
        self.safeReason = safeReason
        self.completedTracks =
            completedTracks.sorted {
                $0.trackID < $1.trackID
            }
    }

    public var canStop: Bool { !state.isTerminal && state != .stopping && state != .finalizing }
    public var blocksWorkspaceSwitch: Bool { !state.isTerminal }
}

@MainActor
public protocol MediaReviewWorkflow: AnyObject {
    func restoreWorkspace() async throws -> WorkspaceReview?
    func restoredMediaReview() async throws
        -> RestoredMediaWorkflowReview?
    func openOrCreateWorkspace(at selectedDirectory: URL) async throws -> WorkspaceReview
    func inspectSelectedMedia(at sourceURL: URL) async throws -> PendingMediaReview
    func discardPendingMedia()
    func importAndProcess(_ submission: MediaImportSubmission) async throws
        -> (ImportedSourceReview, MediaJobReview)
    func jobReview(jobID: JobID) async throws -> MediaJobReview
    func cancel(jobID: JobID) async throws -> MediaJobReview
    func retry(jobID: JobID) async throws -> MediaJobReview
    func transcriptRoute(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> TranscriptRouteReview
    func meetingSpeechToTextRoute(
        canonicalJobID: JobID
    ) async throws -> MeetingSpeechToTextRouteV1?
    func startTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> MediaJobReview
    func publishManualTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission,
        transcriptText: String,
        translatedText: String?,
        confirmsCompleteCoverage: Bool
    ) async throws -> TranscriptReviewBundle
    func transcriptReview(canonicalJobID: JobID) async throws -> TranscriptReviewBundle?
    func correctTranscript(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle
    func correctTranslation(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle
    func confirmSpeaker(
        canonicalJobID: JobID,
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async throws -> TranscriptReviewBundle
    func analysisRoute(canonicalJobID: JobID) async throws -> AnalysisRouteReview
    func startAnalysis(canonicalJobID: JobID) async throws -> MediaJobReview
    func analysisReview(canonicalJobID: JobID) async throws -> AnalysisReviewBundle?
    func confirmAnalysisReview(
        canonicalJobID: JobID,
        confirmsEveryClaim: Bool
    ) async throws -> AnalysisReviewBundle
    func correctPosition(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async throws -> AnalysisReviewBundle
    func briefingRoute(canonicalJobID: JobID) async throws -> BriefingRouteReview
    func startBriefing(canonicalJobID: JobID) async throws -> MediaJobReview
    func briefingReview(canonicalJobID: JobID) async throws -> BriefingReviewBundle?
    func regenerateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType
    ) async throws -> MediaJobReview
    func updateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle
    func exportBriefingMarkdown(
        canonicalJobID: JobID,
        fileName: String,
        expectedClassification: DataClassification
    ) async throws -> BriefingExportRecord
    func historicalIndexStatus() async throws -> HistoricalIndexStatus
    func rebuildHistoricalIndex() async throws -> MediaJobReview
    func searchMeetingHistory(_ query: HistoricalSearchQuery) async throws
        -> HistoricalSearchPage
    func compareHistoricalPositions(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) async throws -> HistoricalComparisonV1
    func confirmHistoricalChange(
        candidateRevisionID: RevisionID
    ) async throws -> HistoricalComparisonV1
    func learnedPreferenceState() async throws -> LearnedPreferenceState
    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?
    ) async throws -> LearnedPreferenceRecord
    func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceRecord
    func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws
    func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceState
    func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64
    ) async throws -> LearnedPreferenceState
    func storageReport() async throws -> WorkspaceStorageReport
    func restoreTrashItem(storageObjectID: StorageObjectID) async throws
        -> WorkspaceStorageReport
    func permanentlyDeleteTrashItem(
        storageObjectID: StorageObjectID,
        confirmsPermanentDeletion: Bool,
        acknowledgesUnlinkIsNotSecureErasure: Bool
    ) async throws -> WorkspaceStorageReport
    func recordingSetup() async throws -> RecordingSetupReview
    func startRecording(_ submission: RecordingStartSubmission) async throws
        -> RecordingSessionReview
    func recordingReview(jobID: JobID) async throws -> RecordingSessionReview
    func resumeRecording(
        jobID: JobID,
        submission: RecordingResumeSubmission
    ) async throws -> RecordingSessionReview
    func stopRecording(jobID: JobID) async throws -> RecordingSessionReview
    func processCompletedRecording(
        jobID: JobID,
        trackID: RecordingTrackID
    ) async throws -> MediaJobReview
    func fetchUNWebTVMetadata(
        url: String,
        explicitNetworkAuthorization: Bool
    ) async throws -> UNWebTVMetadataCandidate
    func codexTurnRequest(
        canonicalJobID: JobID,
        selectedSegmentIDs: [TranscriptSegmentID],
        prompt: String,
        visibleUserAuthorization: Bool
    ) async throws -> CodexMeetingTurnRequest
}

public extension MediaReviewWorkflow {
    func restoredMediaReview() async throws
        -> RestoredMediaWorkflowReview?
    {
        nil
    }

    func historicalIndexStatus() async throws -> HistoricalIndexStatus {
        throw HistoricalReviewError.indexRebuildRequired
    }

    func rebuildHistoricalIndex() async throws -> MediaJobReview {
        throw HistoricalReviewError.indexRebuildRequired
    }

    func searchMeetingHistory(
        _ query: HistoricalSearchQuery
    ) async throws -> HistoricalSearchPage {
        throw HistoricalReviewError.indexRebuildRequired
    }

    func compareHistoricalPositions(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) async throws -> HistoricalComparisonV1 {
        throw HistoricalReviewError.comparisonNotAllowed("Historical comparison is unavailable.")
    }

    func confirmHistoricalChange(
        candidateRevisionID: RevisionID
    ) async throws -> HistoricalComparisonV1 {
        throw HistoricalReviewError.sourceUnavailable(candidateRevisionID)
    }

    func learnedPreferenceState() async throws -> LearnedPreferenceState {
        throw HistoricalReviewError.invalidPreference("Learned preferences are unavailable.")
    }

    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?
    ) async throws -> LearnedPreferenceRecord {
        throw HistoricalReviewError.invalidPreference("Learned preferences are unavailable.")
    }

    func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceRecord {
        throw HistoricalReviewError.preferenceNotFound(preferenceID)
    }

    func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws {
        throw HistoricalReviewError.preferenceNotFound(preferenceID)
    }

    func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        throw HistoricalReviewError.invalidPreference("Learned preferences are unavailable.")
    }

    func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        throw HistoricalReviewError.invalidPreference("Learned preferences are unavailable.")
    }

    func recordingSetup() async throws -> RecordingSetupReview {
        throw TranscriptWorkflowError.unavailable
    }

    func startRecording(
        _ submission: RecordingStartSubmission
    ) async throws -> RecordingSessionReview {
        throw TranscriptWorkflowError.unavailable
    }

    func recordingReview(jobID: JobID) async throws -> RecordingSessionReview {
        throw TranscriptWorkflowError.unavailable
    }

    func resumeRecording(
        jobID: JobID,
        submission _: RecordingResumeSubmission
    ) async throws -> RecordingSessionReview {
        throw TranscriptWorkflowError.unavailable
    }

    func stopRecording(jobID: JobID) async throws -> RecordingSessionReview {
        throw TranscriptWorkflowError.unavailable
    }

    func processCompletedRecording(
        jobID _: JobID,
        trackID _: RecordingTrackID
    ) async throws -> MediaJobReview {
        throw TranscriptWorkflowError.unavailable
    }

    func fetchUNWebTVMetadata(
        url: String,
        explicitNetworkAuthorization: Bool
    ) async throws -> UNWebTVMetadataCandidate {
        throw TranscriptWorkflowError.unavailable
    }

    func codexTurnRequest(
        canonicalJobID _: JobID,
        selectedSegmentIDs _: [TranscriptSegmentID],
        prompt _: String,
        visibleUserAuthorization _: Bool
    ) async throws -> CodexMeetingTurnRequest {
        throw TranscriptWorkflowError.unavailable
    }

    func storageReport() async throws -> WorkspaceStorageReport {
        throw WorkspaceContractError.managedAssetMismatch(
            "Workspace storage reporting is unavailable."
        )
    }

    func restoreTrashItem(
        storageObjectID _: StorageObjectID
    ) async throws -> WorkspaceStorageReport {
        throw WorkspaceContractError.managedAssetMismatch(
            "Workspace Trash restore is unavailable."
        )
    }

    func permanentlyDeleteTrashItem(
        storageObjectID _: StorageObjectID,
        confirmsPermanentDeletion _: Bool,
        acknowledgesUnlinkIsNotSecureErasure _: Bool
    ) async throws -> WorkspaceStorageReport {
        throw WorkspaceContractError.managedAssetMismatch(
            "Permanent Workspace Trash deletion is unavailable."
        )
    }

    func transcriptRoute(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> TranscriptRouteReview {
        throw TranscriptWorkflowError.unavailable
    }

    func meetingSpeechToTextRoute(
        canonicalJobID: JobID
    ) async throws -> MeetingSpeechToTextRouteV1? {
        throw TranscriptWorkflowError.unavailable
    }

    func startTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> MediaJobReview {
        throw TranscriptWorkflowError.unavailable
    }

    func publishManualTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission,
        transcriptText: String,
        translatedText: String?,
        confirmsCompleteCoverage: Bool
    ) async throws -> TranscriptReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func transcriptReview(canonicalJobID: JobID) async throws -> TranscriptReviewBundle? {
        throw TranscriptWorkflowError.unavailable
    }

    func correctTranscript(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func correctTranslation(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func confirmSpeaker(
        canonicalJobID: JobID,
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async throws -> TranscriptReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func analysisRoute(canonicalJobID: JobID) async throws -> AnalysisRouteReview {
        throw TranscriptWorkflowError.unavailable
    }

    func startAnalysis(canonicalJobID: JobID) async throws -> MediaJobReview {
        throw TranscriptWorkflowError.unavailable
    }

    func analysisReview(canonicalJobID: JobID) async throws -> AnalysisReviewBundle? {
        throw TranscriptWorkflowError.unavailable
    }

    func confirmAnalysisReview(
        canonicalJobID: JobID,
        confirmsEveryClaim: Bool
    ) async throws -> AnalysisReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func correctPosition(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async throws -> AnalysisReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func briefingRoute(canonicalJobID: JobID) async throws -> BriefingRouteReview {
        throw TranscriptWorkflowError.unavailable
    }

    func startBriefing(canonicalJobID: JobID) async throws -> MediaJobReview {
        throw TranscriptWorkflowError.unavailable
    }

    func briefingReview(canonicalJobID: JobID) async throws -> BriefingReviewBundle? {
        throw TranscriptWorkflowError.unavailable
    }

    func regenerateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType
    ) async throws -> MediaJobReview {
        throw TranscriptWorkflowError.unavailable
    }

    func updateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle {
        throw TranscriptWorkflowError.unavailable
    }

    func exportBriefingMarkdown(
        canonicalJobID: JobID,
        fileName: String,
        expectedClassification: DataClassification
    ) async throws -> BriefingExportRecord {
        throw TranscriptWorkflowError.unavailable
    }
}
