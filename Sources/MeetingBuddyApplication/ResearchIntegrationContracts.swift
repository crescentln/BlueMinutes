import CryptoKit
import Foundation
import MeetingBuddyDomain

/// The smallest logical Research collection value accepted for Phase 1.
///
/// It deliberately contains no physical WorkspaceID, filesystem root,
/// persistence identity, or Meeting backfill behavior.
public struct ResearchWorkspaceV1: Codable, Hashable, Sendable, DomainValidatable {
    public let workspaceID: ResearchWorkspaceID
    public let schemaVersion: SchemaVersion
    public let kind: ResearchWorkspaceKind
    public let title: String
    public let dataClassification: DataClassification
    public let instructionProfileID: InstructionProfileID?

    public init(
        workspaceID: ResearchWorkspaceID,
        schemaVersion: SchemaVersion = .v1,
        kind: ResearchWorkspaceKind,
        title: String,
        dataClassification: DataClassification,
        instructionProfileID: InstructionProfileID? = nil
    ) throws {
        self.workspaceID = workspaceID
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.title = title
        self.dataClassification = dataClassification
        self.instructionProfileID = instructionProfileID
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if schemaVersion != .v1 {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "schema_version",
                    "ResearchWorkspace.v1 supports schema version 1.0 only."
                )
            )
        }
        if !kind.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "kind",
                    "The Research workspace kind is not supported by this contract version."
                )
            )
        }
        issues += researchBoundedTextIssues(title, path: "title", maximumUTF8Bytes: 2_048)
        if !dataClassification.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "data_classification",
                    "The Research workspace classification is not supported."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: container.decode(ResearchWorkspaceID.self, forKey: .workspaceID),
            schemaVersion: container.decode(SchemaVersion.self, forKey: .schemaVersion),
            kind: container.decode(ResearchWorkspaceKind.self, forKey: .kind),
            title: container.decode(String.self, forKey: .title),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            instructionProfileID: container.decodeIfPresent(
                InstructionProfileID.self,
                forKey: .instructionProfileID
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "research_workspace_id"
        case schemaVersion = "schema_version"
        case kind
        case title
        case dataClassification = "data_classification"
        case instructionProfileID = "instruction_profile_id"
    }
}

/// An explicit canonical-key assertion. `unclaimed` is a first-class state so
/// adapters never synthesize an identity from a URL, filename, or digest.
public struct SourceCanonicalKeyClaim: Codable, Hashable, Sendable, DomainValidatable {
    public let basis: SourceCanonicalKeyClaimBasis
    public let namespace: String?
    public let value: String?
    public let provenance: VersionedComponent?

    public static var unclaimed: Self {
        try! Self(basis: .unclaimed)
    }

    public init(
        basis: SourceCanonicalKeyClaimBasis,
        namespace: String? = nil,
        value: String? = nil,
        provenance: VersionedComponent? = nil
    ) throws {
        self.basis = basis
        self.namespace = namespace
        self.value = value
        self.provenance = provenance
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !basis.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "canonical_key_claim.basis",
                    "The canonical-key claim basis is not supported."
                )
            )
        }

        if basis == .unclaimed {
            if namespace != nil || value != nil || provenance != nil {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "canonical_key_claim",
                        "An unclaimed canonical key cannot contain asserted key material."
                    )
                )
            }
            return issues
        }

        guard let namespace, let value, let provenance else {
            issues.append(
                researchIssue(
                    .missingRequiredValue,
                    "canonical_key_claim",
                    "A claimed canonical key requires a namespace, value, and versioned provenance."
                )
            )
            return issues
        }
        issues += researchOpaqueIdentifierIssues(
            namespace,
            path: "canonical_key_claim.namespace",
            maximumUTF8Bytes: 128
        )
        issues += researchBoundedTextIssues(
            value,
            path: "canonical_key_claim.value",
            maximumUTF8Bytes: 2_048
        )
        issues += provenance.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            basis: container.decode(SourceCanonicalKeyClaimBasis.self, forKey: .basis),
            namespace: container.decodeIfPresent(String.self, forKey: .namespace),
            value: container.decodeIfPresent(String.self, forKey: .value),
            provenance: container.decodeIfPresent(VersionedComponent.self, forKey: .provenance)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case basis
        case namespace
        case value
        case provenance
    }
}

/// A read-only projection of exact accepted source truth.
public struct SharedSourceRef: Codable, Hashable, Sendable, DomainValidatable {
    public let sourceRevision: SemanticRevisionReference
    public let sourceKind: SharedSourceKind
    public let canonicalKeyClaim: SourceCanonicalKeyClaim
    public let authority: SourceAuthority
    public let completeness: SourceCompleteness
    public let dataClassification: DataClassification
    public let retentionClass: RetentionClass
    public let contentDigest: ContentDigest?
    public let externalReference: HTTPSURL?
    public let projectionProvenance: VersionedComponent

