import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import Testing

@Suite
struct MediaContractTests {
    @Test
    func approvedCoreFormatsAreExplicitAndCaseInsensitive() throws {
        #expect(try ApprovedMediaFormat(fileExtension: "MOV") == .mov)
        #expect(try ApprovedMediaFormat(fileExtension: "mp4") == .mp4)
        #expect(try ApprovedMediaFormat(fileExtension: "m4a") == .m4a)
        #expect(try ApprovedMediaFormat(fileExtension: "mp3") == .mp3)
        #expect(try ApprovedMediaFormat(fileExtension: "wav") == .wav)
        #expect(throws: MediaContractError.self) {
            _ = try ApprovedMediaFormat(fileExtension: "mkv")
        }
    }

    @Test
    func chunkPlanUsesExactThirtySecondCoresAndOneSecondContext() throws {
        let plan = try CanonicalChunkPlanner.plan(totalFrameCount: 1_000_000)
        #expect(plan.count == 3)
        #expect(plan[0].coreRange == frameRange(0, 480_000))
        #expect(plan[0].physicalRange == frameRange(0, 496_000))
        #expect(plan[1].coreRange == frameRange(480_000, 960_000))
        #expect(plan[1].physicalRange == frameRange(464_000, 976_000))
        #expect(plan[2].coreRange == frameRange(960_000, 1_000_000))
        #expect(plan[2].physicalRange == frameRange(944_000, 1_000_000))
        #expect(try CanonicalChunkPlanner.plan(totalFrameCount: 1_000_000) == plan)
    }

    @Test
    func canonicalJobPayloadRoundTripsExactIdentifiersAndPolicy() throws {
        let sourceID = SourceAssetID(UUID(uuidString: "50000000-0000-0000-0000-000000000001")!)
        let sourceRevisionID = RevisionID(
            UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
        )
        let sourceReference = try SemanticRevisionReference(
            logicalID: sourceID,
            revisionID: sourceRevisionID
        )
        let plan = try CanonicalAudioJobPlan(
            sourceRevision: sourceReference,
            selectedTrack: MediaTrackIdentifier(7),
            speechSourceKind: .simultaneousInterpretation,
            outputAssetID: SourceAssetID(
                UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
            ),
            outputRevisionID: RevisionID(
                UUID(uuidString: "50000000-0000-0000-0000-000000000004")!
            ),
            outputStorageObjectID: StorageObjectID(
                UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
            ),
            meetingID: MeetingID(
                UUID(uuidString: "50000000-0000-0000-0000-000000000006")!
            ),
            createdAt: UTCInstant(millisecondsSinceUnixEpoch: 1_800_000_000_000),
            dataClassification: .sensitive,
            language: LanguageTag("fr"),
            expectedDurationFrames: 960_000
        )
        #expect(try CanonicalAudioJobPlan.decode(from: plan.jobInputPayload()) == plan)
    }

    @Test
    func localIntakePayloadRoundTripsWithoutPersistingSourceAuthority() throws {
        let inspection = try MediaInspection(
            format: .wav,
            durationFrameCount: 32_000,
            audioTracks: [
                AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(3),
                    durationFrameCount: 32_000,
                    sourceSampleRateHertz: 48_000,
                    sourceChannelCount: 2,
                    codec: "lpcm",
                    language: LanguageTag("en")
                )
            ]
        )
        let plan = try LocalMediaIntakeJobPlan(
            meetingID: mediaID(70, as: MeetingID.self),
            sourceAssetID: mediaID(71, as: SourceAssetID.self),
            sourceRevisionID: mediaID(72, as: RevisionID.self),
            storageObjectID: mediaID(73, as: StorageObjectID.self),
            initialInspection: inspection,
            selectedTrack: MediaTrackIdentifier(3),
            speechSourceKind: .originalSpeakerAudio,
            language: LanguageTag("en"),
            createdAt: mediaInstant(1_800_000_000_100),
            dataClassification: .internal,
            expectedSourceByteSize: 4_096
        )
        let input = try plan.jobInputPayload()
        #expect(try LocalMediaIntakeJobPlan.decode(from: input) == plan)
        let text = try #require(String(data: input.payload, encoding: .utf8))
        #expect(!text.contains("source.wav"))
        #expect(!text.contains("security-scoped"))
    }

    @Test
    func threeHourCheckpointRemainsWithinTheDurableTaskPayloadLimit() throws {
        let totalFrames: UInt64 = 3 * 60 * 60 * 16_000
        let plan = try CanonicalChunkPlanner.plan(totalFrameCount: totalFrames)
        let canonical = try TaskTemporaryFileDescriptor(
            relativePathWithinTask: WorkspaceRelativePath("canonical/audio.caf"),
            contentHash: ContentDigest(
                algorithm: .sha256,
                lowercaseHex: String(repeating: "a", count: 64)
            ),
            byteSize: totalFrames * 2
        )
        let artifacts = try plan.map { entry in
            try CanonicalChunkArtifact(
                plan: entry,
                file: TaskTemporaryFileDescriptor(
                    relativePathWithinTask: entry.relativePath,
                    contentHash: ContentDigest(
                        algorithm: .sha256,
                        lowercaseHex: String(format: "%064x", UInt64(entry.index) + 1)
                    ),
                    byteSize: entry.physicalRange.frameCount * 2
                )
            )
        }
        let checkpoint = try CanonicalAudioCheckpoint(
            canonicalFile: canonical,
            canonicalFrameCount: totalFrames,
            completedChunks: artifacts,
            rangeIssues: []
        )
        let durable = try checkpoint.jobCheckpoint()
        #expect(durable.payload.count <= JobCheckpoint.maximumPayloadBytes)
        #expect(try CanonicalAudioCheckpoint.decode(from: durable) == checkpoint)
    }

    private func frameRange(_ start: UInt64, _ end: UInt64) -> MediaFrameRange {
        try! MediaFrameRange(startFrame: start, endFrame: end)
    }
}
