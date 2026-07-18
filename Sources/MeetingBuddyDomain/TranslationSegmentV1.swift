import Foundation

/// TranslationSegment.v1 preserves translated text beside, never over, source text.
public struct TranslationSegmentV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<TranslationSegmentIDTag>
    public let meetingID: MeetingID
    public let sourceSegmentRevision: SemanticRevisionReference
    public let sourceLanguage: LanguageTag
    public let targetLanguage: LanguageTag
    public let sourceTextHash: ContentDigest
    public let translatedText: String
    public let translationType: TranslationType
    public let alignmentStatus: AlignmentStatus
    public let confidence: ConfidenceScore
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<TranslationSegmentIDTag>,
        meetingID: MeetingID,
        sourceSegmentRevision: SemanticRevisionReference,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag,
        sourceTextHash: ContentDigest,
        translatedText: String,
        translationType: TranslationType,
        alignmentStatus: AlignmentStatus,
        confidence: ConfidenceScore,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.sourceSegmentRevision = sourceSegmentRevision
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceTextHash = sourceTextHash
        self.translatedText = translatedText
        self.translationType = translationType
        self.alignmentStatus = alignmentStatus
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var translationID: TranslationSegmentID { revision.logicalID }
    public var provider: ProviderMetadata? { revision.generationMetadata?.provider }
    public var translationStatus: TranslationStatus {
        translationType.evidenceTranslationStatus
    }
    public var isOriginalVerbatim: Bool { false }

    public static func calculateSourceTextHash(_ sourceText: String) throws -> ContentDigest {
        try ContentDigest.sha256(ofUTF8Text: sourceText)
    }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try SemanticHash.sha256(
            of: SemanticProjection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                meetingID: meetingID,
                sourceSegmentRevision: sourceSegmentRevision,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                sourceTextHash: sourceTextHash,
                translatedText: translatedText,
                translationType: translationType,
                alignmentStatus: alignmentStatus,
                confidence: confidence,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .translationSegment {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "TranslationSegment.v1 requires the translation_segment object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "TranslationSegment.v1 supports schema version 1.0 only."))
        }
        issues.append(contentsOf: sourceSegmentRevision.validationIssues())
        if sourceSegmentRevision.objectType != .transcriptSegment {
            issues.append(Self.issue(.inconsistentValue, "source_segment_revision.object_type", "A translation must reference a TranscriptSegment revision."))
        }
        if !revision.inputRevisions.contains(sourceSegmentRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact source transcript must appear in input revisions."))
        }
        issues.append(contentsOf: sourceLanguage.validationIssues())
        issues.append(contentsOf: targetLanguage.validationIssues())
        if sourceLanguage == targetLanguage {
            issues.append(Self.issue(.inconsistentValue, "target_language", "Source and target languages must differ."))
        }
        issues.append(contentsOf: sourceTextHash.validationIssues())
        issues.append(contentsOf: preservedSourceTextIssues(translatedText, path: "translated_text"))
        if !translationType.isKnown {
            issues.append(Self.issue(.unsupportedValue, "translation_type", "The translation type is not supported by TranslationSegment.v1."))
        }
        if !alignmentStatus.isKnown {
            issues.append(Self.issue(.unsupportedValue, "alignment_status", "The alignment status is not supported by TranslationSegment.v1."))
        }
        issues.append(contentsOf: confidence.validationIssues())
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if translationType == .machineTranslation, revision.generationMetadata == nil {
            issues.append(Self.issue(.missingRequiredValue, "revision.generation_metadata", "Machine translation requires provider-neutral generation metadata."))
        }
        if translationType == .userEditedTranslation {
            if revision.supersedesRevisionID == nil {
                issues.append(Self.issue(.missingRequiredValue, "revision.supersedes_revision_id", "A user-edited translation must supersede an earlier revision."))
            } else {
                let priorRevisionInputs = revision.inputRevisions.filter {
                    $0.objectType == .translationSegment
                        && $0.revisionID == revision.supersedesRevisionID
                }
                if priorRevisionInputs.isEmpty {
                    issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "A user-edited translation must retain the exact prior translation as an input."))
                } else if !priorRevisionInputs.contains(where: {
                    $0.logicalID.canonicalString == revision.logicalID.canonicalString
                }) {
                    issues.append(Self.issue(.inconsistentValue, "revision.input_revisions", "The superseded translation input must share the edited translation's logical identity."))
                }
            }
        }
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed translation revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "TranslationSegment.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<TranslationSegmentIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        sourceSegmentRevision = try container.decode(SemanticRevisionReference.self, forKey: .sourceSegmentRevision)
        sourceLanguage = try container.decode(LanguageTag.self, forKey: .sourceLanguage)
        targetLanguage = try container.decode(LanguageTag.self, forKey: .targetLanguage)
        sourceTextHash = try container.decode(ContentDigest.self, forKey: .sourceTextHash)
        translatedText = try container.decode(String.self, forKey: .translatedText)
        translationType = try container.decode(TranslationType.self, forKey: .translationType)
        alignmentStatus = try container.decode(AlignmentStatus.self, forKey: .alignmentStatus)
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct SemanticProjection: Encodable {
        let objectType: SemanticObjectType
        let schemaVersion: SchemaVersion
        let dataClassification: DataClassification
        let inputRevisions: [SemanticRevisionReference]
        let sourceAssetRevisions: [SemanticRevisionReference]
        let evidenceRevisions: [SemanticRevisionReference]
        let meetingID: MeetingID
        let sourceSegmentRevision: SemanticRevisionReference
        let sourceLanguage: LanguageTag
        let targetLanguage: LanguageTag
        let sourceTextHash: ContentDigest
        let translatedText: String
        let translationType: TranslationType
        let alignmentStatus: AlignmentStatus
        let confidence: ConfidenceScore
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case meetingID = "meeting_id"
            case sourceSegmentRevision = "source_segment_revision"
            case sourceLanguage = "source_language"
            case targetLanguage = "target_language"
            case sourceTextHash = "source_text_hash"
            case translatedText = "translated_text"
            case translationType = "translation_type"
            case alignmentStatus = "alignment_status"
            case confidence
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case sourceSegmentRevision = "source_segment_revision"
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case sourceTextHash = "source_text_hash"
        case translatedText = "translated_text"
        case translationType = "translation_type"
        case alignmentStatus = "alignment_status"
        case confidence
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
