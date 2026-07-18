import Foundation

public struct ParticipantV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<ParticipantIDTag>
    public let meetingID: MeetingID
    public let actorRevision: SemanticRevisionReference
    public let speakingCapacityRevisions: [SemanticRevisionReference]
    public let organizationRevisions: [SemanticRevisionReference]
    public let kind: ParticipantKind
    public let displayName: String
    public let confidence: ConfidenceScore
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<ParticipantIDTag>,
        meetingID: MeetingID,
        actorRevision: SemanticRevisionReference,
        speakingCapacityRevisions: [SemanticRevisionReference],
        organizationRevisions: [SemanticRevisionReference] = [],
        kind: ParticipantKind,
        displayName: String,
        confidence: ConfidenceScore,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.actorRevision = actorRevision
        self.speakingCapacityRevisions = speakingCapacityRevisions.sorted()
        self.organizationRevisions = organizationRevisions.sorted()
        self.kind = kind
        self.displayName = displayName
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var participantID: ParticipantID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .participant,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Participant.v1"
        )
        issues.append(
            contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                actorRevision,
                expectedTypes: [.actor],
                revisionInputs: revision.inputRevisions,
                path: "actor_revision",
                noun: "Actor revision"
            )
        )
        if speakingCapacityRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "speaking_capacity_revisions", "A participant requires at least one meeting capacity."))
        }
        issues.append(contentsOf: duplicateIssues(in: speakingCapacityRevisions, path: "speaking_capacity_revisions"))
        for reference in speakingCapacityRevisions {
            issues.append(
                contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                    reference,
                    expectedTypes: [.speakingCapacity],
                    revisionInputs: revision.inputRevisions,
                    path: "speaking_capacity_revisions",
                    noun: "SpeakingCapacity revision"
                )
            )
        }
        issues.append(contentsOf: duplicateIssues(in: organizationRevisions, path: "organization_revisions"))
        for reference in organizationRevisions {
            issues.append(
                contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                    reference,
                    expectedTypes: [.organization],
                    revisionInputs: revision.inputRevisions,
                    path: "organization_revisions",
                    noun: "Organization revision"
                )
            )
        }
        if !kind.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "kind", "The participant kind is unsupported."))
        }
        issues.append(contentsOf: boundedLabelIssues(displayName, path: "display_name"))
        issues.append(contentsOf: confidence.validationIssues())
        if revision.lifecycleStatus == .published, revision.evidenceRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "revision.evidence_revisions", "A published participant requires exact identity evidence."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<ParticipantIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        actorRevision = try container.decode(SemanticRevisionReference.self, forKey: .actorRevision)
        speakingCapacityRevisions = try container.decode(
            [SemanticRevisionReference].self,
            forKey: .speakingCapacityRevisions
        ).sorted()
        organizationRevisions = try container.decodeIfPresent(
            [SemanticRevisionReference].self,
            forKey: .organizationRevisions
        )?.sorted() ?? []
        kind = try container.decode(ParticipantKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let actorRevision: SemanticRevisionReference
        let speakingCapacityRevisions: [SemanticRevisionReference]
        let organizationRevisions: [SemanticRevisionReference]
        let kind: ParticipantKind
        let displayName: String
        let confidence: ConfidenceScore
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: ParticipantV1) {
            meetingID = value.meetingID
            actorRevision = value.actorRevision
            speakingCapacityRevisions = value.speakingCapacityRevisions
            organizationRevisions = value.organizationRevisions
            kind = value.kind
            displayName = value.displayName
            confidence = value.confidence
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case actorRevision = "actor_revision"
            case speakingCapacityRevisions = "speaking_capacity_revisions"
            case organizationRevisions = "organization_revisions"
            case kind
            case displayName = "display_name"
            case confidence
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case actorRevision = "actor_revision"
        case speakingCapacityRevisions = "speaking_capacity_revisions"
        case organizationRevisions = "organization_revisions"
        case kind
        case displayName = "display_name"
        case confidence
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct OrganizationV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<OrganizationIDTag>
    public let actorRevision: SemanticRevisionReference
    public let kind: OrganizationKind
    public let displayName: String
    public let countryCode: CountryCode?
    public let confidence: ConfidenceScore
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<OrganizationIDTag>,
        actorRevision: SemanticRevisionReference,
        kind: OrganizationKind,
        displayName: String,
        countryCode: CountryCode? = nil,
        confidence: ConfidenceScore,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.actorRevision = actorRevision
        self.kind = kind
        self.displayName = displayName
        self.countryCode = countryCode
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var organizationID: OrganizationID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .organization,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Organization.v1"
        )
        issues.append(
            contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                actorRevision,
                expectedTypes: [.actor],
                revisionInputs: revision.inputRevisions,
                path: "actor_revision",
                noun: "Actor revision"
            )
        )
        if !kind.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "kind", "The organization kind is unsupported."))
        }
        issues.append(contentsOf: boundedLabelIssues(displayName, path: "display_name"))
        issues.append(contentsOf: confidence.validationIssues())
        if let countryCode {
            issues.append(contentsOf: countryCode.validationIssues())
            if kind != .country {
                issues.append(IntelligenceRevisionSupport.issue(.inconsistentValue, "country_code", "Only a country organization may carry a country code."))
            }
        } else if kind == .country {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "country_code", "A country organization requires its country code."))
        }
        if revision.lifecycleStatus == .published, revision.evidenceRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "revision.evidence_revisions", "A published organization requires exact identity evidence."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<OrganizationIDTag>.self, forKey: .revision)
        actorRevision = try container.decode(SemanticRevisionReference.self, forKey: .actorRevision)
        kind = try container.decode(OrganizationKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        countryCode = try container.decodeIfPresent(CountryCode.self, forKey: .countryCode)
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let actorRevision: SemanticRevisionReference
        let kind: OrganizationKind
        let displayName: String
        let countryCode: CountryCode?
        let confidence: ConfidenceScore
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: OrganizationV1) {
            actorRevision = value.actorRevision
            kind = value.kind
            displayName = value.displayName
            countryCode = value.countryCode
            confidence = value.confidence
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case actorRevision = "actor_revision"
            case kind
            case displayName = "display_name"
            case countryCode = "country_code"
            case confidence
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case actorRevision = "actor_revision"
        case kind
        case displayName = "display_name"
        case countryCode = "country_code"
        case confidence
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
