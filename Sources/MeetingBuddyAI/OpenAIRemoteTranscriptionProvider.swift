import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public protocol ExternalTranscriptionProviderBuilding:
    Sendable
{
    func makeProvider(
        configuration: RemoteProviderConfiguration,
        authorization: ExternalModelExecutionAuthorization
    ) throws -> any TranscriptionProvider
}

public struct OpenAIRemoteTranscriptionProviderFactory:
    ExternalTranscriptionProviderBuilding,
    Sendable
{
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    public func makeProvider(
        configuration: RemoteProviderConfiguration,
        authorization: ExternalModelExecutionAuthorization
    ) throws -> any TranscriptionProvider {
        guard let apiKey = try secretStore.read(
            configuration.secretIdentifier
        ) else {
            throw AIProviderContractError
                .secretUnavailable
        }
        return try OpenAIRemoteTranscriptionProvider(
            configuration: configuration,
            apiKey: apiKey,
            authorization: authorization
        )
    }
}

public struct OpenAIRemoteTranscriptionProvider:
    TranscriptionProvider,
    Sendable
{
    public let metadata: ProviderMetadata
    public let route: ModelExecutionRoute =
        .approvedExternal

    private let configuration:
        RemoteProviderConfiguration
    private let apiKey: Data
    private let authorization:
        ExternalModelExecutionAuthorization
    private let transport:
        any OpenAITranscriptionTransport

    public init(
        configuration: RemoteProviderConfiguration,
        apiKey: Data,
        authorization:
            ExternalModelExecutionAuthorization
    ) throws {
        try self.init(
            configuration: configuration,
            apiKey: apiKey,
            authorization: authorization,
            transport:
                SecureOpenAITranscriptionTransport()
        )
    }

    init(
        configuration: RemoteProviderConfiguration,
        apiKey: Data,
        authorization:
            ExternalModelExecutionAuthorization,
        transport: any OpenAITranscriptionTransport
    ) throws {
        let decision = authorization.decision
        guard configuration.family == .openAI,
              configuration.purpose == .speechToText,
              configuration.baseURL.absoluteString
                  == RemoteProviderConfiguration
                  .openAIBaseURL,
              configuration.connectionState == .ready,
              configuration.capabilities.contains(
                  .speechToTextBatch
              ),
              decision.route == .approvedExternal,
              decision.providerIdentifier
                  == configuration.identifier,
              decision.request.capability
                  == .transcription,
              decision.request.destination
                  == .approvedProvider(
                      identifier:
                          configuration.identifier
                  ),
              decision.request.retentionPolicy
                  == .approvedProviderRetention,
              decision.request.dataCategories
                  == [.canonicalAudio],
              decision.request
                  .visibleUserAuthorization,
              !decision.request.offlineMode,
              decision.request.dataClassification
                  .restrictionRank
                  < DataClassification.sensitive
                  .restrictionRank,
              (16...1_024).contains(apiKey.count),
              let key = String(
                  data: apiKey,
                  encoding: .utf8
              ),
              key == key.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !key.unicodeScalars.contains(
                  where:
                      CharacterSet.controlCharacters
                      .contains
              )
        else {
            throw AIProviderContractError.routeDenied(
                "The remote transcription adapter did not receive one exact authorized OpenAI audio route."
            )
        }
        self.configuration = configuration
        self.apiKey = apiKey
        self.authorization = authorization
        self.transport = transport
        metadata = try ProviderMetadata(
            providerIdentifier:
                configuration.identifier,
            modelIdentifier:
                configuration.modelIdentifier,
            clientVersion:
                "blueminutes-openai-transcription-v1"
        )
    }

    public func isModelInstalled(
        for language: LanguageTag
    ) async -> Bool {
        configuration.connectionState == .ready
            && !language.value.isEmpty
    }

    public func transcribe(
        _ request: TranscriptionRequest
    ) async throws -> TranscriptionChunkResult {
        guard request.dataClassification
                == authorization.decision.request
                .dataClassification,
              request.dataClassification.restrictionRank
                  < DataClassification.sensitive
                  .restrictionRank
        else {
            throw AIProviderContractError.routeDenied(
                "The task audio classification does not match the authorized remote route."
            )
        }
        let response = try await transport.transcribe(
            OpenAITranscriptionTransportRequest(
                configuration: configuration,
                apiKey: apiKey,
                audioURL: request.audio.fileURL,
                language: request.language
            )
        )
        return try response.result(
            maximumDurationMilliseconds:
                Int64(
                    request.audio.plan.physicalRange
                        .frameCount / 16
                )
        )
    }
}

