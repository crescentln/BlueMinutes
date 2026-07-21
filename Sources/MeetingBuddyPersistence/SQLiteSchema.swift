import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

enum SQLiteSchema {
    static let currentVersion: UInt32 = 9
    static let initialMigrationIdentifier = "001_initial_persistence"
    static let taskRuntimeMigrationIdentifier = "002_task_runtime"
    static let transcriptCoverageMigrationIdentifier = "003_transcript_coverage"
    static let analysisMigrationIdentifier = "004_analysis_intelligence"
    static let briefingMigrationIdentifier = "005_briefing_foundation"
    static let hardeningMigrationIdentifier = "006_security_storage_hardening"
    static let recordingCaptureMigrationIdentifier = "007_recording_capture_foundation"
    static let automationMigrationIdentifier = "008_automation_command_audit_settings"
    static let mcpAuditOriginMigrationIdentifier = "009_mcp_audit_origin"
    static let maximumSemanticPayloadBytes = 16 * 1_024 * 1_024
    static let maximumJobPayloadBytes = 1 * 1_024 * 1_024

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

    static let taskRuntimeSchemaSQL = """
    CREATE TABLE jobs (
        job_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(job_id) = 36 AND lower(job_id) = job_id
        ),
        job_type TEXT NOT NULL CHECK (
            length(job_type) BETWEEN 1 AND 96
            AND job_type NOT LIKE '%/%'
            AND job_type NOT LIKE '%\\%'
        ),
        meeting_id TEXT CHECK (
            meeting_id IS NULL
            OR (length(meeting_id) = 36 AND lower(meeting_id) = meeting_id)
        ),
        state TEXT NOT NULL CHECK (state IN (
            'queued',
            'running',
            'pause_requested',
            'paused',
            'cancellation_requested',
            'succeeded',
            'failed',
            'cancelled',
            'interrupted'
        )),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        started_at_ms INTEGER CHECK (started_at_ms >= created_at_ms),
        finished_at_ms INTEGER CHECK (
            finished_at_ms IS NULL
            OR finished_at_ms >= COALESCE(started_at_ms, created_at_ms)
        ),
        retry_count INTEGER NOT NULL CHECK (retry_count BETWEEN 0 AND 100),
        maximum_retry_count INTEGER NOT NULL CHECK (
            maximum_retry_count BETWEEN retry_count AND 100
        ),
        record_version INTEGER NOT NULL CHECK (record_version > 0),
        idempotency_key TEXT NOT NULL CHECK (
            length(idempotency_key) = 64 AND lower(idempotency_key) = idempotency_key
        ),
        temporary_directory TEXT NOT NULL UNIQUE CHECK (
            temporary_directory = '.tasks/' || job_id
        ),
        disk_budget_bytes_decimal TEXT NOT NULL CHECK (
            length(disk_budget_bytes_decimal) BETWEEN 1 AND 13
        ),
        privacy_route TEXT NOT NULL CHECK (
            privacy_route IN ('local_only', 'approved_cloud')
        ),
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        resume_capability TEXT NOT NULL CHECK (
            resume_capability IN ('restart_only', 'checkpointed')
        ),
        record_payload BLOB NOT NULL,
        record_sha256 TEXT NOT NULL CHECK (
            length(record_sha256) = 64 AND lower(record_sha256) = record_sha256
        ),
        record_byte_size INTEGER NOT NULL CHECK (
            record_byte_size > 0 AND record_byte_size <= 1048576
        ),
        UNIQUE (job_type, idempotency_key),
        CHECK (
            data_classification != 'restricted'
            OR privacy_route = 'local_only'
        ),
        CHECK (
            (state IN ('succeeded', 'failed', 'cancelled', 'interrupted')
                AND finished_at_ms IS NOT NULL)
            OR
            (state NOT IN ('succeeded', 'failed', 'cancelled', 'interrupted')
                AND finished_at_ms IS NULL)
        ),
        CHECK (
            state NOT IN (
                'running', 'pause_requested', 'paused', 'cancellation_requested'
            ) OR started_at_ms IS NOT NULL
        )
    );

    CREATE INDEX jobs_by_state_created
        ON jobs(state, created_at_ms, job_id);

    CREATE TABLE job_dependencies (
        job_id TEXT NOT NULL,
        dependency_job_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        PRIMARY KEY (job_id, dependency_job_id),
        UNIQUE (job_id, ordinal),
        FOREIGN KEY (job_id) REFERENCES jobs(job_id),
        FOREIGN KEY (dependency_job_id) REFERENCES jobs(job_id),
        CHECK (job_id != dependency_job_id)
    );

    CREATE TABLE job_input_revisions (
        job_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        revision_id TEXT NOT NULL,
        PRIMARY KEY (job_id, revision_id),
        UNIQUE (job_id, ordinal),
        FOREIGN KEY (job_id) REFERENCES jobs(job_id),
        FOREIGN KEY (object_type, logical_id, revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE job_output_revisions (
        job_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        revision_id TEXT NOT NULL,
        PRIMARY KEY (job_id, revision_id),
        UNIQUE (job_id, ordinal),
        FOREIGN KEY (job_id) REFERENCES jobs(job_id),
        FOREIGN KEY (object_type, logical_id, revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE job_state_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        job_id TEXT NOT NULL,
        sequence INTEGER NOT NULL CHECK (sequence > 0),
        previous_state TEXT,
        replacement_state TEXT NOT NULL,
        record_version INTEGER NOT NULL CHECK (record_version > 0),
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        record_payload BLOB NOT NULL,
        record_sha256 TEXT NOT NULL CHECK (
            length(record_sha256) = 64 AND lower(record_sha256) = record_sha256
        ),
        UNIQUE (job_id, sequence),
        UNIQUE (job_id, record_version),
        FOREIGN KEY (job_id) REFERENCES jobs(job_id)
    );

    CREATE TABLE managed_asset_operations (
        operation_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(operation_id) = 36 AND lower(operation_id) = operation_id
        ),
        storage_object_id TEXT NOT NULL CHECK (
            length(storage_object_id) = 36 AND lower(storage_object_id) = storage_object_id
        ),
        operation_kind TEXT NOT NULL CHECK (
            operation_kind IN ('import', 'trash', 'restore')
        ),
        state TEXT NOT NULL CHECK (
            state IN (
                'intent',
                'filesystem_applied',
                'completed',
                'rolled_back',
                'repair_required'
            )
        ),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
        intent_payload BLOB NOT NULL,
        intent_sha256 TEXT NOT NULL CHECK (
            length(intent_sha256) = 64 AND lower(intent_sha256) = intent_sha256
        ),
        result_payload BLOB,
        result_sha256 TEXT,
        failure_code TEXT,
        CHECK (
            (result_payload IS NULL AND result_sha256 IS NULL)
            OR
            (result_payload IS NOT NULL
                AND length(result_sha256) = 64
                AND lower(result_sha256) = result_sha256)
        )
    );

    CREATE INDEX managed_asset_operations_by_state
        ON managed_asset_operations(state, created_at_ms, operation_id);

    CREATE TABLE managed_asset_operation_events (
        operation_id TEXT NOT NULL,
        sequence INTEGER NOT NULL CHECK (sequence > 0),
        state TEXT NOT NULL CHECK (
            state IN (
                'intent',
                'filesystem_applied',
                'completed',
                'rolled_back',
                'repair_required'
            )
        ),
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        event_payload BLOB NOT NULL,
        event_sha256 TEXT NOT NULL CHECK (
            length(event_sha256) = 64 AND lower(event_sha256) = event_sha256
        ),
        PRIMARY KEY (operation_id, sequence),
        FOREIGN KEY (operation_id) REFERENCES managed_asset_operations(operation_id)
    );

    CREATE TRIGGER job_dependencies_no_update
    BEFORE UPDATE ON job_dependencies
    BEGIN
        SELECT RAISE(ABORT, 'job dependencies are immutable');
    END;

    CREATE TRIGGER job_dependencies_no_delete
    BEFORE DELETE ON job_dependencies
    BEGIN
        SELECT RAISE(ABORT, 'job dependencies are immutable');
    END;

    CREATE TRIGGER job_input_revisions_no_update
    BEFORE UPDATE ON job_input_revisions
    BEGIN
        SELECT RAISE(ABORT, 'job input revisions are immutable');
    END;

    CREATE TRIGGER job_input_revisions_no_delete
    BEFORE DELETE ON job_input_revisions
    BEGIN
        SELECT RAISE(ABORT, 'job input revisions are immutable');
    END;

    CREATE TRIGGER job_output_revisions_no_update
    BEFORE UPDATE ON job_output_revisions
    BEGIN
        SELECT RAISE(ABORT, 'job output revisions are immutable');
    END;

    CREATE TRIGGER job_output_revisions_no_delete
    BEFORE DELETE ON job_output_revisions
    BEGIN
        SELECT RAISE(ABORT, 'job output revisions are immutable');
    END;

    CREATE TRIGGER job_state_events_no_update
    BEFORE UPDATE ON job_state_events
    BEGIN
        SELECT RAISE(ABORT, 'job state events are immutable');
    END;

    CREATE TRIGGER job_state_events_no_delete
    BEFORE DELETE ON job_state_events
    BEGIN
        SELECT RAISE(ABORT, 'job state events are immutable');
    END;

    CREATE TRIGGER managed_asset_operation_events_no_update
    BEFORE UPDATE ON managed_asset_operation_events
    BEGIN
        SELECT RAISE(ABORT, 'managed asset operation events are immutable');
    END;

    CREATE TRIGGER managed_asset_operation_events_no_delete
    BEFORE DELETE ON managed_asset_operation_events
    BEGIN
        SELECT RAISE(ABORT, 'managed asset operation events are immutable');
    END;
    """

