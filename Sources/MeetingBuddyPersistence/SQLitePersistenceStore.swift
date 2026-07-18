import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class SQLitePersistenceStore: SemanticRevisionRepository, @unchecked Sendable
{
    public let workspace: LocalWorkspaceDescriptor
    public let migrationOutcome: MigrationOutcome

    let databasePool: DatabasePool

    public convenience init(workspace: LocalWorkspaceDescriptor) throws {
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        try self.init(
            workspace: workspace,
            migrationTimestamp: UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
        )
    }

    public init(
        workspace: LocalWorkspaceDescriptor,
        migrationTimestamp: UTCInstant
    ) throws {
        let result = try SQLiteDatabaseBootstrap.open(
            workspace: workspace,
            migrationTimestamp: migrationTimestamp
        )
        self.workspace = workspace
        self.databasePool = result.databasePool
        self.migrationOutcome = result.outcome
    }

    init(
        workspace: LocalWorkspaceDescriptor,
        migrationTimestamp: UTCInstant,
        additionalMigrations: [SQLiteMigrationDefinition]
    ) throws {
        let result = try SQLiteDatabaseBootstrap.open(
            workspace: workspace,
            migrationTimestamp: migrationTimestamp,
            additionalMigrations: additionalMigrations
        )
        self.workspace = workspace
        self.databasePool = result.databasePool
        self.migrationOutcome = result.outcome
    }

    public func close() throws {
        try databasePool.close()
    }

    public func insert<Object: SemanticRevisionContract>(_ object: Object) throws {
        try ensureSupported(Object.self)
        try object.validate()
        let payload = try CanonicalJSON.encodeValidated(object)
        guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
            throw PersistenceContractError.revisionConflict(object.revision.revisionID)
        }
        do {
            try databasePool.write { db in
                if try existingRevisionMatches(object, payload: payload, in: db) {
                    return
                }
                try validateWorkspaceOwnership(object, in: db)
                if let sourceAsset = object as? SourceAssetV1 {
                    try validateManagedAssetBinding(sourceAsset, in: db)
                }
                try insertRevisionRow(object, payload: payload, in: db)
                for edge in try DependencyEdge.from(downstream: object.revision) {
                    try insert(edge: edge, in: db)
                }
                try db.execute(
                    sql: """
                    INSERT INTO revision_current_state(
                        object_type, logical_id, revision_id, currency_state, last_stale_at_ms
                    ) VALUES (?, ?, ?, 'current', NULL)
                    """,
                    arguments: [
                        object.revision.objectType.encodedValue,
                        object.revision.logicalID.canonicalString,
                        object.revision.revisionID.canonicalString
                    ]
                )
                if let sourceAsset = object as? SourceAssetV1,
                   let reference = sourceAsset.managedStorageReference
                {
                    try db.execute(
                        sql: """
                        INSERT INTO source_asset_file_bindings(
                            source_object_type,
                            source_logical_id,
                            source_revision_id,
                            storage_object_id
                        ) VALUES ('source_asset', ?, ?, ?)
                        """,
                        arguments: [
                            sourceAsset.assetID.canonicalString,
                            sourceAsset.revision.revisionID.canonicalString,
                            reference.storageObjectID.canonicalString
                        ]
                    )
                }
            }
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func fetch<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        revisionID: RevisionID
    ) throws -> Object? {
        try ensureSupported(type)
        return try databasePool.read { db in
            try fetch(type, revisionID: revisionID, in: db)
        }
    }

    public func revisions<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        logicalID: StableID<Object.ObjectIDTag>
    ) throws -> [Object] {
        try ensureSupported(type)
        return try databasePool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM semantic_revisions
                WHERE object_type = ? AND logical_id = ?
                ORDER BY created_at_ms, revision_id
                """,
                arguments: [Object.ObjectIDTag.semanticObjectType.encodedValue, logicalID.canonicalString]
            )
            return try rows.map { try decode(type, row: $0) }
        }
    }

    public func allRevisionReferences() throws -> [SemanticRevisionReference] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT object_type, logical_id, revision_id
                FROM semantic_revisions
                ORDER BY object_type, logical_id, revision_id
                """
            ).map { row in
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: row["object_type"],
                    logicalIDValue: row["logical_id"],
                    revisionIDValue: row["revision_id"]
                )
            }
        }
    }

    public func dependencyEdges() throws -> [DependencyEdge] {
        try databasePool.read { db in try dependencyEdges(in: db) }
    }

    public func activeRevisionState<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        logicalID: StableID<Object.ObjectIDTag>
    ) throws -> ActiveRevisionState<Object>? {
        try ensureSupported(type)
        return try databasePool.read { db in
            guard let revisionIDValue = try String.fetchOne(
                db,
                sql: """
                SELECT revision_id FROM active_published_revisions
                WHERE object_type = ? AND logical_id = ?
                """,
                arguments: [Object.ObjectIDTag.semanticObjectType.encodedValue, logicalID.canonicalString]
            ) else {
                return nil
            }
            let revisionID = try RevisionID(validating: revisionIDValue)
            guard let revision = try fetch(type, revisionID: revisionID, in: db) else {
                throw PersistenceContractError.activeRevisionIntegrity(
                    "The active pointer target is missing."
                )
            }
            let reference = try SemanticRevisionReference(
                logicalID: logicalID,
                revisionID: revisionID
            )
            return ActiveRevisionState(
                revision: revision,
                staleMarks: try staleMarks(for: reference, in: db)
            )
        }
    }

    @discardableResult
    public func activate<Object: SemanticRevisionContract>(
        _ selection: ActivePublishedRevisionSelection<Object.ObjectIDTag>,
        as type: Object.Type,
        expectedCurrentRevisionID: RevisionID?,
        handlingPolicies: [RevisionHandlingPolicy] = [],
        markedAt: UTCInstant
    ) throws -> StalePlan {
        try ensureSupported(type)
        try selection.validate()
        do {
            return try databasePool.write { db in
                guard let replacement = try fetch(
                    type,
                    revisionID: selection.revisionID,
                    in: db
                ) else {
                    throw PersistenceContractError.revisionNotFound(selection.revisionID)
                }
                _ = try ActivePublishedRevisionSelector.select(selection, from: [replacement])

                let state = try String.fetchOne(
                    db,
                    sql: """
                    SELECT currency_state FROM revision_current_state
                    WHERE object_type = ? AND logical_id = ? AND revision_id = ?
                    """,
                    arguments: [
                        selection.objectType.encodedValue,
                        selection.logicalID.canonicalString,
                        selection.revisionID.canonicalString
                    ]
                )
                guard state == "current" else {
                    throw PersistenceContractError.activeRevisionIntegrity(
                        "A stale revision cannot become the active published revision."
                    )
                }
                try validateCurrentDependencyClosure(
                    objectType: selection.objectType,
                    logicalID: selection.logicalID,
                    revisionID: selection.revisionID,
                    in: db
                )

                let pointer = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT revision_id, pointer_version
                    FROM active_published_revisions
                    WHERE object_type = ? AND logical_id = ?
                    """,
                    arguments: [selection.objectType.encodedValue, selection.logicalID.canonicalString]
                )
                let actualPreviousID = try pointer.map {
                    try RevisionID(validating: $0["revision_id"] as String)
                }
                guard actualPreviousID == expectedCurrentRevisionID else {
                    throw PersistenceContractError.activeRevisionIntegrity(
                        "The active pointer changed after the caller's expected state."
                    )
                }

                let previousSelection = try actualPreviousID.map {
                    try ActivePublishedRevisionSelection<Object.ObjectIDTag>(
                        logicalID: selection.logicalID,
                        revisionID: $0
                    )
                }
                let change = try ActivePublishedRevisionChange(
                    previous: previousSelection,
                    replacement: selection
                )
                let plan = try DeterministicStalePlanner.plan(
                    for: change,
                    dependencyEdges: dependencyEdges(in: db),
                    handlingPolicies: handlingPolicies
                )
                if change.isNoOp { return plan }

                let priorVersion: Int64 = pointer?["pointer_version"] ?? 0
                let nextVersion = priorVersion + 1
                let eventID = UUID().uuidString.lowercased()
                try db.execute(
                    sql: """
                    INSERT INTO active_revision_events(
                        event_id,
                        object_type,
                        logical_id,
                        previous_revision_id,
                        replacement_revision_id,
                        pointer_version,
                        changed_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        eventID,
                        selection.objectType.encodedValue,
                        selection.logicalID.canonicalString,
                        actualPreviousID?.canonicalString,
                        selection.revisionID.canonicalString,
                        nextVersion,
                        markedAt.millisecondsSinceUnixEpoch
                    ]
                )
                try db.execute(
                    sql: """
                    INSERT INTO active_published_revisions(
                        object_type, logical_id, revision_id, pointer_version, changed_at_ms
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(object_type, logical_id) DO UPDATE SET
                        revision_id = excluded.revision_id,
                        pointer_version = excluded.pointer_version,
                        changed_at_ms = excluded.changed_at_ms
                    """,
                    arguments: [
                        selection.objectType.encodedValue,
                        selection.logicalID.canonicalString,
                        selection.revisionID.canonicalString,
                        nextVersion,
                        markedAt.millisecondsSinceUnixEpoch
                    ]
                )
                for mark in plan.marks {
                    try insert(
                        staleMark: mark,
                        eventID: eventID,
                        markedAt: markedAt,
                        in: db
                    )
                }
                return plan
            }
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.activeRevisionIntegrity(String(describing: error))
        }
    }

    public func staleMarks(
        for revision: SemanticRevisionReference
    ) throws -> [PersistedStaleMark] {
        try databasePool.read { db in try staleMarks(for: revision, in: db) }
    }

    func registerManagedAsset(_ record: ManagedAssetRecord) throws {
        let payload = try SQLitePayloadCodec.canonicalData(record)
        let digest = SQLitePayloadCodec.sha256(payload)
        do {
            try databasePool.write { db in
                if let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT record_payload, record_sha256 FROM managed_assets WHERE storage_object_id = ?",
                    arguments: [record.storageObjectID.canonicalString]
                ) {
                    let existingPayload: Data = existing["record_payload"]
                    let existingDigest: String = existing["record_sha256"]
                    guard existingPayload == payload, existingDigest == digest else {
                        throw PersistenceContractError.managedAssetConflict(record.storageObjectID)
                    }
                    return
                }
                try insertManagedAsset(record, payload: payload, digest: digest, in: db)
                try insertManagedAssetEvent(record, kind: "registered", in: db)
            }
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.managedAssetConflict(record.storageObjectID)
        }
    }

    func managedAsset(storageObjectID: StorageObjectID) throws -> ManagedAssetRecord? {
        try databasePool.read { db in
            try managedAsset(storageObjectID: storageObjectID, in: db)
        }
    }

    func recordTrashMove(_ record: ManagedAssetRecord) throws {
        try updateManagedAsset(record, expectedState: .active, eventKind: "trashed")
    }

    func recordTrashRestore(_ record: ManagedAssetRecord, at restoredAt: UTCInstant) throws {
        try updateManagedAsset(
            record,
            expectedState: .trashed,
            eventKind: "restored",
            occurredAt: restoredAt
        )
    }

    private func ensureSupported<Object: SemanticRevisionContract>(_ type: Object.Type) throws {
        let supported = type is SourceAssetV1.Type
            || type is EvidenceRefV1.Type
            || type is MeetingProfileV1.Type
            || type is TranscriptSegmentV1.Type
            || type is TranslationSegmentV1.Type
            || type is ActorV1.Type
            || type is SpeakingCapacityV1.Type
            || type is SpeakerAssignmentV1.Type
        guard supported else {
            throw PersistenceContractError.unsupportedStoredObjectType(
                Object.ObjectIDTag.semanticObjectType.encodedValue
            )
        }
    }

    private func validateWorkspaceOwnership<Object: SemanticRevisionContract>(
        _ object: Object,
        in db: Database
    ) throws {
        if let meeting = object as? MeetingProfileV1 {
            guard meeting.workspaceID == workspace.manifest.workspaceID else {
                throw PersistenceContractError.logicalObjectMismatch
            }
            return
        }

        let meetingID: MeetingID?
        switch object {
        case let value as SourceAssetV1:
            meetingID = value.meetingID
        case let value as TranscriptSegmentV1:
            meetingID = value.meetingID
        case let value as TranslationSegmentV1:
            meetingID = value.meetingID
        case let value as SpeakingCapacityV1:
            meetingID = value.meetingID
        case let value as SpeakerAssignmentV1:
            meetingID = value.meetingID
        default:
            meetingID = nil
        }
        guard let meetingID else { return }
        let ownedMeetingExists = try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1 FROM semantic_revisions
                WHERE object_type = 'meeting_profile' AND logical_id = ?
            )
            """,
            arguments: [meetingID.canonicalString]
        ) ?? false
        guard ownedMeetingExists else {
            throw PersistenceContractError.logicalObjectMismatch
        }
    }

    private func existingRevisionMatches<Object: SemanticRevisionContract>(
        _ object: Object,
        payload: Data,
        in db: Database
    ) throws -> Bool {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT object_type, logical_id, canonical_payload, payload_sha256 FROM semantic_revisions WHERE revision_id = ?",
            arguments: [object.revision.revisionID.canonicalString]
        ) else {
            return false
        }
        let existingType: String = row["object_type"]
        let existingLogicalID: String = row["logical_id"]
        let existingPayload: Data = row["canonical_payload"]
        let existingDigest: String = row["payload_sha256"]
        guard existingType == object.revision.objectType.encodedValue,
              existingLogicalID == object.revision.logicalID.canonicalString,
              existingPayload == payload,
              existingDigest == SQLitePayloadCodec.sha256(payload)
        else {
            throw PersistenceContractError.revisionConflict(object.revision.revisionID)
        }
        return true
    }

    private func insertRevisionRow<Object: SemanticRevisionContract>(
        _ object: Object,
        payload: Data,
        in db: Database
    ) throws {
        let revision = object.revision
        try db.execute(
            sql: """
            INSERT INTO semantic_revisions(
                object_type,
                logical_id,
                revision_id,
                schema_major,
                schema_minor,
                lifecycle_status,
                validation_state,
                created_at_ms,
                published_at_ms,
                supersedes_revision_id,
                data_classification,
                semantic_hash_algorithm,
                semantic_hash_hex,
                canonical_payload,
                payload_sha256,
                payload_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                revision.objectType.encodedValue,
                revision.logicalID.canonicalString,
                revision.revisionID.canonicalString,
                Int64(revision.schemaVersion.major),
                Int64(revision.schemaVersion.minor),
                revision.lifecycleStatus.encodedValue,
                revision.validationState.encodedValue,
                revision.createdAt.millisecondsSinceUnixEpoch,
                revision.publishedAt?.millisecondsSinceUnixEpoch,
                revision.supersedesRevisionID?.canonicalString,
                revision.dataClassification.encodedValue,
                revision.semanticContentHash?.algorithm.encodedValue,
                revision.semanticContentHash?.lowercaseHex,
                payload,
                SQLitePayloadCodec.sha256(payload),
                payload.count
            ]
        )
    }

    private func insert(edge: DependencyEdge, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO dependency_edges(
                upstream_object_type,
                upstream_logical_id,
                upstream_revision_id,
                downstream_object_type,
                downstream_logical_id,
                downstream_revision_id,
                role
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                edge.upstreamRevision.objectType.encodedValue,
                edge.upstreamRevision.logicalID.canonicalString,
                edge.upstreamRevision.revisionID.canonicalString,
                edge.downstreamRevision.objectType.encodedValue,
                edge.downstreamRevision.logicalID.canonicalString,
                edge.downstreamRevision.revisionID.canonicalString,
                edge.role.encodedValue
            ]
        )
    }

    private func fetch<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        revisionID: RevisionID,
        in db: Database
    ) throws -> Object? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM semantic_revisions WHERE revision_id = ?",
            arguments: [revisionID.canonicalString]
        ) else {
            return nil
        }
        return try decode(type, row: row)
    }

    private func decode<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        row: Row
    ) throws -> Object {
        let payload: Data = row["canonical_payload"]
        let storedDigest: String = row["payload_sha256"]
        let revisionID = try RevisionID(validating: row["revision_id"] as String)
        guard payload.count == row["payload_byte_size"],
              SQLitePayloadCodec.sha256(payload) == storedDigest
        else {
            throw PersistenceContractError.revisionConflict(revisionID)
        }
        let object = try CanonicalJSON.decodeValidated(type, from: payload)
        let canonical = try CanonicalJSON.encodeValidated(object)
        guard canonical == payload else {
            throw PersistenceContractError.revisionConflict(revisionID)
        }
        let revision = object.revision
        let publishedAt: Int64? = row["published_at_ms"]
        let supersedes: String? = row["supersedes_revision_id"]
        let storedHashAlgorithm: String? = row["semantic_hash_algorithm"]
        let storedHashHex: String? = row["semantic_hash_hex"]
        guard row["object_type"] == revision.objectType.encodedValue,
              row["logical_id"] == revision.logicalID.canonicalString,
              row["revision_id"] == revision.revisionID.canonicalString,
              row["schema_major"] == Int64(revision.schemaVersion.major),
              row["schema_minor"] == Int64(revision.schemaVersion.minor),
              row["lifecycle_status"] == revision.lifecycleStatus.encodedValue,
              row["validation_state"] == revision.validationState.encodedValue,
              row["created_at_ms"] == revision.createdAt.millisecondsSinceUnixEpoch,
              publishedAt == revision.publishedAt?.millisecondsSinceUnixEpoch,
              supersedes == revision.supersedesRevisionID?.canonicalString,
              row["data_classification"] == revision.dataClassification.encodedValue,
              storedHashAlgorithm == revision.semanticContentHash?.algorithm.encodedValue,
              storedHashHex == revision.semanticContentHash?.lowercaseHex
        else {
            throw PersistenceContractError.revisionConflict(revisionID)
        }
        return object
    }

    func validateStoredRevisionRow(_ row: Row) throws -> SemanticRevisionReference {
        let objectTypeValue: String = row["object_type"]
        switch SemanticObjectType(encodedValue: objectTypeValue) {
        case .sourceAsset:
            _ = try decode(SourceAssetV1.self, row: row)
        case .evidenceRef:
            _ = try decode(EvidenceRefV1.self, row: row)
        case .meetingProfile:
            _ = try decode(MeetingProfileV1.self, row: row)
        case .transcriptSegment:
            _ = try decode(TranscriptSegmentV1.self, row: row)
        case .translationSegment:
            _ = try decode(TranslationSegmentV1.self, row: row)
        case .actor:
            _ = try decode(ActorV1.self, row: row)
        case .speakingCapacity:
            _ = try decode(SpeakingCapacityV1.self, row: row)
        case .speakerAssignment:
            _ = try decode(SpeakerAssignmentV1.self, row: row)
        case .userConfirmedNote, .unrecognized:
            throw PersistenceContractError.unsupportedStoredObjectType(objectTypeValue)
        }
        return try SQLiteReferenceCodec.reference(
            objectTypeValue: objectTypeValue,
            logicalIDValue: row["logical_id"],
            revisionIDValue: row["revision_id"]
        )
    }

    private func dependencyEdges(in db: Database) throws -> [DependencyEdge] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM dependency_edges
            ORDER BY
                upstream_object_type,
                upstream_logical_id,
                upstream_revision_id,
                downstream_object_type,
                downstream_logical_id,
                downstream_revision_id,
                role
            """
        ).map(SQLiteReferenceCodec.edge).sorted()
    }

    private func validateCurrentDependencyClosure<Tag: LogicalObjectIDScope>(
        objectType: SemanticObjectType,
        logicalID: StableID<Tag>,
        revisionID: RevisionID,
        in db: Database
    ) throws {
        let hasInvalidUpstream = try Int.fetchOne(
            db,
            sql: """
            WITH RECURSIVE ancestors(object_type, logical_id, revision_id) AS (
                SELECT
                    upstream_object_type,
                    upstream_logical_id,
                    upstream_revision_id
                FROM dependency_edges
                WHERE downstream_object_type = ?
                  AND downstream_logical_id = ?
                  AND downstream_revision_id = ?
                UNION
                SELECT
                    edge.upstream_object_type,
                    edge.upstream_logical_id,
                    edge.upstream_revision_id
                FROM dependency_edges AS edge
                JOIN ancestors AS current
                  ON edge.downstream_object_type = current.object_type
                 AND edge.downstream_logical_id = current.logical_id
                 AND edge.downstream_revision_id = current.revision_id
            )
            SELECT EXISTS (
                SELECT 1
                FROM ancestors AS ancestor
                LEFT JOIN revision_current_state AS state
                  ON state.object_type = ancestor.object_type
                 AND state.logical_id = ancestor.logical_id
                 AND state.revision_id = ancestor.revision_id
                WHERE state.revision_id IS NULL
                   OR state.currency_state != 'current'
                   OR EXISTS (
                       SELECT 1 FROM stale_events AS stale
                       WHERE stale.affected_object_type = ancestor.object_type
                         AND stale.affected_logical_id = ancestor.logical_id
                         AND stale.affected_revision_id = ancestor.revision_id
                   )
            )
            """,
            arguments: [
                objectType.encodedValue,
                logicalID.canonicalString,
                revisionID.canonicalString
            ]
        ) == 1
        guard !hasInvalidUpstream else {
            throw PersistenceContractError.activeRevisionIntegrity(
                "A revision with a missing or stale upstream dependency cannot become active."
            )
        }
    }

    private func insert(
        staleMark: StaleMark,
        eventID: String,
        markedAt: UTCInstant,
        in db: Database
    ) throws {
        let payload = try CanonicalJSON.encodeValidated(staleMark)
        let root = staleMark.reason.invalidation.rootRevision
        try db.execute(
            sql: """
            INSERT INTO stale_events(
                event_id,
                affected_object_type,
                affected_logical_id,
                affected_revision_id,
                root_object_type,
                root_logical_id,
                root_revision_id,
                action,
                mark_payload,
                mark_sha256,
                marked_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(affected_revision_id, root_revision_id, mark_sha256) DO NOTHING
            """,
            arguments: [
                eventID,
                staleMark.affectedRevision.objectType.encodedValue,
                staleMark.affectedRevision.logicalID.canonicalString,
                staleMark.affectedRevision.revisionID.canonicalString,
                root.objectType.encodedValue,
                root.logicalID.canonicalString,
                root.revisionID.canonicalString,
                staleMark.action.encodedValue,
                payload,
                SQLitePayloadCodec.sha256(payload),
                markedAt.millisecondsSinceUnixEpoch
            ]
        )
        try db.execute(
            sql: """
            UPDATE revision_current_state
            SET currency_state = 'stale', last_stale_at_ms = ?
            WHERE object_type = ? AND logical_id = ? AND revision_id = ?
            """,
            arguments: [
                markedAt.millisecondsSinceUnixEpoch,
                staleMark.affectedRevision.objectType.encodedValue,
                staleMark.affectedRevision.logicalID.canonicalString,
                staleMark.affectedRevision.revisionID.canonicalString
            ]
        )
        guard db.changesCount == 1 else {
            throw PersistenceContractError.staleStateIntegrity(
                "The affected revision state could not be marked stale."
            )
        }
    }

    private func staleMarks(
        for revision: SemanticRevisionReference,
        in db: Database
    ) throws -> [PersistedStaleMark] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT mark_payload, mark_sha256, marked_at_ms
            FROM stale_events
            WHERE affected_object_type = ?
              AND affected_logical_id = ?
              AND affected_revision_id = ?
            ORDER BY marked_at_ms, event_id
            """,
            arguments: [
                revision.objectType.encodedValue,
                revision.logicalID.canonicalString,
                revision.revisionID.canonicalString
            ]
        ).map { row in
            let payload: Data = row["mark_payload"]
            let digest: String = row["mark_sha256"]
            guard SQLitePayloadCodec.sha256(payload) == digest else {
                throw PersistenceContractError.staleStateIntegrity(
                    "A persisted stale mark failed its payload digest."
                )
            }
            let mark = try CanonicalJSON.decodeValidated(StaleMark.self, from: payload)
            guard mark.affectedRevision == revision,
                  try CanonicalJSON.encodeValidated(mark) == payload
            else {
                throw PersistenceContractError.staleStateIntegrity(
                    "A persisted stale mark does not match its indexed revision."
                )
            }
            return PersistedStaleMark(
                mark: mark,
                markedAt: try UTCInstant(millisecondsSinceUnixEpoch: row["marked_at_ms"])
            )
        }
    }

    private func validateManagedAssetBinding(
        _ sourceAsset: SourceAssetV1,
        in db: Database
    ) throws {
        guard let reference = sourceAsset.managedStorageReference else { return }
        guard let record = try managedAsset(storageObjectID: reference.storageObjectID, in: db) else {
            throw PersistenceContractError.managedAssetNotFound(reference.storageObjectID)
        }
        guard record.state == .active,
              record.meetingID == sourceAsset.meetingID,
              record.contentHash == sourceAsset.sourceContentHash,
              record.byteSize == sourceAsset.byteSize,
              record.dataClassification == sourceAsset.revision.dataClassification,
              record.retentionClass == sourceAsset.retentionClass
        else {
            throw PersistenceContractError.managedAssetConflict(reference.storageObjectID)
        }
    }

    private func insertManagedAsset(
        _ record: ManagedAssetRecord,
        payload: Data,
        digest: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO managed_assets(
                storage_object_id,
                meeting_id,
                relative_path,
                original_relative_path,
                content_hash_algorithm,
                content_hash_hex,
                byte_size_decimal,
                created_at_ms,
                data_classification,
                retention_class,
                state,
                trashed_at_ms,
                record_payload,
                record_sha256
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                record.storageObjectID.canonicalString,
                record.meetingID.canonicalString,
                record.relativePath.rawValue,
                record.originalRelativePath.rawValue,
                record.contentHash.algorithm.encodedValue,
                record.contentHash.lowercaseHex,
                String(record.byteSize),
                record.createdAt.millisecondsSinceUnixEpoch,
                record.dataClassification.encodedValue,
                record.retentionClass.encodedValue,
                record.state.rawValue,
                record.trashedAt?.millisecondsSinceUnixEpoch,
                payload,
                digest
            ]
        )
    }

    private func managedAsset(
        storageObjectID: StorageObjectID,
        in db: Database
    ) throws -> ManagedAssetRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM managed_assets WHERE storage_object_id = ?",
            arguments: [storageObjectID.canonicalString]
        ) else {
            return nil
        }
        return try SQLitePayloadCodec.managedAsset(from: row)
    }

    private func updateManagedAsset(
        _ record: ManagedAssetRecord,
        expectedState: ManagedAssetState,
        eventKind: String,
        occurredAt: UTCInstant? = nil
    ) throws {
        do {
            try databasePool.write { db in
                guard let current = try managedAsset(
                    storageObjectID: record.storageObjectID,
                    in: db
                ) else {
                    throw PersistenceContractError.managedAssetNotFound(record.storageObjectID)
                }
                guard current.state == expectedState,
                      current.meetingID == record.meetingID,
                      current.originalRelativePath == record.originalRelativePath,
                      current.contentHash == record.contentHash,
                      current.byteSize == record.byteSize,
                      current.createdAt == record.createdAt,
                      current.dataClassification == record.dataClassification,
                      current.retentionClass == record.retentionClass
                else {
                    throw PersistenceContractError.managedAssetConflict(record.storageObjectID)
                }
                let payload = try SQLitePayloadCodec.canonicalData(record)
                try db.execute(
                    sql: """
                    UPDATE managed_assets SET
                        relative_path = ?,
                        state = ?,
                        trashed_at_ms = ?,
                        record_payload = ?,
                        record_sha256 = ?
                    WHERE storage_object_id = ? AND state = ?
                    """,
                    arguments: [
                        record.relativePath.rawValue,
                        record.state.rawValue,
                        record.trashedAt?.millisecondsSinceUnixEpoch,
                        payload,
                        SQLitePayloadCodec.sha256(payload),
                        record.storageObjectID.canonicalString,
                        expectedState.rawValue
                    ]
                )
                guard db.changesCount == 1 else {
                    throw PersistenceContractError.managedAssetConflict(record.storageObjectID)
                }
                try insertManagedAssetEvent(
                    record,
                    kind: eventKind,
                    occurredAt: occurredAt,
                    in: db
                )
            }
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.managedAssetConflict(record.storageObjectID)
        }
    }

    private func insertManagedAssetEvent(
        _ record: ManagedAssetRecord,
        kind: String,
        occurredAt explicitOccurredAt: UTCInstant? = nil,
        in db: Database
    ) throws {
        let payload = try SQLitePayloadCodec.canonicalData(record)
        let occurredAt = explicitOccurredAt ?? record.trashedAt ?? record.createdAt
        try db.execute(
            sql: """
            INSERT INTO managed_asset_events(
                event_id,
                storage_object_id,
                event_kind,
                record_payload,
                record_sha256,
                occurred_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(),
                record.storageObjectID.canonicalString,
                kind,
                payload,
                SQLitePayloadCodec.sha256(payload),
                occurredAt.millisecondsSinceUnixEpoch
            ]
        )
    }
}