    public init(
        sourceRevision: SemanticRevisionReference,
        sourceKind: SharedSourceKind,
        canonicalKeyClaim: SourceCanonicalKeyClaim,
        authority: SourceAuthority,
        completeness: SourceCompleteness,
        dataClassification: DataClassification,
        retentionClass: RetentionClass,
        contentDigest: ContentDigest? = nil,
        externalReference: HTTPSURL? = nil,
        projectionProvenance: VersionedComponent
    ) throws {
        self.sourceRevision = sourceRevision
        self.sourceKind = sourceKind
        self.canonicalKeyClaim = canonicalKeyClaim
        self.authority = authority
        self.completeness = completeness
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
        self.contentDigest = contentDigest
        self.externalReference = externalReference
        self.projectionProvenance = projectionProvenance
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = sourceRevision.validationIssues()
        if sourceRevision.objectType != .sourceAsset {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "source_revision.object_type",
                    "A Phase 1 shared source must reference an exact SourceAsset revision."
                )
            )
        }
        if !sourceKind.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "source_kind",
                    "The shared-source kind is not supported."
                )
            )
        }
        issues += canonicalKeyClaim.validationIssues()
        if !authority.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "authority",
                    "Unknown future authority values cannot be trusted by this contract version."
                )
            )
        }
        if !completeness.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "completeness",
                    "Unknown future completeness values cannot be trusted by this contract version."
                )
            )
        }
        if !dataClassification.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "data_classification",
                    "The shared-source classification is not supported."
                )
            )
        }
        if !retentionClass.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "retention_class",
                    "The shared-source retention class is not supported."
                )
            )
        }
        if let contentDigest {
            issues += contentDigest.validationIssues()
        }
        if let externalReference {
            issues += externalReference.validationIssues()
        }
        issues += projectionProvenance.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .sourceRevision
            ),
            sourceKind: container.decode(SharedSourceKind.self, forKey: .sourceKind),
            canonicalKeyClaim: container.decode(
                SourceCanonicalKeyClaim.self,
                forKey: .canonicalKeyClaim
            ),
            authority: container.decode(SourceAuthority.self, forKey: .authority),
            completeness: container.decode(SourceCompleteness.self, forKey: .completeness),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            retentionClass: container.decode(RetentionClass.self, forKey: .retentionClass),
            contentDigest: container.decodeIfPresent(ContentDigest.self, forKey: .contentDigest),
            externalReference: container.decodeIfPresent(HTTPSURL.self, forKey: .externalReference),
            projectionProvenance: container.decode(
                VersionedComponent.self,
                forKey: .projectionProvenance
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sourceRevision = "source_revision"
        case sourceKind = "source_kind"
        case canonicalKeyClaim = "canonical_key_claim"
        case authority
        case completeness
        case dataClassification = "data_classification"
        case retentionClass = "retention_class"
        case contentDigest = "content_digest"
        case externalReference = "external_reference"
        case projectionProvenance = "projection_provenance"
    }
}

/// A generic catalog reference that never contains or mutates the concrete
/// semantic payload.
public enum ArtifactVersionRef: Codable, Hashable, Sendable, DomainValidatable {
    case semanticRevision(SemanticRevisionReference)
    case researchArtifact(
        artifactID: ArtifactID,
        versionID: ArtifactVersionID,
        schemaVersion: SchemaVersion
    )

    public var artifactID: ArtifactID {
        get throws {
            switch self {
            case let .semanticRevision(reference):
                return try ArtifactID(validating: reference.logicalID.canonicalString)
            case let .researchArtifact(artifactID, _, _):
                return artifactID
            }
        }
    }

    public var exactSemanticRevision: SemanticRevisionReference? {
        guard case let .semanticRevision(reference) = self else { return nil }
        return reference
    }

