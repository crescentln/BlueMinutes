import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

enum SQLiteSchema {
    static let currentVersion: UInt32 = 1
    static let initialMigrationIdentifier = "001_initial_persistence"
    static let maximumSemanticPayloadBytes = 16 * 1_024 * 1_024

    static let initialSchemaSQL = """
    CREATE TABLE schema_migrations (
        identifier TEXT PRIMARY KEY NOT NULL,
        ordinal INTEGER NOT NULL UNIQUE CHECK (ordinal > 0),
        checksum_sha256 TEXT NOT NULL CHECK (
            length(checksum_sha256) = 64 AND lower(checksum_sha256) = checksum_sha256
        ),
        applied_at_ms INTEGER NOT NULL CHECK (applied_at_ms >= 0)
    );

    CREATE TABLE workspace_metadata (
        singleton INTEGER PRIMARY KEY NOT NULL CHECK (singleton = 1),
        workspace_id TEXT NOT NULL CHECK (
            length(workspace_id) = 36 AND lower(workspace_id) = workspace_id
        ),
        database_schema_version INTEGER NOT NULL CHECK (database_schema_version > 0),
        updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
    );

    CREATE TABLE semantic_revisions (
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL CHECK (
            length(logical_id) = 36 AND lower(logical_id) = logical_id
        ),
        revision_id TEXT NOT NULL CHECK (
            length(revision_id) = 36 AND lower(revision_id) = revision_id
        ),
        schema_major INTEGER NOT NULL CHECK (schema_major > 0 AND schema_major <= 65535),
        schema_minor INTEGER NOT NULL CHECK (schema_minor >= 0 AND schema_minor <= 65535),
        lifecycle_status TEXT NOT NULL CHECK (lifecycle_status IN ('draft', 'published')),
        validation_state TEXT NOT NULL CHECK (
            validation_state IN ('not_validated', 'valid', 'invalid', 'needs_review')
        ),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        published_at_ms INTEGER CHECK (published_at_ms >= created_at_ms),
        supersedes_revision_id TEXT,
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        semantic_hash_algorithm TEXT,
        semantic_hash_hex TEXT,
        canonical_payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size > 0 AND payload_byte_size <= 16777216
        ),
        PRIMARY KEY (object_type, logical_id, revision_id),
        UNIQUE (revision_id),
        FOREIGN KEY (object_type, logical_id, supersedes_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        CHECK (
            (semantic_hash_algorithm IS NULL AND semantic_hash_hex IS NULL)
            OR
            (semantic_hash_algorithm = 'sha256'
                AND length(semantic_hash_hex) = 64
                AND lower(semantic_hash_hex) = semantic_hash_hex)
        ),
        CHECK (
            lifecycle_status != 'published'
            OR (validation_state = 'valid'
                AND published_at_ms IS NOT NULL
                AND semantic_hash_hex IS NOT NULL)
        ),
        CHECK (object_type IN (
            'source_asset',
            'evidence_ref',
            'meeting_profile',
            'transcript_segment',
            'translation_segment',
            'actor',
            'speaking_capacity',
            'speaker_assignment'
        ))
    );

    CREATE TABLE active_published_revisions (
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        revision_id TEXT NOT NULL,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        PRIMARY KEY (object_type, logical_id),
        FOREIGN KEY (object_type, logical_id, revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE dependency_edges (
        upstream_object_type TEXT NOT NULL,
        upstream_logical_id TEXT NOT NULL,
        upstream_revision_id TEXT NOT NULL,
        downstream_object_type TEXT NOT NULL,
        downstream_logical_id TEXT NOT NULL,
        downstream_revision_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('input', 'source_asset', 'evidence')),
        PRIMARY KEY (
            upstream_object_type,
            upstream_logical_id,
            upstream_revision_id,
            downstream_object_type,
            downstream_logical_id,
            downstream_revision_id,
            role
        ),
        FOREIGN KEY (
            downstream_object_type,
            downstream_logical_id,
            downstream_revision_id
        ) REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        CHECK (
            upstream_object_type != downstream_object_type
            OR upstream_logical_id != downstream_logical_id
            OR upstream_revision_id != downstream_revision_id
        ),
        CHECK (role != 'source_asset' OR upstream_object_type = 'source_asset'),
        CHECK (role != 'evidence' OR upstream_object_type = 'evidence_ref')
    );

    CREATE INDEX dependency_edges_by_downstream
        ON dependency_edges(
            downstream_object_type,
            downstream_logical_id,
            downstream_revision_id
        );
    CREATE INDEX dependency_edges_by_upstream
        ON dependency_edges(
            upstream_object_type,
            upstream_logical_id,
            upstream_revision_id
        );

    CREATE TABLE active_revision_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        previous_revision_id TEXT,
        replacement_revision_id TEXT NOT NULL,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (object_type, logical_id, previous_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        FOREIGN KEY (object_type, logical_id, replacement_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE stale_events (
        event_id TEXT NOT NULL,
        affected_object_type TEXT NOT NULL,
        affected_logical_id TEXT NOT NULL,
        affected_revision_id TEXT NOT NULL,
        root_object_type TEXT NOT NULL,
        root_logical_id TEXT NOT NULL,
        root_revision_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK (
            action IN ('recompute', 'preserve_and_review', 'blocked')
        ),
        mark_payload BLOB NOT NULL,
        mark_sha256 TEXT NOT NULL CHECK (
            length(mark_sha256) = 64 AND lower(mark_sha256) = mark_sha256
        ),
        marked_at_ms INTEGER NOT NULL CHECK (marked_at_ms >= 0),
        PRIMARY KEY (event_id, affected_revision_id),
        UNIQUE (affected_revision_id, root_revision_id, mark_sha256),
        FOREIGN KEY (event_id) REFERENCES active_revision_events(event_id),
        FOREIGN KEY (
            affected_object_type,
            affected_logical_id,
            affected_revision_id
        ) REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        FOREIGN KEY (
            root_object_type,
            root_logical_id,
            root_revision_id
        ) REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE INDEX stale_events_by_affected
        ON stale_events(affected_object_type, affected_logical_id, affected_revision_id);

    CREATE TABLE revision_current_state (
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        revision_id TEXT NOT NULL,
        currency_state TEXT NOT NULL CHECK (currency_state IN ('current', 'stale')),
        last_stale_at_ms INTEGER,
        PRIMARY KEY (object_type, logical_id, revision_id),
        FOREIGN KEY (object_type, logical_id, revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        CHECK (
            (currency_state = 'current' AND last_stale_at_ms IS NULL)
            OR (currency_state = 'stale' AND last_stale_at_ms IS NOT NULL)
        )
    );

    CREATE TABLE managed_assets (
        storage_object_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(storage_object_id) = 36 AND lower(storage_object_id) = storage_object_id
        ),
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        relative_path TEXT NOT NULL UNIQUE,
        original_relative_path TEXT NOT NULL,
        content_hash_algorithm TEXT NOT NULL CHECK (content_hash_algorithm = 'sha256'),
        content_hash_hex TEXT NOT NULL CHECK (
            length(content_hash_hex) = 64 AND lower(content_hash_hex) = content_hash_hex
        ),
        byte_size_decimal TEXT NOT NULL CHECK (
            length(byte_size_decimal) BETWEEN 1 AND 20
        ),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        retention_class TEXT NOT NULL CHECK (
            retention_class IN ('permanent', 'workspace_managed', 'temporary')
        ),
        state TEXT NOT NULL CHECK (state IN ('active', 'trashed')),
        trashed_at_ms INTEGER,
        record_payload BLOB NOT NULL,
        record_sha256 TEXT NOT NULL CHECK (
            length(record_sha256) = 64 AND lower(record_sha256) = record_sha256
        ),
        CHECK (
            (state = 'active' AND trashed_at_ms IS NULL
                AND relative_path = original_relative_path
                AND relative_path NOT LIKE '.Trash/%')
            OR
            (state = 'trashed' AND trashed_at_ms IS NOT NULL
                AND relative_path LIKE '.Trash/%')
        )
    );

    CREATE TABLE managed_asset_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        storage_object_id TEXT NOT NULL,
        event_kind TEXT NOT NULL CHECK (event_kind IN ('registered', 'trashed', 'restored')),
        record_payload BLOB NOT NULL,
        record_sha256 TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        FOREIGN KEY (storage_object_id) REFERENCES managed_assets(storage_object_id)
    );

    CREATE TABLE source_asset_file_bindings (
        source_object_type TEXT NOT NULL CHECK (source_object_type = 'source_asset'),
        source_logical_id TEXT NOT NULL,
        source_revision_id TEXT NOT NULL,
        storage_object_id TEXT NOT NULL,
        PRIMARY KEY (source_object_type, source_logical_id, source_revision_id),
        UNIQUE (source_revision_id),
        FOREIGN KEY (source_object_type, source_logical_id, source_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id),
        FOREIGN KEY (storage_object_id) REFERENCES managed_assets(storage_object_id)
    );

    CREATE TRIGGER semantic_revisions_no_update
    BEFORE UPDATE ON semantic_revisions
    BEGIN
        SELECT RAISE(ABORT, 'semantic revisions are immutable');
    END;

    CREATE TRIGGER semantic_revisions_no_delete
    BEFORE DELETE ON semantic_revisions
    BEGIN
        SELECT RAISE(ABORT, 'semantic revisions are immutable');
    END;

    CREATE TRIGGER dependency_edges_no_update
    BEFORE UPDATE ON dependency_edges
    BEGIN
        SELECT RAISE(ABORT, 'dependency edges are immutable');
    END;

    CREATE TRIGGER dependency_edges_no_delete
    BEFORE DELETE ON dependency_edges
    BEGIN
        SELECT RAISE(ABORT, 'dependency edges are immutable');
    END;

    CREATE TRIGGER schema_migrations_no_update
    BEFORE UPDATE ON schema_migrations
    BEGIN
        SELECT RAISE(ABORT, 'schema migration records are immutable');
    END;

    CREATE TRIGGER schema_migrations_no_delete
    BEFORE DELETE ON schema_migrations
    BEGIN
        SELECT RAISE(ABORT, 'schema migration records are immutable');
    END;

    CREATE TRIGGER dependency_edges_reject_cycle
    BEFORE INSERT ON dependency_edges
    WHEN EXISTS (
        WITH RECURSIVE descendants(object_type, logical_id, revision_id) AS (
            SELECT
                downstream_object_type,
                downstream_logical_id,
                downstream_revision_id
            FROM dependency_edges
            WHERE upstream_object_type = NEW.downstream_object_type
              AND upstream_logical_id = NEW.downstream_logical_id
              AND upstream_revision_id = NEW.downstream_revision_id
            UNION
            SELECT
                edge.downstream_object_type,
                edge.downstream_logical_id,
                edge.downstream_revision_id
            FROM dependency_edges AS edge
            JOIN descendants AS current
              ON edge.upstream_object_type = current.object_type
             AND edge.upstream_logical_id = current.logical_id
             AND edge.upstream_revision_id = current.revision_id
        )
        SELECT 1 FROM descendants
        WHERE object_type = NEW.upstream_object_type
          AND logical_id = NEW.upstream_logical_id
          AND revision_id = NEW.upstream_revision_id
    )
    BEGIN
        SELECT RAISE(ABORT, 'dependency cycle rejected');
    END;

    CREATE TRIGGER dependency_edges_require_resolved_for_valid_output
    BEFORE INSERT ON dependency_edges
    WHEN NOT EXISTS (
        SELECT 1 FROM semantic_revisions
        WHERE object_type = NEW.upstream_object_type
          AND logical_id = NEW.upstream_logical_id
          AND revision_id = NEW.upstream_revision_id
    ) AND EXISTS (
        SELECT 1 FROM semantic_revisions
        WHERE object_type = NEW.downstream_object_type
          AND logical_id = NEW.downstream_logical_id
          AND revision_id = NEW.downstream_revision_id
          AND (lifecycle_status = 'published' OR validation_state = 'valid')
    )
    BEGIN
        SELECT RAISE(ABORT, 'valid or published revisions require resolved dependencies');
    END;

    CREATE TRIGGER active_revision_validate_insert
    BEFORE INSERT ON active_published_revisions
    WHEN NOT EXISTS (
        SELECT 1 FROM semantic_revisions AS revision
        JOIN revision_current_state AS state
          ON state.object_type = revision.object_type
         AND state.logical_id = revision.logical_id
         AND state.revision_id = revision.revision_id
        WHERE revision.object_type = NEW.object_type
          AND revision.logical_id = NEW.logical_id
          AND revision.revision_id = NEW.revision_id
          AND revision.lifecycle_status = 'published'
          AND revision.validation_state = 'valid'
          AND revision.semantic_hash_hex IS NOT NULL
          AND state.currency_state = 'current'
          AND NOT EXISTS (
              SELECT 1 FROM stale_events AS stale
              WHERE stale.affected_object_type = revision.object_type
                AND stale.affected_logical_id = revision.logical_id
                AND stale.affected_revision_id = revision.revision_id
          )
          AND NOT EXISTS (
              SELECT 1 FROM dependency_edges AS edge
              LEFT JOIN semantic_revisions AS upstream
                ON upstream.object_type = edge.upstream_object_type
               AND upstream.logical_id = edge.upstream_logical_id
               AND upstream.revision_id = edge.upstream_revision_id
              WHERE edge.downstream_object_type = revision.object_type
                AND edge.downstream_logical_id = revision.logical_id
                AND edge.downstream_revision_id = revision.revision_id
                AND upstream.revision_id IS NULL
          )
          AND NOT EXISTS (
              WITH RECURSIVE ancestors(object_type, logical_id, revision_id) AS (
                  SELECT
                      upstream_object_type,
                      upstream_logical_id,
                      upstream_revision_id
                  FROM dependency_edges
                  WHERE downstream_object_type = revision.object_type
                    AND downstream_logical_id = revision.logical_id
                    AND downstream_revision_id = revision.revision_id
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
              SELECT 1
              FROM ancestors AS ancestor
              LEFT JOIN revision_current_state AS upstream_state
                ON upstream_state.object_type = ancestor.object_type
               AND upstream_state.logical_id = ancestor.logical_id
               AND upstream_state.revision_id = ancestor.revision_id
              WHERE upstream_state.revision_id IS NULL
                 OR upstream_state.currency_state != 'current'
                 OR EXISTS (
                     SELECT 1 FROM stale_events AS upstream_stale
                     WHERE upstream_stale.affected_object_type = ancestor.object_type
                       AND upstream_stale.affected_logical_id = ancestor.logical_id
                       AND upstream_stale.affected_revision_id = ancestor.revision_id
                 )
          )
    )
    BEGIN
        SELECT RAISE(ABORT, 'active revision target is not eligible');
    END;

    CREATE TRIGGER active_revision_validate_update
    BEFORE UPDATE OF revision_id ON active_published_revisions
    WHEN NOT EXISTS (
        SELECT 1 FROM semantic_revisions AS revision
        JOIN revision_current_state AS state
          ON state.object_type = revision.object_type
         AND state.logical_id = revision.logical_id
         AND state.revision_id = revision.revision_id
        WHERE revision.object_type = NEW.object_type
          AND revision.logical_id = NEW.logical_id
          AND revision.revision_id = NEW.revision_id
          AND revision.lifecycle_status = 'published'
          AND revision.validation_state = 'valid'
          AND revision.semantic_hash_hex IS NOT NULL
          AND state.currency_state = 'current'
          AND NOT EXISTS (
              SELECT 1 FROM stale_events AS stale
              WHERE stale.affected_object_type = revision.object_type
                AND stale.affected_logical_id = revision.logical_id
                AND stale.affected_revision_id = revision.revision_id
          )
          AND NOT EXISTS (
              SELECT 1 FROM dependency_edges AS edge
              LEFT JOIN semantic_revisions AS upstream
                ON upstream.object_type = edge.upstream_object_type
               AND upstream.logical_id = edge.upstream_logical_id
               AND upstream.revision_id = edge.upstream_revision_id
              WHERE edge.downstream_object_type = revision.object_type
                AND edge.downstream_logical_id = revision.logical_id
                AND edge.downstream_revision_id = revision.revision_id
                AND upstream.revision_id IS NULL
          )
          AND NOT EXISTS (
              WITH RECURSIVE ancestors(object_type, logical_id, revision_id) AS (
                  SELECT
                      upstream_object_type,
                      upstream_logical_id,
                      upstream_revision_id
                  FROM dependency_edges
                  WHERE downstream_object_type = revision.object_type
                    AND downstream_logical_id = revision.logical_id
                    AND downstream_revision_id = revision.revision_id
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
              SELECT 1
              FROM ancestors AS ancestor
              LEFT JOIN revision_current_state AS upstream_state
                ON upstream_state.object_type = ancestor.object_type
               AND upstream_state.logical_id = ancestor.logical_id
               AND upstream_state.revision_id = ancestor.revision_id
              WHERE upstream_state.revision_id IS NULL
                 OR upstream_state.currency_state != 'current'
                 OR EXISTS (
                     SELECT 1 FROM stale_events AS upstream_stale
                     WHERE upstream_stale.affected_object_type = ancestor.object_type
                       AND upstream_stale.affected_logical_id = ancestor.logical_id
                       AND upstream_stale.affected_revision_id = ancestor.revision_id
                 )
          )
    )
    BEGIN
        SELECT RAISE(ABORT, 'active revision target is not eligible');
    END;

    CREATE TRIGGER active_revision_events_no_update
    BEFORE UPDATE ON active_revision_events
    BEGIN
        SELECT RAISE(ABORT, 'active revision events are immutable');
    END;

    CREATE TRIGGER active_revision_events_no_delete
    BEFORE DELETE ON active_revision_events
    BEGIN
        SELECT RAISE(ABORT, 'active revision events are immutable');
    END;

    CREATE TRIGGER stale_events_no_update
    BEFORE UPDATE ON stale_events
    BEGIN
        SELECT RAISE(ABORT, 'stale events are immutable');
    END;

    CREATE TRIGGER stale_events_no_delete
    BEFORE DELETE ON stale_events
    BEGIN
        SELECT RAISE(ABORT, 'stale events are immutable');
    END;

    CREATE TRIGGER revision_current_state_no_return_to_current
    BEFORE UPDATE OF currency_state ON revision_current_state
    WHEN OLD.currency_state = 'stale' AND NEW.currency_state = 'current'
    BEGIN
        SELECT RAISE(ABORT, 'stale revision state is monotonic');
    END;

    CREATE TRIGGER managed_asset_events_no_update
    BEFORE UPDATE ON managed_asset_events
    BEGIN
        SELECT RAISE(ABORT, 'managed asset events are immutable');
    END;

    CREATE TRIGGER managed_asset_events_no_delete
    BEFORE DELETE ON managed_asset_events
    BEGIN
        SELECT RAISE(ABORT, 'managed asset events are immutable');
    END;

    CREATE TRIGGER source_asset_file_bindings_no_update
    BEFORE UPDATE ON source_asset_file_bindings
    BEGIN
        SELECT RAISE(ABORT, 'source asset file bindings are immutable');
    END;

    CREATE TRIGGER source_asset_file_bindings_no_delete
    BEFORE DELETE ON source_asset_file_bindings
    BEGIN
        SELECT RAISE(ABORT, 'source asset file bindings are immutable');
    END;
    """

