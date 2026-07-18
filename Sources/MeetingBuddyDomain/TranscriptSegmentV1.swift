import Foundation

/// Binds a transcript to one exact audio-track revision and one provenance path.
public enum TranscriptSourceProvenance: Codable, Hashable, Sendable, DomainValidatable {
    case originalSpeakerAudio(sourceAssetRevision: SemanticRevisionReference)
    case simultaneousInterpretation(sourceAssetRevision: SemanticRevisionReference)
    case translatedAudioTrack(sourceAssetRevision: SemanticRevisionReference)
    case unknown(sourceAssetRevision: SemanticRevisionReference)

    public var sourceAssetRevision: SemanticRevisionReference {
        switch self {
        case let .originalSpeakerAudio(reference),
             let .simultaneousInterpretation(reference),
             let .translatedAudioTrack(reference),
             let .unknown(reference):
            reference
        }
    }

    public var speechSourceKind: SpeechSourceKind {
        switch self {
        case .originalSpeakerAudio: .originalSpeakerAudio
        case .simultaneousInterpretation: .simultaneousInterpretation
        case .translatedAudioTrack: .translatedAudioTrack
        case .unknown: .unknown
        }
    }

    public var isOriginalVerbatim: Bool {
        speechSourceKind == .originalSpeakerAudio
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = sourceAssetRevision.validationIssues()
        if sourceAssetRevision.objectType != .sourceAsset {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "source_provenance.source_asset_revision.object_type",
                    message: "Transcript provenance must reference a SourceAsset revision."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SpeechSourceKind.self, forKey: .kind)
        let reference = try container.decode(
            SemanticRevisionReference.self,
            forKey: .sourceAssetRevision
        )
        switch kind {
        case .originalSpeakerAudio:
            self = .originalSpeakerAudio(sourceAssetRevision: reference)
        case .simultaneousInterpretation:
            self = .simultaneousInterpretation(sourceAssetRevision: reference)
        case .translatedAudioTrack:
            self = .translatedAudioTrack(sourceAssetRevision: reference)
        case .unknown:
            self = .unknown(sourceAssetRevision: reference)
        case .unrecognized:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "TranscriptSourceProvenance.v1 does not support this speech-source kind."
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speechSourceKind, forKey: .kind)
        try container.encode(sourceAssetRevision, forKey: .sourceAssetRevision)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case sourceAssetRevision = "source_asset_revision"
    }
}

/// TranscriptSegment.v1 contains timestamped source-track text only.
public struct TranscriptSegmentV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<TranscriptSegmentIDTag>
    public let meetingID: MeetingID
    public let sourceProvenance: TranscriptSourceProvenance
    public let timeRange: MediaTimeRange
    public let detectedLanguage: LanguageTag
    public let text: String
    public let confidence: ConfidenceScore
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<TranscriptSegmentIDTag>,
        meetingID: MeetingID,
        sourceProvenance: TranscriptSourceProvenance,
        timeRange: MediaTimeRange,
        detectedLanguage: LanguageTag,
        text: String,
        confidence: ConfidenceScore,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.sourceProvenance = sourceProvenance
        self.timeRange = timeRange
        self.detectedLanguage = detectedLanguage
        self.text = text
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var segmentID: TranscriptSegmentID { revision.logicalID }
    public var sourceAssetRevision: SemanticRevisionReference {
        sourceProvenance.sourceAssetRevision
    }
    public var speechSourceKind: SpeechSourceKind { sourceProvenance.speechSourceKind }
    public var isOriginalVerbatim: Bool { sourceProvenance.isOriginalVerbatim }
    public var transcriptionProvider: ProviderMetadata? {
        revision.generationMetadata?.provider
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
                sourceProvenance: sourceProvenance,
                timeRange: timeRange,
                detectedLanguage: detectedLanguage,
                text: text,
                confidence: confidence,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .transcriptSegment {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "TranscriptSegment.v1 requires the transcript_segment object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "TranscriptSegment.v1 supports schema version 1.0 only."))
        }
        issues.append(contentsOf: sourceProvenance.validationIssues())
        if !revision.inputRevisions.contains(sourceAssetRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact source asset must appear in input revisions."))
        }
        if !revision.sourceAssetRevisions.contains(sourceAssetRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.source_asset_revisions", "The exact source asset must appear in source-asset revisions."))
        }
        issues.append(contentsOf: timeRange.validationIssues())
        issues.append(contentsOf: detectedLanguage.validationIssues())
        issues.append(contentsOf: preservedSourceTextIssues(text, path: "text"))
        issues.append(contentsOf: confidence.validationIssues())
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed transcript revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "TranscriptSegment.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<TranscriptSegmentIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        sourceProvenance = try container.decode(TranscriptSourceProvenance.self, forKey: .sourceProvenance)
        timeRange = try container.decode(MediaTimeRange.self, forKey: .timeRange)
        detectedLanguage = try container.decode(LanguageTag.self, forKey: .detectedLanguage)
        text = try container.decode(String.self, forKey: .text)
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
        let sourceProvenance: TranscriptSourceProvenance
        let timeRange: MediaTimeRange
        let detectedLanguage: LanguageTag
        let text: String
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
            case sourceProvenance = "source_provenance"
            case timeRange = "time_range"
            case detectedLanguage = "detected_language"
            case text
            case confidence
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case sourceProvenance = "source_provenance"
        case timeRange = "time_range"
        case detectedLanguage = "detected_language"
        case text
        case confidence
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