    public func validationIssues() -> [ValidationIssue] {
        switch self {
        case let .semanticRevision(reference):
            var issues = reference.validationIssues()
            if ![SemanticObjectType.finalBriefing, .historicalComparison].contains(
                reference.objectType
            ) {
                issues.append(
                    researchIssue(
                        .unsupportedValue,
                        "artifact_version.semantic_revision.object_type",
                        "Only accepted briefing and historical-comparison revisions are Phase 1 artifact projections."
                    )
                )
            }
            return issues
        case let .researchArtifact(artifactID, versionID, schemaVersion):
            var issues = schemaVersion.validationIssues()
            if artifactID.canonicalString == versionID.canonicalString {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "artifact_version.version_id",
                        "Artifact and version identities must be distinct."
                    )
                )
            }
            return issues
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodingKind.self, forKey: .kind) {
        case .semanticRevision:
            self = .semanticRevision(
                try container.decode(
                    SemanticRevisionReference.self,
                    forKey: .semanticRevision
                )
            )
        case .researchArtifact:
            self = .researchArtifact(
                artifactID: try container.decode(ArtifactID.self, forKey: .artifactID),
                versionID: try container.decode(ArtifactVersionID.self, forKey: .versionID),
                schemaVersion: try container.decode(SchemaVersion.self, forKey: .schemaVersion)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .semanticRevision(reference):
            try container.encode(EncodingKind.semanticRevision, forKey: .kind)
            try container.encode(reference, forKey: .semanticRevision)
        case let .researchArtifact(artifactID, versionID, schemaVersion):
            try container.encode(EncodingKind.researchArtifact, forKey: .kind)
            try container.encode(artifactID, forKey: .artifactID)
            try container.encode(versionID, forKey: .versionID)
            try container.encode(schemaVersion, forKey: .schemaVersion)
        }
    }

    private enum EncodingKind: String, Codable {
        case semanticRevision = "semantic_revision"
        case researchArtifact = "research_artifact"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case semanticRevision = "semantic_revision"
        case artifactID = "artifact_id"
        case versionID = "version_id"
        case schemaVersion = "schema_version"
    }
}

/// Catalog metadata whose currentVersion is only a read-only projection
/// pointer. Existing active-revision repositories remain authoritative.
public struct ArtifactDescriptor: Codable, Hashable, Sendable, DomainValidatable {
    public let artifactID: ArtifactID
    public let kind: ArtifactKind
    public let title: String
    public let currentVersion: ArtifactVersionRef
    public let lifecycleStatus: LifecycleStatus
    public let validationState: ValidationState
    public let dataClassification: DataClassification

    public init(
        artifactID: ArtifactID,
        kind: ArtifactKind,
        title: String,
        currentVersion: ArtifactVersionRef,
        lifecycleStatus: LifecycleStatus,
        validationState: ValidationState,
        dataClassification: DataClassification
    ) throws {
        self.artifactID = artifactID
        self.kind = kind
        self.title = title
        self.currentVersion = currentVersion
        self.lifecycleStatus = lifecycleStatus
        self.validationState = validationState
        self.dataClassification = dataClassification
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = currentVersion.validationIssues()
        if (try? currentVersion.artifactID) != artifactID {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "current_version",
                    "The projected current version must preserve the artifact identity."
                )
            )
        }
        if !kind.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "kind",
                    "The artifact kind is not supported."
                )
            )
        }
        if let reference = currentVersion.exactSemanticRevision {
            let expectedKind: ArtifactKind?
            switch reference.objectType {
            case .finalBriefing: expectedKind = .meetingBriefing
            case .historicalComparison: expectedKind = .historicalComparison
            default: expectedKind = nil
            }
            if expectedKind != kind {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "kind",
                        "The artifact kind must match its exact semantic revision type."
                    )
                )
            }
        } else if kind != .researchArtifact {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "kind",
                    "A native Research artifact version requires the research_artifact kind."
                )
            )
        }
        issues += researchBoundedTextIssues(title, path: "title", maximumUTF8Bytes: 2_048)
        if !lifecycleStatus.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "lifecycle_status",
                    "The artifact lifecycle status is not supported."
                )
            )
        }
        if !validationState.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "validation_state",
                    "The artifact validation state is not supported."
                )
            )
        }
        if !dataClassification.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "data_classification",
                    "The artifact classification is not supported."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            artifactID: container.decode(ArtifactID.self, forKey: .artifactID),
            kind: container.decode(ArtifactKind.self, forKey: .kind),
            title: container.decode(String.self, forKey: .title),
            currentVersion: container.decode(ArtifactVersionRef.self, forKey: .currentVersion),
            lifecycleStatus: container.decode(LifecycleStatus.self, forKey: .lifecycleStatus),
            validationState: container.decode(ValidationState.self, forKey: .validationState),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case kind
        case title
        case currentVersion = "current_version"
        case lifecycleStatus = "lifecycle_status"
        case validationState = "validation_state"
        case dataClassification = "data_classification"
    }
}

/// One immutable context snapshot for a Conversation message.
public struct ConversationContext: Codable, Hashable, Sendable, DomainValidatable {
    public let kind: ConversationContextKind
    public let researchWorkspaceID: ResearchWorkspaceID?
    public let referencedRevisions: [SemanticRevisionReference]
    public let dataClassification: DataClassification

