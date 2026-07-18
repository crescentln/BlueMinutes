import Foundation
import MeetingBuddyDomain

public enum PersistenceContractError: Error, Equatable, Sendable {
    case revisionConflict(RevisionID)
    case revisionNotFound(RevisionID)
    case logicalObjectMismatch
    case activeRevisionIntegrity(String)
    case dependencyIntegrity(String)
    case staleStateIntegrity(String)
    case managedAssetNotFound(StorageObjectID)
    case managedAssetConflict(StorageObjectID)
    case migrationFailed(String)
    case unsupportedStoredObjectType(String)
}

public struct PersistedStaleMark: Codable, Hashable, Sendable {
    public let mark: StaleMark
    public let markedAt: UTCInstant

    public init(mark: StaleMark, markedAt: UTCInstant) {
        self.mark = mark
        self.markedAt = markedAt
    }
}

public struct ActiveRevisionState<Object: SemanticRevisionContract>: Sendable {
    public let revision: Object
    public let staleMarks: [PersistedStaleMark]

    public init(revision: Object, staleMarks: [PersistedStaleMark]) {
        self.revision = revision
        self.staleMarks = staleMarks
    }

    public var isCurrent: Bool { staleMarks.isEmpty }
}

/// Storage port for immutable Task 003A/003B semantic revisions.
///
/// Implementations may insert a revision exactly once. Reinserting identical
/// canonical bytes is idempotent; reusing an ID for different bytes fails.
public protocol SemanticRevisionRepository: Sendable {
    func insert<Object: SemanticRevisionContract>(_ object: Object) throws

    func fetch<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        revisionID: RevisionID
    ) throws -> Object?

    func revisions<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        logicalID: StableID<Object.ObjectIDTag>
    ) throws -> [Object]

    func allRevisionReferences() throws -> [SemanticRevisionReference]
    func dependencyEdges() throws -> [DependencyEdge]

    func activeRevisionState<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        logicalID: StableID<Object.ObjectIDTag>
    ) throws -> ActiveRevisionState<Object>?

    /// Moves the active pointer and persists the deterministic stale plan in
    /// the same SQLite transaction. Historical revision bytes are unchanged.
    @discardableResult
    func activate<Object: SemanticRevisionContract>(
        _ selection: ActivePublishedRevisionSelection<Object.ObjectIDTag>,
        as type: Object.Type,
        expectedCurrentRevisionID: RevisionID?,
        handlingPolicies: [RevisionHandlingPolicy],
        markedAt: UTCInstant
    ) throws -> StalePlan

    func staleMarks(for revision: SemanticRevisionReference) throws -> [PersistedStaleMark]
}
