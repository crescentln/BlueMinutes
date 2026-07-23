import Foundation
import MeetingBuddyDomain

/// A Citation target. Evidence location remains exclusively inside the exact
/// EvidenceRefV1 revision and is never copied into this projection.
public enum CitationTarget: Codable, Hashable, Sendable, DomainValidatable {
    case artifactVersion(ArtifactVersionRef)
    case conversationMessage(conversationID: ConversationID, messageID: MessageID)

    public func validationIssues() -> [ValidationIssue] {
        switch self {
        case let .artifactVersion(reference):
            reference.validationIssues()
        case .conversationMessage:
            []
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodingKind.self, forKey: .kind) {
        case .artifactVersion:
            self = .artifactVersion(
                try container.decode(ArtifactVersionRef.self, forKey: .artifactVersion)
            )
        case .conversationMessage:
            self = .conversationMessage(
                conversationID: try container.decode(
                    ConversationID.self,
                    forKey: .conversationID
                ),
                messageID: try container.decode(MessageID.self, forKey: .messageID)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .artifactVersion(reference):
            try container.encode(EncodingKind.artifactVersion, forKey: .kind)
            try container.encode(reference, forKey: .artifactVersion)
        case let .conversationMessage(conversationID, messageID):
            try container.encode(EncodingKind.conversationMessage, forKey: .kind)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(messageID, forKey: .messageID)
        }
    }

    private enum EncodingKind: String, Codable {
        case artifactVersion = "artifact_version"
        case conversationMessage = "conversation_message"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case artifactVersion = "artifact_version"
        case conversationID = "conversation_id"
        case messageID = "message_id"
    }
}

/// Read-only verification state for one exact evidence revision.
public struct CitationVerificationProjection:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let evidenceRevision: SemanticRevisionReference
    public let status: CitationVerificationStatus
    public let validator: VersionedComponent?
    public let checkedAt: UTCInstant?
    public let safeReasonCode: String?

    public init(
        evidenceRevision: SemanticRevisionReference,
        status: CitationVerificationStatus = .unverified,
        validator: VersionedComponent? = nil,
        checkedAt: UTCInstant? = nil,
        safeReasonCode: String? = nil
    ) throws {
        self.evidenceRevision = evidenceRevision
        self.status = status
        self.validator = validator
        self.checkedAt = checkedAt
        self.safeReasonCode = safeReasonCode
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = citationEvidenceIssues(evidenceRevision)
        if !status.isKnown {
            issues.append(
                citationIssue(
                    .unsupportedValue,
                    "status",
                    "The citation-verification status is not supported."
                )
            )
        }
        switch status {
        case .unverified:
            if validator != nil || checkedAt != nil || safeReasonCode != nil {
                issues.append(
                    citationIssue(
                        .inconsistentValue,
                        "verification",
                        "An unverified citation cannot claim a validator result."
                    )
                )
            }
        case .verified:
            if validator == nil || checkedAt == nil || safeReasonCode != nil {
                issues.append(
                    citationIssue(
                        .inconsistentValue,
                        "verification",
                        "A verified citation requires a validator and timestamp without a failure code."
                    )
                )
            }
        case .invalid, .unresolvable:
            if validator == nil || checkedAt == nil || safeReasonCode == nil {
                issues.append(
                    citationIssue(
                        .inconsistentValue,
                        "verification",
                        "A failed citation check requires validator provenance, time, and a safe reason code."
                    )
                )
            }
        case .unrecognized:
            break
        }
        if let validator {
            issues += validator.validationIssues()
        }
        if let checkedAt {
            issues += checkedAt.validationIssues()
        }
        if let safeReasonCode {
            issues += citationReasonCodeIssues(safeReasonCode)
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            evidenceRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .evidenceRevision
            ),
            status: container.decode(CitationVerificationStatus.self, forKey: .status),
            validator: container.decodeIfPresent(VersionedComponent.self, forKey: .validator),
            checkedAt: container.decodeIfPresent(UTCInstant.self, forKey: .checkedAt),
            safeReasonCode: container.decodeIfPresent(String.self, forKey: .safeReasonCode)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceRevision = "evidence_revision"
        case status
        case validator
        case checkedAt = "checked_at"
        case safeReasonCode = "safe_reason_code"
    }
}

/// Associates a display target with exact accepted evidence truth.
///
/// It deliberately contains no EvidenceLocation, excerpt, page, paragraph, or
/// time range. Consumers resolve those only from EvidenceRefV1.
public struct CitationAssociation: Codable, Hashable, Sendable, DomainValidatable {
    public let target: CitationTarget
    public let evidenceRevision: SemanticRevisionReference
    public let verification: CitationVerificationProjection

    public init(
        target: CitationTarget,
        evidenceRevision: SemanticRevisionReference,
        verification: CitationVerificationProjection? = nil
    ) throws {
        self.target = target
        self.evidenceRevision = evidenceRevision
        self.verification = try verification ?? CitationVerificationProjection(
            evidenceRevision: evidenceRevision
        )
        try validate()
    }

    public static func evidenceRevision(
        for evidence: EvidenceRefV1
    ) throws -> SemanticRevisionReference {
        try evidence.validate()
        return try SemanticRevisionReference(
            logicalID: evidence.evidenceID,
            revisionID: evidence.revision.revisionID
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = target.validationIssues()
        issues += citationEvidenceIssues(evidenceRevision)
        issues += verification.validationIssues()
        if verification.evidenceRevision != evidenceRevision {
            issues.append(
                citationIssue(
                    .inconsistentValue,
                    "verification.evidence_revision",
                    "Citation verification must refer to the association's exact EvidenceRef revision."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            target: container.decode(CitationTarget.self, forKey: .target),
            evidenceRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .evidenceRevision
            ),
            verification: container.decode(
                CitationVerificationProjection.self,
                forKey: .verification
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case evidenceRevision = "evidence_revision"
        case verification
    }
}

private func citationEvidenceIssues(
    _ evidenceRevision: SemanticRevisionReference
) -> [ValidationIssue] {
    var issues = evidenceRevision.validationIssues()
    if evidenceRevision.objectType != .evidenceRef {
        issues.append(
            citationIssue(
                .inconsistentValue,
                "evidence_revision.object_type",
                "A Citation must reference an exact EvidenceRef revision."
            )
        )
    }
    return issues
}

private func citationReasonCodeIssues(_ value: String) -> [ValidationIssue] {
    let bytes = Array(value.utf8)
    let allowed = bytes.allSatisfy { byte in
        (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
            || byte == 45
            || byte == 95
    }
    guard
        !bytes.isEmpty,
        bytes.count <= 96,
        allowed,
        bytes.first != 45,
        bytes.first != 95,
        bytes.last != 45,
        bytes.last != 95
    else {
        return [
            citationIssue(
                .invalidFormat,
                "safe_reason_code",
                "Citation reason codes must be bounded lowercase machine-readable identifiers."
            )
        ]
    }
    return []
}

private func citationIssue(
    _ code: ValidationIssueCode,
    _ path: String,
    _ message: String
) -> ValidationIssue {
    ValidationIssue(code: code, path: path, message: message)
}