    public init(
        kind: ConversationContextKind,
        researchWorkspaceID: ResearchWorkspaceID? = nil,
        referencedRevisions: [SemanticRevisionReference],
        dataClassification: DataClassification
    ) throws {
        self.kind = kind
        self.researchWorkspaceID = researchWorkspaceID
        self.referencedRevisions = referencedRevisions.sorted()
        self.dataClassification = dataClassification
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !kind.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "kind",
                    "The Conversation context kind is not supported."
                )
            )
        }
        switch kind {
        case .meeting:
            if researchWorkspaceID != nil {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "research_workspace_id",
                        "A Meeting Conversation cannot claim a Research workspace identity."
                    )
                )
            }
            if !referencedRevisions.contains(where: { $0.objectType == .meetingProfile }) {
                issues.append(
                    researchIssue(
                        .missingRequiredValue,
                        "referenced_revisions",
                        "A Meeting Conversation requires an exact MeetingProfile revision."
                    )
                )
            }
        case .research:
            if researchWorkspaceID == nil {
                issues.append(
                    researchIssue(
                        .missingRequiredValue,
                        "research_workspace_id",
                        "A Research Conversation requires its distinct logical workspace identity."
                    )
                )
            }
        case .unrecognized:
            break
        }
        if Set(referencedRevisions).count != referencedRevisions.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "referenced_revisions",
                    "Conversation context revisions must be unique."
                )
            )
        }
        for reference in referencedRevisions {
            issues += reference.validationIssues()
        }
        if !dataClassification.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "data_classification",
                    "The Conversation classification is not supported."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(ConversationContextKind.self, forKey: .kind),
            researchWorkspaceID: container.decodeIfPresent(
                ResearchWorkspaceID.self,
                forKey: .researchWorkspaceID
            ),
            referencedRevisions: container.decode(
                [SemanticRevisionReference].self,
                forKey: .referencedRevisions
            ),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case researchWorkspaceID = "research_workspace_id"
        case referencedRevisions = "referenced_revisions"
        case dataClassification = "data_classification"
    }
}

/// An immutable append-only Conversation value. It is not a Meeting fact,
/// evidence object, automation event, or MCP message.
public struct ConversationMessage: Codable, Hashable, Sendable, DomainValidatable {
    public let messageID: MessageID
    public let conversationID: ConversationID
    public let sequence: UInt64
    public let role: ConversationRole
    public let content: String
    public let context: ConversationContext
    public let instructionSnapshotID: InstructionSnapshotID
    public let providerMetadata: ProviderMetadata?
    public let runIdentifier: String?
    public let createdAt: UTCInstant

    public init(
        messageID: MessageID,
        conversationID: ConversationID,
        sequence: UInt64,
        role: ConversationRole,
        content: String,
        context: ConversationContext,
        instructionSnapshotID: InstructionSnapshotID,
        providerMetadata: ProviderMetadata? = nil,
        runIdentifier: String? = nil,
        createdAt: UTCInstant
    ) throws {
        self.messageID = messageID
        self.conversationID = conversationID
        self.sequence = sequence
        self.role = role
        self.content = content
        self.context = context
        self.instructionSnapshotID = instructionSnapshotID
        self.providerMetadata = providerMetadata
        self.runIdentifier = runIdentifier
        self.createdAt = createdAt
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if sequence == 0 {
            issues.append(
                researchIssue(
                    .invalidRange,
                    "sequence",
                    "Conversation message sequence numbers are one-based."
                )
            )
        }
        if !role.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "role",
                    "The Conversation role is not supported."
                )
            )
        }
        issues += researchPreservedTextIssues(
            content,
            path: "content",
            maximumUTF8Bytes: 65_536
        )
        issues += context.validationIssues()
        if role == .user, providerMetadata != nil || runIdentifier != nil {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "provider_metadata",
                    "User-authored messages cannot claim provider or run provenance."
                )
            )
        }
        if let providerMetadata {
            issues += providerMetadata.validationIssues()
        }
        if let runIdentifier {
            issues += researchOpaqueIdentifierIssues(
                runIdentifier,
                path: "run_identifier",
                maximumUTF8Bytes: 128
            )
        }
        issues += createdAt.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            messageID: container.decode(MessageID.self, forKey: .messageID),
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            sequence: container.decode(UInt64.self, forKey: .sequence),
            role: container.decode(ConversationRole.self, forKey: .role),
            content: container.decode(String.self, forKey: .content),
            context: container.decode(ConversationContext.self, forKey: .context),
            instructionSnapshotID: container.decode(
                InstructionSnapshotID.self,
                forKey: .instructionSnapshotID
            ),
            providerMetadata: container.decodeIfPresent(
                ProviderMetadata.self,
                forKey: .providerMetadata
            ),
            runIdentifier: container.decodeIfPresent(String.self, forKey: .runIdentifier),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case conversationID = "conversation_id"
        case sequence
        case role
        case content
        case context
        case instructionSnapshotID = "instruction_snapshot_id"
        case providerMetadata = "provider_metadata"
        case runIdentifier = "run_identifier"
        case createdAt = "created_at"
    }
}