struct OpenAITranscriptionTransportRequest:
    Sendable
{
    let configuration: RemoteProviderConfiguration
    let apiKey: Data
    let audioURL: URL
    let language: LanguageTag
}

protocol OpenAITranscriptionTransport: Sendable {
    func transcribe(
        _ request:
            OpenAITranscriptionTransportRequest
    ) async throws -> OpenAITranscriptionResponse
}

struct OpenAITranscriptionResponse: Sendable {
    struct Segment: Sendable {
        let startSeconds: Double
        let endSeconds: Double
        let text: String
        let averageLogProbability: Double?
    }

    let text: String
    let segments: [Segment]
    let tokenLogProbabilities: [Double]

    func result(
        maximumDurationMilliseconds: Int64
    ) throws -> TranscriptionChunkResult {
        guard maximumDurationMilliseconds > 0 else {
            throw AIProviderContractError
                .invalidResponse(
                    "The remote transcript has no bounded audio duration."
                )
        }
        let boundedSegments = try segments.compactMap {
            segment -> TranscriptionSpan? in
            let text = segment.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty else { return nil }
            guard segment.startSeconds.isFinite,
                  segment.endSeconds.isFinite,
                  segment.startSeconds >= 0,
                  segment.endSeconds
                      > segment.startSeconds,
                  segment.startSeconds
                      <= Double(
                          maximumDurationMilliseconds
                      ) / 1_000,
                  segment.endSeconds
                      <= Double(Int64.max) / 1_000
            else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcript returned an invalid timestamp."
                    )
            }
            let startMilliseconds =
                (segment.startSeconds * 1_000)
                .rounded(.down)
            let endMilliseconds =
                (segment.endSeconds * 1_000)
                .rounded(.up)
            guard let start =
                    Int64(
                        exactly:
                            startMilliseconds
                    ),
                  let unboundedEnd =
                    Int64(
                        exactly:
                            endMilliseconds
                    )
            else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcript returned an invalid timestamp."
                    )
            }
            let end = min(
                unboundedEnd,
                maximumDurationMilliseconds
            )
            guard end > start else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcript returned a timestamp outside the task audio."
                    )
            }
            return try TranscriptionSpan(
                startMilliseconds: start,
                endMilliseconds: end,
                text: text,
                confidence: confidence(
                    logProbability:
                        segment.averageLogProbability
                )
            )
        }
        if !boundedSegments.isEmpty {
            return try TranscriptionChunkResult(
                validatingSpans: boundedSegments
            )
        }

        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return .noSpeech }
        let averageLogProbability:
            Double? =
            tokenLogProbabilities.isEmpty
            ? nil
            : tokenLogProbabilities.reduce(0, +)
                / Double(
                    tokenLogProbabilities.count
                )
        return try TranscriptionChunkResult(
            validatingSpans: [
                TranscriptionSpan(
                    startMilliseconds: 0,
                    endMilliseconds:
                        maximumDurationMilliseconds,
                    text: trimmed,
                    confidence: confidence(
                        logProbability:
                            averageLogProbability
                    )
                )
            ]
        )
    }

    private func confidence(
        logProbability: Double?
    ) throws -> ConfidenceScore {
        let probability: Double
        if let logProbability,
           logProbability.isFinite
        {
            probability = exp(logProbability)
        } else {
            probability = 0.5
        }
        return try ConfidenceScore(
            millionths: UInt32(
                min(max(probability, 0), 1)
                    * 1_000_000
            )
        )
    }
}

