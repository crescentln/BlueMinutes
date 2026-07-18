import Foundation

/// Storage-neutral active pointer. Historical published revisions remain published.
public struct ActivePublishedRevisionSelection<ObjectIDTag: LogicalObjectIDScope>: Codable, Hashable, Sendable, DomainValidatable {
    public let logicalID: StableID<ObjectIDTag>
    public let revisionID: RevisionID
    public let objectType: SemanticObjectType

    public init(logicalID: StableID<ObjectIDTag>, revisionID: RevisionID) throws {
        self.logicalID = logicalID
        self.revisionID = revisionID
        self.objectType = ObjectIDTag.semanticObjectType
        try validate()
    }

    public var reference: SemanticRevisionReference {
        get throws {
            try SemanticRevisionReference(logicalID: logicalID, revisionID: revisionID)
        }
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !objectType.isKnown {
            issues.append(Self.issue(.unsupportedValue, "object_type", "The selected object type is not supported by this contract version."))
        }
        if objectType != ObjectIDTag.semanticObjectType {
            issues.append(Self.issue(.inconsistentValue, "object_type", "The active selection type must match its logical-ID scope."))
        }
        if logicalID.canonicalString == revisionID.canonicalString {
            issues.append(Self.issue(.inconsistentValue, "revision_id", "Logical and revision IDs must be distinct."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalID = try container.decode(StableID<ObjectIDTag>.self, forKey: .logicalID)
        revisionID = try container.decode(RevisionID.self, forKey: .revisionID)
        objectType = try container.decode(SemanticObjectType.self, forKey: .objectType)
        try validate()
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private enum CodingKeys: String, CodingKey {
        case logicalID = "logical_id"
        case revisionID = "revision_id"
        case objectType = "object_type"
    }
}

/// A pointer move, including first publication and idempotent reselection.
public struct ActivePublishedRevisionChange: Codable, Hashable, Sendable, DomainValidatable {
    public let previous: SemanticRevisionReference?
    public let replacement: SemanticRevisionReference

    public init<Tag: LogicalObjectIDScope>(
        previous: ActivePublishedRevisionSelection<Tag>?,
        replacement: ActivePublishedRevisionSelection<Tag>
    ) throws {
        self.previous = try previous?.reference
        self.replacement = try replacement.reference
        try validate()
    }

    public var isInitialPublication: Bool { previous == nil }
    public var isNoOp: Bool { previous == replacement }

    public func validationIssues() -> [ValidationIssue] {
        var issues = replacement.validationIssues()
        if let previous {
            issues.append(contentsOf: previous.validationIssues())
            if previous.objectType != replacement.objectType {
                issues.append(Self.issue(.inconsistentValue, "replacement.object_type", "An active pointer cannot move across object types."))
            }
            if previous.logicalID != replacement.logicalID {
                issues.append(Self.issue(.inconsistentValue, "replacement.logical_id", "An active pointer cannot move across logical objects."))
            }
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        previous = try container.decodeIfPresent(SemanticRevisionReference.self, forKey: .previous)
        replacement = try container.decode(SemanticRevisionReference.self, forKey: .replacement)
        try validate()
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private enum CodingKeys: String, CodingKey {
        case previous
        case replacement
    }
}

/// Pure selection logic; no timestamp or list order can imply active status.
public enum ActivePublishedRevisionSelector {
    public static func select<Object: SemanticRevisionContract>(
        _ selection: ActivePublishedRevisionSelection<Object.ObjectIDTag>,
        from revisions: [Object]
    ) throws -> Object {
        try selection.validate()
        let matches = revisions.filter {
            $0.revision.logicalID == selection.logicalID
                && $0.revision.revisionID == selection.revisionID
        }
        guard matches.count == 1, let selected = matches.first else {
            let issue: ValidationIssue
            if matches.isEmpty {
                issue = ValidationIssue(
                    code: .missingRequiredValue,
                    path: "active_revision",
                    message: "The explicit active revision was not found."
                )
            } else {
                issue = ValidationIssue(
                    code: .duplicateValue,
                    path: "active_revision",
                    message: "The explicit active revision appears more than once."
                )
            }
            throw DomainValidationError(issues: [issue])
        }

        try selected.validate()
        var issues: [ValidationIssue] = []
        if selected.revision.lifecycleStatus != .published {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "active_revision.lifecycle_status",
                    message: "Only a published revision may be selected as active."
                )
            )
        }
        if selected.revision.validationState != .valid {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "active_revision.validation_state",
                    message: "Only a valid revision may be selected as active."
                )
            )
        }
        if selected.revision.semanticContentHash == nil {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "active_revision.semantic_content_hash",
                    message: "An active published revision requires a verified semantic hash."
                )
            )
        }
        guard issues.isEmpty else { throw DomainValidationError(issues: issues) }
        return selected
    }

    public static func validateUniqueSelections<Tag: LogicalObjectIDScope>(
        _ selections: [ActivePublishedRevisionSelection<Tag>]
    ) throws {
        for selection in selections { try selection.validate() }
        let issues = duplicateIssues(in: selections.map(\.logicalID), path: "active_selections.logical_id")
        guard issues.isEmpty else { throw DomainValidationError(issues: issues) }
    }
}