    static let transcriptCoverageSchemaSQL = """
    CREATE TABLE transcript_coverage_manifests (
        manifest_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(manifest_id) = 36 AND lower(manifest_id) = manifest_id
        ),
        transcript_set_id TEXT NOT NULL CHECK (
            length(transcript_set_id) = 36 AND lower(transcript_set_id) = transcript_set_id
        ),
        supersedes_manifest_id TEXT,
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        canonical_source_revision_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('incomplete', 'published')),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        content_hash_algorithm TEXT NOT NULL CHECK (content_hash_algorithm = 'sha256'),
        content_hash_hex TEXT NOT NULL CHECK (
            length(content_hash_hex) = 64 AND lower(content_hash_hex) = content_hash_hex
        ),
        canonical_payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size > 0 AND payload_byte_size <= 16777216
        ),
        FOREIGN KEY (supersedes_manifest_id)
            REFERENCES transcript_coverage_manifests(manifest_id),
        FOREIGN KEY (canonical_source_revision_id)
            REFERENCES semantic_revisions(revision_id),
        CHECK (supersedes_manifest_id IS NULL OR supersedes_manifest_id != manifest_id)
    );

    CREATE INDEX transcript_coverage_by_meeting
        ON transcript_coverage_manifests(meeting_id, created_at_ms, manifest_id);

    CREATE TABLE active_transcript_manifests (
        meeting_id TEXT PRIMARY KEY NOT NULL,
        manifest_id TEXT NOT NULL UNIQUE,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (manifest_id) REFERENCES transcript_coverage_manifests(manifest_id)
    );

    CREATE TABLE transcript_manifest_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        meeting_id TEXT NOT NULL,
        previous_manifest_id TEXT,
        replacement_manifest_id TEXT NOT NULL,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (previous_manifest_id)
            REFERENCES transcript_coverage_manifests(manifest_id),
        FOREIGN KEY (replacement_manifest_id)
            REFERENCES transcript_coverage_manifests(manifest_id)
    );

    CREATE TRIGGER transcript_coverage_manifests_no_update
    BEFORE UPDATE ON transcript_coverage_manifests
    BEGIN
        SELECT RAISE(ABORT, 'transcript coverage manifests are immutable');
    END;

    CREATE TRIGGER transcript_coverage_manifests_no_delete
    BEFORE DELETE ON transcript_coverage_manifests
    BEGIN
        SELECT RAISE(ABORT, 'transcript coverage manifests are immutable');
    END;

    CREATE TRIGGER transcript_manifest_events_no_update
    BEFORE UPDATE ON transcript_manifest_events
    BEGIN
        SELECT RAISE(ABORT, 'transcript manifest events are immutable');
    END;

    CREATE TRIGGER transcript_manifest_events_no_delete
    BEFORE DELETE ON transcript_manifest_events
    BEGIN
        SELECT RAISE(ABORT, 'transcript manifest events are immutable');
    END;

    CREATE TRIGGER active_transcript_manifest_validate_insert
    BEFORE INSERT ON active_transcript_manifests
    WHEN NOT EXISTS (
        SELECT 1 FROM transcript_coverage_manifests
        WHERE manifest_id = NEW.manifest_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN
        SELECT RAISE(ABORT, 'active transcript manifest target is not publishable');
    END;

    CREATE TRIGGER active_transcript_manifest_validate_update
    BEFORE UPDATE OF manifest_id ON active_transcript_manifests
    WHEN NOT EXISTS (
        SELECT 1 FROM transcript_coverage_manifests
        WHERE manifest_id = NEW.manifest_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN
        SELECT RAISE(ABORT, 'active transcript manifest target is not publishable');
    END;
    """

    /// Schema v4 expands the closed semantic type constraint and adds an immutable,
    /// normalized analysis-coverage history. Existing v1-v3 rows are copied byte-for-byte.
    static let analysisSchemaSQL = """
    DROP TRIGGER semantic_revisions_no_update;
    DROP TRIGGER semantic_revisions_no_delete;

    CREATE TABLE semantic_revisions_v4 (
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
            'speaker_assignment',
            'participant',
            'organization',
            'issue',
            'position',
            'commitment',
            'decision',
            'intervention_card',
            'delegation_position_card'
        ))
    );

    INSERT INTO semantic_revisions_v4(
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
    )
    SELECT
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
    FROM semantic_revisions;

    DROP TABLE semantic_revisions;
    ALTER TABLE semantic_revisions_v4 RENAME TO semantic_revisions;

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

    CREATE TABLE analysis_coverage_ledgers (
        ledger_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(ledger_id) = 36 AND lower(ledger_id) = ledger_id
        ),
        supersedes_ledger_id TEXT,
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        transcript_manifest_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('incomplete', 'published')),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        content_hash_algorithm TEXT NOT NULL CHECK (content_hash_algorithm = 'sha256'),
        content_hash_hex TEXT NOT NULL CHECK (
            length(content_hash_hex) = 64 AND lower(content_hash_hex) = content_hash_hex
        ),
        canonical_payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size > 0 AND payload_byte_size <= 16777216
        ),
        FOREIGN KEY (supersedes_ledger_id)
            REFERENCES analysis_coverage_ledgers(ledger_id),
        FOREIGN KEY (transcript_manifest_id)
            REFERENCES transcript_coverage_manifests(manifest_id),
        CHECK (supersedes_ledger_id IS NULL OR supersedes_ledger_id != ledger_id)
    );

    CREATE INDEX analysis_coverage_by_meeting
        ON analysis_coverage_ledgers(meeting_id, created_at_ms, ledger_id);

    CREATE TABLE analysis_coverage_entries (
        ledger_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        segment_object_type TEXT NOT NULL CHECK (segment_object_type = 'transcript_segment'),
        segment_logical_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        disposition TEXT NOT NULL CHECK (
            disposition IN ('substantive', 'non_substantive', 'failed', 'missing')
        ),
        attempt_count INTEGER NOT NULL CHECK (attempt_count BETWEEN 0 AND 100),
        safe_reason_code TEXT,
        PRIMARY KEY (ledger_id, segment_revision_id),
        UNIQUE (ledger_id, ordinal),
        FOREIGN KEY (ledger_id) REFERENCES analysis_coverage_ledgers(ledger_id),
        FOREIGN KEY (segment_object_type, segment_logical_id, segment_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE analysis_coverage_evidence (
        ledger_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        evidence_object_type TEXT NOT NULL CHECK (evidence_object_type = 'evidence_ref'),
        evidence_logical_id TEXT NOT NULL,
        evidence_revision_id TEXT NOT NULL,
        PRIMARY KEY (ledger_id, segment_revision_id, evidence_revision_id),
        FOREIGN KEY (ledger_id, segment_revision_id)
            REFERENCES analysis_coverage_entries(ledger_id, segment_revision_id),
        FOREIGN KEY (evidence_object_type, evidence_logical_id, evidence_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE analysis_coverage_outputs (
        ledger_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        output_object_type TEXT NOT NULL CHECK (output_object_type IN (
            'participant',
            'organization',
            'issue',
            'position',
            'commitment',
            'decision',
            'intervention_card',
            'delegation_position_card'
        )),
        output_logical_id TEXT NOT NULL,
        output_revision_id TEXT NOT NULL,
        PRIMARY KEY (ledger_id, segment_revision_id, output_revision_id),
        FOREIGN KEY (ledger_id, segment_revision_id)
            REFERENCES analysis_coverage_entries(ledger_id, segment_revision_id),
        FOREIGN KEY (output_object_type, output_logical_id, output_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE active_analysis_ledgers (
        meeting_id TEXT PRIMARY KEY NOT NULL,
        ledger_id TEXT NOT NULL UNIQUE,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (ledger_id) REFERENCES analysis_coverage_ledgers(ledger_id)
    );

    CREATE TABLE analysis_ledger_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        meeting_id TEXT NOT NULL,
        previous_ledger_id TEXT,
        replacement_ledger_id TEXT NOT NULL,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (previous_ledger_id) REFERENCES analysis_coverage_ledgers(ledger_id),
        FOREIGN KEY (replacement_ledger_id) REFERENCES analysis_coverage_ledgers(ledger_id)
    );

    CREATE TRIGGER analysis_coverage_ledgers_no_update
    BEFORE UPDATE ON analysis_coverage_ledgers
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage ledgers are immutable');
    END;

    CREATE TRIGGER analysis_coverage_ledgers_no_delete
    BEFORE DELETE ON analysis_coverage_ledgers
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage ledgers are immutable');
    END;

    CREATE TRIGGER analysis_coverage_entries_no_update
    BEFORE UPDATE ON analysis_coverage_entries
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage entries are immutable');
    END;

    CREATE TRIGGER analysis_coverage_entries_no_delete
    BEFORE DELETE ON analysis_coverage_entries
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage entries are immutable');
    END;

    CREATE TRIGGER analysis_coverage_evidence_no_update
    BEFORE UPDATE ON analysis_coverage_evidence
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage evidence is immutable');
    END;

    CREATE TRIGGER analysis_coverage_evidence_no_delete
    BEFORE DELETE ON analysis_coverage_evidence
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage evidence is immutable');
    END;

    CREATE TRIGGER analysis_coverage_outputs_no_update
    BEFORE UPDATE ON analysis_coverage_outputs
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage outputs are immutable');
    END;

    CREATE TRIGGER analysis_coverage_outputs_no_delete
    BEFORE DELETE ON analysis_coverage_outputs
    BEGIN
        SELECT RAISE(ABORT, 'analysis coverage outputs are immutable');
    END;

    CREATE TRIGGER analysis_ledger_events_no_update
    BEFORE UPDATE ON analysis_ledger_events
    BEGIN
        SELECT RAISE(ABORT, 'analysis ledger events are immutable');
    END;

    CREATE TRIGGER analysis_ledger_events_no_delete
    BEFORE DELETE ON analysis_ledger_events
    BEGIN
        SELECT RAISE(ABORT, 'analysis ledger events are immutable');
    END;

    CREATE TRIGGER active_analysis_ledger_validate_insert
    BEFORE INSERT ON active_analysis_ledgers
    WHEN NOT EXISTS (
        SELECT 1 FROM analysis_coverage_ledgers
        WHERE ledger_id = NEW.ledger_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN
        SELECT RAISE(ABORT, 'active analysis ledger target is not publishable');
    END;

    CREATE TRIGGER active_analysis_ledger_validate_update
    BEFORE UPDATE OF ledger_id ON active_analysis_ledgers
    WHEN NOT EXISTS (
        SELECT 1 FROM analysis_coverage_ledgers
        WHERE ledger_id = NEW.ledger_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN
        SELECT RAISE(ABORT, 'active analysis ledger target is not publishable');
    END;
    """