/// A pure value-layer append operation. It creates a new history and has no
/// repository, database, retention, or UI behavior.
public struct ConversationHistory: Codable, Hashable, Sendable, DomainValidatable {
    public let conversationID: ConversationID
    public let messages: [ConversationMessage]

    public init(conversationID: ConversationID, messages: [ConversationMessage] = []) throws {
        self.conversationID = conversationID
        self.messages = messages
        try validate()
    }

    public func appending(_ message: ConversationMessage) throws -> Self {
        try Self(conversationID: conversationID, messages: messages + [message])
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if messages.count > 10_000 {
            issues.append(
                researchIssue(
                    .invalidRange,
                    "messages",
                    "A single in-memory Conversation history is bounded to 10,000 messages."
                )
            )
        }
        if Set(messages.map(\.messageID)).count != messages.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "messages.message_id",
                    "Conversation message identities must be unique."
                )
            )
        }
        for (index, message) in messages.enumerated() {
            issues += message.validationIssues()
            if message.conversationID != conversationID {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "messages[\(index)].conversation_id",
                        "Every message must belong to the enclosing Conversation."
                    )
                )
            }
            if message.sequence != UInt64(index + 1) {
                issues.append(
                    researchIssue(
                        .inconsistentValue,
                        "messages[\(index)].sequence",
                        "Conversation messages must form one append-only contiguous sequence."
                    )
                )
            }
            if index > 0 {
                let prior = messages[index - 1]
                if message.createdAt < prior.createdAt {
                    issues.append(
                        researchIssue(
                            .invalidRange,
                            "messages[\(index)].created_at",
                            "Appended messages cannot precede the prior message."
                        )
                    )
                }
                if message.context.kind != prior.context.kind {
                    issues.append(
                        researchIssue(
                            .inconsistentValue,
                            "messages[\(index)].context.kind",
                            "A Conversation cannot switch between Meeting and Research contexts."
                        )
                    )
                }
            }
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            messages: container.decode([ConversationMessage].self, forKey: .messages)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case messages
    }
}

/// A small structured value vocabulary for instruction settings. It is not a
/// compiled prompt and does not accept executable content.
public enum InstructionScalarValue: Codable, Hashable, Sendable, DomainValidatable {
    case boolean(Bool)
    case integer(Int64)
    case text(String)

    public func validationIssues() -> [ValidationIssue] {
        guard case let .text(value) = self else { return [] }
        return researchPreservedTextIssues(
            value,
            path: "instruction_value.text",
            maximumUTF8Bytes: 4_096
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodingKind.self, forKey: .kind) {
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .integer:
            self = .integer(try container.decode(Int64.self, forKey: .integer))
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .boolean(value):
            try container.encode(EncodingKind.boolean, forKey: .kind)
            try container.encode(value, forKey: .boolean)
        case let .integer(value):
            try container.encode(EncodingKind.integer, forKey: .kind)
            try container.encode(value, forKey: .integer)
        case let .text(value):
            try container.encode(EncodingKind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        }
    }

    private enum EncodingKind: String, Codable {
        case boolean
        case integer
        case text
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case boolean
        case integer
        case text
    }
}

public struct InstructionSetting: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let key: String
    public let value: InstructionScalarValue

