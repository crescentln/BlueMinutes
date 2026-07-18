import Foundation

/// SpeakerAssignment.v1 preserves uncertainty and exact assignment evidence.
public struct SpeakerAssignmentV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<SpeakerAssignmentIDTag>
    public let meetingID: MeetingID
    public let transcriptSegmentRevisions: [SemanticRevisionReference]
    public let actorRevision: SemanticRevisionReference
    public let speakingCapacityRevision: SemanticRevisionReference
    public let confidence: ConfidenceScore
    public let certainty: AssignmentCertainty
    public let assignmentSources: [SpeakerAssignmentSource]
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<SpeakerAssignmentIDTag>,
        meetingID: MeetingID,
        transcriptSegmentRevisions: [SemanticRevisionReference],
        actorRevision: SemanticRevisionReference,
        speakingCapacityRevision: SemanticRevisionReference,
        confidence: ConfidenceScore,
        certainty: AssignmentCertainty,
        assignmentSources: [SpeakerAssignmentSource],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.transcriptSegmentRevisions = transcriptSegmentRevisions.sorted()
        self.actorRevision = actorRevision
        self.speakingCapacityRevision = speakingCapacityRevision
        self.confidence = confidence
        self.certainty = certainty
        self.assignmentSources = assignmentSources.sorted()
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var assignmentID: SpeakerAssignmentID { revision.logicalID }
    public var evidenceRevisions: [SemanticRevisionReference] {
        revision.evidenceRevisions
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
                transcriptSegmentRevisions: transcriptSegmentRevisions,
                actorRevision: actorRevision,
                speakingCapacityRevision: speakingCapacityRevision,
                confidence: confidence,
                certainty: certainty,
                assignmentSources: assignmentSources,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .speakerAssignment {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "SpeakerAssignment.v1 requires the speaker_assignment object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "SpeakerAssignment.v1 supports schema version 1.0 only."))
        }
        if transcriptSegmentRevisions.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "transcript_segment_revisions", "A speaker assignment requires at least one transcript segment."))
        }
        for reference in transcriptSegmentRevisions {
            issues.append(contentsOf: reference.validationIssues())
            if reference.objectType != .transcriptSegment {
                issues.append(Self.issue(.inconsistentValue, "transcript_segment_revisions.object_type", "Speaker assignments may cover only TranscriptSegment revisions."))
            }
            if !revision.inputRevisions.contains(reference) {
                issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "Every assigned transcript segment must appear in input revisions."))
            }
        }
        issues.append(contentsOf: duplicateIssues(in: transcriptSegmentRevisions, path: "transcript_segment_revisions"))
        issues.append(contentsOf: actorRevision.validationIssues())
        if actorRevision.objectType != .actor {
            issues.append(Self.issue(.inconsistentValue, "actor_revision.object_type", "The assigned speaker must reference an Actor revision."))
        }
        if !revision.inputRevisions.contains(actorRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact assigned Actor must appear in input revisions."))
        }
        issues.append(contentsOf: speakingCapacityRevision.validationIssues())
        if speakingCapacityRevision.objectType != .speakingCapacity {
            issues.append(Self.issue(.inconsistentValue, "speaking_capacity_revision.object_type", "The assignment must reference a SpeakingCapacity revision."))
        }
        if !revision.inputRevisions.contains(speakingCapacityRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact speaking capacity must appear in input revisions."))
        }
        if revision.evidenceRevisions.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "revision.evidence_revisions", "A speaker assignment requires exact evidence revisions."))
        }
        issues.append(contentsOf: confidence.validationIssues())
        if !certainty.isKnown {
            issues.append(Self.issue(.unsupportedValue, "certainty", "The assignment certainty is not supported by SpeakerAssignment.v1."))
        }
        if assignmentSources.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "assignment_sources", "A speaker assignment requires at least one typed source."))
        }
        for source in assignmentSources where !source.isKnown {
            issues.append(Self.issue(.unsupportedValue, "assignment_sources", "An assignment source is not supported by SpeakerAssignment.v1."))
        }
        issues.append(contentsOf: duplicateIssues(in: assignmentSources, path: "assignment_sources"))
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        switch certainty {
        case .uncertain:
            if reviewStatus != .needsReview || userConfirmed {
                issues.append(Self.issue(.inconsistentValue, "certainty", "An uncertain assignment must remain unconfirmed in needs-review state."))
            }
        case .confirmed:
            if reviewStatus != .confirmed || !userConfirmed {
                issues.append(Self.issue(.inconsistentValue, "certainty", "A confirmed assignment requires explicit user confirmation."))
            }
        case .probable:
            if userConfirmed {
                issues.append(Self.issue(.inconsistentValue, "certainty", "A probable assignment cannot be user-confirmed without becoming confirmed."))
            }
        case .unrecognized:
            break
        }
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed assignment revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "SpeakerAssignment.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<SpeakerAssignmentIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        transcriptSegmentRevisions = try container.decode(
            [SemanticRevisionReference].self,
            forKey: .transcriptSegmentRevisions
        ).sorted()
        actorRevision = try container.decode(SemanticRevisionReference.self, forKey: .actorRevision)
        speakingCapacityRevision = try container.decode(SemanticRevisionReference.self, forKey: .speakingCapacityRevision)
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        certainty = try container.decode(AssignmentCertainty.self, forKey: .certainty)
        assignmentSources = try container.decode([SpeakerAssignmentSource].self, forKey: .assignmentSources).sorted()
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
        let transcriptSegmentRevisions: [SemanticRevisionReference]
        let actorRevision: SemanticRevisionReference
        let speakingCapacityRevision: SemanticRevisionReference
        let confidence: ConfidenceScore
        let certainty: AssignmentCertainty
        let assignmentSources: [SpeakerAssignmentSource]
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
            case transcriptSegmentRevisions = "transcript_segment_revisions"
            case actorRevision = "actor_revision"
            case speakingCapacityRevision = "speaking_capacity_revision"
            case confidence
            case certainty
            case assignmentSources = "assignment_sources"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case transcriptSegmentRevisions = "transcript_segment_revisions"
        case actorRevision = "actor_revision"
        case speakingCapacityRevision = "speaking_capacity_revision"
        case confidence
        case certainty
        case assignmentSources = "assignment_sources"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
