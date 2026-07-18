import Foundation

/// Stable participant identity. Meeting roles and representation live in SpeakingCapacity.v1.
public enum ActorIdentity: Codable, Hashable, Sendable, DomainValidatable {
    case person(displayName: String, personName: String)
    case country(displayName: String, countryCode: CountryCode)
    case internationalOrganization(displayName: String)
    case formalGroup(displayName: String)
    case unOrgan(displayName: String)
    case unSecretariat(displayName: String)
    case unidentifiedParticipant(label: String)
    case other(displayName: String)

    private enum Kind: String, Codable {
        case person
        case country
        case internationalOrganization = "international_organization"
        case formalGroup = "formal_group"
        case unOrgan = "un_organ"
        case unSecretariat = "un_secretariat"
        case unidentifiedParticipant = "unidentified_participant"
        case other
    }

    public var displayName: String {
        switch self {
        case let .person(displayName, _),
             let .country(displayName, _),
             let .internationalOrganization(displayName),
             let .formalGroup(displayName),
             let .unOrgan(displayName),
             let .unSecretariat(displayName),
             let .other(displayName):
            displayName
        case let .unidentifiedParticipant(label):
            label
        }
    }

    public var countryCode: CountryCode? {
        guard case let .country(_, countryCode) = self else { return nil }
        return countryCode
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = boundedLabelIssues(
            displayName,
            path: "actor_identity.display_name",
            maximumUTF8Bytes: 512
        )
        switch self {
        case let .person(_, personName):
            issues.append(
                contentsOf: boundedLabelIssues(
                    personName,
                    path: "actor_identity.person_name",
                    maximumUTF8Bytes: 512
                )
            )
        case let .country(_, countryCode):
            issues.append(contentsOf: countryCode.validationIssues())
        case .internationalOrganization,
             .formalGroup,
             .unOrgan,
             .unSecretariat,
             .unidentifiedParticipant,
             .other:
            break
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .person:
            self = .person(
                displayName: try container.decode(String.self, forKey: .displayName),
                personName: try container.decode(String.self, forKey: .personName)
            )
        case .country:
            self = .country(
                displayName: try container.decode(String.self, forKey: .displayName),
                countryCode: try container.decode(CountryCode.self, forKey: .countryCode)
            )
        case .internationalOrganization:
            self = .internationalOrganization(
                displayName: try container.decode(String.self, forKey: .displayName)
            )
        case .formalGroup:
            self = .formalGroup(displayName: try container.decode(String.self, forKey: .displayName))
        case .unOrgan:
            self = .unOrgan(displayName: try container.decode(String.self, forKey: .displayName))
        case .unSecretariat:
            self = .unSecretariat(displayName: try container.decode(String.self, forKey: .displayName))
        case .unidentifiedParticipant:
            self = .unidentifiedParticipant(label: try container.decode(String.self, forKey: .label))
        case .other:
            self = .other(displayName: try container.decode(String.self, forKey: .displayName))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .person(displayName, personName):
            try container.encode(Kind.person, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(personName, forKey: .personName)
        case let .country(displayName, countryCode):
            try container.encode(Kind.country, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(countryCode, forKey: .countryCode)
        case let .internationalOrganization(displayName):
            try container.encode(Kind.internationalOrganization, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
        case let .formalGroup(displayName):
            try container.encode(Kind.formalGroup, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
        case let .unOrgan(displayName):
            try container.encode(Kind.unOrgan, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
        case let .unSecretariat(displayName):
            try container.encode(Kind.unSecretariat, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
        case let .unidentifiedParticipant(label):
            try container.encode(Kind.unidentifiedParticipant, forKey: .kind)
            try container.encode(label, forKey: .label)
        case let .other(displayName):
            try container.encode(Kind.other, forKey: .kind)
            try container.encode(displayName, forKey: .displayName)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case displayName = "display_name"
        case personName = "person_name"
        case countryCode = "country_code"
        case label
    }
}

public struct ActorV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<ActorIDTag>
    public let identity: ActorIdentity
    public let canonicalAliases: [String]
    public let affiliationRevision: SemanticRevisionReference?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<ActorIDTag>,
        identity: ActorIdentity,
        canonicalAliases: [String] = [],
        affiliationRevision: SemanticRevisionReference? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.identity = identity
        self.canonicalAliases = canonicalAliases.sorted()
        self.affiliationRevision = affiliationRevision
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var actorID: ActorID { revision.logicalID }
    public var displayName: String { identity.displayName }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try SemanticHash.sha256(
            of: SemanticProjection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                identity: identity,
                canonicalAliases: canonicalAliases,
                affiliationRevision: affiliationRevision,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .actor {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "Actor.v1 requires the actor object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "Actor.v1 supports schema version 1.0 only."))
        }
        issues.append(contentsOf: identity.validationIssues())
        for alias in canonicalAliases {
            issues.append(contentsOf: boundedLabelIssues(alias, path: "canonical_aliases", maximumUTF8Bytes: 512))
        }
        issues.append(contentsOf: duplicateIssues(in: canonicalAliases, path: "canonical_aliases"))
        if let affiliationRevision {
            issues.append(contentsOf: affiliationRevision.validationIssues())
            if affiliationRevision.objectType != .actor {
                issues.append(Self.issue(.inconsistentValue, "affiliation_revision.object_type", "An actor affiliation must reference another Actor revision."))
            }
            if !revision.inputRevisions.contains(affiliationRevision) {
                issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "The exact affiliated actor must appear in input revisions."))
            }
        }
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed actor revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "Actor.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<ActorIDTag>.self, forKey: .revision)
        identity = try container.decode(ActorIdentity.self, forKey: .identity)
        canonicalAliases = try container.decodeIfPresent([String].self, forKey: .canonicalAliases)?.sorted() ?? []
        affiliationRevision = try container.decodeIfPresent(SemanticRevisionReference.self, forKey: .affiliationRevision)
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
        let identity: ActorIdentity
        let canonicalAliases: [String]
        let affiliationRevision: SemanticRevisionReference?
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case identity
            case canonicalAliases = "canonical_aliases"
            case affiliationRevision = "affiliation_revision"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case identity
        case canonicalAliases = "canonical_aliases"
        case affiliationRevision = "affiliation_revision"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
