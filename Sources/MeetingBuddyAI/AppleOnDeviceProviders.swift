@preconcurrency import AVFAudio
import CoreMedia
import Foundation
import FoundationModels
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

@available(macOS 26.0, *)
@Generable(description: "A bounded diplomatic extraction candidate. Never add fields outside this schema.")
private struct AppleDiplomaticAnalysisOutput {
    var substantive: Bool
    @Guide(.anyOf([
        "not_substantive",
        "insufficient_semantic_content",
        "procedural_only",
        "uncertain"
    ]))
    var nonSubstantiveReasonCode: String
    @Guide(.anyOf([
        "statement",
        "question",
        "response",
        "right_of_reply",
        "procedural",
        "other"
    ]))
    var interventionType: String
    var issueTitle: String
    @Guide(.anyOf([
        "supports",
        "opposes",
        "requests",
        "proposes",
        "reserves_position",
        "supports_with_conditions",
        "opposes_with_qualification",
        "uncertain"
    ]))
    var positionType: String
    var positionStatement: String
    @Guide(.maximumCount(16))
    var reservations: [String]
    @Guide(.maximumCount(16))
    var conditions: [String]
    var commitment: AppleDiplomaticCommitmentOutput?
    var decision: AppleDiplomaticDecisionOutput?
    @Guide(.range(0...1_000_000))
    var confidenceMillionths: Int
}

@available(macOS 26.0, *)
@Generable(description: "One explicitly stated but not completed commitment candidate.")
private struct AppleDiplomaticCommitmentOutput {
    var content: String
    var recipientLabel: String?
    @Guide(.maximumCount(16))
    var conditions: [String]
    var deadlineDescription: String?
    @Guide(.anyOf([
        "proposed",
        "announced",
        "accepted",
        "in_progress",
        "withdrawn",
        "uncertain"
    ]))
    var status: String
}

@available(macOS 26.0, *)
@Generable(description: "One possible decision that must remain uncertain until human confirmation.")
private struct AppleDiplomaticDecisionOutput {
    var content: String
    @Guide(.constant("uncertain"))
    var decisionType: String
}

/// Apple Foundation Models adapter. Each call uses a fresh, no-tool session and
/// guided generation; every returned field is revalidated by provider-neutral contracts.
@available(macOS 26.0, *)
public actor AppleFoundationModelsAnalysisProvider: AnalysisProvider {
    public static let adapterVersion = "meetingbuddy-task006a-v1"

    public nonisolated let metadata = try! ProviderMetadata(
        providerIdentifier: "apple-foundation-models",
        modelIdentifier: "system-language-model-default",
        modelVersion: appleSystemModelVersion,
        clientVersion: adapterVersion
    )
    public nonisolated let route: ModelExecutionRoute = .appleOnDevice

    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public func isModelAvailable(localeIdentifier: String) async -> Bool {
        model.availability == .available
            && model.supportsLocale(Locale(identifier: localeIdentifier))
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisOutputCandidate {
        guard await isModelAvailable(localeIdentifier: request.localeIdentifier) else {
            throw AIProviderContractError.modelUnavailable(
                "The on-device Apple Foundation Model is unavailable for this locale."
            )
        }
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: DiplomaticAnalysisPrompt.protectedRules
        )
        let response: LanguageModelSession.Response<AppleDiplomaticAnalysisOutput>
        do {
            response = try await session.respond(
                to: DiplomaticAnalysisPrompt.prompt(for: request),
                generating: AppleDiplomaticAnalysisOutput.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: nil,
                    maximumResponseTokens: 2_048
                )
            )
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError.invalidResponse(
                "Apple Foundation Models did not return a valid guided analysis response."
            )
        }
        return try Self.validate(response.content)
    }

    private static func validate(
        _ output: AppleDiplomaticAnalysisOutput
    ) throws -> AnalysisOutputCandidate {
        guard (0...1_000_000).contains(output.confidenceMillionths) else {
            throw AIProviderContractError.invalidResponse("Analysis confidence is outside its contract range.")
        }
        let confidence = try ConfidenceScore(
            millionths: UInt32(output.confidenceMillionths)
        )
        if !output.substantive {
            return try AnalysisOutputCandidate(
                substantive: false,
                nonSubstantiveReasonCode: output.nonSubstantiveReasonCode,
                confidence: confidence
            )
        }
        let intervention = InterventionType(encodedValue: output.interventionType)
        let position = PositionType(encodedValue: output.positionType)
        var invalidRequiredFields: [String] = []
        if !intervention.isKnown { invalidRequiredFields.append("intervention_type") }
        if output.issueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalidRequiredFields.append("issue_title")
        }
        if !position.isKnown || position == .noStatedPosition {
            invalidRequiredFields.append("position_type")
        }
        if output.positionStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalidRequiredFields.append("position_statement")
        }
        guard invalidRequiredFields.isEmpty else {
            throw AIProviderContractError.invalidResponse(
                "Guided substantive analysis omitted or contradicted required fields: "
                    + invalidRequiredFields.joined(separator: ",")
            )
        }
        let commitment: AnalysisCommitmentCandidate?
        if let value = output.commitment {
            commitment = try AnalysisCommitmentCandidate(
                content: value.content,
                recipientLabel: value.recipientLabel,
                conditions: value.conditions,
                deadlineDescription: value.deadlineDescription,
                status: CommitmentStatus(encodedValue: value.status)
            )
        } else {
            commitment = nil
        }
        let decision: AnalysisDecisionCandidate?
        if let value = output.decision {
            decision = try AnalysisDecisionCandidate(
                content: value.content,
                decisionType: DecisionType(encodedValue: value.decisionType)
            )
        } else {
            decision = nil
        }
        return try AnalysisOutputCandidate(
            substantive: true,
            interventionType: intervention,
            issueTitle: output.issueTitle,
            positionType: position,
            positionStatement: output.positionStatement,
            reservations: output.reservations,
            conditions: output.conditions,
            commitment: commitment,
            decision: decision,
            confidence: confidence
        )
    }
}
