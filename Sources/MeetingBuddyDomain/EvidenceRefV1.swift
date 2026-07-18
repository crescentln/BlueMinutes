import Foundation

/// The closed discriminator set for the EvidenceRef.v1 tagged union.
public enum EvidenceKind: String, Codable, Hashable, Sendable {
    case transcriptSegment = "transcript_segment"
    case documentLocation = "document_location"
    case mediaTimeRange = "media_time_range"
    case userConfirmedNote = "user_confirmed_note"
    case meetingMetadata = "meeting_metadata"
    case semanticObjectRevision = "semantic_object_revision"
    case officialStatement = "official_statement"
}

/// A typed source revision and location.
///
/// The union binds each locator to its exact source. Unknown future
/// discriminators are rejected because v1 cannot interpret their payload.
public enum EvidenceLocation: Codable, Hashable, Sendable, DomainValidatable {
    case transcriptSegment(source: SemanticRevisionReference, textRange: UTF8TextRange?)
    case documentLocation(source: SemanticRevisionReference, location: DocumentLocation)
    case mediaTimeRange(source: SemanticRevisionReference, range: MediaTimeRange)
    case userConfirmedNote(source: SemanticRevisionReference, textRange: UTF8TextRange?)
    case meetingMetadata(source: SemanticRevisionReference, field: String)
    case semanticObjectRevision(source: SemanticRevisionReference, jsonPointer: String?)
    case officialStatement(source: SemanticRevisionReference, location: DocumentLocation)

    public var kind: EvidenceKind {
        switch self {
        case .transcriptSegment: .transcriptSegment
        case .documentLocation: .documentLocation
        case .mediaTimeRange: .mediaTimeRange
        case .userConfirmedNote: .userConfirmedNote
        case .meetingMetadata: .meetingMetadata
        case .semanticObjectRevision: .semanticObjectRevision
        case .officialStatement: .officialStatement
        }
    }

