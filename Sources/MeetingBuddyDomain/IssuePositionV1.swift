import Foundation

public struct IssueV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<IssueIDTag>
    public let meetingID: MeetingID
    public let title: EvidenceLinkedClaim
    public let summary: EvidenceLinkedClaim?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<IssueIDTag>,
        meetingID: MeetingID,
        title: EvidenceLinkedClaim,
        summary: EvidenceLinkedClaim? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.title = title
        self.summary = summary
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var issueID: IssueID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .issue,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Issue.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        let claims = [title] + [summary].compactMap { $0 }
        for claim in claims { issues.append(contentsOf: claim.validationIssues()) }
        issues.append(
            contentsOf: IntelligenceRevisionSupport.evidenceClosureIssues(
                claims: claims,
                revisionEvidence: revision.evidenceRevisions,
                lifecycle: revision.lifecycleStatus,
                createdBy: revision.createdBy,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
        if title.text.utf8.count > 512 {
            issues.append(IntelligenceRevisionSupport.issue(.invalidRange, "title.text", "An issue title must not exceed 512 UTF-8 bytes."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<IssueIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        title = try container.decode(EvidenceLinkedClaim.self, forKey: .title)
        summary = try container.decodeIfPresent(EvidenceLinkedClaim.self, forKey: .summary)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let title: EvidenceLinkedClaim
        let summary: EvidenceLinkedClaim?
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: IssueV1) {
            meetingID = value.meetingID
            title = value.title
            summary = value.summary
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case title
            case summary
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case title
        case summary
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct PositionV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<PositionIDTag>
    public let meetingID: MeetingID
    public let actorRevision: SemanticRevisionReference
    public let representedEntityRevision: SemanticRevisionReference
    public let speakingCapacityRevision: SemanticRevisionReference
    public let issueRevision: SemanticRevisionReference
    public let positionType: PositionType
    public let statement: EvidenceLinkedClaim
    public let reservations: [EvidenceLinkedClaim]
    public let conditions: [EvidenceLinkedClaim]
    public let effectiveTimeRange: MediaTimeRange?
    public let comparisonState: PositionComparisonState
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<PositionIDTag>,
        meetingID: MeetingID,
        actorRevision: SemanticRevisionReference,
        representedEntityRevision: SemanticRevisionReference,
        speakingCapacityRevision: SemanticRevisionReference,
        issueRevision: SemanticRevisionReference,
        positionType: PositionType,
        statement: EvidenceLinkedClaim,
        reservations: [EvidenceLinkedClaim] = [],
        conditions: [EvidenceLinkedClaim] = [],
        effectiveTimeRange: MediaTimeRange? = nil,
        comparisonState: PositionComparisonState,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.actorRevision = actorRevision
        self.representedEntityRevision = representedEntityRevision
        self.speakingCapacityRevision = speakingCapacityRevision
        self.issueRevision = issueRevision
        self.positionType = positionType
        self.statement = statement
        self.reservations = reservations
        self.conditions = conditions
        self.effectiveTimeRange = effectiveTimeRange
        self.comparisonState = comparisonState
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var positionID: PositionID { revision.logicalID }

    public var materialClaims: [EvidenceLinkedClaim] {
        [statement] + reservations + conditions
    }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .position,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "Position.v1"
        )
        issues.append(contentsOf: IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions))
        let required: [(SemanticRevisionReference, Set<SemanticObjectType>, String, String)] = [
            (actorRevision, [.actor], "actor_revision", "Actor revision"),
            (representedEntityRevision, [.participant, .organization], "represented_entity_revision", "represented entity revision"),
            (speakingCapacityRevision, [.speakingCapacity], "speaking_capacity_revision", "SpeakingCapacity revision"),
            (issueRevision, [.issue], "issue_revision", "Issue revision")
        ]
        for (reference, types, path, noun) in required {
            issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(reference, expectedTypes: types, revisionInputs: revision.inputRevisions, path: path, noun: noun))
        }
        if !positionType.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "position_type", "The position type is unsupported."))
        }
        if !comparisonState.isKnown {
            issues.append(IntelligenceRevisionSupport.issue(.unsupportedValue, "comparison_state", "The comparison state is unsupported."))
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
        issues.append(contentsOf: duplicateIssues(in: reservations, path: "reservations"))
        issues.append(contentsOf: duplicateIssues(in: conditions, path: "conditions"))
        if let effectiveTimeRange { issues.append(contentsOf: effectiveTimeRange.validationIssues()) }
        if positionType == .supportsWithConditions, conditions.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "conditions", "Conditional support must preserve at least one exact condition."))
        }
        if positionType == .opposesWithQualification, reservations.isEmpty {
            issues.append(IntelligenceRevisionSupport.issue(.missingRequiredValue, "reservations", "Qualified opposition must preserve at least one qualification or reservation."))
        }
        if positionType == .noStatedPosition,
           !(revision.createdBy == .user
                && userConfirmed
                && statement.taxonomy == .userConfirmedConclusion
                && statement.isPublishable)
        {
            issues.append(IntelligenceRevisionSupport.issue(.inconsistentValue, "position_type", "Silence cannot become a position; no-stated-position requires an explicit evidence-backed user conclusion."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<PositionIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        actorRevision = try container.decode(SemanticRevisionReference.self, forKey: .actorRevision)
        representedEntityRevision = try container.decode(SemanticRevisionReference.self, forKey: .representedEntityRevision)
        speakingCapacityRevision = try container.decode(SemanticRevisionReference.self, forKey: .speakingCapacityRevision)
        issueRevision = try container.decode(SemanticRevisionReference.self, forKey: .issueRevision)
        positionType = try container.decode(PositionType.self, forKey: .positionType)
        statement = try container.decode(EvidenceLinkedClaim.self, forKey: .statement)
        reservations = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .reservations) ?? []
        conditions = try container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .conditions) ?? []
        effectiveTimeRange = try container.decodeIfPresent(MediaTimeRange.self, forKey: .effectiveTimeRange)
        comparisonState = try container.decode(PositionComparisonState.self, forKey: .comparisonState)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let actorRevision: SemanticRevisionReference
        let representedEntityRevision: SemanticRevisionReference
        let speakingCapacityRevision: SemanticRevisionReference
        let issueRevision: SemanticRevisionReference
        let positionType: PositionType
        let statement: EvidenceLinkedClaim
        let reservations: [EvidenceLinkedClaim]
        let conditions: [EvidenceLinkedClaim]
        let effectiveTimeRange: MediaTimeRange?
        let comparisonState: PositionComparisonState
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: PositionV1) {
            meetingID = value.meetingID
            actorRevision = value.actorRevision
            representedEntityRevision = value.representedEntityRevision
            speakingCapacityRevision = value.speakingCapacityRevision
            issueRevision = value.issueRevision
            positionType = value.positionType
            statement = value.statement
            reservations = value.reservations
            conditions = value.conditions
            effectiveTimeRange = value.effectiveTimeRange
            comparisonState = value.comparisonState
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case actorRevision = "actor_revision"
            case representedEntityRevision = "represented_entity_revision"
            case speakingCapacityRevision = "speaking_capacity_revision"
            case issueRevision = "issue_revision"
            case positionType = "position_type"
            case statement
            case reservations
            case conditions
            case effectiveTimeRange = "effective_time_range"
            case comparisonState = "comparison_state"
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
        case issueRevision = "issue_revision"
        case positionType = "position_type"
        case statement
        case reservations
        case conditions
        case effectiveTimeRange = "effective_time_range"
        case comparisonState = "comparison_state"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
