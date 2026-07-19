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

public struct TranscriptRouteReview: Hashable, Sendable {
    public let transcription: ModelRouteDecision
    public let translation: ModelRouteDecision?

    public init(transcription: ModelRouteDecision, translation: ModelRouteDecision?) {
        self.transcription = transcription
        self.translation = translation
    }

    public var isOnDeviceReady: Bool {
        transcription.route == .appleOnDevice
            && (translation?.route == .appleOnDevice || translation == nil)
    }
}

public struct TranscriptStartSubmission: Sendable {
    public let sourceLanguage: LanguageTag
    public let targetLanguage: LanguageTag?

    public init(sourceLanguage: LanguageTag, targetLanguage: LanguageTag?) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
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

    public init(
        meetingTitle: String,
        dataClassification: DataClassification,
        selectedTrack: MediaTrackIdentifier?,
        speechSourceKind: SpeechSourceKind,
        language: LanguageTag?
    ) {
        self.meetingTitle = meetingTitle
        self.dataClassification = dataClassification
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
        self.language = language
    }
}

@MainActor
public protocol MediaReviewWorkflow: AnyObject {
    func restoreWorkspace() async throws -> WorkspaceReview?
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
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle
    func exportBriefingMarkdown(
        canonicalJobID: JobID,
        fileName: String,
        expectedClassification: DataClassification
    ) async throws -> BriefingExportRecord
}

public extension MediaReviewWorkflow {
    func transcriptRoute(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> TranscriptRouteReview {
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
