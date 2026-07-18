import Foundation

/// A UUID-backed identifier whose phantom tag prevents cross-kind assignment.
public struct StableID<Tag>: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    let value: UUID

    public init(_ value: UUID) {
        self.value = value
    }

    public init(validating string: String) throws {
        guard let value = UUID(uuidString: string) else {
            throw DomainValidationError(
                issues: [
                    ValidationIssue(
                        code: .invalidFormat,
                        path: "id",
                        message: "A stable ID must be a canonical UUID string."
                    )
                ]
            )
        }
        self.value = value
    }

    public var canonicalString: String {
        value.uuidString.lowercased()
    }

    public var description: String {
        canonicalString
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.canonicalString < rhs.canonicalString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A stable ID must be a UUID string."
            )
        }
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }
}

public protocol LogicalObjectIDScope: Sendable {
    static var semanticObjectType: SemanticObjectType { get }
}

public enum LogicalObjectIDTag: Sendable {}
public enum RevisionIDTag: Sendable {}
public enum MeetingIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .meetingProfile }
}
public enum SourceAssetIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .sourceAsset }
}
public enum EvidenceIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .evidenceRef }
}
public enum TranscriptSegmentIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .transcriptSegment }
}
public enum TranslationSegmentIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .translationSegment }
}
public enum ActorIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .actor }
}
public enum SpeakingCapacityIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .speakingCapacity }
}
public enum SpeakerAssignmentIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .speakerAssignment }
}
public enum UserConfirmedNoteIDTag: LogicalObjectIDScope {
    public static var semanticObjectType: SemanticObjectType { .userConfirmedNote }
}
public enum StorageObjectIDTag: Sendable {}
public enum AgendaItemIDTag: Sendable {}
public enum BriefingTemplateIDTag: Sendable {}
public enum WorkspaceIDTag: Sendable {}
public enum TranscriptSetIDTag: Sendable {}
public enum TranscriptCoverageManifestIDTag: Sendable {}

public typealias LogicalObjectID = StableID<LogicalObjectIDTag>
public typealias RevisionID = StableID<RevisionIDTag>
public typealias MeetingID = StableID<MeetingIDTag>
public typealias SourceAssetID = StableID<SourceAssetIDTag>
public typealias EvidenceID = StableID<EvidenceIDTag>
public typealias TranscriptSegmentID = StableID<TranscriptSegmentIDTag>
public typealias TranslationSegmentID = StableID<TranslationSegmentIDTag>
public typealias ActorID = StableID<ActorIDTag>
public typealias SpeakingCapacityID = StableID<SpeakingCapacityIDTag>
public typealias SpeakerAssignmentID = StableID<SpeakerAssignmentIDTag>
public typealias UserConfirmedNoteID = StableID<UserConfirmedNoteIDTag>
public typealias StorageObjectID = StableID<StorageObjectIDTag>
public typealias AgendaItemID = StableID<AgendaItemIDTag>
public typealias BriefingTemplateID = StableID<BriefingTemplateIDTag>
public typealias WorkspaceID = StableID<WorkspaceIDTag>
public typealias TranscriptSetID = StableID<TranscriptSetIDTag>
public typealias TranscriptCoverageManifestID = StableID<TranscriptCoverageManifestIDTag>

/// An exact semantic revision reference, never a bare logical identifier.
public struct SemanticRevisionReference: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let objectType: SemanticObjectType
    public let logicalID: LogicalObjectID
    public let revisionID: RevisionID

    public init<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID
    ) throws {
        self.objectType = Tag.semanticObjectType
        self.logicalID = LogicalObjectID(logicalID.value)
        self.revisionID = revisionID
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !objectType.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "object_type",
                    message: "The object type is not supported by this contract version."
                )
            )
        }
        if logicalID.canonicalString == revisionID.canonicalString {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "revision_id",
                    message: "Logical and revision IDs must be distinct."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectType = try container.decode(SemanticObjectType.self, forKey: .objectType)
        logicalID = try container.decode(LogicalObjectID.self, forKey: .logicalID)
        revisionID = try container.decode(RevisionID.self, forKey: .revisionID)
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (
            lhs.objectType.encodedValue,
            lhs.logicalID.canonicalString,
            lhs.revisionID.canonicalString
        ) < (
            rhs.objectType.encodedValue,
            rhs.logicalID.canonicalString,
            rhs.revisionID.canonicalString
        )
    }

    private enum CodingKeys: String, CodingKey {
        case objectType = "object_type"
        case logicalID = "logical_id"
        case revisionID = "revision_id"
    }
}
