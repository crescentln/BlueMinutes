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
        await store.openOrCreateWorkspace(at: URL(fileURLWithPath: "/selected-workspace"))
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
        await store.openOrCreateWorkspace(at: URL(fileURLWithPath: "/selected-workspace"))
        await store.inspectMedia(at: URL(fileURLWithPath: "/selected-source.wav"))
        store.meetingTitle = "Review fixture"

        #expect(store.selectedTrack == nil)
        await store.importAndProcess()
        #expect(store.safeErrorMessage == "Select one audio track before processing this media.")
        #expect(workflow.importCallCount == 0)
    }

    @Test @MainActor
    func aSecondLongOperationCannotReplaceAnActiveWorkspaceRuntime() async throws {
        let gate = AsyncGate()
        let workflow = try MediaReviewWorkflowProbe(openGate: gate)
        let store = MediaReviewStore(workflow: workflow)
        let opening = Task {
            await store.openOrCreateWorkspace(
                at: URL(fileURLWithPath: "/selected-workspace")
            )
        }
        await gate.waitUntilEntered()

        await store.inspectMedia(at: URL(fileURLWithPath: "/selected-source.wav"))
        #expect(store.safeErrorMessage == "Wait for the current local operation to finish.")
        #expect(workflow.inspectCallCount == 0)

        await gate.release()
        await opening.value
        #expect(store.workspace?.displayName == "Synthetic Workspace")
    }
}

@MainActor
private final class MediaReviewWorkflowProbe: MediaReviewWorkflow {
    private let inspection: MediaInspection
    private let openGate: AsyncGate?
    private(set) var inspectCallCount = 0
    private(set) var importCallCount = 0
    private(set) var permanentDeletionCallCount = 0
    private(set) var lastDeletionConfirmed = false
    private(set) var lastUnlinkAcknowledged = false

    init(openGate: AsyncGate? = nil) throws {
        self.openGate = openGate
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

    func restoreWorkspace() async throws -> WorkspaceReview? { nil }

    func openOrCreateWorkspace(at _: URL) async throws -> WorkspaceReview {
        if let openGate { await openGate.block() }
        return WorkspaceReview(
            workspaceID: WorkspaceID(
                UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
            ),
            displayName: "Synthetic Workspace"
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
        throw ProbeError.unexpectedCall
    }

    func jobReview(jobID _: JobID) async throws -> MediaJobReview {
        throw ProbeError.unexpectedCall
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
}

private func featureID<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
    StableID<Tag>(
        UUID(uuidString: String(format: "51000000-0000-0000-0000-%012d", suffix))!
    )
}

private func featureInstant(_ milliseconds: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
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

private enum ProbeError: Error {
    case unexpectedCall
}
