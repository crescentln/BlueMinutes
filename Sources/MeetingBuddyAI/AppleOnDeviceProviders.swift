@preconcurrency import AVFAudio
import CoreMedia
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Speech
import Translation

private let appleSystemModelVersion: String = {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "system-model-macos-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}()

@available(macOS 26.0, *)
public actor AppleOnDeviceTranscriptionProvider: TranscriptionProvider {
    public nonisolated let metadata = try! ProviderMetadata(
        providerIdentifier: "apple-speech",
        modelIdentifier: "speech-analyzer-transcriber",
        modelVersion: appleSystemModelVersion,
        clientVersion: "meetingbuddy-task005b-v1"
    )
    public nonisolated let route: ModelExecutionRoute = .appleOnDevice

    public init() {}

    public func isModelInstalled(for language: LanguageTag) async -> Bool {
        let requested = Locale(identifier: language.value)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return false
        }
        return await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == supported.identifier(.bcp47)
        }
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionChunkResult {
        guard await isModelInstalled(for: request.language), SpeechTranscriber.isAvailable else {
            throw AIProviderContractError.modelUnavailable("The requested on-device speech model is not installed.")
        }
        let locale = try await installedLocale(for: request.language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: request.audio.fileURL)
        } catch {
            throw AIProviderContractError.invalidRequest("The verified task audio chunk could not be opened.")
        }

        var spans: [TranscriptionSpan] = []
        async let analysis: Void = analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        do {
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = Self.milliseconds(result.range.start)
                let end = Self.milliseconds(CMTimeRangeGetEnd(result.range))
                guard end > start else { continue }
                let confidenceValues = result.text.runs.compactMap {
                    $0[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
                }
                let confidence = confidenceValues.isEmpty
                    ? 500_000
                    : UInt32(
                        min(
                            max(
                                (confidenceValues.reduce(0, +) / Double(confidenceValues.count))
                                    * 1_000_000,
                                0
                            ),
                            1_000_000
                        ).rounded()
                    )
                spans.append(
                    try TranscriptionSpan(
                        startMilliseconds: start,
                        endMilliseconds: end,
                        text: text,
                        confidence: ConfidenceScore(millionths: confidence)
                    )
                )
            }
            try await analysis
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError.invalidResponse("Apple Speech could not complete this local chunk.")
        }
        if spans.isEmpty { return .noSpeech }
        return try TranscriptionChunkResult(validatingSpans: spans)
    }

    private func installedLocale(for language: LanguageTag) async throws -> Locale {
        let requested = Locale(identifier: language.value)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested),
              await SpeechTranscriber.installedLocales.contains(where: {
                  $0.identifier(.bcp47) == supported.identifier(.bcp47)
              })
        else {
            throw AIProviderContractError.modelUnavailable("The requested on-device speech model is not installed.")
        }
        return supported
    }

    private static func milliseconds(_ time: CMTime) -> Int64 {
        guard time.isNumeric else { return 0 }
        return Int64(max(CMTimeGetSeconds(time) * 1_000, 0).rounded(.down))
    }
}

@available(macOS 26.0, *)
public actor AppleOnDeviceTranslationProvider: TranslationProvider {
    public nonisolated let metadata = try! ProviderMetadata(
        providerIdentifier: "apple-translation",
        modelIdentifier: "translation-session-installed",
        modelVersion: appleSystemModelVersion,
        clientVersion: "meetingbuddy-task005b-v1"
    )
    public nonisolated let route: ModelExecutionRoute = .appleOnDevice

    public init() {}

    public func isModelInstalled(source: LanguageTag, target: LanguageTag) async -> Bool {
        await LanguageAvailability().status(
            from: Locale.Language(identifier: source.value),
            to: Locale.Language(identifier: target.value)
        ) == .installed
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        guard await isModelInstalled(source: request.sourceLanguage, target: request.targetLanguage) else {
            throw AIProviderContractError.modelUnavailable("The requested on-device translation pair is not installed.")
        }
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: request.sourceLanguage.value),
            target: Locale.Language(identifier: request.targetLanguage.value)
        )
        let response: TranslationSession.Response
        do {
            response = try await session.translate(request.sourceText)
        } catch {
            throw AIProviderContractError.invalidResponse("Apple Translation could not complete this local text segment.")
        }
        return try TranslationResponse(
            translatedText: response.targetText.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: ConfidenceScore(millionths: 750_000)
        )
    }
}
