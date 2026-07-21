import Foundation
import MeetingBuddyDomain

public enum UNWebTVMetadataError: Error, Equatable, Sendable {
    case invalidURL
    case outboundDisabled
    case userActionRequired
    case redirectRejected
    case authenticationRejected
    case unexpectedStatus(Int)
    case unsupportedContentType
    case responseTooLarge
    case malformedResponse
    case parserDrift
}

public struct ValidatedUNWebTVAssetURL: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let supportedLocales: Set<String> = ["ar", "zh", "en", "fr", "ru", "es"]

    public let absoluteString: String
    public let locale: String
    public let collectionID: String
    public let assetID: String

    public init(_ candidate: String) throws {
        guard candidate == candidate.trimmingCharacters(in: .whitespacesAndNewlines),
              candidate.utf8.count <= 512,
              !candidate.contains("%"),
              let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "webtv.un.org",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil,
              components.fragment == nil
        else {
            throw UNWebTVMetadataError.invalidURL
        }

        let path = components.percentEncodedPath
        let pieces = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard pieces.count == 4,
              Self.supportedLocales.contains(pieces[0]),
              pieces[1] == "asset",
              Self.isOpaqueID(pieces[2]),
              Self.isOpaqueID(pieces[3]),
              path == "/\(pieces[0])/asset/\(pieces[2])/\(pieces[3])"
        else {
            throw UNWebTVMetadataError.invalidURL
        }

        locale = pieces[0]
        collectionID = pieces[2]
        assetID = pieces[3]
        absoluteString = "https://webtv.un.org/\(locale)/asset/\(collectionID)/\(assetID)"
    }

    public var description: String { absoluteString }
    public var url: URL { URL(string: absoluteString)! }

    private static func isOpaqueID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...64).contains(bytes.count) && bytes.allSatisfy { byte in
            (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
        } && value != "." && value != ".."
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(absoluteString)
    }
}

public enum UNWebTVMetadataField: String, Codable, CaseIterable, Hashable, Sendable {
    case title
    case description
    case canonicalURL = "canonical_url"
    case productionDate = "production_date"
    case duration
    case category
    case languageAvailability = "language_availability"
    case broadcastingEntity = "broadcasting_entity"
    case summary
}

public enum UNWebTVParserSource: String, Codable, Hashable, Sendable {
    case htmlTitle = "html_title"
    case metaName = "meta_name"
    case metaProperty = "meta_property"
    case canonicalLink = "canonical_link"
    case jsonLD = "json_ld"
    case visibleLabel = "visible_label"
}

public enum UNWebTVMetadataConfidence: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low
}

public struct UNWebTVFieldProvenance: Codable, Hashable, Sendable {
    public let parserVersion: UInt32
    public let source: UNWebTVParserSource
    public let sourceKey: String
    public let normalizedValueDigest: ContentDigest
    public let confidence: UNWebTVMetadataConfidence

    public init(
        parserVersion: UInt32 = 1,
        source: UNWebTVParserSource,
        sourceKey: String,
        normalizedValueDigest: ContentDigest,
        confidence: UNWebTVMetadataConfidence
    ) throws {
        guard parserVersion == 1,
              !sourceKey.isEmpty,
              sourceKey.utf8.count <= 128,
              !sourceKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              normalizedValueDigest.algorithm == .sha256
        else {
            throw UNWebTVMetadataError.parserDrift
        }
        self.parserVersion = parserVersion
        self.source = source
        self.sourceKey = sourceKey
        self.normalizedValueDigest = normalizedValueDigest
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case parserVersion, source, sourceKey, normalizedValueDigest, confidence
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            parserVersion: values.decode(UInt32.self, forKey: .parserVersion),
            source: values.decode(UNWebTVParserSource.self, forKey: .source),
            sourceKey: values.decode(String.self, forKey: .sourceKey),
            normalizedValueDigest: values.decode(
                ContentDigest.self,
                forKey: .normalizedValueDigest
            ),
            confidence: values.decode(
                UNWebTVMetadataConfidence.self,
                forKey: .confidence
            )
        )
    }
}

public struct UNWebTVFieldCandidate: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let field: UNWebTVMetadataField
    public let value: String
    public let provenance: UNWebTVFieldProvenance

    public init(
        id: UUID = UUID(),
        field: UNWebTVMetadataField,
        value: String,
        provenance: UNWebTVFieldProvenance
    ) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumBytes = field == .description || field == .summary ? 4_096 : 512
        guard !normalized.isEmpty,
              normalized.utf8.count <= maximumBytes,
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw UNWebTVMetadataError.malformedResponse
        }
        self.id = id
        self.field = field
        self.value = normalized
        self.provenance = provenance
    }
}

public struct UNWebTVMetadataCandidate: Codable, Hashable, Sendable {
    public let requestedURL: ValidatedUNWebTVAssetURL
    public let finalURL: ValidatedUNWebTVAssetURL
    public let fields: [UNWebTVFieldCandidate]
    public let requiresReview: Bool
    public let fetchedAt: UTCInstant

    public init(
        requestedURL: ValidatedUNWebTVAssetURL,
        finalURL: ValidatedUNWebTVAssetURL,
        fields: [UNWebTVFieldCandidate],
        fetchedAt: UTCInstant
    ) throws {
        guard !fields.isEmpty, fields.count <= 64 else {
            throw UNWebTVMetadataError.parserDrift
        }
        let counts = Dictionary(grouping: fields, by: \.field).mapValues(\.count)
        self.requestedURL = requestedURL
        self.finalURL = finalURL
        self.fields = fields
        requiresReview = UNWebTVMetadataField.allCases.contains { (counts[$0] ?? 0) != 1 }
        self.fetchedAt = fetchedAt
    }
}

public struct UNWebTVMetadataRequestPolicy: Hashable, Sendable {
    public let directUserAction: Bool
    public let outboundEnabled: Bool
    public let maximumRedirects: UInt8
    public let maximumDecodedBodyBytes: Int

    public init(
        directUserAction: Bool,
        outboundEnabled: Bool,
        maximumRedirects: UInt8 = 2,
        maximumDecodedBodyBytes: Int = 1_048_576
    ) throws {
        guard directUserAction,
              maximumRedirects <= 2,
              maximumDecodedBodyBytes > 0,
              maximumDecodedBodyBytes <= 1_048_576
        else {
            throw UNWebTVMetadataError.userActionRequired
        }
        self.directUserAction = directUserAction
        self.outboundEnabled = outboundEnabled
        self.maximumRedirects = maximumRedirects
        self.maximumDecodedBodyBytes = maximumDecodedBodyBytes
    }
}

public protocol UNWebTVMetadataSource: Sendable {
    func metadataCandidate(
        for url: ValidatedUNWebTVAssetURL,
        policy: UNWebTVMetadataRequestPolicy
    ) async throws -> UNWebTVMetadataCandidate
}
