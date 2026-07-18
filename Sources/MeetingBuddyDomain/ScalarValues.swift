import Foundation

/// A major/minor semantic-contract version. Major version zero is invalid.
public struct SchemaVersion: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let major: UInt16
    public let minor: UInt16

    public static let v1 = try! SchemaVersion(major: 1, minor: 0)

    public init(major: UInt16, minor: UInt16 = 0) throws {
        self.major = major
        self.minor = minor
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    public func validationIssues() -> [ValidationIssue] {
        guard major == 0 else { return [] }
        return [
            ValidationIssue(
                code: .invalidRange,
                path: "schema_version.major",
                message: "Schema major version must be greater than zero."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        major = try container.decode(UInt16.self, forKey: .major)
        minor = try container.decodeIfPresent(UInt16.self, forKey: .minor) ?? 0
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case major
        case minor
    }
}

/// A deterministic UTC instant represented as integer Unix epoch milliseconds.
public struct UTCInstant: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let millisecondsSinceUnixEpoch: Int64

    public init(millisecondsSinceUnixEpoch: Int64) throws {
        self.millisecondsSinceUnixEpoch = millisecondsSinceUnixEpoch
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.millisecondsSinceUnixEpoch < rhs.millisecondsSinceUnixEpoch
    }

    public func validationIssues() -> [ValidationIssue] {
        guard millisecondsSinceUnixEpoch < 0 else { return [] }
        return [
            ValidationIssue(
                code: .invalidRange,
                path: "utc_instant",
                message: "MeetingBuddy contract timestamps cannot precede the Unix epoch."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        millisecondsSinceUnixEpoch = try container.decode(Int64.self)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(millisecondsSinceUnixEpoch)
    }
}

/// A probability-like value in integer millionths, from zero through one million.
public struct ConfidenceScore: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let millionths: UInt32

    public init(millionths: UInt32) throws {
        self.millionths = millionths
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.millionths < rhs.millionths
    }

    public func validationIssues() -> [ValidationIssue] {
        guard millionths > 1_000_000 else { return [] }
        return [
            ValidationIssue(
                code: .invalidRange,
                path: "confidence",
                message: "Confidence must be between 0 and 1,000,000 millionths."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        millionths = try container.decode(UInt32.self)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(millionths)
    }
}

/// A normalized, bounded language tag suitable for a stable wire contract.
public struct LanguageTag: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let value: String

    public init(_ value: String) throws {
        self.value = value.lowercased()
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    public func validationIssues() -> [ValidationIssue] {
        let bytes = Array(value.utf8)
        let allowed = bytes.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
        }
        guard
            value == value.meetingBuddyTrimmed,
            (2...35).contains(bytes.count),
            allowed,
            bytes.first != 45,
            bytes.last != 45,
            !value.contains("--")
        else {
            return [
                ValidationIssue(
                    code: .invalidFormat,
                    path: "language",
                    message: "Language tags must use 2–35 ASCII letters, digits, or separated hyphens."
                )
            ]
        }
        return []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self).lowercased()
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// A normalized Internet media type without parameters.
public struct MIMEType: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let value: String

    public init(_ value: String) throws {
        self.value = value.lowercased()
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    public func validationIssues() -> [ValidationIssue] {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let tokenBytesAreValid = components.allSatisfy { component in
            !component.isEmpty && component.utf8.allSatisfy { byte in
                (byte >= 97 && byte <= 122)
                    || (byte >= 48 && byte <= 57)
                    || byte == 33
                    || byte == 35
                    || byte == 36
                    || byte == 38
                    || byte == 43
                    || byte == 45
                    || byte == 46
                    || byte == 94
                    || byte == 95
            }
        }
        guard
            value == value.meetingBuddyTrimmed,
            components.count == 2,
            tokenBytesAreValid
        else {
            return [
                ValidationIssue(
                    code: .invalidFormat,
                    path: "mime_type",
                    message: "A MIME type must contain two valid lowercase tokens separated by one slash."
                )
            ]
        }
        return []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self).lowercased()
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// A content digest. Source bytes and semantic revision content use distinct fields.
public struct ContentDigest: Codable, Hashable, Sendable, DomainValidatable {
    public let algorithm: HashAlgorithm
    public let lowercaseHex: String

    public init(algorithm: HashAlgorithm, lowercaseHex: String) throws {
        self.algorithm = algorithm
        self.lowercaseHex = lowercaseHex.lowercased()
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !algorithm.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "content_digest.algorithm",
                    message: "The hash algorithm is not supported by this contract version."
                )
            )
        }
        let bytes = Array(lowercaseHex.utf8)
        let isHex = bytes.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
        if bytes.isEmpty || bytes.count % 2 != 0 || !isHex {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "content_digest.lowercase_hex",
                    message: "A content digest must be a non-empty, even-length lowercase hexadecimal string."
                )
            )
        } else if algorithm == .sha256 && bytes.count != 64 {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "content_digest.lowercase_hex",
                    message: "A SHA-256 digest must contain exactly 64 hexadecimal characters."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decode(HashAlgorithm.self, forKey: .algorithm)
        lowercaseHex = try container.decode(String.self, forKey: .lowercaseHex).lowercased()
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case lowercaseHex = "lowercase_hex"
    }
}

/// An opaque storage-service identifier. It deliberately contains no path.
public struct ManagedAssetReference: Codable, Hashable, Sendable {
    public let storageObjectID: StorageObjectID

    public init(storageObjectID: StorageObjectID) {
        self.storageObjectID = storageObjectID
    }

    private enum CodingKeys: String, CodingKey {
        case storageObjectID = "storage_object_id"
    }
}

/// A structurally safe HTTPS source reference. Domain validation does not perform I/O.
public struct HTTPSURL: Codable, Hashable, Sendable, DomainValidatable {
    public let absoluteString: String

    public init(_ absoluteString: String) throws {
        self.absoluteString = absoluteString
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        guard
            absoluteString == absoluteString.meetingBuddyTrimmed,
            absoluteString.utf8.count <= 2_048,
            !absoluteString.contains("\\"),
            let components = URLComponents(string: absoluteString),
            components.scheme == "https",
            let host = components.host,
            !host.isEmpty,
            host == host.lowercased(),
            components.user == nil,
            components.password == nil,
            components.url?.isFileURL == false
        else {
            return [
                ValidationIssue(
                    code: .invalidFormat,
                    path: "source_url",
                    message: "A source URL must be an absolute HTTPS URL without user information."
                )
            ]
        }
        return []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        absoluteString = try container.decode(String.self)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(absoluteString)
    }
}

/// A non-empty half-open UTF-8 byte range.
public struct UTF8TextRange: Codable, Hashable, Sendable, DomainValidatable {
    public let startOffset: UInt64
    public let length: UInt64

    public init(startOffset: UInt64, length: UInt64) throws {
        self.startOffset = startOffset
        self.length = length
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        guard length == 0 else { return [] }
        return [
            ValidationIssue(
                code: .invalidRange,
                path: "text_range.length",
                message: "A text range must contain at least one UTF-8 byte."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startOffset = try container.decode(UInt64.self, forKey: .startOffset)
        length = try container.decode(UInt64.self, forKey: .length)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case startOffset = "start_offset"
        case length
    }
}

/// A non-empty half-open media time range in integer milliseconds.
public struct MediaTimeRange: Codable, Hashable, Sendable, DomainValidatable {
    public let startMilliseconds: Int64
    public let endMilliseconds: Int64

    public init(startMilliseconds: Int64, endMilliseconds: Int64) throws {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        guard startMilliseconds < 0 || endMilliseconds <= startMilliseconds else {
            return []
        }
        return [
            ValidationIssue(
                code: .invalidRange,
                path: "media_time_range",
                message: "A media range must start at or after zero and end after its start."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startMilliseconds = try container.decode(Int64.self, forKey: .startMilliseconds)
        endMilliseconds = try container.decode(Int64.self, forKey: .endMilliseconds)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case startMilliseconds = "start_milliseconds"
        case endMilliseconds = "end_milliseconds"
    }
}

/// A precise, one-based location inside a document revision.
public struct DocumentLocation: Codable, Hashable, Sendable, DomainValidatable {
    public let pageNumber: UInt32?
    public let paragraphNumber: UInt32?
    public let section: String?
    public let textRange: UTF8TextRange?

    public init(
        pageNumber: UInt32? = nil,
        paragraphNumber: UInt32? = nil,
        section: String? = nil,
        textRange: UTF8TextRange? = nil
    ) throws {
        self.pageNumber = pageNumber
        self.paragraphNumber = paragraphNumber
        self.section = section
        self.textRange = textRange
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if pageNumber == nil, paragraphNumber == nil, section == nil, textRange == nil {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "document_location",
                    message: "A document location must contain at least one exact locator."
                )
            )
        }
        if pageNumber == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "document_location.page_number",
                    message: "Document page numbers are one-based."
                )
            )
        }
        if paragraphNumber == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "document_location.paragraph_number",
                    message: "Document paragraph numbers are one-based."
                )
            )
        }
        if let section,
           section != section.meetingBuddyTrimmed
            || section.isEmpty
            || section.utf8.count > 512
            || section.meetingBuddyContainsControlCharacter
        {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "document_location.section",
                    message: "A section locator must be non-empty and contain no control characters."
                )
            )
        }
        if let textRange {
            issues.append(contentsOf: textRange.validationIssues())
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageNumber = try container.decodeIfPresent(UInt32.self, forKey: .pageNumber)
        paragraphNumber = try container.decodeIfPresent(UInt32.self, forKey: .paragraphNumber)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        textRange = try container.decodeIfPresent(UTF8TextRange.self, forKey: .textRange)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case pageNumber = "page_number"
        case paragraphNumber = "paragraph_number"
        case section
        case textRange = "text_range"
    }
}
