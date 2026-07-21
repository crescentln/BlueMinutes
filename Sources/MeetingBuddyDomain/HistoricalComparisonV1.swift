import Foundation

public enum HistoricalDifferenceState: StableStringValue {
    case unknown
    case insufficientEvidence
    case noConfirmedDifference
    case possibleDifference
    case userConfirmedDifference
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unknown": self = .unknown
        case "insufficient_evidence": self = .insufficientEvidence
        case "no_confirmed_difference": self = .noConfirmedDifference
        case "possible_difference": self = .possibleDifference
        case "user_confirmed_difference": self = .userConfirmedDifference
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unknown: "unknown"
        case .insufficientEvidence: "insufficient_evidence"
        case .noConfirmedDifference: "no_confirmed_difference"
        case .possibleDifference: "possible_difference"
        case .userConfirmedDifference: "user_confirmed_difference"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// A closed vocabulary whose display text remains deliberately qualified.
public enum HistoricalFinding: StableStringValue {
    case insufficientEvidence
    case repeatedPosition
    case wordingOnlyDifference
    case possibleChange
    case potentiallyStrongerWording
    case possibleNewReservation
    case noConfirmedChange
    case userConfirmedChange
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "insufficient_evidence": self = .insufficientEvidence
        case "repeated_position": self = .repeatedPosition
        case "wording_only_difference": self = .wordingOnlyDifference
        case "possible_change": self = .possibleChange
        case "potentially_stronger_wording": self = .potentiallyStrongerWording
        case "possible_new_reservation": self = .possibleNewReservation
        case "no_confirmed_change": self = .noConfirmedChange
        case "user_confirmed_change": self = .userConfirmedChange
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .insufficientEvidence: "insufficient_evidence"
        case .repeatedPosition: "repeated_position"
        case .wordingOnlyDifference: "wording_only_difference"
        case .possibleChange: "possible_change"
        case .potentiallyStrongerWording: "potentially_stronger_wording"
        case .possibleNewReservation: "possible_new_reservation"
        case .noConfirmedChange: "no_confirmed_change"
        case .userConfirmedChange: "user_confirmed_change"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public var qualifiedSummary: String {
        switch self {
        case .insufficientEvidence:
            "Insufficient exact published evidence to compare these positions."
        case .repeatedPosition:
            "The same structured position is repeated; no change is confirmed."
        case .wordingOnlyDifference:
            "Wording differs; a policy change is not established."
        case .possibleChange:
            "The structured positions differ; this is a possible change pending user review."
        case .potentiallyStrongerWording:
            "The wording may be stronger, but a policy change is not confirmed."
        case .possibleNewReservation:
            "A reservation may be new; this remains a possible change pending user review."
        case .noConfirmedChange:
            "No confirmed change is supported by the exact published evidence."
        case .userConfirmedChange:
            "A user confirmed the evidence-linked change in a superseding revision."
        case .unrecognized:
            "The historical finding is unsupported by this application version."
        }
    }