    /// Schema v5 adds the closed Task 006B semantic vocabulary plus immutable,
    /// normalized briefing coverage and explicit local export history. Existing
    /// v4 semantic and coverage payload bytes are copied without re-encoding.
    static let briefingSchemaSQL = """
    DROP TRIGGER semantic_revisions_no_update;
    DROP TRIGGER semantic_revisions_no_delete;

    CREATE TABLE semantic_revisions_v5 (
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
            'speaker_assignment',
            'participant',
            'organization',
            'issue',
            'position',
            'commitment',
            'decision',
            'intervention_card',
            'delegation_position_card',
            'meeting_template',
            'issue_position_graph',
            'briefing_section',
            'validation_report',
            'final_briefing'
        ))
    );

    INSERT INTO semantic_revisions_v5(
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
    )
    SELECT
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
    FROM semantic_revisions;

    DROP TABLE semantic_revisions;
    ALTER TABLE semantic_revisions_v5 RENAME TO semantic_revisions;

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

    CREATE TABLE briefing_coverage_ledgers (
        ledger_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(ledger_id) = 36 AND lower(ledger_id) = ledger_id
        ),
        supersedes_ledger_id TEXT,
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        transcript_manifest_id TEXT NOT NULL,
        analysis_ledger_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('incomplete', 'published')),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        content_hash_algorithm TEXT NOT NULL CHECK (content_hash_algorithm = 'sha256'),
        content_hash_hex TEXT NOT NULL CHECK (
            length(content_hash_hex) = 64 AND lower(content_hash_hex) = content_hash_hex
        ),
        canonical_payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size > 0 AND payload_byte_size <= 16777216
        ),
        FOREIGN KEY (supersedes_ledger_id)
            REFERENCES briefing_coverage_ledgers(ledger_id),
        FOREIGN KEY (transcript_manifest_id)
            REFERENCES transcript_coverage_manifests(manifest_id),
        FOREIGN KEY (analysis_ledger_id)
            REFERENCES analysis_coverage_ledgers(ledger_id),
        CHECK (supersedes_ledger_id IS NULL OR supersedes_ledger_id != ledger_id)
    );

    CREATE INDEX briefing_coverage_by_meeting
        ON briefing_coverage_ledgers(meeting_id, created_at_ms, ledger_id);

    CREATE TABLE briefing_coverage_entries (
        ledger_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        segment_object_type TEXT NOT NULL CHECK (segment_object_type = 'transcript_segment'),
        segment_logical_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        disposition TEXT NOT NULL CHECK (
            disposition IN (
                'represented', 'reviewed_not_rendered', 'non_substantive', 'failed', 'missing'
            )
        ),
        safe_reason_code TEXT,
        PRIMARY KEY (ledger_id, segment_revision_id),
        UNIQUE (ledger_id, ordinal),
        FOREIGN KEY (ledger_id) REFERENCES briefing_coverage_ledgers(ledger_id),
        FOREIGN KEY (segment_object_type, segment_logical_id, segment_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE briefing_coverage_evidence (
        ledger_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        evidence_object_type TEXT NOT NULL CHECK (evidence_object_type = 'evidence_ref'),
        evidence_logical_id TEXT NOT NULL,
        evidence_revision_id TEXT NOT NULL,
        PRIMARY KEY (ledger_id, segment_revision_id, evidence_revision_id),
        FOREIGN KEY (ledger_id, segment_revision_id)
            REFERENCES briefing_coverage_entries(ledger_id, segment_revision_id),
        FOREIGN KEY (evidence_object_type, evidence_logical_id, evidence_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE briefing_coverage_analysis_outputs (
        ledger_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        output_object_type TEXT NOT NULL CHECK (output_object_type IN (
            'participant', 'organization', 'issue', 'position', 'commitment',
            'decision', 'intervention_card', 'delegation_position_card'
        )),
        output_logical_id TEXT NOT NULL,
        output_revision_id TEXT NOT NULL,
        PRIMARY KEY (ledger_id, segment_revision_id, output_revision_id),
        FOREIGN KEY (ledger_id, segment_revision_id)
            REFERENCES briefing_coverage_entries(ledger_id, segment_revision_id),
        FOREIGN KEY (output_object_type, output_logical_id, output_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE briefing_coverage_conclusions (
        ledger_id TEXT NOT NULL,
        segment_revision_id TEXT NOT NULL,
        output_object_type TEXT NOT NULL CHECK (
            output_object_type IN ('issue_position_graph', 'briefing_section')
        ),
        output_logical_id TEXT NOT NULL,
        output_revision_id TEXT NOT NULL,
        item_id TEXT NOT NULL CHECK (length(item_id) = 36 AND lower(item_id) = item_id),
        PRIMARY KEY (ledger_id, segment_revision_id, output_revision_id, item_id),
        FOREIGN KEY (ledger_id, segment_revision_id)
            REFERENCES briefing_coverage_entries(ledger_id, segment_revision_id),
        FOREIGN KEY (output_object_type, output_logical_id, output_revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE active_briefing_ledgers (
        meeting_id TEXT PRIMARY KEY NOT NULL,
        ledger_id TEXT NOT NULL UNIQUE,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (ledger_id) REFERENCES briefing_coverage_ledgers(ledger_id)
    );

    CREATE TABLE briefing_ledger_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        meeting_id TEXT NOT NULL,
        previous_ledger_id TEXT,
        replacement_ledger_id TEXT NOT NULL,
        pointer_version INTEGER NOT NULL CHECK (pointer_version > 0),
        changed_at_ms INTEGER NOT NULL CHECK (changed_at_ms >= 0),
        FOREIGN KEY (previous_ledger_id) REFERENCES briefing_coverage_ledgers(ledger_id),
        FOREIGN KEY (replacement_ledger_id) REFERENCES briefing_coverage_ledgers(ledger_id)
    );

    CREATE TABLE briefing_export_records (
        export_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(export_id) = 36 AND lower(export_id) = export_id
        ),
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        final_revision_id TEXT NOT NULL,
        relative_path TEXT NOT NULL UNIQUE,
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        exported_at_ms INTEGER NOT NULL CHECK (exported_at_ms >= 0),
        canonical_payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size > 0 AND payload_byte_size <= 1048576
        ),
        FOREIGN KEY (final_revision_id) REFERENCES semantic_revisions(revision_id)
    );

    CREATE INDEX briefing_exports_by_meeting
        ON briefing_export_records(meeting_id, exported_at_ms, export_id);

    CREATE TRIGGER briefing_coverage_ledgers_no_update
    BEFORE UPDATE ON briefing_coverage_ledgers
    BEGIN SELECT RAISE(ABORT, 'briefing coverage ledgers are immutable'); END;

    CREATE TRIGGER briefing_coverage_ledgers_no_delete
    BEFORE DELETE ON briefing_coverage_ledgers
    BEGIN SELECT RAISE(ABORT, 'briefing coverage ledgers are immutable'); END;

    CREATE TRIGGER briefing_coverage_entries_no_update
    BEFORE UPDATE ON briefing_coverage_entries
    BEGIN SELECT RAISE(ABORT, 'briefing coverage entries are immutable'); END;

    CREATE TRIGGER briefing_coverage_entries_no_delete
    BEFORE DELETE ON briefing_coverage_entries
    BEGIN SELECT RAISE(ABORT, 'briefing coverage entries are immutable'); END;

    CREATE TRIGGER briefing_coverage_evidence_no_update
    BEFORE UPDATE ON briefing_coverage_evidence
    BEGIN SELECT RAISE(ABORT, 'briefing coverage evidence is immutable'); END;

    CREATE TRIGGER briefing_coverage_evidence_no_delete
    BEFORE DELETE ON briefing_coverage_evidence
    BEGIN SELECT RAISE(ABORT, 'briefing coverage evidence is immutable'); END;

    CREATE TRIGGER briefing_coverage_analysis_outputs_no_update
    BEFORE UPDATE ON briefing_coverage_analysis_outputs
    BEGIN SELECT RAISE(ABORT, 'briefing coverage outputs are immutable'); END;

    CREATE TRIGGER briefing_coverage_analysis_outputs_no_delete
    BEFORE DELETE ON briefing_coverage_analysis_outputs
    BEGIN SELECT RAISE(ABORT, 'briefing coverage outputs are immutable'); END;

    CREATE TRIGGER briefing_coverage_conclusions_no_update
    BEFORE UPDATE ON briefing_coverage_conclusions
    BEGIN SELECT RAISE(ABORT, 'briefing conclusions are immutable'); END;

    CREATE TRIGGER briefing_coverage_conclusions_no_delete
    BEFORE DELETE ON briefing_coverage_conclusions
    BEGIN SELECT RAISE(ABORT, 'briefing conclusions are immutable'); END;

    CREATE TRIGGER briefing_ledger_events_no_update
    BEFORE UPDATE ON briefing_ledger_events
    BEGIN SELECT RAISE(ABORT, 'briefing ledger events are immutable'); END;

    CREATE TRIGGER briefing_ledger_events_no_delete
    BEFORE DELETE ON briefing_ledger_events
    BEGIN SELECT RAISE(ABORT, 'briefing ledger events are immutable'); END;

    CREATE TRIGGER briefing_export_records_no_update
    BEFORE UPDATE ON briefing_export_records
    BEGIN SELECT RAISE(ABORT, 'briefing export records are immutable'); END;

    CREATE TRIGGER briefing_export_records_no_delete
    BEFORE DELETE ON briefing_export_records
    BEGIN SELECT RAISE(ABORT, 'briefing export records are immutable'); END;

    CREATE TRIGGER active_briefing_ledger_validate_insert
    BEFORE INSERT ON active_briefing_ledgers
    WHEN NOT EXISTS (
        SELECT 1 FROM briefing_coverage_ledgers
        WHERE ledger_id = NEW.ledger_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN SELECT RAISE(ABORT, 'active briefing ledger target is not publishable'); END;

    CREATE TRIGGER active_briefing_ledger_validate_update
    BEFORE UPDATE OF ledger_id ON active_briefing_ledgers
    WHEN NOT EXISTS (
        SELECT 1 FROM briefing_coverage_ledgers
        WHERE ledger_id = NEW.ledger_id
          AND meeting_id = NEW.meeting_id
          AND status = 'published'
    )
    BEGIN SELECT RAISE(ABORT, 'active briefing ledger target is not publishable'); END;
    """