    public init(key: String, value: InstructionScalarValue) throws {
        self.key = key
        self.value = value
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.key < rhs.key
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = Self.keyIssues(key)
        issues += value.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            value: container.decode(InstructionScalarValue.self, forKey: .value)
        )
    }

    private static func keyIssues(_ value: String) -> [ValidationIssue] {
        let bytes = Array(value.utf8)
        let allowed = bytes.allSatisfy { byte in
            (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45
                || byte == 46
                || byte == 95
        }
        let reservedRoots = [
            "classification",
            "citation",
            "diplomatic_rules",
            "evidence",
            "factual_rules",
            "human_confirmation",
            "network",
            "policy",
            "prompt_injection",
            "provider",
            "retention",
            "tool_authority"
        ]
        let firstComponent = value.split(separator: ".", maxSplits: 1).first.map(String.init)
        guard
            !bytes.isEmpty,
            bytes.count <= 128,
            allowed,
            bytes.first != 46,
            bytes.last != 46,
            !value.contains(".."),
            firstComponent.map({ !reservedRoots.contains($0) }) == true
        else {
            return [
                researchIssue(
                    .invalidFormat,
                    "instruction_setting.key",
                    "Instruction keys must be bounded lowercase paths outside protected policy namespaces."
                )
            ]
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case value
    }
}

public struct InstructionProfileReference:
    Codable,
    Hashable,
    Sendable,
    Comparable,
    DomainValidatable
{
    public let profileID: InstructionProfileID
    public let scope: InstructionProfileScope
    public let version: UInt32

    public init(
        profileID: InstructionProfileID,
        scope: InstructionProfileScope,
        version: UInt32
    ) throws {
        self.profileID = profileID
        self.scope = scope
        self.version = version
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.scope != rhs.scope {
            return lhs.scope < rhs.scope
        }
        return lhs.profileID < rhs.profileID
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !scope.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "scope",
                    "The instruction profile scope is not supported."
                )
            )
        }
        if version == 0 {
            issues.append(
                researchIssue(
                    .invalidRange,
                    "version",
                    "Instruction profile versions are one-based."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profileID: container.decode(InstructionProfileID.self, forKey: .profileID),
            scope: container.decode(InstructionProfileScope.self, forKey: .scope),
            version: container.decode(UInt32.self, forKey: .version)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case scope
        case version
    }
}

public struct InstructionProfile: Codable, Hashable, Sendable, DomainValidatable {
    public let reference: InstructionProfileReference
    public let settings: [InstructionSetting]

    public init(reference: InstructionProfileReference, settings: [InstructionSetting]) throws {
        self.reference = reference
        self.settings = settings.sorted()
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = reference.validationIssues()
        if settings.count > 128 {
            issues.append(
                researchIssue(
                    .invalidRange,
                    "settings",
                    "An instruction profile is bounded to 128 structured settings."
                )
            )
        }
        if Set(settings.map(\.key)).count != settings.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "settings.key",
                    "An instruction profile cannot define one key twice."
                )
            )
        }
        for setting in settings {
            issues += setting.validationIssues()
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: container.decode(InstructionProfileReference.self, forKey: .reference),
            settings: container.decode([InstructionSetting].self, forKey: .settings)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case reference
        case settings
    }
}

/// Non-overridable policy is typed separately from user instruction settings.
/// Phase 1 authorizes no external destination and no executable tool authority.
public struct ProtectedInstructionPolicy: Codable, Hashable, Sendable, DomainValidatable {
    public let policyVersion: VersionedComponent
    public let dataClassification: DataClassification
    public let noOutboundMode: Bool
    public let destination: ModelDestinationPolicy
    public let retentionPolicy: ProviderRetentionPolicy
    public let toolAuthority: InstructionToolAuthority
    public let evidenceRequired: Bool
    public let citationsRequired: Bool
    public let humanConfirmationRequired: Bool
    public let promptInjectionIsolationRequired: Bool
    public let factualValidationRequired: Bool

    public init(
        policyVersion: VersionedComponent,
        dataClassification: DataClassification,
        noOutboundMode: Bool = true,
        destination: ModelDestinationPolicy = .localDevice,
        retentionPolicy: ProviderRetentionPolicy = .localWorkspaceOnly,
        toolAuthority: InstructionToolAuthority = .none,
        evidenceRequired: Bool = true,
        citationsRequired: Bool = true,
        humanConfirmationRequired: Bool = true,
        promptInjectionIsolationRequired: Bool = true,
        factualValidationRequired: Bool = true
    ) throws {
        self.policyVersion = policyVersion
        self.dataClassification = dataClassification
        self.noOutboundMode = noOutboundMode
        self.destination = destination
        self.retentionPolicy = retentionPolicy
        self.toolAuthority = toolAuthority
        self.evidenceRequired = evidenceRequired
        self.citationsRequired = citationsRequired
        self.humanConfirmationRequired = humanConfirmationRequired
        self.promptInjectionIsolationRequired = promptInjectionIsolationRequired
        self.factualValidationRequired = factualValidationRequired
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = policyVersion.validationIssues()
        if !dataClassification.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "data_classification",
                    "Instruction policy requires a known classification."
                )
            )
        }
        if !toolAuthority.isKnown {
            issues.append(
                researchIssue(
                    .unsupportedValue,
                    "tool_authority",
                    "Instruction policy requires a known tool-authority boundary."
                )
            )
        } else if toolAuthority != .none {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "tool_authority",
                    "Phase 1 grants no executable tool authority."
                )
            )
        }
        if !noOutboundMode
            || destination != .localDevice
            || retentionPolicy != .localWorkspaceOnly
        {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "provider_policy",
                    "Phase 1 instruction policy is local-only and grants no outbound route."
                )
            )
        }
        if !evidenceRequired
            || !citationsRequired
            || !humanConfirmationRequired
            || !promptInjectionIsolationRequired
            || !factualValidationRequired
        {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "protected_requirements",
                    "Protected evidence, citation, confirmation, injection, and factual rules cannot be disabled."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            policyVersion: container.decode(VersionedComponent.self, forKey: .policyVersion),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            noOutboundMode: container.decode(Bool.self, forKey: .noOutboundMode),
            destination: container.decode(ModelDestinationPolicy.self, forKey: .destination),
            retentionPolicy: container.decode(
                ProviderRetentionPolicy.self,
                forKey: .retentionPolicy
            ),
            toolAuthority: container.decode(
                InstructionToolAuthority.self,
                forKey: .toolAuthority
            ),
            evidenceRequired: container.decode(Bool.self, forKey: .evidenceRequired),
            citationsRequired: container.decode(Bool.self, forKey: .citationsRequired),
            humanConfirmationRequired: container.decode(
                Bool.self,
                forKey: .humanConfirmationRequired
            ),
            promptInjectionIsolationRequired: container.decode(
                Bool.self,
                forKey: .promptInjectionIsolationRequired
            ),
            factualValidationRequired: container.decode(
                Bool.self,
                forKey: .factualValidationRequired
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case dataClassification = "data_classification"
        case noOutboundMode = "no_outbound_mode"
        case destination
        case retentionPolicy = "retention_policy"
        case toolAuthority = "tool_authority"
        case evidenceRequired = "evidence_required"
        case citationsRequired = "citations_required"
        case humanConfirmationRequired = "human_confirmation_required"
        case promptInjectionIsolationRequired = "prompt_injection_isolation_required"
        case factualValidationRequired = "factual_validation_required"
    }
}

