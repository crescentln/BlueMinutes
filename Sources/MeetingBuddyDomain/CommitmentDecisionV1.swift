import Foundation

public struct CommitmentV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<CommitmentIDTag>
    public let meetingID: MeetingID
    public let actorRevision: SemanticRevisionReference
    public let representedEntityRevision: SemanticRevisionReference
    public let speakingCapacityRevision: SemanticRevisionReference
    public let recipientRevision: SemanticRevisionReference
    public let issueRevision: SemanticRevisionReference
    public let content: EvidenceLinkedClaim
    public let conditions: [EvidenceLinkedClaim]
    public let deadline: CommitmentDeadline
    public let status: CommitmentStatus
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<CommitmentIDTag>,
        meetingID: MeetingID,
        actorRevision: SemanticRevisionReference,
        representedEntityRevision: SemanticRevisionReference,
        speakingCapacityRevision: SemanticRevisionReference,
        recipientRevision: SemanticRevisionReference,
        issueRevision: SemanticRevisionReference,
        content: EvidenceLinkedClaim,
        conditions: [EvidenceLinkedClaim] = [],
        deadline: CommitmentDeadline,
        status: CommitmentStatus,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.actorRevision = actorRevision
        self.representedEntityRevision = representedEntityRevision
        self.speakingCapacityRevision = speakingCapacityRevision
        self.recipientRevision = recipientRevision
        self.issueRevision = issueRevision
        self.content = content
        self.conditions = conditions
        self.deadline = deadline
        self.status = status
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var commitmentID: CommitmentID { revision.logicalID }
    public var materialClaims: [EvidenceLinkedClaim] { [content] + conditions }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .commitment,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Commitment.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        let required: [(SemanticRevisionReference, Set<SemanticObjectType>, String, String)] = [
            (actorRevision, [.actor], "actor_revision", "Actor revision"),
            (representedEntityRevision, [.participant, .organization], "represented_entity_revision", "represented entity revision"),
            (speakingCapacityRevision, [.speakingCapacity], "speaking_capacity_revision", "SpeakingCapacity revision"),
            (recipientRevision, [.participant, .organization, .actor], "recipient_revision", "recipient entity revision"),
            (issueRevision, [.issue], "issue_revision", "Issue revision")
        ]
        for (reference, types, path, noun) in required {
            issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(reference, expectedTypes: types, revisionInputs: revision.inputRevisions, path: path, noun: noun))
        }
        for claim in materialClaims { issues.append(contentsOf: claim.validationIssues()) }
        issues.append(contentsOf: IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: materialClaims,
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        ))
        issues.append(contentsOf: duplicateIssues(in: conditions, path: "conditions"))
        issues.append(contentsOf: deadline.validationIssues())
        if !status.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "status", "The commitment status is unsupported."))
        }
        if status == .completed, !userConfirmed {
            issues.append(IntelligenceRevisionSupport.issue(.inconsistentValue, "status", "A completed commitment requires explicit human confirmation."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<CommitmentIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        actorRevision = try container.decode(SemanticRevisionReference.self, forKey: .actorRevision)
        representedEntityRevision = try container.decode(SemanticRevisionReference.self, forKey: .representedEntityRevision)
        speakingCapacityRevision = try container.decode(SemanticRevisionReference.self, forKey: .speakingCapacityRevision)
        recipientRevision = try container.decode(SemanticRevisionReference.self, forKey: .recipientRevision)
        issueRevision = try container.decode(SemanticRevisionReference.self, forKey: .issueRevision)
        content = try container.decode(EvidenceLinkedClaim.self, forKey: .content)
        conditions = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .conditions) ?? []
        deadline = try container.decode(CommitmentDeadline.self, forKey: .deadline)
        status = try container.decode(CommitmentStatus.self, forKey: .status)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let actorRevision: SemanticRevisionReference
        let representedEntityRevision: SemanticRevisionReference
        let speakingCapacityRevision: SemanticRevisionReference
        let recipientRevision: SemanticRevisionReference
        let issueRevision: SemanticRevisionReference
        let content: EvidenceLinkedClaim
        let conditions: [EvidenceLinkedClaim]
        let deadline: CommitmentDeadline
        let status: CommitmentStatus
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: CommitmentV1) {
            meetingID = value.meetingID
            actorRevision = value.actorRevision
            representedEntityRevision = value.representedEntityRevision
            speakingCapacityRevision = value.speakingCapacityRevision
            recipientRevision = value.recipientRevision
            issueRevision = value.issueRevision
            content = value.content
            conditions = value.conditions
            deadline = value.deadline
            status = value.status
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case actorRevision = "actor_revision"
            case representedEntityRevision = "represented_entity_revision"
            case speakingCapacityRevision = "speaking_capacity_revision"
            case recipientRevision = "recipient_revision"
            case issueRevision = "issue_revision"
            case content
            case conditions
            case deadline
            case status
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case actorRevision = "actor_revision"
        case representedEntityRevision = "represented_entity_revision"
        case speakingCapacityRevision = "speaking_capacity_revision"
        case recipientRevision = "recipient_revision"
        case issueRevision = "issue_revision"
        case content
        case conditions
        case deadline
        case status
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct DecisionV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<DecisionIDTag>
    public let meetingID: MeetingID
    public let issueRevision: SemanticRevisionReference
    public let decisionType: DecisionType
    public let statement: EvidenceLinkedClaim
    public let responsibleEntityRevisions: [SemanticRevisionReference]
    public let effectiveTimeRange: MediaTimeRange?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<DecisionIDTag>,
        meetingID: MeetingID,
        issueRevision: SemanticRevisionReference,
        decisionType: DecisionType,
        statement: EvidenceLinkedClaim,
        responsibleEntityRevisions: [SemanticRevisionReference],
        effectiveTimeRange: MediaTimeRange? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.issueRevision = issueRevision
        self.decisionType = decisionType
        self.statement = statement
        self.responsibleEntityRevisions = responsibleEntityRevisions.sorted()
        self.effectiveTimeRange = effectiveTimeRange
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var decisionID: DecisionID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .decision,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Decision.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(issueRevision, expectedTypes: [.issue], revisionInputs: revision.inputRevisions, path: "issue_revision", noun: "Issue revision"))
        if !decisionType.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "decision_type", "The decision type is unsupported."))
        }
        issues.append(contentsOf: statement.validationIssues())
        issues.append(contentsOf: IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: [statement],
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        ))
        if responsibleEntityRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "responsible_entity_revisions", "A decision requires at least one responsible or deciding entity."))
        }
        issues.append(contentsOf: duplicateIssues(in: responsibleEntityRevisions, path: "responsible_entity_revisions"))
        for reference in responsibleEntityRevisions {
            issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(reference, expectedTypes: [.actor, .participant, .organization], revisionInputs: revision.inputRevisions, path: "responsible_entity_revisions", noun: "responsible entity revision"))
        }
        if let effectiveTimeRange { issues.append(contentsOf: effectiveTimeRange.validationIssues()) }
        if decisionType != .uncertain, !userConfirmed {
            issues.append(IntelligenceRevisionSupport.issue(.inconsistentValue, "decision_type", "A non-uncertain decision requires explicit human confirmation."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<DecisionIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        issueRevision = try container.decode(SemanticRevisionReference.self, forKey: .issueRevision)
        decisionType = try container.decode(DecisionType.self, forKey: .decisionType)
        statement = try container.decode(EvidenceLinkedClaim.self, forKey: .statement)
        responsibleEntityRevisions = try container.decode([SemanticRevisionReference].self, forKey: .responsibleEntityRevisions).sorted()
        effectiveTimeRange = try container.decodeIfPresent(MediaTimeRange.self, forKey: .effectiveTimeRange)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let issueRevision: SemanticRevisionReference
        let decisionType: DecisionType
        let statement: EvidenceLinkedClaim
        let responsibleEntityRevisions: [SemanticRevisionReference]
        let effectiveTimeRange: MediaTimeRange?
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: DecisionV1) {
            meetingID = value.meetingID
            issueRevision = value.issueRevision
            decisionType = value.decisionType
            statement = value.statement
            responsibleEntityRevisions = value.responsibleEntityRevisions
            effectiveTimeRange = value.effectiveTimeRange
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case issueRevision = "issue_revision"
            case decisionType = "decision_type"
            case statement
            case responsibleEntityRevisions = "responsible_entity_revisions"
            case effectiveTimeRange = "effective_time_range"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case issueRevision = "issue_revision"
        case decisionType = "decision_type"
        case statement
        case responsibleEntityRevisions = "responsible_entity_revisions"
        case effectiveTimeRange = "effective_time_range"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