    public var source: SemanticRevisionReference {
        switch self {
        case let .transcriptSegment(source, _),
             let .documentLocation(source, _),
             let .mediaTimeRange(source, _),
             let .userConfirmedNote(source, _),
             let .meetingMetadata(source, _),
             let .semanticObjectRevision(source, _),
             let .officialStatement(source, _):
            source
        }
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = source.validationIssues()

        switch self {
        case let .transcriptSegment(source, textRange):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .transcriptSegment))
            issues.append(contentsOf: textRange?.validationIssues() ?? [])
        case let .documentLocation(source, location):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .sourceAsset))
            issues.append(contentsOf: location.validationIssues())
        case let .mediaTimeRange(source, range):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .sourceAsset))
            issues.append(contentsOf: range.validationIssues())
        case let .userConfirmedNote(source, textRange):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .userConfirmedNote))
            issues.append(contentsOf: textRange?.validationIssues() ?? [])
        case let .meetingMetadata(source, field):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .meetingProfile))
            guard
                field == field.meetingBuddyTrimmed,
                !field.isEmpty,
                field.utf8.count <= 256,
                !field.meetingBuddyContainsControlCharacter
            else {
                issues.append(
                    ValidationIssue(
                        code: .invalidFormat,
                        path: "evidence_location.field",
                        message: "A metadata field locator must be non-empty, bounded text."
                    )
                )
                return issues
            }
        case let .semanticObjectRevision(source, jsonPointer):
            if !source.objectType.isKnown {
                issues.append(
                    ValidationIssue(
                        code: .unsupportedValue,
                        path: "evidence_location.source.object_type",
                        message: "A semantic revision locator requires a known source object type."
                    )
                )
            }
            if let jsonPointer {
                issues.append(contentsOf: Self.jsonPointerIssues(jsonPointer))
            }
        case let .officialStatement(source, location):
            issues.append(contentsOf: expectedSourceIssue(source, expected: .sourceAsset))
            issues.append(contentsOf: location.validationIssues())
        }

        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(EvidenceKind.self, forKey: .kind)
        let source = try container.decode(SemanticRevisionReference.self, forKey: .source)
        switch kind {
        case .transcriptSegment:
            self = .transcriptSegment(
                source: source,
                textRange: try container.decodeIfPresent(UTF8TextRange.self, forKey: .textRange)
            )
        case .documentLocation:
            self = .documentLocation(
                source: source,
                location: try container.decode(DocumentLocation.self, forKey: .documentLocation)
            )
        case .mediaTimeRange:
            self = .mediaTimeRange(
                source: source,
                range: try container.decode(MediaTimeRange.self, forKey: .mediaTimeRange)
            )
        case .userConfirmedNote:
            self = .userConfirmedNote(
                source: source,
                textRange: try container.decodeIfPresent(UTF8TextRange.self, forKey: .textRange)
            )
        case .meetingMetadata:
            self = .meetingMetadata(
                source: source,
                field: try container.decode(String.self, forKey: .field)
            )
        case .semanticObjectRevision:
            self = .semanticObjectRevision(
                source: source,
                jsonPointer: try container.decodeIfPresent(String.self, forKey: .jsonPointer)
            )
        case .officialStatement:
            self = .officialStatement(
                source: source,
                location: try container.decode(DocumentLocation.self, forKey: .documentLocation)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(source, forKey: .source)
        switch self {
        case let .transcriptSegment(_, textRange), let .userConfirmedNote(_, textRange):
            try container.encodeIfPresent(textRange, forKey: .textRange)
        case let .documentLocation(_, location), let .officialStatement(_, location):
            try container.encode(location, forKey: .documentLocation)
        case let .mediaTimeRange(_, range):
            try container.encode(range, forKey: .mediaTimeRange)
        case let .meetingMetadata(_, field):
            try container.encode(field, forKey: .field)
        case let .semanticObjectRevision(_, jsonPointer):
            try container.encodeIfPresent(jsonPointer, forKey: .jsonPointer)
        }
    }

    private func expectedSourceIssue(
        _ source: SemanticRevisionReference,
        expected: SemanticObjectType
    ) -> [ValidationIssue] {
        guard source.objectType != expected else { return [] }
        return [
            ValidationIssue(
                code: .inconsistentValue,
                path: "evidence_location.source.object_type",
                message: "The evidence kind requires a \(expected.encodedValue) source revision."
            )
        ]
    }

    private static func jsonPointerIssues(_ value: String) -> [ValidationIssue] {
        let bytes = Array(value.utf8)
        guard
            !bytes.isEmpty,
            bytes.count <= 1_024,
            bytes.first == 47,
            !value.meetingBuddyContainsControlCharacter
        else {
            return [
                ValidationIssue(
                    code: .invalidFormat,
                    path: "evidence_location.json_pointer",
                    message: "A semantic-object locator must be a bounded absolute JSON Pointer."
                )
            ]
        }

        var index = 0
        while index < bytes.count {
            if bytes[index] == 126 {
                guard index + 1 < bytes.count, bytes[index + 1] == 48 || bytes[index + 1] == 49 else {
                    return [
                        ValidationIssue(
                            code: .invalidFormat,
                            path: "evidence_location.json_pointer",
                            message: "JSON Pointer tildes must use the ~0 or ~1 escape."
                        )
                    ]
                }
                index += 2
            } else {
                index += 1
            }
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case source
        case textRange = "text_range"
        case documentLocation = "document_location"
        case mediaTimeRange = "media_time_range"
        case field
        case jsonPointer = "json_pointer"
    }
}

/// Required evidence text plus its language and translation relationship.
public struct EvidenceExcerpt: Codable, Hashable, Sendable, DomainValidatable {
    public let text: String
    public let language: LanguageTag
    public let translationStatus: TranslationStatus

    public init(
        text: String,
        language: LanguageTag,
        translationStatus: TranslationStatus
    ) throws {
        self.text = text
        self.language = language
        self.translationStatus = translationStatus
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = language.validationIssues()
        if text.meetingBuddyTrimmed.isEmpty || text.utf8.count > 16_384 || text.contains("\u{0}") {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "excerpt",
                    message: "Evidence text must be non-empty, at most 16 KiB, and contain no null byte."
                )
            )
        }
        if !translationStatus.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "translation_status",
                    message: "The translation status is not supported by EvidenceRef.v1."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        language = try container.decode(LanguageTag.self, forKey: .language)
        translationStatus = try container.decode(TranslationStatus.self, forKey: .translationStatus)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case language
        case translationStatus = "translation_status"
    }
}