/// Immutable instruction snapshot containing canonical structured
/// configuration only. Full compiled prompt text is intentionally absent.
public struct InstructionSnapshot: Codable, Hashable, Sendable, DomainValidatable {
    public let snapshotID: InstructionSnapshotID
    public let protectedPolicy: ProtectedInstructionPolicy
    public let protectedRuleModules: [VersionedComponent]
    public let profileVersions: [InstructionProfileReference]
    public let canonicalConfiguration: [InstructionSetting]
    public let configurationHash: ContentDigest
    public let createdAt: UTCInstant

    public init(
        snapshotID: InstructionSnapshotID,
        protectedPolicy: ProtectedInstructionPolicy,
        protectedRuleModules: [VersionedComponent],
        profileVersions: [InstructionProfileReference],
        canonicalConfiguration: [InstructionSetting],
        createdAt: UTCInstant,
        configurationHash: ContentDigest? = nil
    ) throws {
        self.snapshotID = snapshotID
        self.protectedPolicy = protectedPolicy
        self.protectedRuleModules = protectedRuleModules.sorted()
        self.profileVersions = profileVersions.sorted()
        self.canonicalConfiguration = canonicalConfiguration.sorted()
        self.createdAt = createdAt
        self.configurationHash = try configurationHash ?? Self.hash(
            protectedPolicy: protectedPolicy,
            protectedRuleModules: protectedRuleModules.sorted(),
            profileVersions: profileVersions.sorted(),
            canonicalConfiguration: canonicalConfiguration.sorted()
        )
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = protectedPolicy.validationIssues()
        if protectedRuleModules.isEmpty {
            issues.append(
                researchIssue(
                    .missingRequiredValue,
                    "protected_rule_modules",
                    "At least one exact protected diplomatic or factual rule module is required."
                )
            )
        }
        if Set(protectedRuleModules.map(\.identifier)).count != protectedRuleModules.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "protected_rule_modules.identifier",
                    "Protected rule module identifiers must be unique."
                )
            )
        }
        for module in protectedRuleModules {
            issues += module.validationIssues()
        }
        if Set(profileVersions.map(\.scope)).count != profileVersions.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "profile_versions.scope",
                    "An instruction snapshot may contain at most one profile per precedence layer."
                )
            )
        }
        for profile in profileVersions {
            issues += profile.validationIssues()
        }
        if Set(canonicalConfiguration.map(\.key)).count != canonicalConfiguration.count {
            issues.append(
                researchIssue(
                    .duplicateValue,
                    "canonical_configuration.key",
                    "Canonical instruction settings must have unique keys."
                )
            )
        }
        for setting in canonicalConfiguration {
            issues += setting.validationIssues()
        }
        issues += configurationHash.validationIssues()
        if configurationHash != (try? Self.hash(
            protectedPolicy: protectedPolicy,
            protectedRuleModules: protectedRuleModules,
            profileVersions: profileVersions,
            canonicalConfiguration: canonicalConfiguration
        )) {
            issues.append(
                researchIssue(
                    .inconsistentValue,
                    "configuration_hash",
                    "The instruction snapshot hash must match the canonical structured configuration."
                )
            )
        }
        issues += createdAt.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            snapshotID: container.decode(InstructionSnapshotID.self, forKey: .snapshotID),
            protectedPolicy: container.decode(
                ProtectedInstructionPolicy.self,
                forKey: .protectedPolicy
            ),
            protectedRuleModules: container.decode(
                [VersionedComponent].self,
                forKey: .protectedRuleModules
            ),
            profileVersions: container.decode(
                [InstructionProfileReference].self,
                forKey: .profileVersions
            ),
            canonicalConfiguration: container.decode(
                [InstructionSetting].self,
                forKey: .canonicalConfiguration
            ),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            configurationHash: container.decode(ContentDigest.self, forKey: .configurationHash)
        )
    }

    private static func hash(
        protectedPolicy: ProtectedInstructionPolicy,
        protectedRuleModules: [VersionedComponent],
        profileVersions: [InstructionProfileReference],
        canonicalConfiguration: [InstructionSetting]
    ) throws -> ContentDigest {
        try researchCanonicalHash(
            HashProjection(
                protectedPolicy: protectedPolicy,
                protectedRuleModules: protectedRuleModules,
                profileVersions: profileVersions,
                canonicalConfiguration: canonicalConfiguration
            )
        )
    }

    private struct HashProjection: Codable {
        let protectedPolicy: ProtectedInstructionPolicy
        let protectedRuleModules: [VersionedComponent]
        let profileVersions: [InstructionProfileReference]
        let canonicalConfiguration: [InstructionSetting]

        private enum CodingKeys: String, CodingKey {
            case protectedPolicy = "protected_policy"
            case protectedRuleModules = "protected_rule_modules"
            case profileVersions = "profile_versions"
            case canonicalConfiguration = "canonical_configuration"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case protectedPolicy = "protected_policy"
        case protectedRuleModules = "protected_rule_modules"
        case profileVersions = "profile_versions"
        case canonicalConfiguration = "canonical_configuration"
        case configurationHash = "configuration_hash"
        case createdAt = "created_at"
    }
}