    /// Schema v6 adds the two independent Task 007 policy contracts and an
    /// auditable, crash-recoverable filesystem-unlink ledger. Existing semantic
    /// payload bytes remain unchanged and no migration fabricates policy authority.
    static let hardeningSchemaSQL = """
    DROP TRIGGER semantic_revisions_no_update;
    DROP TRIGGER semantic_revisions_no_delete;

    CREATE TABLE semantic_revisions_v6 (
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
            'speaker_assignment',
            'participant',
            'organization',
            'issue',
            'position',
            'commitment',
            'decision',
            'intervention_card',
            'delegation_position_card',
            'meeting_template',
            'issue_position_graph',
            'briefing_section',
            'validation_report',
            'final_briefing',
            'sensitivity_label',
            'access_policy'
        ))
    );

    INSERT INTO semantic_revisions_v6(
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
    )
    SELECT
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
    FROM semantic_revisions;

    DROP TABLE semantic_revisions;
    ALTER TABLE semantic_revisions_v6 RENAME TO semantic_revisions;

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

    CREATE TABLE managed_asset_purge_operations (
        operation_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(operation_id) = 36 AND lower(operation_id) = operation_id
        ),
        storage_object_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK (
            state IN ('intent', 'completed', 'rolled_back', 'repair_required')
        ),
        requested_at_ms INTEGER NOT NULL CHECK (requested_at_ms >= 0),
        finished_at_ms INTEGER CHECK (finished_at_ms >= requested_at_ms),
        failure_code TEXT CHECK (failure_code IS NULL OR length(failure_code) BETWEEN 1 AND 96),
        intent_payload BLOB NOT NULL,
        intent_sha256 TEXT NOT NULL CHECK (
            length(intent_sha256) = 64 AND lower(intent_sha256) = intent_sha256
        ),
        intent_byte_size INTEGER NOT NULL CHECK (
            intent_byte_size > 0 AND intent_byte_size <= 1048576
        ),
        receipt_payload BLOB,
        receipt_sha256 TEXT,
        receipt_byte_size INTEGER,
        FOREIGN KEY (storage_object_id) REFERENCES managed_assets(storage_object_id),
        CHECK (
            (state = 'intent' AND finished_at_ms IS NULL AND failure_code IS NULL
                AND receipt_payload IS NULL AND receipt_sha256 IS NULL
                AND receipt_byte_size IS NULL)
            OR
            (state = 'completed' AND finished_at_ms IS NOT NULL AND failure_code IS NULL
                AND receipt_payload IS NOT NULL
                AND length(receipt_sha256) = 64 AND lower(receipt_sha256) = receipt_sha256
                AND receipt_byte_size > 0 AND receipt_byte_size <= 1048576)
            OR
            (state = 'rolled_back' AND finished_at_ms IS NOT NULL
                AND receipt_payload IS NULL AND receipt_sha256 IS NULL
                AND receipt_byte_size IS NULL)
            OR
            (state = 'repair_required' AND finished_at_ms IS NOT NULL
                AND failure_code IS NOT NULL)
        )
    );

    CREATE INDEX managed_asset_purge_operations_by_state
        ON managed_asset_purge_operations(state, requested_at_ms, operation_id);

    CREATE UNIQUE INDEX managed_asset_purge_operations_one_live_per_asset
        ON managed_asset_purge_operations(storage_object_id)
        WHERE state IN ('intent', 'repair_required', 'completed');

    CREATE TABLE managed_asset_purge_receipts (
        purge_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(purge_id) = 36 AND lower(purge_id) = purge_id
        ),
        storage_object_id TEXT NOT NULL UNIQUE,
        purged_at_ms INTEGER NOT NULL CHECK (purged_at_ms >= 0),
        deletion_method TEXT NOT NULL CHECK (
            deletion_method = 'filesystem_unlink_no_erasure_guarantee'
        ),
        prior_hash_algorithm TEXT NOT NULL CHECK (prior_hash_algorithm = 'sha256'),
        prior_hash_hex TEXT NOT NULL CHECK (
            length(prior_hash_hex) = 64 AND lower(prior_hash_hex) = prior_hash_hex
        ),
        prior_byte_size_decimal TEXT NOT NULL CHECK (
            length(prior_byte_size_decimal) BETWEEN 1 AND 20
        ),
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        receipt_payload BLOB NOT NULL,
        receipt_sha256 TEXT NOT NULL CHECK (
            length(receipt_sha256) = 64 AND lower(receipt_sha256) = receipt_sha256
        ),
        receipt_byte_size INTEGER NOT NULL CHECK (
            receipt_byte_size > 0 AND receipt_byte_size <= 1048576
        ),
        FOREIGN KEY (storage_object_id) REFERENCES managed_assets(storage_object_id)
    );

    CREATE TRIGGER managed_asset_purge_receipts_no_update
    BEFORE UPDATE ON managed_asset_purge_receipts
    BEGIN SELECT RAISE(ABORT, 'managed asset purge receipts are immutable'); END;

    CREATE TRIGGER managed_asset_purge_receipts_no_delete
    BEFORE DELETE ON managed_asset_purge_receipts
    BEGIN SELECT RAISE(ABORT, 'managed asset purge receipts are immutable'); END;
    """

