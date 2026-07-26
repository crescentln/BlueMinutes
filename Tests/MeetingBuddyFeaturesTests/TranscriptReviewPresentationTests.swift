import Foundation
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct TranscriptReviewPresentationTests {
    @Test
    func navigationIndexKeepsThreeHundredSixtySegmentsDeterministic()
    {
        let segmentIDs = (0 ..< 360).map {
            transcriptID($0, TranscriptSegmentID.self)
        }
        let index = TranscriptNavigationIndex(
            orderedSegmentIDs: segmentIDs
        )

        #expect(index.orderedSegmentIDs == segmentIDs)
        #expect(index.previous(to: segmentIDs.first) == nil)
        #expect(index.next(to: segmentIDs.first) == segmentIDs[1])
        #expect(
            index.previous(to: segmentIDs[180])
                == segmentIDs[179]
        )
        #expect(
            index.next(to: segmentIDs[180])
                == segmentIDs[181]
        )
        #expect(index.previous(to: segmentIDs.last) == segmentIDs[358])
        #expect(index.next(to: segmentIDs.last) == nil)
        #expect(index.previous(to: nil) == nil)
        #expect(index.next(to: nil) == nil)
    }

    @Test
    func focusedSaveNeverChoosesAnAmbiguousOrDifferentDraft() {
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .transcript,
                transcriptIsDirty: true,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == .transcript
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .translation,
                transcriptIsDirty: true,
                translationIsDirty: false,
                speakerIsDirty: false
            ) == nil
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: nil,
                transcriptIsDirty: false,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == .translation
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: nil,
                transcriptIsDirty: true,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == nil
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .speaker,
                transcriptIsDirty: false,
                translationIsDirty: false,
                speakerIsDirty: true
            ) == .speaker
        )
    }

    @Test @MainActor
    func commandNavigationReusesDirtyDraftNegotiation() {
        let segmentIDs = (0 ..< 3).map {
            transcriptID($0, TranscriptSegmentID.self)
        }
        let index = TranscriptNavigationIndex(
            orderedSegmentIDs: segmentIDs
        )
        let state = MediaReviewSceneState()
        state.transcript.select(segmentIDs[1])
        state.transcript.transcriptText = "Unsaved correction"

        state.requestTranscriptSelection(
            index.previous(to: segmentIDs[1])
        )

        #expect(
            state.transcript.selectedSegmentID
                == segmentIDs[1]
        )
        #expect(state.isNavigationConfirmationPresented)
        state.cancelPendingNavigation()

        state.requestTranscriptSelection(
            index.next(to: segmentIDs[1])
        )
        #expect(
            state.transcript.selectedSegmentID
                == segmentIDs[1]
        )
        #expect(state.isNavigationConfirmationPresented)
    }

    @Test
    func transcriptCommandsAndInspectorUseOnlyRealReviewContracts()
        throws
    {
        let app = try source(
            "Sources/MeetingBuddyApp/MeetingBuddyApp.swift"
        )
        let commands = try source(
            "Sources/MeetingBuddyFeatures/Views/BlueMinutesTranscriptCommands.swift"
        )
        let review = try source(
            "Sources/MeetingBuddyFeatures/Views/TranscriptReviewView.swift"
        )
        let inspector = try source(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/EvidenceInspectorPanel.swift"
        )
        let persistence = try source(
            "Sources/MeetingBuddyPersistence/SQLitePersistenceStore.swift"
        )

        #expect(app.contains("BlueMinutesTranscriptCommands()"))
        #expect(
            commands.contains(
                "@FocusedValue(\\.blueMinutesTranscriptCommandActions)"
            )
        )
        #expect(commands.contains("Previous Segment"))
        #expect(commands.contains("Next Segment"))
        #expect(commands.contains("Save Focused Transcript Draft"))
        #expect(commands.contains("Toggle Evidence Inspector"))
        #expect(
            review.contains(
                "sceneState.requestTranscriptSelection("
            )
        )
        #expect(!review.contains("transcript.select("))
        #expect(review.contains(".inspector(isPresented:"))
        #expect(review.contains("EvidenceInspectorPanel("))
        #expect(review.contains("Unsaved local draft"))
        #expect(review.contains("Saved"))
        #expect(review.contains("Coverage and route proof"))
        #expect(review.contains("Machine transcription"))
        #expect(review.contains("Human correction"))
        #expect(!review.contains("Play Segment"))
        #expect(!review.contains("Open Source"))
        #expect(!review.contains("SQLitePersistenceStore"))
        #expect(inspector.contains("EvidenceRef.v1"))
        #expect(inspector.contains("Evidence excerpt"))
        #expect(!inspector.contains("sourceURL"))
        #expect(
            persistence.contains(
                "let evidenceRefs = try evidenceReferences.map"
            )
        )
        #expect(
            persistence.contains(
                "throw TranscriptCoverageError.publicationConflict"
            )
        )
    }

    private func transcriptID<Tag>(
        _ index: Int,
        _ type: StableID<Tag>.Type
    ) -> StableID<Tag> {
        StableID<Tag>(
            UUID(
                uuidString: String(
                    format:
                        "5f000000-0000-0000-0000-%012d",
                    index + 1
                )
            )!
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf:
                repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
