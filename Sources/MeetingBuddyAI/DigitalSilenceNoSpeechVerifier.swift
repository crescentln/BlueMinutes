@preconcurrency import AVFAudio
import Foundation
import MeetingBuddyApplication

/// A deliberately strict, application-owned fail-closed check. It confirms
/// only exact zero-valued PCM samples in the deterministic core range; noisy
/// silence remains reviewable through the manual transcript workflow.
public struct DigitalSilenceNoSpeechVerifier: TranscriptNoSpeechVerifying {
    public init() {}

    public func confirmation(
        for audio: TaskOwnedAudioChunk
    ) async -> TranscriptNoSpeechConfirmation? {
        do {
            let file = try AVAudioFile(
                forReading: audio.fileURL,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            guard file.processingFormat.channelCount == 1,
                  file.processingFormat.sampleRate
                    == Double(CanonicalAudioProfile.v1.sampleRateHertz),
                  audio.plan.coreRange.startFrame >= audio.plan.physicalRange.startFrame
            else { return nil }

            let relativeStart = audio.plan.coreRange.startFrame
                - audio.plan.physicalRange.startFrame
            let coreFrameCount = audio.plan.coreRange.frameCount
            guard relativeStart <= UInt64(file.length),
                  coreFrameCount <= UInt64(file.length) - relativeStart
            else { return nil }

            file.framePosition = AVAudioFramePosition(relativeStart)
            var remaining = coreFrameCount
            while remaining > 0 {
                let requested = AVAudioFrameCount(min(remaining, 8_192))
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: requested
                ) else { return nil }
                try file.read(into: buffer, frameCount: requested)
                guard buffer.frameLength == requested,
                      let samples = buffer.int16ChannelData?[0]
                else { return nil }
                let values = UnsafeBufferPointer(
                    start: samples,
                    count: Int(buffer.frameLength)
                )
                guard values.allSatisfy({ $0 == 0 }) else { return nil }
                remaining -= UInt64(buffer.frameLength)
            }
            return try TranscriptNoSpeechConfirmation(
                verifiedCoreRange: audio.plan.coreRange
            )
        } catch {
            return nil
        }
    }
}
