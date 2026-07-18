import Foundation

/// Immutable metadata shared by versioned semantic objects.
///
/// `semanticContentHash` identifies the concrete object's documented semantic
/// projection. The projection omits the hash itself and is distinct from a
/// SourceAsset's source-byte digest.
public struct RevisionEnvelope<ObjectIDTag: LogicalObjectIDScope>: Codable, Hashable, Sendable, DomainValidatable {
    public let logicalID: StableID<ObjectIDTag>
    public let revisionID: RevisionID
    public let objectType: SemanticObjectType
    public let schemaVersion: SchemaVersion
    public let lifecycleStatus: LifecycleStatus
    public let validationState: ValidationState
    public let createdAt: UTCInstant
    public let createdBy: CreationActor
    public let publishedAt: UTCInstant?
    public let supersedesRevisionID: RevisionID?
    public let inputRevisions: [SemanticRevisionReference]
    public let sourceAssetRevisions: [SemanticRevisionReference]
    public let evidenceRevisions: [SemanticRevisionReference]
    public let dataClassification: DataClassification
    public let generationMetadata: GenerationMetadata?
    public let semanticContentHash: ContentDigest?

    public init(
        logicalID: StableID<ObjectIDTag>,
        revisionID: RevisionID,
        schemaVersion: SchemaVersion,
        lifecycleStatus: LifecycleStatus,
        validationState: ValidationState,
        createdAt: UTCInstant,
        createdBy: CreationActor,
        publishedAt: UTCInstant? = nil,
        supersedesRevisionID: RevisionID? = nil,
        inputRevisions: [SemanticRevisionReference] = [],
        sourceAssetRevisions: [SemanticRevisionReference] = [],
        evidenceRevisions: [SemanticRevisionReference] = [],
        dataClassification: DataClassification,
        generationMetadata: GenerationMetadata? = nil,
        semanticContentHash: ContentDigest? = nil
    ) throws {
        self.logicalID = logicalID
        self.revisionID = revisionID
        self.objectType = ObjectIDTag.semanticObjectType
        self.schemaVersion = schemaVersion
        self.lifecycleStatus = lifecycleStatus
        self.validationState = validationState
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.publishedAt = publishedAt
        self.supersedesRevisionID = supersedesRevisionID
        self.inputRevisions = inputRevisions.sorted()
        self.sourceAssetRevisions = sourceAssetRevisions.sorted()
        self.evidenceRevisions = evidenceRevisions.sorted()
        self.dataClassification = dataClassification
        self.generationMetadata = generationMetadata
        self.semanticContentHash = semanticContentHash
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if logicalID.canonicalString == revisionID.canonicalString {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "revision_id",
                    message: "Logical and revision IDs must be distinct."
                )
            )
        }
        if !objectType.isKnown {
            issues.append(Self.unsupportedIssue(path: "object_type", noun: "object type"))
        }
        if objectType != ObjectIDTag.semanticObjectType {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "object_type",
                    message: "The object type does not match the logical ID scope."
                )
            )
        }
        issues.append(contentsOf: schemaVersion.validationIssues())
        if !lifecycleStatus.isKnown {
            issues.append(Self.unsupportedIssue(path: "lifecycle_status", noun: "lifecycle status"))
        }
        if !validationState.isKnown {
            issues.append(Self.unsupportedIssue(path: "validation_state", noun: "validation state"))
        }
        if !createdBy.isKnown {
            issues.append(Self.unsupportedIssue(path: "created_by", noun: "creation actor"))
        }
        if !dataClassification.isKnown {
            issues.append(Self.unsupportedIssue(path: "data_classification", noun: "data classification"))
        }

        switch lifecycleStatus {
        case .published:
            if publishedAt == nil {
                issues.append(
                    ValidationIssue(
                        code: .missingRequiredValue,
                        path: "published_at",
                        message: "A published revision requires a publication timestamp."
                    )
                )
            }
            if validationState != .valid {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "validation_state",
                        message: "A published revision must be valid."
                    )
                )
            }
            if semanticContentHash == nil {
                issues.append(
                    ValidationIssue(
                        code: .missingRequiredValue,
                        path: "semantic_content_hash",
                        message: "A published revision requires a semantic content hash."
                    )
                )
            }
        case .draft:
            if publishedAt != nil {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "published_at",
                        message: "A draft revision cannot have a publication timestamp."
                    )
                )
            }
        case .unrecognized:
            break
        }

        if let publishedAt, publishedAt < createdAt {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "published_at",
                    message: "Publication cannot precede creation."
                )
            )
        }
        if supersedesRevisionID?.canonicalString == revisionID.canonicalString {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "supersedes_revision_id",
                    message: "A revision cannot supersede itself."
                )
            )
        }

        issues.append(contentsOf: duplicateIssues(in: inputRevisions, path: "input_revisions"))
        issues.append(contentsOf: duplicateIssues(in: sourceAssetRevisions, path: "source_asset_revisions"))
        issues.append(contentsOf: duplicateIssues(in: evidenceRevisions, path: "evidence_revisions"))

        for reference in inputRevisions {
            issues.append(contentsOf: reference.validationIssues())
            if reference.revisionID == revisionID {
                issues.append(Self.selfDependencyIssue(path: "input_revisions"))
            }
        }
        for reference in sourceAssetRevisions {
            issues.append(contentsOf: reference.validationIssues())
            if reference.revisionID == revisionID {
                issues.append(Self.selfDependencyIssue(path: "source_asset_revisions"))
            }
            if reference.objectType != .sourceAsset {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "source_asset_revisions.object_type",
                        message: "Source-asset references must identify SourceAsset revisions."
                    )
                )
            }
        }
        for reference in evidenceRevisions {
            issues.append(contentsOf: reference.validationIssues())
            if reference.revisionID == revisionID {
                issues.append(Self.selfDependencyIssue(path: "evidence_revisions"))
            }
            if reference.objectType != .evidenceRef {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "evidence_revisions.object_type",
                        message: "Evidence references must identify EvidenceRef revisions."
                    )
                )
            }
        }

        if let generationMetadata {
            issues.append(contentsOf: generationMetadata.validationIssues())
            if generationMetadata.generatedAt > createdAt {
                issues.append(
                    ValidationIssue(
                        code: .invalidRange,
                        path: "generation_metadata.generated_at",
                        message: "Generation cannot occur after revision creation."
                    )
                )
            }
            if generationMetadata.outputSchemaVersion != schemaVersion {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "generation_metadata.output_schema_version",
                        message: "Generation metadata must record the enclosing revision schema version."
                    )
                )
            }
        }
        if createdBy == .provider, generationMetadata == nil {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "generation_metadata",
                    message: "Provider-created content requires provider-neutral generation metadata."
                )
            )
        }
        if let semanticContentHash {
            issues.append(contentsOf: semanticContentHash.validationIssues())
        }

        return issues
    }

    private static func selfDependencyIssue(path: String) -> ValidationIssue {
        ValidationIssue(
            code: .inconsistentValue,
            path: path,
            message: "A revision cannot depend on itself."
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalID = try container.decode(StableID<ObjectIDTag>.self, forKey: .logicalID)
        revisionID = try container.decode(RevisionID.self, forKey: .revisionID)
        objectType = try container.decode(SemanticObjectType.self, forKey: .objectType)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        lifecycleStatus = try container.decode(LifecycleStatus.self, forKey: .lifecycleStatus)
        validationState = try container.decode(ValidationState.self, forKey: .validationState)
        createdAt = try container.decode(UTCInstant.self, forKey: .createdAt)
        createdBy = try container.decode(CreationActor.self, forKey: .createdBy)
        publishedAt = try container.decodeIfPresent(UTCInstant.self, forKey: .publishedAt)
        supersedesRevisionID = try container.decodeIfPresent(
            RevisionID.self,
            forKey: .supersedesRevisionID
        )
        inputRevisions = try container.decodeIfPresent(
            [SemanticRevisionReference].self,
            forKey: .inputRevisions
        )?.sorted() ?? []
        sourceAssetRevisions = try container.decodeIfPresent(
            [SemanticRevisionReference].self,
            forKey: .sourceAssetRevisions
        )?.sorted() ?? []
        evidenceRevisions = try container.decodeIfPresent(
            [SemanticRevisionReference].self,
            forKey: .evidenceRevisions
        )?.sorted() ?? []
        dataClassification = try container.decode(
            DataClassification.self,
            forKey: .dataClassification
        )
        generationMetadata = try container.decodeIfPresent(
            GenerationMetadata.self,
            forKey: .generationMetadata
        )
        semanticContentHash = try container.decodeIfPresent(
            ContentDigest.self,
            forKey: .semanticContentHash
        )
        try validate()
    }

    private static func unsupportedIssue(path: String, noun: String) -> ValidationIssue {
        ValidationIssue(
            code: .unsupportedValue,
            path: path,
            message: "The \(noun) is not supported by this contract version."
        )
    }

    private enum CodingKeys: String, CodingKey {
        case logicalID = "logical_id"
        case revisionID = "revision_id"
        case objectType = "object_type"
        case schemaVersion = "schema_version"
        case lifecycleStatus = "lifecycle_status"
        case validationState = "validation_state"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case publishedAt = "published_at"
        case supersedesRevisionID = "supersedes_revision_id"
        case inputRevisions = "input_revisions"
        case sourceAssetRevisions = "source_asset_revisions"
        case evidenceRevisions = "evidence_revisions"
        case dataClassification = "data_classification"
        case generationMetadata = "generation_metadata"
        case semanticContentHash = "semantic_content_hash"
    }
}
