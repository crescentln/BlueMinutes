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