    static let recordingCaptureSchemaSQL = """
    CREATE TABLE recording_sessions (
        session_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(session_id) = 36 AND lower(session_id) = session_id
        ),
        job_id TEXT NOT NULL UNIQUE CHECK (
            length(job_id) = 36 AND lower(job_id) = job_id
        ),
        meeting_id TEXT NOT NULL CHECK (
            length(meeting_id) = 36 AND lower(meeting_id) = meeting_id
        ),
        intent_format_version INTEGER NOT NULL CHECK (intent_format_version = 1),
        capture_mode TEXT NOT NULL CHECK (capture_mode IN (
            'microphone_only', 'application_audio_only',
            'microphone_and_application_audio'
        )),
        requested_track_count INTEGER NOT NULL CHECK (requested_track_count IN (1, 2)),
        sensitivity_label_revision_id TEXT NOT NULL CHECK (
            length(sensitivity_label_revision_id) = 36
                AND lower(sensitivity_label_revision_id) = sensitivity_label_revision_id
        ),
        access_policy_revision_id TEXT NOT NULL CHECK (
            length(access_policy_revision_id) = 36
                AND lower(access_policy_revision_id) = access_policy_revision_id
        ),
        data_classification TEXT NOT NULL CHECK (
            data_classification IN ('public', 'internal', 'sensitive', 'restricted')
        ),
        no_outbound_mode INTEGER NOT NULL CHECK (no_outbound_mode IN (0, 1)),
        authorization_event_id TEXT NOT NULL UNIQUE CHECK (
            length(authorization_event_id) = 36 AND lower(authorization_event_id) = authorization_event_id
        ),
        state TEXT NOT NULL CHECK (state IN (
            'preparing', 'recording', 'interrupted', 'recovering', 'stopping',
            'finalizing', 'completed', 'incomplete', 'failed'
        )),
        state_version INTEGER NOT NULL CHECK (state_version > 0),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
        terminal_reason TEXT,
        final_manifest_logical_id TEXT,
        final_manifest_revision_id TEXT,
        intent_payload BLOB NOT NULL CHECK (
            length(intent_payload) BETWEEN 1 AND 65536
        ),
        intent_sha256 TEXT NOT NULL CHECK (
            length(intent_sha256) = 64 AND lower(intent_sha256) = intent_sha256
        ),
        CHECK (
            (state IN ('completed', 'incomplete', 'failed') AND terminal_reason IS NOT NULL)
            OR (state NOT IN ('completed', 'incomplete', 'failed') AND terminal_reason IS NULL)
        ),
        CHECK (
            (final_manifest_logical_id IS NULL AND final_manifest_revision_id IS NULL)
            OR (state = 'completed'
                AND length(final_manifest_logical_id) = 36
                AND lower(final_manifest_logical_id) = final_manifest_logical_id
                AND length(final_manifest_revision_id) = 36
                AND lower(final_manifest_revision_id) = final_manifest_revision_id)
        )
    );

    CREATE TABLE recording_state_events (
        event_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(event_id) = 36 AND lower(event_id) = event_id
        ),
        session_id TEXT NOT NULL,
        prior_state TEXT NOT NULL CHECK (prior_state IN (
            'preparing', 'recording', 'interrupted', 'recovering', 'stopping',
            'finalizing', 'completed', 'incomplete', 'failed'
        )),
        replacement_state TEXT NOT NULL CHECK (replacement_state IN (
            'preparing', 'recording', 'interrupted', 'recovering', 'stopping',
            'finalizing', 'completed', 'incomplete', 'failed'
        )),
        prior_version INTEGER NOT NULL CHECK (prior_version > 0),
        replacement_version INTEGER NOT NULL CHECK (replacement_version = prior_version + 1),
        reason TEXT NOT NULL,
        actor TEXT NOT NULL CHECK (actor IN (
            'user', 'capture_provider', 'persistence_coordinator',
            'task_manager', 'startup_recovery'
        )),
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        event_payload BLOB NOT NULL CHECK (length(event_payload) BETWEEN 1 AND 65536),
        event_sha256 TEXT NOT NULL CHECK (
            length(event_sha256) = 64 AND lower(event_sha256) = event_sha256
        ),
        UNIQUE (session_id, prior_version),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id),
        CHECK (
            (prior_state = 'preparing' AND replacement_state IN ('recording', 'stopping', 'failed'))
            OR (prior_state = 'recording' AND replacement_state IN ('interrupted', 'stopping'))
            OR (prior_state = 'interrupted' AND replacement_state = 'recovering')
            OR (prior_state = 'recovering' AND replacement_state IN ('recording', 'stopping', 'finalizing'))
            OR (prior_state = 'stopping' AND replacement_state = 'finalizing')
            OR (prior_state = 'finalizing' AND replacement_state IN ('completed', 'incomplete', 'failed'))
        )
    );

    CREATE TABLE recording_tracks (
        track_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(track_id) = 36 AND lower(track_id) = track_id
        ),
        session_id TEXT NOT NULL,
        source_kind TEXT NOT NULL CHECK (source_kind IN ('microphone', 'application_audio')),
        is_required INTEGER NOT NULL CHECK (is_required IN (0, 1)),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        UNIQUE (session_id, source_kind),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id)
    );

    CREATE TABLE recording_epochs (
        epoch_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(epoch_id) = 36 AND lower(epoch_id) = epoch_id
        ),
        session_id TEXT NOT NULL,
        epoch_sequence INTEGER NOT NULL CHECK (epoch_sequence > 0),
        selected_at_ms INTEGER NOT NULL CHECK (selected_at_ms >= 0),
        source_count INTEGER NOT NULL CHECK (source_count IN (1, 2)),
        source_set_digest_sha256 TEXT NOT NULL CHECK (
            length(source_set_digest_sha256) = 64
                AND lower(source_set_digest_sha256) = source_set_digest_sha256
        ),
        start_host_ns_decimal TEXT NOT NULL CHECK (length(start_host_ns_decimal) BETWEEN 1 AND 20),
        ended_at_ms INTEGER,
        end_reason TEXT,
        epoch_payload BLOB NOT NULL CHECK (length(epoch_payload) BETWEEN 1 AND 65536),
        epoch_sha256 TEXT NOT NULL CHECK (
            length(epoch_sha256) = 64 AND lower(epoch_sha256) = epoch_sha256
        ),
        UNIQUE (session_id, epoch_sequence),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id),
        CHECK (
            (ended_at_ms IS NULL AND end_reason IS NULL)
            OR (ended_at_ms >= selected_at_ms AND end_reason IS NOT NULL)
        )
    );

    CREATE TABLE recording_segments (
        segment_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(segment_id) = 36 AND lower(segment_id) = segment_id
        ),
        session_id TEXT NOT NULL,
        epoch_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        segment_sequence INTEGER NOT NULL CHECK (segment_sequence > 0),
        media_start_ns_decimal TEXT NOT NULL CHECK (length(media_start_ns_decimal) BETWEEN 1 AND 20),
        media_end_ns_decimal TEXT NOT NULL CHECK (length(media_end_ns_decimal) BETWEEN 1 AND 20),
        host_start_ns_decimal TEXT NOT NULL CHECK (length(host_start_ns_decimal) BETWEEN 1 AND 20),
        host_end_ns_decimal TEXT NOT NULL CHECK (length(host_end_ns_decimal) BETWEEN 1 AND 20),
        frame_count_decimal TEXT NOT NULL CHECK (length(frame_count_decimal) BETWEEN 1 AND 20),
        storage_object_id TEXT NOT NULL UNIQUE,
        content_hash_sha256 TEXT NOT NULL CHECK (
            length(content_hash_sha256) = 64 AND lower(content_hash_sha256) = content_hash_sha256
        ),
        byte_size_decimal TEXT NOT NULL CHECK (length(byte_size_decimal) BETWEEN 1 AND 20),
        rolling_descriptor_sha256 TEXT NOT NULL CHECK (
            length(rolling_descriptor_sha256) = 64
                AND lower(rolling_descriptor_sha256) = rolling_descriptor_sha256
        ),
        sealed_at_ms INTEGER NOT NULL CHECK (sealed_at_ms >= 0),
        checkpoint_committed_at_ms INTEGER NOT NULL CHECK (checkpoint_committed_at_ms >= sealed_at_ms),
        segment_payload BLOB NOT NULL CHECK (length(segment_payload) BETWEEN 1 AND 65536),
        segment_sha256 TEXT NOT NULL CHECK (
            length(segment_sha256) = 64 AND lower(segment_sha256) = segment_sha256
        ),
        UNIQUE (track_id, epoch_id, segment_sequence),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id),
        FOREIGN KEY (epoch_id) REFERENCES recording_epochs(epoch_id),
        FOREIGN KEY (track_id) REFERENCES recording_tracks(track_id),
        FOREIGN KEY (storage_object_id) REFERENCES managed_assets(storage_object_id)
    );

    CREATE TABLE recording_gaps (
        gap_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(gap_id) = 36 AND lower(gap_id) = gap_id
        ),
        session_id TEXT NOT NULL,
        epoch_id TEXT,
        track_id TEXT NOT NULL,
        media_start_ns_decimal TEXT,
        media_end_ns_decimal TEXT,
        host_start_ns_decimal TEXT,
        host_end_ns_decimal TEXT,
        reason TEXT NOT NULL,
        detected_by TEXT NOT NULL CHECK (detected_by IN (
            'user', 'capture_provider', 'persistence_coordinator',
            'task_manager', 'startup_recovery'
        )),
        detected_at_ms INTEGER NOT NULL CHECK (detected_at_ms >= 0),
        user_acknowledged_at_ms INTEGER CHECK (user_acknowledged_at_ms >= detected_at_ms),
        gap_payload BLOB NOT NULL CHECK (length(gap_payload) BETWEEN 1 AND 65536),
        gap_sha256 TEXT NOT NULL CHECK (
            length(gap_sha256) = 64 AND lower(gap_sha256) = gap_sha256
        ),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id),
        FOREIGN KEY (epoch_id) REFERENCES recording_epochs(epoch_id),
        FOREIGN KEY (track_id) REFERENCES recording_tracks(track_id),
        CHECK (
            (media_start_ns_decimal IS NULL AND media_end_ns_decimal IS NULL)
            OR (media_start_ns_decimal IS NOT NULL AND media_end_ns_decimal IS NOT NULL)
        ),
        CHECK (
            (host_start_ns_decimal IS NULL AND host_end_ns_decimal IS NULL)
            OR (host_start_ns_decimal IS NOT NULL AND host_end_ns_decimal IS NOT NULL)
        )
    );

    CREATE TABLE recording_checkpoints (
        checkpoint_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(checkpoint_id) = 36 AND lower(checkpoint_id) = checkpoint_id
        ),
        session_id TEXT NOT NULL,
        state_version INTEGER NOT NULL CHECK (state_version > 0),
        format_identifier TEXT NOT NULL CHECK (
            format_identifier = 'meetingbuddy.recording-checkpoint.v1'
        ),
        format_version INTEGER NOT NULL CHECK (format_version = 1),
        created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
        checkpoint_payload BLOB NOT NULL CHECK (length(checkpoint_payload) BETWEEN 1 AND 65536),
        checkpoint_sha256 TEXT NOT NULL CHECK (
            length(checkpoint_sha256) = 64 AND lower(checkpoint_sha256) = checkpoint_sha256
        ),
        UNIQUE (session_id, checkpoint_sha256),
        FOREIGN KEY (session_id) REFERENCES recording_sessions(session_id)
    );

    CREATE INDEX recording_sessions_by_state ON recording_sessions(state, updated_at_ms);
    CREATE INDEX recording_segments_by_session_track
        ON recording_segments(session_id, track_id, segment_sequence);
    CREATE INDEX recording_gaps_by_session_track
        ON recording_gaps(session_id, track_id, detected_at_ms);
    CREATE INDEX recording_checkpoints_by_session
        ON recording_checkpoints(session_id, created_at_ms, checkpoint_id);

    CREATE TRIGGER recording_state_events_no_update
    BEFORE UPDATE ON recording_state_events
    BEGIN SELECT RAISE(ABORT, 'recording state events are immutable'); END;
    CREATE TRIGGER recording_state_events_no_delete
    BEFORE DELETE ON recording_state_events
    BEGIN SELECT RAISE(ABORT, 'recording state events are immutable'); END;
    CREATE TRIGGER recording_tracks_no_update
    BEFORE UPDATE ON recording_tracks
    BEGIN SELECT RAISE(ABORT, 'recording tracks are immutable'); END;
    CREATE TRIGGER recording_tracks_no_delete
    BEFORE DELETE ON recording_tracks
    BEGIN SELECT RAISE(ABORT, 'recording tracks are immutable'); END;
    CREATE TRIGGER recording_epochs_no_update
    BEFORE UPDATE ON recording_epochs
    BEGIN SELECT RAISE(ABORT, 'recording epochs are immutable'); END;
    CREATE TRIGGER recording_epochs_no_delete
    BEFORE DELETE ON recording_epochs
    BEGIN SELECT RAISE(ABORT, 'recording epochs are immutable'); END;
    CREATE TRIGGER recording_segments_no_update
    BEFORE UPDATE ON recording_segments
    BEGIN SELECT RAISE(ABORT, 'recording segments are immutable'); END;
    CREATE TRIGGER recording_segments_no_delete
    BEFORE DELETE ON recording_segments
    BEGIN SELECT RAISE(ABORT, 'recording segments are immutable'); END;
    CREATE TRIGGER recording_gaps_no_update
    BEFORE UPDATE ON recording_gaps
    BEGIN SELECT RAISE(ABORT, 'recording gaps are immutable'); END;
    CREATE TRIGGER recording_gaps_no_delete
    BEFORE DELETE ON recording_gaps
    BEGIN SELECT RAISE(ABORT, 'recording gaps are immutable'); END;
    CREATE TRIGGER recording_checkpoints_no_update
    BEFORE UPDATE ON recording_checkpoints
    BEGIN SELECT RAISE(ABORT, 'recording checkpoints are immutable'); END;
    CREATE TRIGGER recording_checkpoints_no_delete
    BEFORE DELETE ON recording_checkpoints
    BEGIN SELECT RAISE(ABORT, 'recording checkpoints are immutable'); END;
    """