    public func isCompatible(with state: HistoricalDifferenceState) -> Bool {
        switch self {
        case .insufficientEvidence:
            state == .unknown || state == .insufficientEvidence
        case .repeatedPosition, .wordingOnlyDifference, .noConfirmedChange:
            state == .noConfirmedDifference
        case .possibleChange, .potentiallyStrongerWording, .possibleNewReservation:
            state == .possibleDifference
        case .userConfirmedChange:
            state == .userConfirmedDifference
        case .unrecognized:
            false
        }
    }
}

/// HistoricalComparison.v1 records one transparent comparison without rewriting
/// either source Position revision. Automatic findings are always qualified;
/// only a superseding user-authored revision may record a confirmed difference.
public struct HistoricalComparisonV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<HistoricalComparisonIDTag>
    public let currentPositionRevision: SemanticRevisionReference
    public let historicalPositionRevision: SemanticRevisionReference
    public let currentMeetingRevision: SemanticRevisionReference
    public let historicalMeetingRevision: SemanticRevisionReference
    public let currentActorRevision: SemanticRevisionReference
    public let historicalActorRevision: SemanticRevisionReference
    public let currentIssueRevision: SemanticRevisionReference
    public let historicalIssueRevision: SemanticRevisionReference
    public let currentSensitivityLabelRevision: SemanticRevisionReference
    public let historicalSensitivityLabelRevision: SemanticRevisionReference
    public let currentAccessPolicyRevision: SemanticRevisionReference
    public let historicalAccessPolicyRevision: SemanticRevisionReference
    public let currentEffectiveDate: CalendarDate?
    public let historicalEffectiveDate: CalendarDate?
    public let currentEffectiveTimeRange: MediaTimeRange?
    public let historicalEffectiveTimeRange: MediaTimeRange?
    public let currentConfidence: ConfidenceScore
    public let historicalConfidence: ConfidenceScore
    public let currentEvidenceRevisions: [SemanticRevisionReference]
    public let historicalEvidenceRevisions: [SemanticRevisionReference]
    public let differenceState: HistoricalDifferenceState
    public let finding: HistoricalFinding
    public let confirmationOfRevision: SemanticRevisionReference?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<HistoricalComparisonIDTag>,
        currentPositionRevision: SemanticRevisionReference,
        historicalPositionRevision: SemanticRevisionReference,
        currentMeetingRevision: SemanticRevisionReference,
        historicalMeetingRevision: SemanticRevisionReference,
        currentActorRevision: SemanticRevisionReference,
        historicalActorRevision: SemanticRevisionReference,
        currentIssueRevision: SemanticRevisionReference,
        historicalIssueRevision: SemanticRevisionReference,
        currentSensitivityLabelRevision: SemanticRevisionReference,
        historicalSensitivityLabelRevision: SemanticRevisionReference,
        currentAccessPolicyRevision: SemanticRevisionReference,
        historicalAccessPolicyRevision: SemanticRevisionReference,
        currentEffectiveDate: CalendarDate?,
        historicalEffectiveDate: CalendarDate?,
        currentEffectiveTimeRange: MediaTimeRange?,
        historicalEffectiveTimeRange: MediaTimeRange?,
        currentConfidence: ConfidenceScore,
        historicalConfidence: ConfidenceScore,
        currentEvidenceRevisions: [SemanticRevisionReference],
        historicalEvidenceRevisions: [SemanticRevisionReference],
        differenceState: HistoricalDifferenceState,
        finding: HistoricalFinding,
        confirmationOfRevision: SemanticRevisionReference? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.currentPositionRevision = currentPositionRevision
        self.historicalPositionRevision = historicalPositionRevision
        self.currentMeetingRevision = currentMeetingRevision
        self.historicalMeetingRevision = historicalMeetingRevision
        self.currentActorRevision = currentActorRevision
        self.historicalActorRevision = historicalActorRevision
        self.currentIssueRevision = currentIssueRevision
        self.historicalIssueRevision = historicalIssueRevision
        self.currentSensitivityLabelRevision = currentSensitivityLabelRevision
        self.historicalSensitivityLabelRevision = historicalSensitivityLabelRevision
        self.currentAccessPolicyRevision = currentAccessPolicyRevision
        self.historicalAccessPolicyRevision = historicalAccessPolicyRevision
        self.currentEffectiveDate = currentEffectiveDate
        self.historicalEffectiveDate = historicalEffectiveDate
        self.currentEffectiveTimeRange = currentEffectiveTimeRange
        self.historicalEffectiveTimeRange = historicalEffectiveTimeRange
        self.currentConfidence = currentConfidence
        self.historicalConfidence = historicalConfidence
        self.currentEvidenceRevisions = currentEvidenceRevisions.sorted()
        self.historicalEvidenceRevisions = historicalEvidenceRevisions.sorted()
        self.differenceState = differenceState
        self.finding = finding
        self.confirmationOfRevision = confirmationOfRevision
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var comparisonID: HistoricalComparisonID { revision.logicalID }
    public var qualifiedSummary: String { finding.qualifiedSummary }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .historicalComparison,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "HistoricalComparison.v1"
        )
        let exactInputs: [(SemanticRevisionReference, Set<SemanticObjectType>, String)] = [
            (currentPositionRevision, [.position], "current_position_revision"),
            (historicalPositionRevision, [.position], "historical_position_revision"),
            (currentMeetingRevision, [.meetingProfile], "current_meeting_revision"),
            (historicalMeetingRevision, [.meetingProfile], "historical_meeting_revision"),
            (currentActorRevision, [.actor], "current_actor_revision"),
            (historicalActorRevision, [.actor], "historical_actor_revision"),
            (currentIssueRevision, [.issue], "current_issue_revision"),
            (historicalIssueRevision, [.issue], "historical_issue_revision"),
            (currentSensitivityLabelRevision, [.sensitivityLabel], "current_sensitivity_label_revision"),
            (historicalSensitivityLabelRevision, [.sensitivityLabel], "historical_sensitivity_label_revision"),
            (currentAccessPolicyRevision, [.accessPolicy], "current_access_policy_revision"),
            (historicalAccessPolicyRevision, [.accessPolicy], "historical_access_policy_revision")
        ]
        for (reference, types, path) in exactInputs {
            issues.append(contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                reference,
                expectedTypes: types,
                revisionInputs: revision.inputRevisions,
                path: path,
                noun: path.replacingOccurrences(of: "_", with: " ")
            ))
        }
        if currentPositionRevision == historicalPositionRevision
            || currentMeetingRevision == historicalMeetingRevision
        {
            issues.append(Self.issue(.inconsistentValue, "historical_revision", "A historical comparison requires two distinct position and meeting revisions."))
        }
        let evidence = currentEvidenceRevisions + historicalEvidenceRevisions
        if Set(currentEvidenceRevisions).count != currentEvidenceRevisions.count
            || Set(historicalEvidenceRevisions).count != historicalEvidenceRevisions.count
        {
            issues.append(Self.issue(.duplicateValue, "evidence_revisions", "Each evidence trail must contain unique exact revision references."))
        }
        if evidence.contains(where: { $0.objectType != .evidenceRef })
            || !Set(evidence).isSubset(of: Set(revision.evidenceRevisions))
        {
            issues.append(Self.issue(.missingRequiredValue, "revision.evidence_revisions", "Both exact evidence trails must be present in the revision envelope."))
        }
        if !differenceState.isKnown || !finding.isKnown {
            issues.append(Self.issue(.unsupportedValue, "finding", "The comparison state and finding must be recognized."))
        }
        if let currentEffectiveDate, let historicalEffectiveDate,
           currentEffectiveDate <= historicalEffectiveDate,
           differenceState != .unknown,
           differenceState != .insufficientEvidence
        {
            issues.append(Self.issue(.inconsistentValue, "effective_date", "A non-ambiguous comparison requires the current meeting date to follow the historical meeting date."))
        }
        if (currentEffectiveDate == nil || historicalEffectiveDate == nil),
           differenceState != .unknown,
           differenceState != .insufficientEvidence
        {
            issues.append(Self.issue(.missingRequiredValue, "effective_date", "Missing effective dates require an unknown or insufficient-evidence result."))
        }
        if (currentEvidenceRevisions.isEmpty || historicalEvidenceRevisions.isEmpty),
           differenceState != .unknown,
           differenceState != .insufficientEvidence
        {
            issues.append(Self.issue(.missingRequiredValue, "evidence_revisions", "A substantive comparison requires exact evidence on both sides."))
        }
        if !finding.isCompatible(with: differenceState) {
            issues.append(Self.issue(
                .inconsistentValue,
                "difference_state",
                "The finding is incompatible with the declared historical difference state."
            ))
        }
        if differenceState == .userConfirmedDifference || finding == .userConfirmedChange {
            if !(differenceState == .userConfirmedDifference
                && finding == .userConfirmedChange
                && revision.createdBy == .user
                && reviewStatus == .confirmed
                && userConfirmed
                && revision.supersedesRevisionID != nil
                && confirmationOfRevision?.objectType == .historicalComparison
                && confirmationOfRevision?.revisionID == revision.supersedesRevisionID
                && confirmationOfRevision.map(revision.inputRevisions.contains) == true)
            {
                issues.append(Self.issue(.inconsistentValue, "confirmation_of_revision", "A confirmed change requires a user-authored superseding revision that cites the exact candidate comparison."))
            }
        } else if confirmationOfRevision != nil || userConfirmed {
            issues.append(Self.issue(.inconsistentValue, "user_confirmed", "Automatic or unconfirmed comparisons cannot carry user confirmation."))
        }
        issues.append(contentsOf: currentConfidence.validationIssues())
        issues.append(contentsOf: historicalConfidence.validationIssues())
        if let currentEffectiveTimeRange {
            issues.append(contentsOf: currentEffectiveTimeRange.validationIssues())
        }
        if let historicalEffectiveTimeRange {
            issues.append(contentsOf: historicalEffectiveTimeRange.validationIssues())
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<HistoricalComparisonIDTag>.self, forKey: .revision),
            currentPositionRevision: container.decode(SemanticRevisionReference.self, forKey: .currentPositionRevision),
            historicalPositionRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalPositionRevision),
            currentMeetingRevision: container.decode(SemanticRevisionReference.self, forKey: .currentMeetingRevision),
            historicalMeetingRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalMeetingRevision),
            currentActorRevision: container.decode(SemanticRevisionReference.self, forKey: .currentActorRevision),
            historicalActorRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalActorRevision),
            currentIssueRevision: container.decode(SemanticRevisionReference.self, forKey: .currentIssueRevision),
            historicalIssueRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalIssueRevision),
            currentSensitivityLabelRevision: container.decode(SemanticRevisionReference.self, forKey: .currentSensitivityLabelRevision),
            historicalSensitivityLabelRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalSensitivityLabelRevision),
            currentAccessPolicyRevision: container.decode(SemanticRevisionReference.self, forKey: .currentAccessPolicyRevision),
            historicalAccessPolicyRevision: container.decode(SemanticRevisionReference.self, forKey: .historicalAccessPolicyRevision),
            currentEffectiveDate: container.decodeIfPresent(CalendarDate.self, forKey: .currentEffectiveDate),
            historicalEffectiveDate: container.decodeIfPresent(CalendarDate.self, forKey: .historicalEffectiveDate),
            currentEffectiveTimeRange: container.decodeIfPresent(MediaTimeRange.self, forKey: .currentEffectiveTimeRange),
            historicalEffectiveTimeRange: container.decodeIfPresent(MediaTimeRange.self, forKey: .historicalEffectiveTimeRange),
            currentConfidence: container.decode(ConfidenceScore.self, forKey: .currentConfidence),
            historicalConfidence: container.decode(ConfidenceScore.self, forKey: .historicalConfidence),
            currentEvidenceRevisions: container.decode([SemanticRevisionReference].self, forKey: .currentEvidenceRevisions),
            historicalEvidenceRevisions: container.decode([SemanticRevisionReference].self, forKey: .historicalEvidenceRevisions),
            differenceState: container.decode(HistoricalDifferenceState.self, forKey: .differenceState),
            finding: container.decode(HistoricalFinding.self, forKey: .finding),
            confirmationOfRevision: container.decodeIfPresent(SemanticRevisionReference.self, forKey: .confirmationOfRevision),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private struct Content: Codable, Hashable, Sendable {
        let currentPositionRevision: SemanticRevisionReference
        let historicalPositionRevision: SemanticRevisionReference
        let currentMeetingRevision: SemanticRevisionReference
        let historicalMeetingRevision: SemanticRevisionReference
        let currentActorRevision: SemanticRevisionReference
        let historicalActorRevision: SemanticRevisionReference
        let currentIssueRevision: SemanticRevisionReference
        let historicalIssueRevision: SemanticRevisionReference
        let currentSensitivityLabelRevision: SemanticRevisionReference
        let historicalSensitivityLabelRevision: SemanticRevisionReference
        let currentAccessPolicyRevision: SemanticRevisionReference
        let historicalAccessPolicyRevision: SemanticRevisionReference
        let currentEffectiveDate: CalendarDate?
        let historicalEffectiveDate: CalendarDate?
        let currentEffectiveTimeRange: MediaTimeRange?
        let historicalEffectiveTimeRange: MediaTimeRange?
        let currentConfidence: ConfidenceScore
        let historicalConfidence: ConfidenceScore
        let currentEvidenceRevisions: [SemanticRevisionReference]
        let historicalEvidenceRevisions: [SemanticRevisionReference]
        let differenceState: HistoricalDifferenceState
        let finding: HistoricalFinding
        let confirmationOfRevision: SemanticRevisionReference?
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: HistoricalComparisonV1) {
            currentPositionRevision = value.currentPositionRevision
            historicalPositionRevision = value.historicalPositionRevision
            currentMeetingRevision = value.currentMeetingRevision
            historicalMeetingRevision = value.historicalMeetingRevision
            currentActorRevision = value.currentActorRevision
            historicalActorRevision = value.historicalActorRevision
            currentIssueRevision = value.currentIssueRevision
            historicalIssueRevision = value.historicalIssueRevision
            currentSensitivityLabelRevision = value.currentSensitivityLabelRevision
            historicalSensitivityLabelRevision = value.historicalSensitivityLabelRevision
            currentAccessPolicyRevision = value.currentAccessPolicyRevision
            historicalAccessPolicyRevision = value.historicalAccessPolicyRevision
            currentEffectiveDate = value.currentEffectiveDate
            historicalEffectiveDate = value.historicalEffectiveDate
            currentEffectiveTimeRange = value.currentEffectiveTimeRange
            historicalEffectiveTimeRange = value.historicalEffectiveTimeRange
            currentConfidence = value.currentConfidence
            historicalConfidence = value.historicalConfidence
            currentEvidenceRevisions = value.currentEvidenceRevisions
            historicalEvidenceRevisions = value.historicalEvidenceRevisions
            differenceState = value.differenceState
            finding = value.finding
            confirmationOfRevision = value.confirmationOfRevision
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case currentPositionRevision = "current_position_revision"
        case historicalPositionRevision = "historical_position_revision"
        case currentMeetingRevision = "current_meeting_revision"
        case historicalMeetingRevision = "historical_meeting_revision"
        case currentActorRevision = "current_actor_revision"
        case historicalActorRevision = "historical_actor_revision"
        case currentIssueRevision = "current_issue_revision"
        case historicalIssueRevision = "historical_issue_revision"
        case currentSensitivityLabelRevision = "current_sensitivity_label_revision"
        case historicalSensitivityLabelRevision = "historical_sensitivity_label_revision"
        case currentAccessPolicyRevision = "current_access_policy_revision"
        case historicalAccessPolicyRevision = "historical_access_policy_revision"
        case currentEffectiveDate = "current_effective_date"
        case historicalEffectiveDate = "historical_effective_date"
        case currentEffectiveTimeRange = "current_effective_time_range"
        case historicalEffectiveTimeRange = "historical_effective_time_range"
        case currentConfidence = "current_confidence"
        case historicalConfidence = "historical_confidence"
        case currentEvidenceRevisions = "current_evidence_revisions"
        case historicalEvidenceRevisions = "historical_evidence_revisions"
        case differenceState = "difference_state"
        case finding
        case confirmationOfRevision = "confirmation_of_revision"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }
}
