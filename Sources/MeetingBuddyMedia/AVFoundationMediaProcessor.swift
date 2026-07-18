@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class AVFoundationMediaProcessor: NativeMediaProcessing, @unchecked Sendable {
    public init() {}

    public func inspect(_ sourceURL: URL) async throws -> MediaInspection {
        let format = try ApprovedMediaFormat(fileExtension: sourceURL.pathExtension)
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isNumeric, duration > .zero else {
            throw MediaContractError.unreadableMedia
        }
        guard !tracks.isEmpty else {
            throw MediaContractError.noAudioTrack
        }

        let durationFrames = try frameCount(for: duration)
        var descriptors: [AudioTrackDescriptor] = []
        for track in tracks {
            let timeRange = try await track.load(.timeRange)
            let formatDescriptions = try await track.load(.formatDescriptions)
            let languageValue = try await track.load(.extendedLanguageTag)
            let basicDescription = formatDescriptions.first.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }
            let codec = formatDescriptions.first.map {
                fourCharacterCode(CMFormatDescriptionGetMediaSubType($0))
            }
            let trackDuration = try frameCount(for: timeRange.duration)
            descriptors.append(
                try AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(track.trackID),
                    durationFrameCount: trackDuration,
                    sourceSampleRateHertz: basicDescription.flatMap {
                        guard $0.mSampleRate > 0,
                              $0.mSampleRate <= Double(UInt32.max)
                        else { return nil }
                        return UInt32($0.mSampleRate.rounded())
                    },
                    sourceChannelCount: basicDescription.flatMap {
                        guard $0.mChannelsPerFrame > 0,
                              $0.mChannelsPerFrame <= UInt32(UInt16.max)
                        else { return nil }
                        return UInt16($0.mChannelsPerFrame)
                    },
                    codec: codec,
                    language: languageValue.flatMap { try? LanguageTag($0) }
                )
            )
        }
        return try MediaInspection(
            format: format,
            durationFrameCount: durationFrames,
            audioTracks: descriptors
        )
    }

    public func writeCanonicalAudio(
        from sourceURL: URL,
        selectedTrack: MediaTrackIdentifier,
        expectedTimelineFrameCount: UInt64,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws -> CanonicalAudioWriteResult {
        guard expectedTimelineFrameCount > 0,
              expectedTimelineFrameCount <= UInt64(Int64.max)
        else {
            throw MediaContractError.invalidTimeline(
                "The expected canonical timeline is outside the supported range."
            )
        }
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first(where: { $0.trackID == selectedTrack.rawValue }) else {
            throw MediaContractError.selectedTrackUnavailable(selectedTrack)
        }
        let result = try await transcode(
            asset: asset,
            track: track,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(
                    value: CMTimeValue(expectedTimelineFrameCount),
                    timescale: CMTimeScale(profile.sampleRateHertz)
                )
            ),
            timelineOffset: .zero,
            sessionEndFrameCount: expectedTimelineFrameCount,
            profile: profile,
            destinationURL: destinationURL,
            reportGaps: true
        )
        return try CanonicalAudioWriteResult(
            frameCount: result.frameCount,
            rangeIssues: result.rangeIssues
        )
    }

    public func writeCanonicalChunk(
        from canonicalAudioURL: URL,
        range: MediaFrameRange,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws {
        guard range.endFrame <= UInt64(Int64.max) else {
            throw MediaContractError.invalidTimeline(
                "The canonical chunk range is outside the supported range."
            )
        }
        let asset = AVURLAsset(url: canonicalAudioURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw MediaContractError.noAudioTrack
        }
        let start = CMTime(
            value: CMTimeValue(range.startFrame),
            timescale: CMTimeScale(profile.sampleRateHertz)
        )
        let duration = CMTime(
            value: CMTimeValue(range.frameCount),
            timescale: CMTimeScale(profile.sampleRateHertz)
        )
        _ = try await transcode(
            asset: asset,
            track: track,
            timeRange: CMTimeRange(start: start, duration: duration),
            timelineOffset: start,
            sessionEndFrameCount: range.frameCount,
            profile: profile,
            destinationURL: destinationURL,
            reportGaps: false
        )
    }

    private struct TranscodeResult {
        let frameCount: UInt64
        let rangeIssues: [MediaRangeIssue]
    }

    private func transcode(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange?,
        timelineOffset: CMTime,
        sessionEndFrameCount: UInt64,
        profile: CanonicalAudioProfile,
        destinationURL: URL,
        reportGaps: Bool
    ) async throws -> TranscodeResult {
        guard profile == .v1 else {
            throw MediaContractError.invalidCanonicalProfile(profile.identifier)
        }
        let settings = audioSettings(for: profile)
        let reader = try AVAssetReader(asset: asset)
        if let timeRange {
            reader.timeRange = timeRange
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw MediaContractError.processingFailed("AVFoundation rejected the audio reader output.")
        }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .caf)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw MediaContractError.processingFailed("AVFoundation rejected the canonical audio writer input.")
        }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw MediaContractError.processingFailed(
                safeAVFailure(reader.error ?? writer.error)
            )
        }
        writer.startSession(atSourceTime: .zero)

        var maximumEndFrame: UInt64 = 0
        var previousEndFrame: UInt64?
        var issues: [MediaRangeIssue] = []
        do {
            while reader.status == .reading {
                try Task.checkCancellation()
                guard input.isReadyForMoreMediaData else {
                    try await Task.sleep(for: .milliseconds(2))
                    continue
                }
                guard let sourceBuffer = output.copyNextSampleBuffer() else { break }
                let sampleBuffer = try retimed(
                    sourceBuffer,
                    subtracting: timelineOffset
                )
                let startFrame = try nonnegativeFrame(
                    CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                )
                let sampleCount = UInt64(max(CMSampleBufferGetNumSamples(sampleBuffer), 0))
                let endFrame = startFrame + sampleCount
                let gapStart: UInt64? = if let previousEndFrame {
                    startFrame > previousEndFrame ? previousEndFrame : nil
                } else {
                    startFrame > 0 ? 0 : nil
                }
                if reportGaps, let gapStart {
                    issues.append(
                        try MediaRangeIssue(
                            kind: .missing,
                            range: MediaFrameRange(
                                startFrame: gapStart,
                                endFrame: startFrame
                            ),
                            safeSummary: "The source audio timeline contains a missing range."
                        )
                    )
                }
                previousEndFrame = max(previousEndFrame ?? 0, endFrame)
                maximumEndFrame = max(maximumEndFrame, endFrame)
                guard input.append(sampleBuffer) else {
                    throw MediaContractError.processingFailed(safeAVFailure(writer.error))
                }
            }
            guard reader.status == .completed else {
                throw MediaContractError.processingFailed(safeAVFailure(reader.error))
            }
            input.markAsFinished()
            writer.endSession(
                atSourceTime: CMTime(
                    value: CMTimeValue(sessionEndFrameCount),
                    timescale: CMTimeScale(profile.sampleRateHertz)
                )
            )
            await writer.finishWriting()
            guard writer.status == .completed, maximumEndFrame > 0 else {
                throw MediaContractError.processingFailed(safeAVFailure(writer.error))
            }
            return TranscodeResult(frameCount: maximumEndFrame, rangeIssues: issues)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
    }

    private func audioSettings(for profile: CanonicalAudioProfile) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: profile.sampleRateHertz,
            AVNumberOfChannelsKey: profile.channelCount,
            AVLinearPCMBitDepthKey: profile.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: !profile.isLittleEndian,
            AVLinearPCMIsNonInterleaved: !profile.isInterleaved
        ]
    }

    private func frameCount(for time: CMTime) throws -> UInt64 {
        guard time.isNumeric, time > .zero else {
            throw MediaContractError.invalidTimeline("A media duration must be positive and numeric.")
        }
        let scaled = CMTimeConvertScale(
            time,
            timescale: CMTimeScale(CanonicalAudioProfile.v1.sampleRateHertz),
            method: .roundHalfAwayFromZero
        )
        guard scaled.value > 0 else {
            throw MediaContractError.invalidTimeline("A media duration rounded to zero frames.")
        }
        return UInt64(scaled.value)
    }

    private func nonnegativeFrame(_ time: CMTime) throws -> UInt64 {
        guard time.isNumeric else {
            throw MediaContractError.invalidTimeline("An audio sample has no numeric timestamp.")
        }
        let scaled = CMTimeConvertScale(
            time,
            timescale: CMTimeScale(CanonicalAudioProfile.v1.sampleRateHertz),
            method: .roundHalfAwayFromZero
        )
        return UInt64(max(scaled.value, 0))
    }

    private func retimed(
        _ sampleBuffer: CMSampleBuffer,
        subtracting offset: CMTime
    ) throws -> CMSampleBuffer {
        guard offset != .zero else { return sampleBuffer }
        var count = 0
        let countStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard countStatus == noErr, count > 0 else {
            throw MediaContractError.processingFailed("Audio timing metadata could not be read.")
        }
        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: count
        )
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        )
        guard timingStatus == noErr else {
            throw MediaContractError.processingFailed("Audio timing metadata could not be copied.")
        }
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isNumeric {
                timing[index].presentationTimeStamp = CMTimeSubtract(
                    timing[index].presentationTimeStamp,
                    offset
                )
            }
            if timing[index].decodeTimeStamp.isNumeric {
                timing[index].decodeTimeStamp = CMTimeSubtract(
                    timing[index].decodeTimeStamp,
                    offset
                )
            }
        }
        var copy: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timing.count,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        guard copyStatus == noErr, let copy else {
            throw MediaContractError.processingFailed("Audio timestamps could not be normalized.")
        }
        return copy
    }

    private func safeAVFailure(_ error: Error?) -> String {
        guard error != nil else { return "AVFoundation media processing failed." }
        return "AVFoundation media processing failed with a local framework error."
    }

    private func fourCharacterCode(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let visible = bytes.map { byte in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        let value = String(visible).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown-fourcc" : value
    }
}
