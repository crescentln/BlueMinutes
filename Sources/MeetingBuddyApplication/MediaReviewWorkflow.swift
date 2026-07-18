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
    }

    public var progressFraction: Double {
        guard totalUnitCount > 0 else { return 0 }
        return Double(completedUnitCount) / Double(totalUnitCount)
    }
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
}
