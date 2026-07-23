import Foundation

// These IDs intentionally do not conform to LogicalObjectIDScope. Phase 1
// reserves contract identities without extending the persisted semantic-object
// vocabulary or SQLite schema.
public enum ResearchWorkspaceIDTag: Sendable {}
public enum ArtifactIDTag: Sendable {}
public enum ArtifactVersionIDTag: Sendable {}
public enum ConversationIDTag: Sendable {}
public enum MessageIDTag: Sendable {}
public enum InstructionProfileIDTag: Sendable {}
public enum InstructionSnapshotIDTag: Sendable {}

public typealias ResearchWorkspaceID = StableID<ResearchWorkspaceIDTag>
public typealias ArtifactID = StableID<ArtifactIDTag>
public typealias ArtifactVersionID = StableID<ArtifactVersionIDTag>
public typealias ConversationID = StableID<ConversationIDTag>
public typealias MessageID = StableID<MessageIDTag>
public typealias InstructionProfileID = StableID<InstructionProfileIDTag>
public typealias InstructionSnapshotID = StableID<InstructionSnapshotIDTag>

/// A logical Research collection kind. It is distinct from the physical
/// WorkspaceID used to authorize one local data root.
public enum ResearchWorkspaceKind: StableStringValue {
    case meetingResearch
    case resolution
    case document
    case topic
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "meeting_research": self = .meetingResearch
        case "resolution": self = .resolution
        case "document": self = .document
        case "topic": self = .topic
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .meetingResearch: "meeting_research"
        case .resolution: "resolution"
        case .document: "document"
        case .topic: "topic"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// A descriptive source category. It is not an authority ranking.
public enum SharedSourceKind: StableStringValue {
    case meetingSourceAsset
    case importedTranscript
    case officialTranscript
    case officialRecord
    case externalDocument
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "meeting_source_asset": self = .meetingSourceAsset
        case "imported_transcript": self = .importedTranscript
        case "official_transcript": self = .officialTranscript
        case "official_record": self = .officialRecord
        case "external_document": self = .externalDocument
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .meetingSourceAsset: "meeting_source_asset"
        case .importedTranscript: "imported_transcript"
        case .officialTranscript: "official_transcript"
        case .officialRecord: "official_record"
        case .externalDocument: "external_document"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// Records the basis of an authority claim without defining cross-source
/// precedence. URLs, filenames, and Meeting metadata never imply a value here.
public enum SourceAuthority: StableStringValue {
    case unknown
    case unverified
    case userAsserted
    case providerAsserted
    case independentlyVerified
    case official
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unknown": self = .unknown
        case "unverified": self = .unverified
        case "user_asserted": self = .userAsserted
        case "provider_asserted": self = .providerAsserted
        case "independently_verified": self = .independentlyVerified
        case "official": self = .official
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unknown: "unknown"
        case .unverified: "unverified"
        case .userAsserted: "user_asserted"
        case .providerAsserted: "provider_asserted"
        case .independentlyVerified: "independently_verified"
        case .official: "official"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// Describes source completeness without fabricating timing or alignment.
public enum SourceCompleteness: StableStringValue {
    case unknown
    case partial
    case complete
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unknown": self = .unknown
        case "partial": self = .partial
        case "complete": self = .complete
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unknown: "unknown"
        case .partial: "partial"
        case .complete: "complete"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum SourceCanonicalKeyClaimBasis: StableStringValue {
    case unclaimed
    case userAsserted
    case providerAsserted
    case applicationVerified
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unclaimed": self = .unclaimed
        case "user_asserted": self = .userAsserted
        case "provider_asserted": self = .providerAsserted
        case "application_verified": self = .applicationVerified
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unclaimed: "unclaimed"
        case .userAsserted: "user_asserted"
        case .providerAsserted: "provider_asserted"
        case .applicationVerified: "application_verified"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum ArtifactKind: StableStringValue {
    case meetingBriefing
    case historicalComparison
    case researchArtifact
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "meeting_briefing": self = .meetingBriefing
        case "historical_comparison": self = .historicalComparison
        case "research_artifact": self = .researchArtifact
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .meetingBriefing: "meeting_briefing"
        case .historicalComparison: "historical_comparison"
        case .researchArtifact: "research_artifact"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum ConversationContextKind: StableStringValue {
    case meeting
    case research
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "meeting": self = .meeting
        case "research": self = .research
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .meeting: "meeting"
        case .research: "research"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum ConversationRole: StableStringValue {
    case user
    case assistant
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "user": self = .user
        case "assistant": self = .assistant
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .user: "user"
        case .assistant: "assistant"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum InstructionProfileScope: StableStringValue, Comparable {
    case global
    case template
    case researchWorkspace
    case request
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "global": self = .global
        case "template": self = .template
        case "research_workspace": self = .researchWorkspace
        case "request": self = .request
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .global: "global"
        case .template: "template"
        case .researchWorkspace: "research_workspace"
        case .request: "request"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public var precedence: Int {
        switch self {
        case .global: 0
        case .template: 1
        case .researchWorkspace: 2
        case .request: 3
        case .unrecognized: 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.precedence != rhs.precedence {
            return lhs.precedence < rhs.precedence
        }
        return lhs.encodedValue < rhs.encodedValue
    }
}

public enum InstructionToolAuthority: StableStringValue {
    case none
    case boundedReadOnly
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "none": self = .none
        case "bounded_read_only": self = .boundedReadOnly
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .none: "none"
        case .boundedReadOnly: "bounded_read_only"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum CitationVerificationStatus: StableStringValue {
    case unverified
    case verified
    case invalid
    case unresolvable
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unverified": self = .unverified
        case "verified": self = .verified
        case "invalid": self = .invalid
        case "unresolvable": self = .unresolvable
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unverified: "unverified"
        case .verified: "verified"
        case .invalid: "invalid"
        case .unresolvable: "unresolvable"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}
