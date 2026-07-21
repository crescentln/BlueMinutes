import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class URLSessionUNWebTVMetadataSource: UNWebTVMetadataSource, @unchecked Sendable {
    private let parser: UNWebTVMetadataHTMLParser
    private let clock: @Sendable () -> UTCInstant
    private let protocolClasses: [AnyClass]?

    public init(
        parser: UNWebTVMetadataHTMLParser = UNWebTVMetadataHTMLParser(),
        protocolClasses: [AnyClass]? = nil,
        clock: @escaping @Sendable () -> UTCInstant = {
            try! UTCInstant(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
            )
        }
    ) {
        self.parser = parser
        self.protocolClasses = protocolClasses
        self.clock = clock
    }

    public func metadataCandidate(
        for url: ValidatedUNWebTVAssetURL,
        policy: UNWebTVMetadataRequestPolicy
    ) async throws -> UNWebTVMetadataCandidate {
        guard policy.directUserAction else { throw UNWebTVMetadataError.userActionRequired }
        guard policy.outboundEnabled else { throw UNWebTVMetadataError.outboundDisabled }

        let delegate = UNWebTVSessionDelegate(maximumRedirects: policy.maximumRedirects)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = false
        if let protocolClasses { configuration.protocolClasses = protocolClasses }

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(
            url: url.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.httpMethod = "GET"
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  let responseURL = response.url,
                  response.statusCode == 200
            else {
                if let response = response as? HTTPURLResponse {
                    throw UNWebTVMetadataError.unexpectedStatus(response.statusCode)
                }
                throw UNWebTVMetadataError.malformedResponse
            }
            let finalURL = try ValidatedUNWebTVAssetURL(responseURL.absoluteString)
            guard response.mimeType?.lowercased() == "text/html" else {
                throw UNWebTVMetadataError.unsupportedContentType
            }
            let headerBytes = response.allHeaderFields.reduce(0) { partial, entry in
                partial + String(describing: entry.key).utf8.count
                    + String(describing: entry.value).utf8.count
            }
            guard response.allHeaderFields.count <= 64, headerBytes <= 32_768,
                  response.expectedContentLength < 0
                    || response.expectedContentLength <= Int64(policy.maximumDecodedBodyBytes)
            else {
                throw UNWebTVMetadataError.responseTooLarge
            }

            var body = Data()
            body.reserveCapacity(min(policy.maximumDecodedBodyBytes, 65_536))
            for try await byte in bytes {
                guard body.count < policy.maximumDecodedBodyBytes else {
                    throw UNWebTVMetadataError.responseTooLarge
                }
                body.append(byte)
            }
            guard !body.isEmpty else { throw UNWebTVMetadataError.malformedResponse }
            return try parser.parse(
                body,
                requestedURL: url,
                finalURL: finalURL,
                fetchedAt: clock()
            )
        } catch let error as UNWebTVMetadataError {
            throw error
        } catch {
            if delegate.redirectWasRejected {
                throw UNWebTVMetadataError.redirectRejected
            }
            if delegate.authenticationWasRejected {
                throw UNWebTVMetadataError.authenticationRejected
            }
            throw UNWebTVMetadataError.malformedResponse
        }
    }
}

private final class UNWebTVSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let maximumRedirects: UInt8
    private let lock = NSLock()
    private var redirectCount: UInt8 = 0
    private var rejectedRedirect = false
    private var rejectedAuthentication = false

    init(maximumRedirects: UInt8) {
        self.maximumRedirects = maximumRedirects
    }

    var redirectWasRejected: Bool {
        lock.withLock { rejectedRedirect }
    }

    var authenticationWasRejected: Bool {
        lock.withLock { rejectedAuthentication }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let accepted = lock.withLock { () -> Bool in
            guard redirectCount < maximumRedirects,
                  request.httpMethod == "GET",
                  request.httpBody == nil,
                  let target = request.url,
                  (try? ValidatedUNWebTVAssetURL(target.absoluteString)) != nil
            else {
                rejectedRedirect = true
                return false
            }
            redirectCount += 1
            return true
        }
        completionHandler(accepted ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            lock.withLock { rejectedAuthentication = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