/// Deterministic Global -> Template -> Research workspace -> Request compiler.
/// Protected policy is a separate typed input and cannot be shadowed by a
/// profile setting.
public struct InstructionCompiler: Sendable {
    public init() {}

    public func compile(
        snapshotID: InstructionSnapshotID,
        protectedPolicy: ProtectedInstructionPolicy,
        protectedRuleModules: [VersionedComponent],
        profiles: [InstructionProfile],
        createdAt: UTCInstant
    ) throws -> InstructionSnapshot {
        for profile in profiles {
            try profile.validate()
        }
        let sortedProfiles = profiles.sorted { $0.reference < $1.reference }
        guard Set(sortedProfiles.map(\.reference.scope)).count == sortedProfiles.count else {
            throw DomainValidationError(
                issues: [
                    researchIssue(
                        .duplicateValue,
                        "profiles.scope",
                        "Instruction compilation accepts at most one profile per precedence layer."
                    )
                ]
            )
        }

        var merged: [String: InstructionScalarValue] = [:]
        for profile in sortedProfiles {
            for setting in profile.settings {
                merged[setting.key] = setting.value
            }
        }
        let configuration = try merged
            .map { try InstructionSetting(key: $0.key, value: $0.value) }
            .sorted()
        return try InstructionSnapshot(
            snapshotID: snapshotID,
            protectedPolicy: protectedPolicy,
            protectedRuleModules: protectedRuleModules,
            profileVersions: sortedProfiles.map(\.reference),
            canonicalConfiguration: configuration,
            createdAt: createdAt
        )
    }
}

private func researchIssue(
    _ code: ValidationIssueCode,
    _ path: String,
    _ message: String
) -> ValidationIssue {
    ValidationIssue(code: code, path: path, message: message)
}

private func researchBoundedTextIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        value == trimmed,
        !value.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
        return [
            researchIssue(
                .invalidFormat,
                path,
                "The value must be non-empty, trimmed, bounded text without control characters."
            )
        ]
    }
    return []
}

private func researchPreservedTextIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    guard
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.contains("\0")
    else {
        return [
            researchIssue(
                .invalidFormat,
                path,
                "Text must be non-empty, bounded, and contain no null byte."
            )
        ]
    }
    return []
}

private func researchOpaqueIdentifierIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        value == trimmed,
        !value.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.contains("/"),
        !value.contains("\\"),
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
        return [
            researchIssue(
                .invalidFormat,
                path,
                "The value must be a bounded opaque identifier, not a path."
            )
        ]
    }
    return []
}

private func researchCanonicalHash<Value: Encodable>(_ value: Value) throws -> ContentDigest {
    let digest = SHA256.hash(data: try CanonicalJSON.encode(value))
    let lowercaseHex = digest.map { String(format: "%02x", $0) }.joined()
    return try ContentDigest(algorithm: .sha256, lowercaseHex: lowercaseHex)
}
