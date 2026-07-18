import Foundation

public struct RepresentationRelationship: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let kind: RepresentationKind
    public let entityRevision: SemanticRevisionReference

    public init(kind: RepresentationKind, entityRevision: SemanticRevisionReference) throws {
        self.kind = kind
        self.entityRevision = entityRevision
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.kind.encodedValue != rhs.kind.encodedValue {
            return lhs.kind.encodedValue < rhs.kind.encodedValue
        }
        return lhs.entityRevision < rhs.entityRevision
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = entityRevision.validationIssues()
        if !kind.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "representation_relationship.kind",
                    message: "The representation relationship is not supported by this contract version."
                )
            )
        }
        if entityRevision.objectType != .actor {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "representation_relationship.entity_revision.object_type",
                    message: "A represented entity must reference an Actor revision."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(RepresentationKind.self, forKey: .kind)
        entityRevision = try container.decode(SemanticRevisionReference.self, forKey: .entityRevision)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case entityRevision = "entity_revision"
    }
}

/// SpeakingCapacity.v1 records who speaks and whom they represent in one meeting context.
public struct SpeakingCapacityV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<SpeakingCapacityIDTag>
    public let meetingID: MeetingID
    public let speakerActorRevision: SemanticRevisionReference
    public let representationRelationships: [RepresentationRelationship]
    public let meetingRole: MeetingRole
    public let capacityLabel: String?
    public let effectiveTimeRange: MediaTimeRange?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<SpeakingCapacityIDTag>,
        meetingID: MeetingID,
        speakerActorRevision: SemanticRevisionReference,
        representationRelationships: [RepresentationRelationship] = [],
        meetingRole: MeetingRole,
        capacityLabel: String? = nil,
        effectiveTimeRange: MediaTimeRange? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.speakerActorRevision = speakerActorRevision
        self.representationRelationships = representationRelationships.sorted()
        self.meetingRole = meetingRole
        self.capacityLabel = capacityLabel
        self.effectiveTimeRange = effectiveTimeRange
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var capacityID: SpeakingCapacityID { revision.logicalID }
    public var representedEntityRevisions: [SemanticRevisionReference] {
        representationRelationships.compactMap {
            $0.kind == .represents ? $0.entityRevision : nil
        }
    }
    public var onBehalfOfEntityRevisions: [SemanticRevisionReference] {
        representationRelationships.compactMap {
            $0.kind == .speaksOnBehalfOf ? $0.entityRevision : nil
        }
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
                speakerActorRevision: speakerActorRevision,
                representationRelationships: representationRelationships,
                meetingRole: meetingRole,
                capacityLabel: capacityLabel,
                effectiveTimeRange: effectiveTimeRange,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .speakingCapacity {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "SpeakingCapacity.v1 requires the speaking_capacity object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "SpeakingCapacity.v1 supports schema version 1.0 only."))
        }
        issues.append(contentsOf: speakerActorRevision.validationIssues())
        if speakerActorRevision.objectType != .actor {
            issues.append(Self.issue(.inconsistentValue, "speaker_actor_revision.object_type", "The speaker must reference an Actor revision."))
        }
        if !revision.inputRevisions.contains(speakerActorRevision) {
            issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact speaker Actor must appear in input revisions."))
        }
        for relationship in representationRelationships {
            issues.append(contentsOf: relationship.validationIssues())
            if !revision.inputRevisions.contains(relationship.entityRevision) {
                issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "Every represented entity must appear in input revisions."))
            }
        }
        issues.append(contentsOf: duplicateIssues(in: representationRelationships, path: "representation_relationships"))
        if !meetingRole.isKnown {
            issues.append(Self.issue(.unsupportedValue, "meeting_role", "The meeting role is not supported by SpeakingCapacity.v1."))
        }
        if (meetingRole == .delegate || meetingRole == .groupRepresentative),
           representationRelationships.isEmpty
        {
            issues.append(Self.issue(.missingRequiredValue, "representation_relationships", "Delegates and group representatives require an explicit represented entity."))
        }
        if let capacityLabel {
            issues.append(contentsOf: boundedLabelIssues(capacityLabel, path: "capacity_label", maximumUTF8Bytes: 512))
        } else if meetingRole == .other {
            issues.append(Self.issue(.missingRequiredValue, "capacity_label", "An other meeting role requires an explicit capacity label."))
        }
        if let effectiveTimeRange { issues.append(contentsOf: effectiveTimeRange.validationIssues()) }
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed capacity revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "SpeakingCapacity.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<SpeakingCapacityIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        speakerActorRevision = try container.decode(SemanticRevisionReference.self, forKey: .speakerActorRevision)
        representationRelationships = try container.decodeIfPresent(
            [RepresentationRelationship].self,
            forKey: .representationRelationships
        )?.sorted() ?? []
        meetingRole = try container.decode(MeetingRole.self, forKey: .meetingRole)
        capacityLabel = try container.decodeIfPresent(String.self, forKey: .capacityLabel)
        effectiveTimeRange = try container.decodeIfPresent(MediaTimeRange.self, forKey: .effectiveTimeRange)
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
        let speakerActorRevision: SemanticRevisionReference
        let representationRelationships: [RepresentationRelationship]
        let meetingRole: MeetingRole
        let capacityLabel: String?
        let effectiveTimeRange: MediaTimeRange?
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
            case speakerActorRevision = "speaker_actor_revision"
            case representationRelationships = "representation_relationships"
            case meetingRole = "meeting_role"
            case capacityLabel = "capacity_label"
            case effectiveTimeRange = "effective_time_range"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case speakerActorRevision = "speaker_actor_revision"
        case representationRelationships = "representation_relationships"
        case meetingRole = "meeting_role"
        case capacityLabel = "capacity_label"
        case effectiveTimeRange = "effective_time_range"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