/// EvidenceRef.v1 links an exact semantic revision to an exact typed location.
public struct EvidenceRefV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<EvidenceIDTag>
    public let location: EvidenceLocation
    public let excerpt: EvidenceExcerpt
    public let confidence: ConfidenceScore

    public init(
        revision: RevisionEnvelope<EvidenceIDTag>,
        location: EvidenceLocation,
        excerpt: EvidenceExcerpt,
        confidence: ConfidenceScore
    ) throws {
        self.revision = revision
        self.location = location
        self.excerpt = excerpt
        self.confidence = confidence
        try validate()
    }

    public var evidenceID: EvidenceID {
        revision.logicalID
    }

    public var evidenceKind: EvidenceKind {
        location.kind
    }

    public var source: SemanticRevisionReference {
        location.source
    }

    /// SHA-256 of the evidence meaning and exact dependencies, excluding
    /// revision lifecycle and generation provenance.
    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try SemanticHash.sha256(
            of: SemanticProjection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                location: location,
                excerpt: excerpt,
                confidence: confidence
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .evidenceRef {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "revision.object_type",
                    message: "EvidenceRef.v1 requires the evidence_ref object type."
                )
            )
        }
        if revision.schemaVersion != .v1 {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "revision.schema_version",
                    message: "EvidenceRef.v1 supports schema version 1.0 only."
                )
            )
        }
        issues.append(contentsOf: location.validationIssues())
        issues.append(contentsOf: excerpt.validationIssues())
        issues.append(contentsOf: confidence.validationIssues())

        if source.revisionID == revision.revisionID {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "location.source.revision_id",
                    message: "An evidence revision cannot cite itself as its source."
                )
            )
        }
        if !revision.inputRevisions.contains(source) {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "revision.input_revisions",
                    message: "The exact evidence source must appear in input revisions."
                )
            )
        }
        if let storedHash = revision.semanticContentHash {
            do {
                if storedHash != (try calculatedSemanticContentHash()) {
                    issues.append(
                        ValidationIssue(
                            code: .inconsistentValue,
                            path: "revision.semantic_content_hash",
                            message: "The stored semantic hash does not match EvidenceRef.v1 content."
                        )
                    )
                }
            } catch {
                issues.append(
                    ValidationIssue(
                        code: .invalidFormat,
                        path: "revision.semantic_content_hash",
                        message: "EvidenceRef.v1 semantic content could not be hashed canonically."
                    )
                )
            }
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<EvidenceIDTag>.self, forKey: .revision)
        location = try container.decode(EvidenceLocation.self, forKey: .location)
        excerpt = try EvidenceExcerpt(
            text: container.decode(String.self, forKey: .excerpt),
            language: container.decode(LanguageTag.self, forKey: .excerptLanguage),
            translationStatus: container.decode(TranslationStatus.self, forKey: .translationStatus)
        )
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encode(location, forKey: .location)
        try container.encode(excerpt.text, forKey: .excerpt)
        try container.encode(excerpt.language, forKey: .excerptLanguage)
        try container.encode(excerpt.translationStatus, forKey: .translationStatus)
        try container.encode(confidence, forKey: .confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case location
        case excerpt
        case excerptLanguage = "excerpt_language"
        case translationStatus = "translation_status"
        case confidence
    }

    private struct SemanticProjection: Encodable {
        let objectType: SemanticObjectType
        let schemaVersion: SchemaVersion
        let dataClassification: DataClassification
        let inputRevisions: [SemanticRevisionReference]
        let sourceAssetRevisions: [SemanticRevisionReference]
        let evidenceRevisions: [SemanticRevisionReference]
        let location: EvidenceLocation
        let excerpt: EvidenceExcerpt
        let confidence: ConfidenceScore

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case location
            case excerpt
            case confidence
        }
    }
}
