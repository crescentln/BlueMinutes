import Foundation

public struct InterventionCardV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<InterventionCardIDTag>
    public let meetingID: MeetingID
    public let speakerAssignmentRevision: SemanticRevisionReference
    public let participantRevision: SemanticRevisionReference
    public let timeRange: MediaTimeRange
    public let interventionType: InterventionType
    public let shortSummary: EvidenceLinkedClaim
    public let issueRevisions: [SemanticRevisionReference]
    public let positionRevisions: [SemanticRevisionReference]
    public let commitmentRevisions: [SemanticRevisionReference]
    public let decisionRevisions: [SemanticRevisionReference]
    public let notableWording: [EvidenceLinkedClaim]
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<InterventionCardIDTag>,
        meetingID: MeetingID,
        speakerAssignmentRevision: SemanticRevisionReference,
        participantRevision: SemanticRevisionReference,
        timeRange: MediaTimeRange,
        interventionType: InterventionType,
        shortSummary: EvidenceLinkedClaim,
        issueRevisions: [SemanticRevisionReference],
        positionRevisions: [SemanticRevisionReference] = [],
        commitmentRevisions: [SemanticRevisionReference] = [],
        decisionRevisions: [SemanticRevisionReference] = [],
        notableWording: [EvidenceLinkedClaim] = [],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.speakerAssignmentRevision = speakerAssignmentRevision
        self.participantRevision = participantRevision
        self.timeRange = timeRange
        self.interventionType = interventionType
        self.shortSummary = shortSummary
        self.issueRevisions = issueRevisions.sorted()
        self.positionRevisions = positionRevisions.sorted()
        self.commitmentRevisions = commitmentRevisions.sorted()
        self.decisionRevisions = decisionRevisions.sorted()
        self.notableWording = notableWording
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var interventionID: InterventionCardID { revision.logicalID }
    public var materialClaims: [EvidenceLinkedClaim] { [shortSummary] + notableWording }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .interventionCard,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "InterventionCard.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(speakerAssignmentRevision, expectedTypes: [.speakerAssignment], revisionInputs: revision.inputRevisions, path: "speaker_assignment_revision", noun: "SpeakerAssignment revision"))
        issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(participantRevision, expectedTypes: [.participant], revisionInputs: revision.inputRevisions, path: "participant_revision", noun: "Participant revision"))
        issues.append(contentsOf: timeRange.validationIssues())
        if !interventionType.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "intervention_type", "The intervention type is unsupported."))
        }
        let groups: [([SemanticRevisionReference], SemanticObjectType, String)] = [
            (issueRevisions, .issue, "issue_revisions"),
            (positionRevisions, .position, "position_revisions"),
            (commitmentRevisions, .commitment, "commitment_revisions"),
            (decisionRevisions, .decision, "decision_revisions")
        ]
        for (references, expectedType, path) in groups {
            issues.append(contentsOf: duplicateIssues(in: references, path: path))
            for reference in references {
                issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(reference, expectedTypes: [expectedType], revisionInputs: revision.inputRevisions, path: path, noun: expectedType.encodedValue + " revision"))
            }
        }
        if issueRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "issue_revisions", "A substantive intervention requires at least one evidence-linked issue."))
        }
        if positionRevisions.isEmpty && commitmentRevisions.isEmpty && decisionRevisions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "position_revisions", "A substantive intervention requires a typed position, commitment, or decision."))
        }
        for claim in materialClaims { issues.append(contentsOf: claim.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: notableWording, path: "notable_wording"))
        issues.append(contentsOf: IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: materialClaims,
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        ))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<InterventionCardIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        speakerAssignmentRevision = try container.decode(SemanticRevisionReference.self, forKey: .speakerAssignmentRevision)
        participantRevision = try container.decode(SemanticRevisionReference.self, forKey: .participantRevision)
        timeRange = try container.decode(MediaTimeRange.self, forKey: .timeRange)
        interventionType = try container.decode(InterventionType.self, forKey: .interventionType)
        shortSummary = try container.decode(EvidenceLinkedClaim.self, forKey: .shortSummary)
        issueRevisions = try container.decode([SemanticRevisionReference].self, forKey: .issueRevisions).sorted()
        positionRevisions = try container.decodeIfPresent([SemanticRevisionReference].self, forKey: .positionRevisions)?.sorted() ?? []
        commitmentRevisions = try container.decodeIfPresent([SemanticRevisionReference].self, forKey: .commitmentRevisions)?.sorted() ?? []
        decisionRevisions = try container.decodeIfPresent([SemanticRevisionReference].self, forKey: .decisionRevisions)?.sorted() ?? []
        notableWording = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .notableWording) ?? []
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let speakerAssignmentRevision: SemanticRevisionReference
        let participantRevision: SemanticRevisionReference
        let timeRange: MediaTimeRange
        let interventionType: InterventionType
        let shortSummary: EvidenceLinkedClaim
        let issueRevisions: [SemanticRevisionReference]
        let positionRevisions: [SemanticRevisionReference]
        let commitmentRevisions: [SemanticRevisionReference]
        let decisionRevisions: [SemanticRevisionReference]
        let notableWording: [EvidenceLinkedClaim]
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: InterventionCardV1) {
            meetingID = value.meetingID
            speakerAssignmentRevision = value.speakerAssignmentRevision
            participantRevision = value.participantRevision
            timeRange = value.timeRange
            interventionType = value.interventionType
            shortSummary = value.shortSummary
            issueRevisions = value.issueRevisions
            positionRevisions = value.positionRevisions
            commitmentRevisions = value.commitmentRevisions
            decisionRevisions = value.decisionRevisions
            notableWording = value.notableWording
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case speakerAssignmentRevision = "speaker_assignment_revision"
            case participantRevision = "participant_revision"
            case timeRange = "time_range"
            case interventionType = "intervention_type"
            case shortSummary = "short_summary"
            case issueRevisions = "issue_revisions"
            case positionRevisions = "position_revisions"
            case commitmentRevisions = "commitment_revisions"
            case decisionRevisions = "decision_revisions"
            case notableWording = "notable_wording"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case speakerAssignmentRevision = "speaker_assignment_revision"
        case participantRevision = "participant_revision"
        case timeRange = "time_range"
        case interventionType = "intervention_type"
        case shortSummary = "short_summary"
        case issueRevisions = "issue_revisions"
        case positionRevisions = "position_revisions"
        case commitmentRevisions = "commitment_revisions"
        case decisionRevisions = "decision_revisions"
        case notableWording = "notable_wording"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct DelegationPositionCardV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<DelegationPositionCardIDTag>
    public let meetingID: MeetingID
    public let representedEntityRevision: SemanticRevisionReference
    public let speakingCapacityRevisions: [SemanticRevisionReference]
    public let issueRevision: SemanticRevisionReference
    public let positionRevisions: [SemanticRevisionReference]
    public let commitmentRevisions: [SemanticRevisionReference]
    public let decisionRevisions: [SemanticRevisionReference]
    public let overallPosition: EvidenceLinkedClaim
    public let reservations: [EvidenceLinkedClaim]
    public let conditions: [EvidenceLinkedClaim]
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<DelegationPositionCardIDTag>,
        meetingID: MeetingID,
        representedEntityRevision: SemanticRevisionReference,
        speakingCapacityRevisions: [SemanticRevisionReference],
        issueRevision: SemanticRevisionReference,
        positionRevisions: [SemanticRevisionReference],
        commitmentRevisions: [SemanticRevisionReference] = [],
        decisionRevisions: [SemanticRevisionReference] = [],
        overallPosition: EvidenceLinkedClaim,
        reservations: [EvidenceLinkedClaim] = [],
        conditions: [EvidenceLinkedClaim] = [],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.representedEntityRevision = representedEntityRevision
        self.speakingCapacityRevisions = speakingCapacityRevisions.sorted()
        self.issueRevision = issueRevision
        self.positionRevisions = positionRevisions.sorted()
        self.commitmentRevisions = commitmentRevisions.sorted()
        self.decisionRevisions = decisionRevisions.sorted()
        self.overallPosition = overallPosition
        self.reservations = reservations
        self.conditions = conditions
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var cardID: DelegationPositionCardID { revision.logicalID }
    public var materialClaims: [EvidenceLinkedClaim] { [overallPosition] + reservations + conditions }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .delegationPositionCard,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "DelegationPositionCard.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(representedEntityRevision, expectedTypes: [.participant, .organization], revisionInputs: revision.inputRevisions, path: "represented_entity_revision", noun: "represented entity revision"))
        issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(issueRevision, expectedTypes: [.issue], revisionInputs: revision.inputRevisions, path: "issue_revision", noun: "Issue revision"))
        let groups: [([SemanticRevisionReference], SemanticObjectType, String, Bool)] = [
            (speakingCapacityRevisions, .speakingCapacity, "speaking_capacity_revisions", true),
            (positionRevisions, .position, "position_revisions", true),
            (commitmentRevisions, .commitment, "commitment_revisions", false),
            (decisionRevisions, .decision, "decision_revisions", false)
        ]
        for (references, expectedType, path, required) in groups {
            if required, references.isEmpty {
                issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, path, "A delegation-position card requires at least one \(expectedType.encodedValue) revision."))
            }
            issues.append(contentsOf: duplicateIssues(in: references, path: path))
            for reference in references {
                issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(reference, expectedTypes: [expectedType], revisionInputs: revision.inputRevisions, path: path, noun: expectedType.encodedValue + " revision"))
            }
        }
        for claim in materialClaims { issues.append(contentsOf: claim.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: reservations, path: "reservations"))
        issues.append(contentsOf: duplicateIssues(in: conditions, path: "conditions"))
        issues.append(contentsOf: IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: materialClaims,
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        ))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<DelegationPositionCardIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        representedEntityRevision = try container.decode(SemanticRevisionReference.self, forKey: .representedEntityRevision)
        speakingCapacityRevisions = try container.decode([SemanticRevisionReference].self, forKey: .speakingCapacityRevisions).sorted()
        issueRevision = try container.decode(SemanticRevisionReference.self, forKey: .issueRevision)
        positionRevisions = try container.decode([SemanticRevisionReference].self, forKey: .positionRevisions).sorted()
        commitmentRevisions = try container.decodeIfPresent([SemanticRevisionReference].self, forKey: .commitmentRevisions)?.sorted() ?? []
        decisionRevisions = try container.decodeIfPresent([SemanticRevisionReference].self, forKey: .decisionRevisions)?.sorted() ?? []
        overallPosition = try container.decode(EvidenceLinkedClaim.self, forKey: .overallPosition)
        reservations = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .reservations) ?? []
        conditions = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .conditions) ?? []
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let representedEntityRevision: SemanticRevisionReference
        let speakingCapacityRevisions: [SemanticRevisionReference]
        let issueRevision: SemanticRevisionReference
        let positionRevisions: [SemanticRevisionReference]
        let commitmentRevisions: [SemanticRevisionReference]
        let decisionRevisions: [SemanticRevisionReference]
        let overallPosition: EvidenceLinkedClaim
        let reservations: [EvidenceLinkedClaim]
        let conditions: [EvidenceLinkedClaim]
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: DelegationPositionCardV1) {
            meetingID = value.meetingID
            representedEntityRevision = value.representedEntityRevision
            speakingCapacityRevisions = value.speakingCapacityRevisions
            issueRevision = value.issueRevision
            positionRevisions = value.positionRevisions
            commitmentRevisions = value.commitmentRevisions
            decisionRevisions = value.decisionRevisions
            overallPosition = value.overallPosition
            reservations = value.reservations
            conditions = value.conditions
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case representedEntityRevision = "represented_entity_revision"
            case speakingCapacityRevisions = "speaking_capacity_revisions"
            case issueRevision = "issue_revision"
            case positionRevisions = "position_revisions"
            case commitmentRevisions = "commitment_revisions"
            case decisionRevisions = "decision_revisions"
            case overallPosition = "overall_position"
            case reservations
            case conditions
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case representedEntityRevision = "represented_entity_revision"
        case speakingCapacityRevisions = "speaking_capacity_revisions"
        case issueRevision = "issue_revision"
        case positionRevisions = "position_revisions"
        case commitmentRevisions = "commitment_revisions"
        case decisionRevisions = "decision_revisions"
        case overallPosition = "overall_position"
        case reservations
        case conditions
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