    /// Schema v8 adds the local automation audit/replay boundary and one
    /// versioned, reversible safe setting. It neither rewrites semantic rows
    /// nor materializes the compiled settings default.
    static let automationSchemaSQL = """
    CREATE TABLE automation_command_records (
        command_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(command_id) = 36 AND lower(command_id) = command_id
        ),
        replay_nonce TEXT NOT NULL CHECK (
            length(replay_nonce) = 36 AND lower(replay_nonce) = replay_nonce
        ),
        claims_replay_nonce INTEGER NOT NULL CHECK (claims_replay_nonce IN (0, 1)),
        replay_of_command_id TEXT,
        command_name TEXT NOT NULL CHECK (command_name IN (
            'get_command_catalog', 'get_workspace_status', 'get_meeting_policy_status',
            'get_storage_report', 'get_settings', 'describe_settings',
            'update_settings', 'rollback_settings', 'list_activity',
            'run_workspace_diagnostics'
        )),
        request_sha256 TEXT NOT NULL CHECK (
            length(request_sha256) = 64 AND lower(request_sha256) = request_sha256
        ),
        workspace_id TEXT NOT NULL CHECK (
            length(workspace_id) = 36 AND lower(workspace_id) = workspace_id
        ),
        meeting_id TEXT,
        actor_id TEXT NOT NULL CHECK (length(actor_id) BETWEEN 1 AND 128),
        origin TEXT NOT NULL CHECK (origin IN ('application', 'cli')),
        adapter_version TEXT NOT NULL CHECK (length(adapter_version) BETWEEN 1 AND 64),
        granted_permission TEXT NOT NULL CHECK (
            granted_permission IN ('read', 'safe_configuration', 'operational', 'sensitive')
        ),
        required_permission TEXT NOT NULL CHECK (
            required_permission IN ('read', 'safe_configuration', 'operational', 'sensitive')
        ),
        decision TEXT NOT NULL CHECK (decision IN ('authorized', 'denied', 'replayed')),
        safe_reason_code TEXT NOT NULL CHECK (length(safe_reason_code) BETWEEN 1 AND 96),
        confirmation_requirement TEXT NOT NULL CHECK (
            confirmation_requirement IN ('none', 'trusted_application_one_time')
        ),
        root_command_id TEXT,
        parent_command_id TEXT,
        hop_count INTEGER NOT NULL CHECK (hop_count BETWEEN 0 AND 255),
        recorded_at_ms INTEGER NOT NULL CHECK (recorded_at_ms >= 0),
        canonical_payload BLOB NOT NULL CHECK (length(canonical_payload) BETWEEN 1 AND 1048576),
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size = length(canonical_payload)
                AND payload_byte_size BETWEEN 1 AND 1048576
        ),
        FOREIGN KEY (replay_of_command_id) REFERENCES automation_command_records(command_id),
        CHECK (
            (claims_replay_nonce = 1 AND replay_of_command_id IS NULL AND decision != 'replayed')
            OR (claims_replay_nonce = 0 AND replay_of_command_id IS NOT NULL AND decision = 'replayed')
        ),
        CHECK (
            (hop_count = 0 AND root_command_id IS NULL AND parent_command_id IS NULL)
            OR (hop_count > 0 AND root_command_id IS NOT NULL AND parent_command_id IS NOT NULL)
        )
    );

    CREATE UNIQUE INDEX automation_command_records_claimed_nonce
        ON automation_command_records(replay_nonce)
        WHERE claims_replay_nonce = 1;
    CREATE INDEX automation_command_records_activity
        ON automation_command_records(recorded_at_ms DESC, command_id DESC);

    CREATE TABLE automation_command_input_revisions (
        command_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0 AND ordinal < 32),
        object_type TEXT NOT NULL,
        logical_id TEXT NOT NULL,
        revision_id TEXT NOT NULL,
        PRIMARY KEY (command_id, ordinal),
        UNIQUE (command_id, object_type, logical_id, revision_id),
        FOREIGN KEY (command_id) REFERENCES automation_command_records(command_id),
        FOREIGN KEY (object_type, logical_id, revision_id)
            REFERENCES semantic_revisions(object_type, logical_id, revision_id)
    );

    CREATE TABLE automation_command_result_events (
        event_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(event_id) = 36 AND lower(event_id) = event_id
        ),
        command_id TEXT NOT NULL UNIQUE,
        sequence INTEGER NOT NULL CHECK (sequence = 1),
        outcome TEXT NOT NULL CHECK (
            outcome IN ('completed', 'failed', 'rejected', 'rolled_back')
        ),
        safe_code TEXT NOT NULL CHECK (length(safe_code) BETWEEN 1 AND 96),
        result_sha256 TEXT,
        prior_settings_version INTEGER,
        replacement_settings_version INTEGER,
        rollback_of_command_id TEXT,
        used_restricted_task_directory INTEGER NOT NULL CHECK (
            used_restricted_task_directory IN (0, 1)
        ),
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        canonical_payload BLOB NOT NULL CHECK (length(canonical_payload) BETWEEN 1 AND 1048576),
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size = length(canonical_payload)
                AND payload_byte_size BETWEEN 1 AND 1048576
        ),
        FOREIGN KEY (command_id) REFERENCES automation_command_records(command_id),
        FOREIGN KEY (rollback_of_command_id) REFERENCES automation_command_records(command_id),
        CHECK (
            (outcome IN ('completed', 'rolled_back')
                AND length(result_sha256) = 64 AND lower(result_sha256) = result_sha256)
            OR (outcome IN ('failed', 'rejected') AND result_sha256 IS NULL)
        ),
        CHECK (
            (prior_settings_version IS NULL AND replacement_settings_version IS NULL)
            OR (prior_settings_version >= 0
                AND replacement_settings_version = prior_settings_version + 1)
        ),
        CHECK (outcome != 'rolled_back' OR rollback_of_command_id IS NOT NULL)
    );

    CREATE TABLE automation_settings_state (
        singleton INTEGER PRIMARY KEY NOT NULL CHECK (singleton = 1),
        version INTEGER NOT NULL CHECK (version > 0),
        status_list_limit INTEGER NOT NULL CHECK (status_list_limit BETWEEN 1 AND 200),
        updated_by_command_id TEXT NOT NULL UNIQUE,
        updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0),
        canonical_payload BLOB NOT NULL CHECK (length(canonical_payload) BETWEEN 1 AND 65536),
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size = length(canonical_payload)
                AND payload_byte_size BETWEEN 1 AND 65536
        ),
        FOREIGN KEY (updated_by_command_id) REFERENCES automation_command_records(command_id)
    );

    CREATE TABLE automation_settings_events (
        event_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(event_id) = 36 AND lower(event_id) = event_id
        ),
        command_id TEXT NOT NULL UNIQUE,
        prior_version INTEGER NOT NULL CHECK (prior_version >= 0),
        replacement_version INTEGER NOT NULL CHECK (replacement_version = prior_version + 1),
        prior_status_list_limit INTEGER NOT NULL CHECK (prior_status_list_limit BETWEEN 1 AND 200),
        replacement_status_list_limit INTEGER NOT NULL CHECK (
            replacement_status_list_limit BETWEEN 1 AND 200
        ),
        rollback_of_command_id TEXT,
        occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
        canonical_payload BLOB NOT NULL CHECK (length(canonical_payload) BETWEEN 1 AND 65536),
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size = length(canonical_payload)
                AND payload_byte_size BETWEEN 1 AND 65536
        ),
        FOREIGN KEY (command_id) REFERENCES automation_command_records(command_id),
        FOREIGN KEY (rollback_of_command_id) REFERENCES automation_command_records(command_id),
        CHECK (prior_status_list_limit != replacement_status_list_limit)
    );

    CREATE TRIGGER automation_command_records_no_update
    BEFORE UPDATE ON automation_command_records
    BEGIN SELECT RAISE(ABORT, 'automation command records are immutable'); END;
    CREATE TRIGGER automation_command_records_no_delete
    BEFORE DELETE ON automation_command_records
    BEGIN SELECT RAISE(ABORT, 'automation command records are immutable'); END;
    CREATE TRIGGER automation_command_input_revisions_no_update
    BEFORE UPDATE ON automation_command_input_revisions
    BEGIN SELECT RAISE(ABORT, 'automation command inputs are immutable'); END;
    CREATE TRIGGER automation_command_input_revisions_no_delete
    BEFORE DELETE ON automation_command_input_revisions
    BEGIN SELECT RAISE(ABORT, 'automation command inputs are immutable'); END;
    CREATE TRIGGER automation_command_result_events_no_update
    BEFORE UPDATE ON automation_command_result_events
    BEGIN SELECT RAISE(ABORT, 'automation result events are immutable'); END;
    CREATE TRIGGER automation_command_result_events_no_delete
    BEFORE DELETE ON automation_command_result_events
    BEGIN SELECT RAISE(ABORT, 'automation result events are immutable'); END;
    CREATE TRIGGER automation_settings_events_no_update
    BEFORE UPDATE ON automation_settings_events
    BEGIN SELECT RAISE(ABORT, 'automation settings events are immutable'); END;
    CREATE TRIGGER automation_settings_events_no_delete
    BEFORE DELETE ON automation_settings_events
    BEGIN SELECT RAISE(ABORT, 'automation settings events are immutable'); END;
    CREATE TRIGGER automation_settings_state_first_version
    BEFORE INSERT ON automation_settings_state WHEN NEW.version != 1
    BEGIN SELECT RAISE(ABORT, 'automation settings must begin at version one'); END;
    CREATE TRIGGER automation_settings_state_next_version
    BEFORE UPDATE ON automation_settings_state WHEN NEW.version != OLD.version + 1
    BEGIN SELECT RAISE(ABORT, 'automation settings version must advance exactly once'); END;
    CREATE TRIGGER automation_settings_state_no_delete
    BEFORE DELETE ON automation_settings_state
    BEGIN SELECT RAISE(ABORT, 'automation settings state cannot be deleted'); END;
    """

