import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct OpenAIProviderConnectionTester:
    RemoteProviderConnectionTesting,
    Sendable
{
    public init() {}

    public func test(
        configuration: RemoteProviderConfiguration,
        apiKey: Data
    ) async -> RemoteProviderConnectionState {
        guard configuration.family == .openAI,
              configuration.baseURL.absoluteString
                == RemoteProviderConfiguration.openAIBaseURL,
              apiKey.count >= 16,
              apiKey.count <= 1_024,
              let key = String(data: apiKey, encoding: .utf8),
              key == key.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !key.unicodeScalars.contains(
                  where: CharacterSet.controlCharacters.contains
              ),
              var components = URLComponents(
                  string:
                    RemoteProviderConfiguration.openAIBaseURL
              )
        else {
            return .invalidCredential
        }
        if configuration.purpose
            == .speechToText
        {
            return await testSpeechToText(
                configuration: configuration,
                apiKey: apiKey
            )
        }
        components.path =
            "/v1/models/\(configuration.modelIdentifier)"
        guard let url = components.url,
              url.scheme == "https",
              url.host == "api.openai.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil
        else {
            return .serverRejected
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        do {
            let (_, http) = try await response(
                for: request,
                maximumBytes: 256 * 1_024
            )
            switch http.statusCode {
            case 200:
                return .ready
            case 401, 403:
                return .invalidCredential
            case 404:
                return .modelUnavailable
            default:
                return .serverRejected
            }
        } catch is URLError {
            return .networkUnavailable
        } catch {
            return .serverRejected
        }
    }

    private func testSpeechToText(
        configuration: RemoteProviderConfiguration,
        apiKey: Data
    ) async -> RemoteProviderConnectionState {
        let fileManager = FileManager.default
        let directory = fileManager
            .temporaryDirectory
            .appendingPathComponent(
                "blueminutes-stt-connection-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )
            defer {
                try? fileManager.removeItem(
                    at: directory
                )
            }
            let sampleURL = directory
                .appendingPathComponent(
                    "bundled-non-sensitive-sample.wav"
                )
            try BundledSTTConnectionSample
                .wavData()
                .write(
                    to: sampleURL,
                    options: [.atomic]
                )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: sampleURL.path
            )
            let request = try
                SecureOpenAITranscriptionTransport()
                .urlRequest(
                    OpenAITranscriptionTransportRequest(
                        configuration:
                            configuration,
                        apiKey: apiKey,
                        audioURL: sampleURL,
                        language:
                            try LanguageTag("en")
                    )
                )
            let (data, http) = try await response(
                for: request,
                maximumBytes:
                    SecureOpenAITranscriptionTransport
                    .maximumResponseBytes
            )
            switch http.statusCode {
            case 200:
                return Self
                    .containsExpectedSampleTranscript(
                        data
                    )
                    ? .ready
                    : .serverRejected
            case 401, 403:
                return .invalidCredential
            case 404:
                return .modelUnavailable
            default:
                return .serverRejected
            }
        } catch is URLError {
            return .networkUnavailable
        } catch let error
            as AIProviderContractError
        {
            return switch error {
            case .secretUnavailable:
                .invalidCredential
            case .modelUnavailable:
                .modelUnavailable
            case .invalidRequest,
                 .invalidResponse,
                 .routeDenied:
                .serverRejected
            }
        } catch {
            return .serverRejected
        }
    }

    static func containsExpectedSampleTranscript(
        _ data: Data
    ) -> Bool {
        struct Response: Decodable {
            let text: String
        }
        guard data.count <=
                SecureOpenAITranscriptionTransport
                .maximumResponseBytes,
              let response = try? JSONDecoder()
                .decode(Response.self, from: data),
              !response.text.contains("\0"),
              response.text.utf8.count <= 4_096
        else {
            return false
        }
        let normalized = response.text
            .lowercased()
            .unicodeScalars
            .filter {
                CharacterSet.alphanumerics
                    .contains($0)
            }
            .map(String.init)
            .joined()
        return normalized.contains(
            BundledSTTConnectionSample
                .expectedNormalizedTranscript
        )
    }

    private func response(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw AIProviderContractError
                .invalidRequest(
                    "The OpenAI connection request has no approved URL."
                )
        }
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        let delegate =
            OpenAIConnectionSessionDelegate(
                allowedURL: url
            )
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (bytes, response) =
            try await session.bytes(
                for: request
            )
        guard let http =
                response as? HTTPURLResponse,
              http.url == url
        else {
            throw AIProviderContractError
                .invalidResponse(
                    "The provider connection response did not come from the approved endpoint."
                )
        }
        var data = Data()
        data.reserveCapacity(
            min(maximumBytes, 64 * 1_024)
        )
        for try await byte in bytes {
            guard data.count < maximumBytes
            else {
                throw AIProviderContractError
                    .invalidResponse(
                        "The provider connection response exceeded its bounded contract."
                    )
            }
            data.append(byte)
        }
        return (data, http)
    }
}

private final class OpenAIConnectionSessionDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let allowedURL: URL

    init(allowedURL: URL) {
        self.allowedURL = allowedURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
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
