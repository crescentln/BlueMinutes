@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MeetingBuddyApplication
import MeetingBuddyMedia
import MeetingBuddyDomain
import Testing

@Suite(.serialized)
struct AVFoundationMediaProcessorTests {
    @Test
    func nativeCoreFormatsInspectWithReadableAudioTracks() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let wav = directory.appendingPathComponent("synthetic.wav")
        let m4a = directory.appendingPathComponent("synthetic.m4a")
        let mp4 = directory.appendingPathComponent("synthetic.mp4")
        let mp3 = directory.appendingPathComponent("synthetic.mp3")
        let mov = directory.appendingPathComponent("synthetic.mov")
        try writeSyntheticAudio(to: wav, fileType: kAudioFileWAVEType, formatID: kAudioFormatLinearPCM)
        try writeSyntheticAudio(to: m4a, fileType: kAudioFileM4AType, formatID: kAudioFormatMPEG4AAC)
        try writeSyntheticAudio(to: mp4, fileType: kAudioFileMPEG4Type, formatID: kAudioFormatMPEG4AAC)
        try writeSyntheticSilentMP3(to: mp3)
        try await exportQuickTimeMovie(from: m4a, to: mov)

        let processor = AVFoundationMediaProcessor()
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        try workspace.installMeeting()
        let intake = LocalMediaIntakeService(
            processor: processor,
            storage: workspace.coordinator,
            catalog: workspace.store,
            fileAccess: workspace.fileAccess
        )
        let fixtures: [(URL, ApprovedMediaFormat)] = [
            (wav, .wav),
            (m4a, .m4a),
            (mp4, .mp4),
            (mp3, .mp3),
            (mov, .mov)
        ]
        for (index, fixture) in fixtures.enumerated() {
            let (url, expectedFormat) = fixture
            let originalBytes = try Data(contentsOf: url)
            let inspection = try await processor.inspect(url)
            #expect(inspection.format == expectedFormat)
            #expect(inspection.audioTracks.count == 1)
            #expect(inspection.durationFrameCount >= 15_000)
            #expect(inspection.durationFrameCount <= 17_000)
            let selectedTrack = try #require(inspection.audioTracks.first)
            let imported = try await intake.importSelectedMedia(
                from: url,
                initialInspection: inspection,
                request: MediaIntakeRequest(
                    meetingID: workspace.meetingID,
                    sourceAssetID: mediaID(100 + index * 3, as: SourceAssetID.self),
                    sourceRevisionID: mediaID(101 + index * 3, as: RevisionID.self),
                    storageObjectID: mediaID(102 + index * 3, as: StorageObjectID.self),
                    selectedTrack: selectedTrack.trackIdentifier,
                    speechSourceKind: .unknown,
                    createdAt: mediaInstant(1_800_100_001_000 + Int64(index)),
                    dataClassification: .internal,
                    expectedSourceByteSize: UInt64(originalBytes.count)
                )
            )
            #expect(imported.inspection.format == expectedFormat)
            #expect(imported.sourceAsset.byteSize == UInt64(originalBytes.count))
            #expect(try Data(contentsOf: url) == originalBytes)
            let reference = try #require(imported.sourceAsset.managedStorageReference)
            _ = try workspace.fileAccess.verifiedFileURL(for: reference)
        }
    }

    @Test
    func realCanonicalPCMAndChunkPreserveDurationWithoutChangingSource() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic.wav")
        let canonical = directory.appendingPathComponent("canonical.caf")
        let chunk = directory.appendingPathComponent("chunk.caf")
        try writeSyntheticAudio(
            to: source,
            fileType: kAudioFileWAVEType,
            formatID: kAudioFormatLinearPCM
        )
        let originalBytes = try Data(contentsOf: source)

        let processor = AVFoundationMediaProcessor()
        let inspection = try await processor.inspect(source)
        let selected = try inspection.requireTrack(nil)
        let result = try await processor.writeCanonicalAudio(
            from: source,
            selectedTrack: selected.trackIdentifier,
            expectedTimelineFrameCount: inspection.durationFrameCount,
            profile: .v1,
            to: canonical
        )
        let difference = result.frameCount > inspection.durationFrameCount
            ? result.frameCount - inspection.durationFrameCount
            : inspection.durationFrameCount - result.frameCount
        #expect(difference <= 800)
        #expect(result.rangeIssues.isEmpty)
        #expect(try Data(contentsOf: source) == originalBytes)

        let canonicalFile = try AVAudioFile(forReading: canonical)
        #expect(canonicalFile.fileFormat.sampleRate == 16_000)
        #expect(canonicalFile.fileFormat.channelCount == 1)
        #expect(canonicalFile.fileFormat.commonFormat == .pcmFormatInt16)
        #expect(canonicalFile.fileFormat.isInterleaved)
        #expect(
            canonicalFile.length
                == AVAudioFramePosition(min(result.frameCount, inspection.durationFrameCount))
        )

        let range = try MediaFrameRange(startFrame: 4_000, endFrame: 12_000)
        try await processor.writeCanonicalChunk(
            from: canonical,
            range: range,
            profile: .v1,
            to: chunk
        )
        let chunkFile = try AVAudioFile(forReading: chunk)
        #expect(chunkFile.fileFormat.sampleRate == 16_000)
        #expect(chunkFile.fileFormat.channelCount == 1)
        #expect(chunkFile.length == 8_000)
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meetingbuddy-native-media-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func writeSyntheticAudio(
        to url: URL,
        fileType: AudioFileTypeID,
        formatID: AudioFormatID
    ) throws {
        let sampleRate = 48_000.0
        let frameCount = 48_000
        var output = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags(for: formatID),
            mBytesPerPacket: formatID == kAudioFormatLinearPCM ? 2 : 0,
            mFramesPerPacket: framesPerPacket(for: formatID),
            mBytesPerFrame: formatID == kAudioFormatLinearPCM ? 2 : 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: formatID == kAudioFormatLinearPCM ? 16 : 0,
            mReserved: 0
        )
        var file: ExtAudioFileRef?
        try checkAudioStatus(
            ExtAudioFileCreateWithURL(
                url as CFURL,
                fileType,
                &output,
                nil,
                AudioFileFlags.eraseFile.rawValue,
                &file
            ),
            context: "create-\(fileType)-\(formatID)"
        )
        guard let file else { throw NativeFixtureError.creationFailed }
        defer { _ = ExtAudioFileDispose(file) }

        var client = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        let clientSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try checkAudioStatus(
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ClientDataFormat,
                clientSize,
                &client
            ),
            context: "client-format-\(fileType)-\(formatID)"
        )

        var samples = (0..<frameCount).map { frame -> Int16 in
            let phase = Double(frame) * 2 * Double.pi * 440 / sampleRate
            return Int16((sin(phase) * 8_000).rounded())
        }
        try samples.withUnsafeMutableBytes { bytes in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            try checkAudioStatus(
                ExtAudioFileWrite(file, UInt32(frameCount), &bufferList),
                context: "write-\(fileType)-\(formatID)"
            )
        }
    }

    private func exportQuickTimeMovie(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw NativeFixtureError.creationFailed
        }
        try await exporter.export(to: destination, as: .mov)
    }

    /// MPEG-1 Layer III frames with empty side information and main data are
    /// deterministic synthetic silence. No external encoder or fixture rights
    /// are involved.
    private func writeSyntheticSilentMP3(to url: URL) throws {
        var data = Data()
        for _ in 0..<40 {
            data.append(contentsOf: [0xff, 0xfb, 0x90, 0x00])
            data.append(Data(repeating: 0, count: 413))
        }
        try data.write(to: url, options: [.atomic])
    }

    private func checkAudioStatus(_ status: OSStatus, context: String) throws {
        guard status == noErr else {
            throw NativeFixtureError.audioStatus(status, context)
        }
    }

    private func formatFlags(for formatID: AudioFormatID) -> AudioFormatFlags {
        switch formatID {
        case kAudioFormatLinearPCM:
            kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        case kAudioFormatMPEG4AAC:
            // MPEG-4 Audio Object Type 2 is AAC Low Complexity.
            2
        default:
            0
        }
    }

    private func framesPerPacket(for formatID: AudioFormatID) -> UInt32 {
        switch formatID {
        case kAudioFormatLinearPCM: 1
        case kAudioFormatMPEG4AAC: 1_024
        case kAudioFormatMPEGLayer3: 1_152
        default: 0
        }
    }
}

private enum NativeFixtureError: Error {
    case creationFailed
    case audioStatus(OSStatus, String)
}