struct SecureOpenAITranscriptionTransport:
    OpenAITranscriptionTransport,
    Sendable
{
    static let maximumAudioBytes =
        8 * 1_024 * 1_024
    static let maximumResponseBytes =
        2 * 1_024 * 1_024

    func transcribe(
        _ input: OpenAITranscriptionTransportRequest
    ) async throws -> OpenAITranscriptionResponse {
        let request = try urlRequest(input)
        let sessionConfiguration =
            URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.urlCredentialStorage =
            nil
        sessionConfiguration.httpCookieAcceptPolicy =
            .never
        sessionConfiguration.httpShouldSetCookies =
            false
        sessionConfiguration.waitsForConnectivity =
            false
        sessionConfiguration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        sessionConfiguration.timeoutIntervalForRequest =
            90
        sessionConfiguration.timeoutIntervalForResource =
            120
        let delegate =
            OpenAITranscriptionSessionDelegate(
                allowedURL: request.url
            )
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) =
                try await session.bytes(for: request)
            guard let http =
                    response as? HTTPURLResponse,
                  http.url == request.url
            else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcription response did not come from the approved endpoint."
                    )
            }
            var data = Data()
            data.reserveCapacity(64 * 1_024)
            for try await byte in bytes {
                guard data.count
                        < Self.maximumResponseBytes
                else {
                    throw AIProviderContractError
                        .invalidResponse(
                            "The remote transcription response exceeded the bounded size."
                        )
                }
                data.append(byte)
            }
            switch http.statusCode {
            case 200:
                return try decode(
                    data,
                    modelIdentifier:
                        input.configuration
                        .modelIdentifier
                )
            case 401, 403:
                throw AIProviderContractError
                    .secretUnavailable
            case 404:
                throw AIProviderContractError
                    .modelUnavailable(
                        "The configured remote speech model is unavailable."
                    )
            default:
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcription provider rejected the bounded request."
                    )
            }
        } catch let error as AIProviderContractError {
            throw error
        } catch is URLError {
            throw AIProviderContractError
                .invalidResponse(
                    "The remote transcription provider could not be reached."
                )
        } catch {
            throw AIProviderContractError
                .invalidResponse(
                    "The remote transcription response could not be verified."
                )
        }
    }

    func urlRequest(
        _ input: OpenAITranscriptionTransportRequest
    ) throws -> URLRequest {
        guard input.configuration.family == .openAI,
              input.configuration.purpose
                  == .speechToText,
              input.configuration.baseURL
                  .absoluteString
                  == RemoteProviderConfiguration
                  .openAIBaseURL,
              input.configuration.capabilities
                  .contains(.speechToTextBatch),
              let key = String(
                  data: input.apiKey,
                  encoding: .utf8
              ),
              (16...1_024).contains(
                  input.apiKey.count
              ),
              var components = URLComponents(
                  string:
                      RemoteProviderConfiguration
                      .openAIBaseURL
              )
        else {
            throw AIProviderContractError
                .invalidRequest(
                    "The remote transcription request is not an approved OpenAI audio request."
                )
        }
        let values = try input.audioURL.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ]
        )
        guard input.audioURL.isFileURL,
              input.audioURL.pathExtension
                  .lowercased() == "wav",
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumAudioBytes
        else {
            throw AIProviderContractError
                .invalidRequest(
                    "Remote transcription accepts one bounded verified WAV task artifact."
                )
        }
        let audio = try Data(
            contentsOf: input.audioURL,
            options: [.mappedIfSafe]
        )
        guard audio.count == fileSize else {
            throw AIProviderContractError
                .invalidRequest(
                    "The remote transcription task artifact changed before upload."
                )
        }

        components.path = "/v1/audio/transcriptions"
        guard let url = components.url,
              url.scheme == "https",
              url.host == "api.openai.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil
        else {
            throw AIProviderContractError
                .routeDenied(
                    "The remote transcription endpoint is not approved."
                )
        }
        let boundary =
            "BlueMinutes-\(UUID().uuidString)"
        var body = Data()
        appendField(
            name: "model",
            value:
                input.configuration
                .modelIdentifier,
            boundary: boundary,
            to: &body
        )
        if let language = iso639Language(
            input.language
        ) {
            appendField(
                name: "language",
                value: language,
                boundary: boundary,
                to: &body
            )
        }
        switch input.configuration.modelIdentifier {
        case "whisper-1":
            appendField(
                name: "response_format",
                value: "verbose_json",
                boundary: boundary,
                to: &body
            )
            appendField(
                name:
                    "timestamp_granularities[]",
                value: "segment",
                boundary: boundary,
                to: &body
            )
        case "gpt-4o-transcribe-diarize":
            appendField(
                name: "response_format",
                value: "diarized_json",
                boundary: boundary,
                to: &body
            )
            appendField(
                name: "chunking_strategy",
                value: "auto",
                boundary: boundary,
                to: &body
            )
        default:
            appendField(
                name: "response_format",
                value: "json",
                boundary: boundary,
                to: &body
            )
            appendField(
                name: "include[]",
                value: "logprobs",
                boundary: boundary,
                to: &body
            )
        }
        appendFile(
            audio,
            boundary: boundary,
            to: &body
        )
        body.append(
            Data("--\(boundary)--\r\n".utf8)
        )

        var request = URLRequest(
            url: url,
            cachePolicy:
                .reloadIgnoringLocalCacheData,
            timeoutInterval: 90
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "Bearer \(key)",
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    private func decode(
        _ data: Data,
        modelIdentifier: String
    ) throws -> OpenAITranscriptionResponse {
        do {
            let value = try JSONDecoder().decode(
                WireResponse.self,
                from: data
            )
            let segments =
                value.segments?.map {
                    OpenAITranscriptionResponse
                        .Segment(
                            startSeconds:
                                $0.start,
                            endSeconds: $0.end,
                            text: $0.text,
                            averageLogProbability:
                                $0.avgLogprob
                        )
                } ?? []
            let logProbabilities =
                value.logprobs?.compactMap(
                    \.logprob
                ) ?? []
            guard !value.text.contains("\0"),
                  value.text.utf8.count
                      <= 1_048_576,
                  segments.count <= 4_096,
                  segments.allSatisfy({
                      !$0.text.contains("\0")
                          && $0.text.utf8.count
                              <= 65_536
                  })
            else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The remote transcript exceeded its bounded response contract."
                    )
            }
            return OpenAITranscriptionResponse(
                text: value.text,
                segments: segments,
                tokenLogProbabilities:
                    logProbabilities
            )
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError
                .invalidResponse(
                    "The \(modelIdentifier) transcription response did not match the verified schema."
                )
        }
    }

    private func appendField(
        name: String,
        value: String,
        boundary: String,
        to data: inout Data
    ) {
        data.append(
            Data(
                """
                --\(boundary)\r
                Content-Disposition: form-data; name="\(name)"\r
                \r
                \(value)\r
                """.utf8
            )
        )
    }

    private func appendFile(
        _ audio: Data,
        boundary: String,
        to data: inout Data
    ) {
        data.append(
            Data(
                """
                --\(boundary)\r
                Content-Disposition: form-data; name="file"; filename="chunk.wav"\r
                Content-Type: audio/wav\r
                \r
                """.utf8
            )
        )
        data.append(audio)
        data.append(Data("\r\n".utf8))
    }

    private func iso639Language(
        _ language: LanguageTag
    ) -> String? {
        let primary = language.value
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
        guard let primary,
              primary.count == 2,
              primary.allSatisfy(\.isLetter)
        else { return nil }
        return primary
    }

    private struct WireResponse: Decodable {
        let text: String
        let segments: [WireSegment]?
        let logprobs: [WireLogProbability]?
    }

    private struct WireSegment: Decodable {
        let start: Double
        let end: Double
        let text: String
        let avgLogprob: Double?

        private enum CodingKeys:
            String,
            CodingKey
        {
            case start
            case end
            case text
            case avgLogprob = "avg_logprob"
        }
    }

    private struct WireLogProbability: Decodable {
        let logprob: Double?
    }
}

private final class OpenAITranscriptionSessionDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let allowedURL: URL?

    init(allowedURL: URL?) {
        self.allowedURL = allowedURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection
            response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler:
            @escaping (URLRequest?) -> Void
    ) {
        completionHandler(
            request.url == allowedURL
                ? request
                : nil
        )
    }
}