    static var initialChecksum: String {
        SHA256.hash(data: Data(initialSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct SQLiteMigrationDefinition: Sendable {
    let identifier: String
    let apply: @Sendable (Database) throws -> Void

    init(identifier: String, apply: @escaping @Sendable (Database) throws -> Void) {
        self.identifier = identifier
        self.apply = apply
    }
}

struct SQLiteBootstrapResult: Sendable {
    let databasePool: DatabasePool
    let outcome: MigrationOutcome
}

enum SQLiteDatabaseBootstrap {
    static func open(
        workspace: LocalWorkspaceDescriptor,
        migrationTimestamp: UTCInstant,
        additionalMigrations: [SQLiteMigrationDefinition] = []
    ) throws -> SQLiteBootstrapResult {
        let databaseURL = try WorkspacePathSecurity.confinedURL(
            workspace.layout.databaseFile,
            within: workspace.layout.root,
            allowMissingLeaf: true
        )
        let existed = FileManager.default.fileExists(atPath: databaseURL.path)
        let migrator = makeMigrator(
            workspaceID: workspace.manifest.workspaceID,
            migrationTimestamp: migrationTimestamp,
            additionalMigrations: additionalMigrations
        )

        if existed {
            try preflightExistingDatabase(
                at: databaseURL,
                migrator: migrator,
                expectedWorkspaceID: workspace.manifest.workspaceID
            )
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        configuration.maximumReaderCount = 4
        configuration.label = "MeetingBuddy.Persistence"
        let databasePool = try DatabasePool(
            path: databaseURL.path,
            configuration: configuration
        )

        let completedBefore = try databasePool.read { db in
            try migrator.completedMigrations(db)
        }
        let hasPending = completedBefore.count < migrator.migrations.count
        let rollbackAnchor: DatabaseBackupDescriptor?
        if existed, hasPending {
            rollbackAnchor = try createMigrationBackup(
                databasePool: databasePool,
                workspace: workspace,
                createdAt: migrationTimestamp,
                sourceSchemaVersion: try currentSchemaVersion(in: databasePool) ?? 0
            )
        } else {
            rollbackAnchor = nil
        }

        do {
            try migrator.migrate(databasePool)
            try validateRegisteredMigrations(in: databasePool, migrator: migrator)
            try validateWorkspaceIdentity(
                in: databasePool,
                expectedWorkspaceID: workspace.manifest.workspaceID
            )
            try enforceDatabasePermissions(databaseURL)
            let schemaVersion = try currentSchemaVersion(in: databasePool)
            guard schemaVersion == SQLiteSchema.currentVersion else {
                throw PersistenceContractError.migrationFailed(
                    "Database schema marker did not reach the expected version."
                )
            }
            return SQLiteBootstrapResult(
                databasePool: databasePool,
                outcome: MigrationOutcome(
                    schemaVersion: schemaVersion ?? 0,
                    appliedMigrations: try databasePool.read { db in
                        try migrator.completedMigrations(db)
                    },
                    rollbackAnchor: rollbackAnchor
                )
            )
        } catch {
            try? databasePool.close()
            throw PersistenceContractError.migrationFailed(
                "Database open or migration validation failed. A failing migration transaction "
                    + "was rolled back, but any earlier successful migration may already be committed. "
                    + "Rollback anchor: "
                    + (rollbackAnchor?.artifact.relativePath.rawValue ?? "none")
                    + ". Cause: \(error)"
            )
        }
    }

    static func makeMigrator(
        workspaceID: WorkspaceID,
        migrationTimestamp: UTCInstant,
        additionalMigrations: [SQLiteMigrationDefinition]
    ) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration(SQLiteSchema.initialMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.initialSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.initialMigrationIdentifier,
                    1,
                    SQLiteSchema.initialChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO workspace_metadata(
                    singleton, workspace_id, database_schema_version, updated_at_ms
                ) VALUES (1, ?, ?, ?)
                """,
                arguments: [
                    workspaceID.canonicalString,
                    SQLiteSchema.currentVersion,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        for migration in additionalMigrations {
            migrator.registerMigration(migration.identifier, migrate: migration.apply)
        }
        return migrator
    }

    private static func preflightExistingDatabase(
        at databaseURL: URL,
        migrator: DatabaseMigrator,
        expectedWorkspaceID: WorkspaceID
    ) throws {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        defer { try? queue.close() }
        try queue.read { db in
            if try migrator.hasBeenSuperseded(db) {
                throw PersistenceContractError.migrationFailed(
                    "The database contains a migration unknown to this application version."
                )
            }
            let applied = try migrator.appliedIdentifiers(db)
            if applied.isEmpty {
                let userObjects = try String.fetchAll(
                    db,
                    sql: """
                    SELECT name FROM sqlite_master
                    WHERE name NOT LIKE 'sqlite_%'
                      AND name != 'grdb_migrations'
                    ORDER BY name
                    """
                )
                guard userObjects.isEmpty else {
                    throw PersistenceContractError.migrationFailed(
                        "An unversioned non-empty database is not a supported prior state."
                    )
                }
            } else {
                guard try db.tableExists("workspace_metadata"),
                      try String.fetchOne(
                          db,
                          sql: "SELECT workspace_id FROM workspace_metadata WHERE singleton = 1"
                      ) == expectedWorkspaceID.canonicalString
                else {
                    throw PersistenceContractError.migrationFailed(
                        "Database workspace identity does not match the workspace manifest."
                    )
                }
                if try migrator.hasSchemaChanges(db) {
                    throw PersistenceContractError.migrationFailed(
                        "The stored schema does not match its registered migrations."
                    )
                }
            }
        }
    }

    private static func validateRegisteredMigrations(
        in pool: DatabasePool,
        migrator: DatabaseMigrator
    ) throws {
        try pool.read { db in
            if try migrator.hasBeenSuperseded(db) {
                throw PersistenceContractError.migrationFailed(
                    "The database contains an unknown future migration."
                )
            }
            guard try migrator.hasCompletedMigrations(db) else {
                throw PersistenceContractError.migrationFailed(
                    "Not all registered migrations completed."
                )
            }
            let storedChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.initialMigrationIdentifier]
            )
            guard storedChecksum == SQLiteSchema.initialChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The initial migration checksum does not match the accepted schema."
                )
            }
        }
    }

    private static func validateWorkspaceIdentity(
        in pool: DatabasePool,
        expectedWorkspaceID: WorkspaceID
    ) throws {
        let storedWorkspaceID = try pool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT workspace_id FROM workspace_metadata WHERE singleton = 1"
            )
        }
        guard storedWorkspaceID == expectedWorkspaceID.canonicalString else {
            throw PersistenceContractError.migrationFailed(
                "Database workspace identity does not match the workspace manifest."
            )
        }
    }

    private static func createMigrationBackup(
        databasePool: DatabasePool,
        workspace: LocalWorkspaceDescriptor,
        createdAt: UTCInstant,
        sourceSchemaVersion: UInt32
    ) throws -> DatabaseBackupDescriptor {
        let requestedDirectory = workspace.layout.backups
            .appendingPathComponent("Migrations", isDirectory: true)
        let directory = try WorkspacePathSecurity.createPrivateDirectory(
            requestedDirectory,
            within: workspace.layout.root
        )
        let filename = "pre-migration-\(createdAt.millisecondsSinceUnixEpoch)-"
            + UUID().uuidString.lowercased() + ".sqlite"
        let backupURL = directory.appendingPathComponent(filename)
        let destination = try DatabaseQueue(path: backupURL.path)
        try databasePool.backup(to: destination)
        try makeBackupReadOnlyPortable(destination)
        try destination.close()
        try removeObsoleteBackupSidecars(at: backupURL)
        try enforceDatabasePermissions(backupURL)
        let artifact = try recoveryArtifact(
            at: backupURL,
            workspaceRoot: workspace.layout.root
        )
        return DatabaseBackupDescriptor(
            artifact: artifact,
            createdAt: createdAt,
            sourceSchemaVersion: sourceSchemaVersion
        )
    }

    static func recoveryArtifact(
        at url: URL,
        workspaceRoot: URL
    ) throws -> RecoveryArtifactDescriptor {
        let confined = try WorkspacePathSecurity.confinedURL(url, within: workspaceRoot)
        let handle = try FileHandle(forReadingFrom: confined)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteSize: UInt64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            let (next, overflow) = byteSize.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A recovery artifact exceeded the supported byte-size range."
                )
            }
            byteSize = next
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let rootPath = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = confined.path
        guard path.hasPrefix(rootPath) else {
            throw WorkspaceContractError.pathEscapesWorkspace(path)
        }
        return try RecoveryArtifactDescriptor(
            relativePath: WorkspaceRelativePath(String(path.dropFirst(rootPath.count))),
            contentHash: ContentDigest(algorithm: .sha256, lowercaseHex: hash),
            byteSize: byteSize
        )
    }

    static func currentSchemaVersion(in pool: DatabasePool) throws -> UInt32? {
        try pool.read { db in
            guard try db.tableExists("workspace_metadata") else { return nil }
            let value = try Int64.fetchOne(
                db,
                sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
            )
            guard let value, value >= 0, value <= Int64(UInt32.max) else { return nil }
            return UInt32(value)
        }
    }

    /// SQLite's online backup copies the source database header, including
    /// WAL journal mode. A standalone recovery artifact has no WAL sidecars,
    /// so normalize it to DELETE mode before hashing. This keeps the backup
    /// independently openable from read-only recovery media.
    static func makeBackupReadOnlyPortable(_ database: DatabaseQueue) throws {
        let journalMode = try database.writeWithoutTransaction { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE")
        }
        guard journalMode?.lowercased() == "delete" else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The standalone SQLite backup could not leave WAL journal mode."
            )
        }
    }

    static func removeObsoleteBackupSidecars(at databaseURL: URL) throws {
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
    }

    private static func enforceDatabasePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
