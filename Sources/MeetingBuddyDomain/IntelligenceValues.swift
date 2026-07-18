import Foundation

public enum ClaimTaxonomy: StableStringValue {
    case sourceFact
    case delegationClaim
    case meetingBuddyExtraction
    case meetingBuddyInference
    case userConfirmedConclusion
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "source_fact": self = .sourceFact
        case "delegation_claim": self = .delegationClaim
        case "meetingbuddy_extraction": self = .meetingBuddyExtraction
        case "meetingbuddy_inference": self = .meetingBuddyInference
        case "user_confirmed_conclusion": self = .userConfirmedConclusion
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .sourceFact: "source_fact"
        case .delegationClaim: "delegation_claim"
        case .meetingBuddyExtraction: "meetingbuddy_extraction"
        case .meetingBuddyInference: "meetingbuddy_inference"
        case .userConfirmedConclusion: "user_confirmed_conclusion"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum EvidenceSupportStatus: StableStringValue {
    case supported
    case uncertain
    case unsupported
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "supported": self = .supported
        case "uncertain": self = .uncertain
        case "unsupported": self = .unsupported
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .supported: "supported"
        case .uncertain: "uncertain"
        case .unsupported: "unsupported"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// One material statement with its exact evidence and epistemic category.
public struct EvidenceLinkedClaim: Codable, Hashable, Sendable, DomainValidatable {
    public let text: String
    public let taxonomy: ClaimTaxonomy
    public let supportStatus: EvidenceSupportStatus
    public let evidenceRevisions: [SemanticRevisionReference]
    public let confidence: ConfidenceScore

    public init(
        text: String,
        taxonomy: ClaimTaxonomy,
        supportStatus: EvidenceSupportStatus,
        evidenceRevisions: [SemanticRevisionReference],
        confidence: ConfidenceScore
    ) throws {
        self.text = text
        self.taxonomy = taxonomy
        self.supportStatus = supportStatus
        self.evidenceRevisions = evidenceRevisions.sorted()
        self.confidence = confidence
        try validate()
    }

    public var isPublishable: Bool {
        supportStatus != .unsupported
            && !evidenceRevisions.isEmpty
            && evidenceRevisions.allSatisfy { $0.objectType == .evidenceRef }
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = preservedSourceTextIssues(
            text,
            path: "claim.text",
            maximumUTF8Bytes: 16_384
        )
        if !taxonomy.isKnown {
            issues.append(Self.issue(.unsupportedValue, "claim.taxonomy", "The claim taxonomy is unsupported."))
        }
        if !supportStatus.isKnown {
            issues.append(Self.issue(.unsupportedValue, "claim.support_status", "The evidence-support state is unsupported."))
        }
        issues.append(contentsOf: confidence.validationIssues())
        issues.append(contentsOf: duplicateIssues(in: evidenceRevisions, path: "claim.evidence_revisions"))
        for reference in evidenceRevisions {
            issues.append(contentsOf: reference.validationIssues())
            if reference.objectType != .evidenceRef {
                issues.append(Self.issue(.inconsistentValue, "claim.evidence_revisions.object_type", "Material claims may reference only EvidenceRef revisions."))
            }
        }
        switch supportStatus {
        case .supported, .uncertain:
            if evidenceRevisions.isEmpty {
                issues.append(Self.issue(.missingRequiredValue, "claim.evidence_revisions", "Supported or uncertain material requires exact evidence."))
            }
        case .unsupported:
            if !evidenceRevisions.isEmpty {
                issues.append(Self.issue(.inconsistentValue, "claim.evidence_revisions", "An explicitly unsupported claim cannot imply supporting evidence."))
            }
        case .unrecognized:
            break
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        taxonomy = try container.decode(ClaimTaxonomy.self, forKey: .taxonomy)
        supportStatus = try container.decode(EvidenceSupportStatus.self, forKey: .supportStatus)
        evidenceRevisions = try container.decode(
            [SemanticRevisionReference].self,
            forKey: .evidenceRevisions
        ).sorted()
        confidence = try container.decode(ConfidenceScore.self, forKey: .confidence)
        try validate()
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case taxonomy
        case supportStatus = "support_status"
        case evidenceRevisions = "evidence_revisions"
        case confidence
    }
}

public enum ParticipantKind: StableStringValue {
    case person
    case chair
    case expert
    case observer
    case briefer
    case unidentified
    case other
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "person": self = .person
        case "chair": self = .chair
        case "expert": self = .expert
        case "observer": self = .observer
        case "briefer": self = .briefer
        case "unidentified": self = .unidentified
        case "other": self = .other
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .person: "person"
        case .chair: "chair"
        case .expert: "expert"
        case .observer: "observer"
        case .briefer: "briefer"
        case .unidentified: "unidentified"
        case .other: "other"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum OrganizationKind: StableStringValue {
    case country
    case internationalOrganization
    case formalGroup
    case unOrgan
    case unSecretariat
    case other
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "country": self = .country
        case "international_organization": self = .internationalOrganization
        case "formal_group": self = .formalGroup
        case "un_organ": self = .unOrgan
        case "un_secretariat": self = .unSecretariat
        case "other": self = .other
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .country: "country"
        case .internationalOrganization: "international_organization"
        case .formalGroup: "formal_group"
        case .unOrgan: "un_organ"
        case .unSecretariat: "un_secretariat"
        case .other: "other"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum PositionType: StableStringValue {
    case supports
    case opposes
    case requests
    case proposes
    case reservesPosition
    case supportsWithConditions
    case opposesWithQualification
    case noStatedPosition
    case uncertain
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "supports": self = .supports
        case "opposes": self = .opposes
        case "requests": self = .requests
        case "proposes": self = .proposes
        case "reserves_position": self = .reservesPosition
        case "supports_with_conditions": self = .supportsWithConditions
        case "opposes_with_qualification": self = .opposesWithQualification
        case "no_stated_position": self = .noStatedPosition
        case "uncertain": self = .uncertain
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .supports: "supports"
        case .opposes: "opposes"
        case .requests: "requests"
        case .proposes: "proposes"
        case .reservesPosition: "reserves_position"
        case .supportsWithConditions: "supports_with_conditions"
        case .opposesWithQualification: "opposes_with_qualification"
        case .noStatedPosition: "no_stated_position"
        case .uncertain: "uncertain"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum PositionComparisonState: StableStringValue {
    case unknown
    case insufficientEvidence
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unknown": self = .unknown
        case "insufficient_evidence": self = .insufficientEvidence
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unknown: "unknown"
        case .insufficientEvidence: "insufficient_evidence"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum CommitmentStatus: StableStringValue {
    case proposed
    case announced
    case accepted
    case inProgress
    case completed
    case withdrawn
    case uncertain
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "proposed": self = .proposed
        case "announced": self = .announced
        case "accepted": self = .accepted
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        case "withdrawn": self = .withdrawn
        case "uncertain": self = .uncertain
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .proposed: "proposed"
        case .announced: "announced"
        case .accepted: "accepted"
        case .inProgress: "in_progress"
        case .completed: "completed"
        case .withdrawn: "withdrawn"
        case .uncertain: "uncertain"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum DecisionType: StableStringValue {
    case adopted
    case rejected
    case deferred
    case noted
    case procedural
    case uncertain
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "adopted": self = .adopted
        case "rejected": self = .rejected
        case "deferred": self = .deferred
        case "noted": self = .noted
        case "procedural": self = .procedural
        case "uncertain": self = .uncertain
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .adopted: "adopted"
        case .rejected: "rejected"
        case .deferred: "deferred"
        case .noted: "noted"
        case .procedural: "procedural"
        case .uncertain: "uncertain"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum InterventionType: StableStringValue {
    case statement
    case question
    case response
    case rightOfReply
    case procedural
    case other
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "statement": self = .statement
        case "question": self = .question
        case "response": self = .response
        case "right_of_reply": self = .rightOfReply
        case "procedural": self = .procedural
        case "other": self = .other
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .statement: "statement"
        case .question: "question"
        case .response: "response"
        case .rightOfReply: "right_of_reply"
        case .procedural: "procedural"
        case .other: "other"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum CommitmentDeadline: Codable, Hashable, Sendable, DomainValidatable {
    case date(CalendarDate)
    case described(String)
    case notStated

    private enum Kind: String, Codable {
        case date
        case described
        case notStated = "not_stated"
    }

    public func validationIssues() -> [ValidationIssue] {
        switch self {
        case let .date(value): value.validationIssues()
        case let .described(value): boundedLabelIssues(value, path: "deadline.description", maximumUTF8Bytes: 512)
        case .notStated: []
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .date:
            self = .date(try container.decode(CalendarDate.self, forKey: .date))
        case .described:
            self = .described(try container.decode(String.self, forKey: .description))
        case .notStated:
            self = .notStated
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .date(value):
            try container.encode(Kind.date, forKey: .kind)
            try container.encode(value, forKey: .date)
        case let .described(value):
            try container.encode(Kind.described, forKey: .kind)
            try container.encode(value, forKey: .description)
        case .notStated:
            try container.encode(Kind.notStated, forKey: .kind)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case date
        case description
    }
}