    /// Schema v9 preserves every v8 audit/settings byte while allowing the
    /// shared command repository to attribute local MCP calls truthfully.
    /// No semantic, settings, command, or result payload is rewritten.
    static let mcpAuditOriginSchemaSQL = """
    CREATE TABLE automation_command_records_v9 (
        command_id TEXT PRIMARY KEY NOT NULL CHECK (
            length(command_id) = 36 AND lower(command_id) = command_id
        ),
        replay_nonce TEXT NOT NULL CHECK (
            length(replay_nonce) = 36 AND lower(replay_nonce) = replay_nonce
        ),
        claims_replay_nonce INTEGER NOT NULL CHECK (claims_replay_nonce IN (0, 1)),
        replay_of_command_id TEXT,
        command_name TEXT NOT NULL CHECK (command_name IN (
            'get_command_catalog', 'get_workspace_status', 'get_meeting_policy_status',
            'get_storage_report', 'get_settings', 'describe_settings',
            'update_settings', 'rollback_settings', 'list_activity',
            'run_workspace_diagnostics'
        )),
        request_sha256 TEXT NOT NULL CHECK (
            length(request_sha256) = 64 AND lower(request_sha256) = request_sha256
        ),
        workspace_id TEXT NOT NULL CHECK (
            length(workspace_id) = 36 AND lower(workspace_id) = workspace_id
        ),
        meeting_id TEXT,
        actor_id TEXT NOT NULL CHECK (length(actor_id) BETWEEN 1 AND 128),
        origin TEXT NOT NULL CHECK (origin IN ('application', 'cli', 'mcp')),
        adapter_version TEXT NOT NULL CHECK (length(adapter_version) BETWEEN 1 AND 64),
        granted_permission TEXT NOT NULL CHECK (
            granted_permission IN ('read', 'safe_configuration', 'operational', 'sensitive')
        ),
        required_permission TEXT NOT NULL CHECK (
            required_permission IN ('read', 'safe_configuration', 'operational', 'sensitive')
        ),
        decision TEXT NOT NULL CHECK (decision IN ('authorized', 'denied', 'replayed')),
        safe_reason_code TEXT NOT NULL CHECK (length(safe_reason_code) BETWEEN 1 AND 96),
        confirmation_requirement TEXT NOT NULL CHECK (
            confirmation_requirement IN ('none', 'trusted_application_one_time')
        ),
        root_command_id TEXT,
        parent_command_id TEXT,
        hop_count INTEGER NOT NULL CHECK (hop_count BETWEEN 0 AND 255),
        recorded_at_ms INTEGER NOT NULL CHECK (recorded_at_ms >= 0),
        canonical_payload BLOB NOT NULL CHECK (length(canonical_payload) BETWEEN 1 AND 1048576),
        payload_sha256 TEXT NOT NULL CHECK (
            length(payload_sha256) = 64 AND lower(payload_sha256) = payload_sha256
        ),
        payload_byte_size INTEGER NOT NULL CHECK (
            payload_byte_size = length(canonical_payload)
                AND payload_byte_size BETWEEN 1 AND 1048576
        ),
        FOREIGN KEY (replay_of_command_id) REFERENCES automation_command_records(command_id),
        CHECK (
            (claims_replay_nonce = 1 AND replay_of_command_id IS NULL AND decision != 'replayed')
            OR (claims_replay_nonce = 0 AND replay_of_command_id IS NOT NULL AND decision = 'replayed')
        ),
        CHECK (
            (hop_count = 0 AND root_command_id IS NULL AND parent_command_id IS NULL)
            OR (hop_count > 0 AND root_command_id IS NOT NULL AND parent_command_id IS NOT NULL)
        )
    );

    INSERT INTO automation_command_records_v9(
        command_id, replay_nonce, claims_replay_nonce, replay_of_command_id,
        command_name, request_sha256, workspace_id, meeting_id, actor_id,
        origin, adapter_version, granted_permission, required_permission,
        decision, safe_reason_code, confirmation_requirement, root_command_id,
        parent_command_id, hop_count, recorded_at_ms, canonical_payload,
        payload_sha256, payload_byte_size
    )
    SELECT
        command_id, replay_nonce, claims_replay_nonce, replay_of_command_id,
        command_name, request_sha256, workspace_id, meeting_id, actor_id,
        origin, adapter_version, granted_permission, required_permission,
        decision, safe_reason_code, confirmation_requirement, root_command_id,
        parent_command_id, hop_count, recorded_at_ms, canonical_payload,
        payload_sha256, payload_byte_size
    FROM automation_command_records;

    DROP TABLE automation_command_records;
    ALTER TABLE automation_command_records_v9 RENAME TO automation_command_records;

    CREATE UNIQUE INDEX automation_command_records_claimed_nonce
        ON automation_command_records(replay_nonce)
        WHERE claims_replay_nonce = 1;
    CREATE INDEX automation_command_records_activity
        ON automation_command_records(recorded_at_ms DESC, command_id DESC);

    CREATE TRIGGER automation_command_records_no_update
    BEFORE UPDATE ON automation_command_records
    BEGIN SELECT RAISE(ABORT, 'automation command records are immutable'); END;
    CREATE TRIGGER automation_command_records_no_delete
    BEFORE DELETE ON automation_command_records
    BEGIN SELECT RAISE(ABORT, 'automation command records are immutable'); END;
    """

    static var taskRuntimeChecksum: String {
        SHA256.hash(data: Data(taskRuntimeSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var transcriptCoverageChecksum: String {
        SHA256.hash(data: Data(transcriptCoverageSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var analysisChecksum: String {
        SHA256.hash(data: Data(analysisSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var briefingChecksum: String {
        SHA256.hash(data: Data(briefingSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var hardeningChecksum: String {
        SHA256.hash(data: Data(hardeningSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var recordingCaptureChecksum: String {
        SHA256.hash(data: Data(recordingCaptureSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var automationChecksum: String {
        SHA256.hash(data: Data(automationSchemaSQL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static var mcpAuditOriginChecksum: String {
        SHA256.hash(data: Data(mcpAuditOriginSchemaSQL.utf8))
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
            try enforceDatabaseFamilyPermissions(databaseURL)
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
                    1,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.taskRuntimeMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.taskRuntimeSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.taskRuntimeMigrationIdentifier,
                    2,
                    SQLiteSchema.taskRuntimeChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    2,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.transcriptCoverageMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.transcriptCoverageSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.transcriptCoverageMigrationIdentifier,
                    3,
                    SQLiteSchema.transcriptCoverageChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    3,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.analysisMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.analysisSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.analysisMigrationIdentifier,
                    4,
                    SQLiteSchema.analysisChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    4,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.briefingMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.briefingSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.briefingMigrationIdentifier,
                    5,
                    SQLiteSchema.briefingChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    5,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.hardeningMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.hardeningSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.hardeningMigrationIdentifier,
                    6,
                    SQLiteSchema.hardeningChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    6,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.recordingCaptureMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.recordingCaptureSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.recordingCaptureMigrationIdentifier,
                    7,
                    SQLiteSchema.recordingCaptureChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    7,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.automationMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.automationSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.automationMigrationIdentifier,
                    8,
                    SQLiteSchema.automationChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    8,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
        }
        migrator.registerMigration(SQLiteSchema.mcpAuditOriginMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.mcpAuditOriginSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.mcpAuditOriginMigrationIdentifier,
                    9,
                    SQLiteSchema.mcpAuditOriginChecksum,
                    migrationTimestamp.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                UPDATE workspace_metadata
                SET database_schema_version = ?, updated_at_ms = ?
                WHERE singleton = 1
                """,
                arguments: [
                    9,
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
            let taskRuntimeChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.taskRuntimeMigrationIdentifier]
            )
            guard taskRuntimeChecksum == SQLiteSchema.taskRuntimeChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The task-runtime migration checksum does not match the accepted schema."
                )
            }
            let transcriptCoverageChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.transcriptCoverageMigrationIdentifier]
            )
            guard transcriptCoverageChecksum == SQLiteSchema.transcriptCoverageChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The transcript-coverage migration checksum does not match the accepted schema."
                )
            }
            let analysisChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.analysisMigrationIdentifier]
            )
            guard analysisChecksum == SQLiteSchema.analysisChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The analysis-intelligence migration checksum does not match the accepted schema."
                )
            }
            let briefingChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.briefingMigrationIdentifier]
            )
            guard briefingChecksum == SQLiteSchema.briefingChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The briefing-foundation migration checksum does not match the accepted schema."
                )
            }
            let hardeningChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.hardeningMigrationIdentifier]
            )
            guard hardeningChecksum == SQLiteSchema.hardeningChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The security/storage hardening migration checksum does not match the accepted schema."
                )
            }
            let recordingCaptureChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.recordingCaptureMigrationIdentifier]
            )
            guard recordingCaptureChecksum == SQLiteSchema.recordingCaptureChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The recording-capture migration checksum does not match the accepted schema."
                )
            }
            let automationChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.automationMigrationIdentifier]
            )
            guard automationChecksum == SQLiteSchema.automationChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The automation-command migration checksum does not match the accepted schema."
                )
            }
            let mcpAuditOriginChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.mcpAuditOriginMigrationIdentifier]
            )
            guard mcpAuditOriginChecksum == SQLiteSchema.mcpAuditOriginChecksum else {
                throw PersistenceContractError.migrationFailed(
                    "The MCP audit-origin migration checksum does not match the accepted schema."
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
        try enforceDatabaseFamilyPermissions(backupURL)
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

    private static func enforceDatabaseFamilyPermissions(_ url: URL) throws {
        let fileManager = FileManager.default
        for candidate in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-journal")
        ] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: candidate.path
            )
        }
    }
}
