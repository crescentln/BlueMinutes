import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct WorkspaceAndMigrationTests {
    @Test
    func createsPrivateWorkspaceAndIdempotentSchema() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }

        let store = try workspace.makeStore()
        #expect(store.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        #expect(
            store.migrationOutcome.appliedMigrations == [
                SQLiteSchema.initialMigrationIdentifier,
                SQLiteSchema.taskRuntimeMigrationIdentifier,
                SQLiteSchema.transcriptCoverageMigrationIdentifier,
                SQLiteSchema.analysisMigrationIdentifier,
                SQLiteSchema.briefingMigrationIdentifier,
                SQLiteSchema.hardeningMigrationIdentifier,
                SQLiteSchema.recordingCaptureMigrationIdentifier
            ]
        )
        #expect(store.migrationOutcome.rollbackAnchor == nil)

        let databaseFacts = try store.databasePool.read { db in
            (
                journalMode: try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(),
                foreignKeys: try Int.fetchOne(db, sql: "PRAGMA foreign_keys"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check"),
                foreignKeyFailures: try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count,
                hasRevisions: try db.tableExists("semantic_revisions"),
                hasAssets: try db.tableExists("managed_assets"),
                hasPointers: try db.tableExists("active_published_revisions"),
                hasJobs: try db.tableExists("jobs"),
                hasJobEvents: try db.tableExists("job_state_events"),
                hasAssetOperations: try db.tableExists("managed_asset_operations")
                    ,
                hasTranscriptCoverage: try db.tableExists("transcript_coverage_manifests"),
                hasActiveTranscript: try db.tableExists("active_transcript_manifests"),
                hasAnalysisCoverage: try db.tableExists("analysis_coverage_ledgers"),
                hasActiveAnalysis: try db.tableExists("active_analysis_ledgers"),
                hasBriefingCoverage: try db.tableExists("briefing_coverage_ledgers"),
                hasActiveBriefing: try db.tableExists("active_briefing_ledgers"),
                hasBriefingExports: try db.tableExists("briefing_export_records"),
                hasPurgeOperations: try db.tableExists("managed_asset_purge_operations"),
                hasPurgeReceipts: try db.tableExists("managed_asset_purge_receipts"),
                hasRecordingSessions: try db.tableExists("recording_sessions"),
                hasRecordingSegments: try db.tableExists("recording_segments"),
                hasRecordingCheckpoints: try db.tableExists("recording_checkpoints")
            )
        }
        #expect(databaseFacts.journalMode == "wal")
        #expect(databaseFacts.foreignKeys == 1)
        #expect(databaseFacts.quickCheck == "ok")
        #expect(databaseFacts.foreignKeyFailures == 0)
        #expect(databaseFacts.hasRevisions)
        #expect(databaseFacts.hasAssets)
        #expect(databaseFacts.hasPointers)
        #expect(databaseFacts.hasJobs)
        #expect(databaseFacts.hasJobEvents)
        #expect(databaseFacts.hasAssetOperations)
        #expect(databaseFacts.hasTranscriptCoverage)
        #expect(databaseFacts.hasActiveTranscript)
        #expect(databaseFacts.hasAnalysisCoverage)
        #expect(databaseFacts.hasActiveAnalysis)
        #expect(databaseFacts.hasBriefingCoverage)
        #expect(databaseFacts.hasActiveBriefing)
        #expect(databaseFacts.hasBriefingExports)
        #expect(databaseFacts.hasPurgeOperations)
        #expect(databaseFacts.hasPurgeReceipts)
        #expect(databaseFacts.hasRecordingSessions)
        #expect(databaseFacts.hasRecordingSegments)
        #expect(databaseFacts.hasRecordingCheckpoints)

        let rootMode = try posixMode(at: workspace.root)
        let manifestMode = try posixMode(at: workspace.descriptor.layout.workspaceManifest)
        let databaseMode = try posixMode(at: workspace.descriptor.layout.databaseFile)
        #expect(rootMode == 0o700)
        #expect(manifestMode == 0o600)
        #expect(databaseMode == 0o600)

        try store.close()
        let reopened = try workspace.makeStore()
        #expect(
            reopened.migrationOutcome.appliedMigrations == [
                SQLiteSchema.initialMigrationIdentifier,
                SQLiteSchema.taskRuntimeMigrationIdentifier,
                SQLiteSchema.transcriptCoverageMigrationIdentifier,
                SQLiteSchema.analysisMigrationIdentifier,
                SQLiteSchema.briefingMigrationIdentifier,
                SQLiteSchema.hardeningMigrationIdentifier,
                SQLiteSchema.recordingCaptureMigrationIdentifier
            ]
        )
        #expect(reopened.migrationOutcome.rollbackAnchor == nil)
        try reopened.close()
    }

    @Test
    func migratesEmptyDatabaseAndRejectsUnknownFutureMigration() throws {
        let emptyWorkspace = try DisposableMeetingBuddyWorkspace(suffix: "empty-prior-state")
        defer { emptyWorkspace.cleanup() }

        let emptyDatabase = try DatabaseQueue(
            path: emptyWorkspace.descriptor.layout.databaseFile.path
        )
        try emptyDatabase.close()

        let migrated = try emptyWorkspace.makeStore()
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        #expect(
            migrated.migrationOutcome.appliedMigrations == [
                SQLiteSchema.initialMigrationIdentifier,
                SQLiteSchema.taskRuntimeMigrationIdentifier,
                SQLiteSchema.transcriptCoverageMigrationIdentifier,
                SQLiteSchema.analysisMigrationIdentifier,
                SQLiteSchema.briefingMigrationIdentifier,
                SQLiteSchema.hardeningMigrationIdentifier,
                SQLiteSchema.recordingCaptureMigrationIdentifier
            ]
        )
        try migrated.close()

        let futureWorkspace = try DisposableMeetingBuddyWorkspace(suffix: "future-migration")
        defer { futureWorkspace.cleanup() }
        let current = try futureWorkspace.makeStore()
        try current.databasePool.write { db in
            try db.execute(
                sql: "INSERT INTO grdb_migrations(identifier) VALUES (?)",
                arguments: ["999_future_application_migration"]
            )
        }
        try current.close()

        #expect(throws: PersistenceContractError.self) {
            _ = try futureWorkspace.makeStore()
        }
        let migrationBackupDirectory = futureWorkspace.descriptor.layout.backups
            .appendingPathComponent("Migrations", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: migrationBackupDirectory.path))
    }

    @Test
    func migratesAcceptedVersionOneDatabaseWithVerifiedRollbackAnchor() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v1")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        var versionOneMigrator = DatabaseMigrator()
        versionOneMigrator.registerMigration(SQLiteSchema.initialMigrationIdentifier) { db in
            try db.execute(sql: SQLiteSchema.initialSchemaSQL)
            try db.execute(
                sql: """
                INSERT INTO schema_migrations(
                    identifier, ordinal, checksum_sha256, applied_at_ms
                ) VALUES (?, 1, ?, ?)
                """,
                arguments: [
                    SQLiteSchema.initialMigrationIdentifier,
                    SQLiteSchema.initialChecksum,
                    PersistenceFixtures.createdAt.millisecondsSinceUnixEpoch
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO workspace_metadata(
                    singleton, workspace_id, database_schema_version, updated_at_ms
                ) VALUES (1, ?, 1, ?)
                """,
                arguments: [
                    workspace.descriptor.manifest.workspaceID.canonicalString,
                    PersistenceFixtures.createdAt.millisecondsSinceUnixEpoch
                ]
            )
        }
        try versionOneMigrator.migrate(queue)
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        #expect(
            migrated.migrationOutcome.appliedMigrations == [
                SQLiteSchema.initialMigrationIdentifier,
                SQLiteSchema.taskRuntimeMigrationIdentifier,
                SQLiteSchema.transcriptCoverageMigrationIdentifier,
                SQLiteSchema.analysisMigrationIdentifier,
                SQLiteSchema.briefingMigrationIdentifier,
                SQLiteSchema.hardeningMigrationIdentifier,
                SQLiteSchema.recordingCaptureMigrationIdentifier
            ]
        )
        let rollbackAnchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(rollbackAnchor.sourceSchemaVersion == 1)
        #expect(
            try migrated.databasePool.read { db in
                try db.tableExists("jobs") && db.tableExists("managed_asset_operations")
            }
        )
        try migrated.close()

        let backupURL = workspace.root.appendingPathComponent(
            rollbackAnchor.artifact.relativePath.rawValue
        )
        let backup = try DatabaseQueue(path: backupURL.path)
        let backupFacts = try backup.read { db in
            (
                version: try UInt32.fetchOne(
                    db,
                    sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
                ),
                hasJobs: try db.tableExists("jobs"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check")
            )
        }
        #expect(backupFacts.version == 1)
        #expect(!backupFacts.hasJobs)
        #expect(backupFacts.quickCheck == "ok")
        try backup.close()
    }

    @Test
    func migratesAcceptedVersionTwoWithoutChangingPriorRows() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v2")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        let migrator = SQLiteDatabaseBootstrap.makeMigrator(
            workspaceID: workspace.descriptor.manifest.workspaceID,
            migrationTimestamp: PersistenceFixtures.createdAt,
            additionalMigrations: []
        )
        try migrator.migrate(queue, upTo: SQLiteSchema.taskRuntimeMigrationIdentifier)
        let canary = Data("accepted-v2-canary".utf8)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO jobs(
                    job_id, job_type, meeting_id, state, created_at_ms,
                    started_at_ms, finished_at_ms, retry_count,
                    maximum_retry_count, record_version, idempotency_key,
                    temporary_directory, disk_budget_bytes_decimal,
                    privacy_route, data_classification, resume_capability,
                    record_payload, record_sha256, record_byte_size
                ) VALUES (
                    '50000000-0000-0000-0000-000000000001', 'v2-canary', NULL,
                    'queued', ?, NULL, NULL, 0, 0, 1, ?,
                    '.tasks/50000000-0000-0000-0000-000000000001',
                    '1024', 'local_only', 'internal', 'restart_only', ?, ?, ?
                )
                """,
                arguments: [
                    PersistenceFixtures.createdAt.millisecondsSinceUnixEpoch,
                    String(repeating: "a", count: 64), canary,
                    SQLitePayloadCodec.sha256(canary), canary.count
                ]
            )
        }
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        let preserved: Data? = try migrated.databasePool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT record_payload FROM jobs WHERE job_type = 'v2-canary'"
            )
        }
        #expect(preserved == canary)
        let anchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(anchor.sourceSchemaVersion == 2)
        try migrated.close()
    }

    @Test
    func migratesAcceptedVersionThreeWithoutChangingTranscriptEraSemanticRows() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v3")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        let migrator = SQLiteDatabaseBootstrap.makeMigrator(
            workspaceID: workspace.descriptor.manifest.workspaceID,
            migrationTimestamp: PersistenceFixtures.createdAt,
            additionalMigrations: []
        )
        try migrator.migrate(queue, upTo: SQLiteSchema.transcriptCoverageMigrationIdentifier)
        let meeting = try PersistenceFixtures.meetingProfile()
        let payload = try CanonicalJSON.encodeValidated(meeting)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO semantic_revisions(
                    object_type, logical_id, revision_id, schema_major, schema_minor,
                    lifecycle_status, validation_state, created_at_ms, published_at_ms,
                    supersedes_revision_id, data_classification, semantic_hash_algorithm,
                    semantic_hash_hex, canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString,
                    Int64(meeting.revision.schemaVersion.major),
                    Int64(meeting.revision.schemaVersion.minor),
                    meeting.revision.lifecycleStatus.encodedValue,
                    meeting.revision.validationState.encodedValue,
                    meeting.revision.createdAt.millisecondsSinceUnixEpoch,
                    meeting.revision.dataClassification.encodedValue,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO revision_current_state(
                    object_type, logical_id, revision_id, currency_state, last_stale_at_ms
                ) VALUES (?, ?, ?, 'current', NULL)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString
                ]
            )
        }
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        let rollbackAnchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(rollbackAnchor.sourceSchemaVersion == 3)
        #expect(
            try migrated.fetch(
                MeetingProfileV1.self,
                revisionID: meeting.revision.revisionID
            ) == meeting
        )
        let preserved: Data? = try migrated.databasePool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                arguments: [meeting.revision.revisionID.canonicalString]
            )
        }
        #expect(preserved == payload)
        #expect(
            try migrated.databasePool.read { db in
                try db.tableExists("analysis_coverage_ledgers")
                    && db.tableExists("active_analysis_ledgers")
                    && Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty
            }
        )
        try migrated.close()

        let backupURL = workspace.root.appendingPathComponent(
            rollbackAnchor.artifact.relativePath.rawValue
        )
        let backup = try DatabaseQueue(path: backupURL.path)
        let backupFacts = try backup.read { db in
            (
                version: try UInt32.fetchOne(
                    db,
                    sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
                ),
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasAnalysis: try db.tableExists("analysis_coverage_ledgers"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check")
            )
        }
        #expect(backupFacts.version == 3)
        #expect(backupFacts.payload == payload)
        #expect(!backupFacts.hasAnalysis)
        #expect(backupFacts.quickCheck == "ok")
        try backup.close()
    }

    @Test
    func migratesAcceptedVersionFourWithoutChangingAnalysisEraSemanticRows() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v4")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        let migrator = SQLiteDatabaseBootstrap.makeMigrator(
            workspaceID: workspace.descriptor.manifest.workspaceID,
            migrationTimestamp: PersistenceFixtures.createdAt,
            additionalMigrations: []
        )
        try migrator.migrate(queue, upTo: SQLiteSchema.analysisMigrationIdentifier)
        let meeting = try PersistenceFixtures.meetingProfile()
        let payload = try CanonicalJSON.encodeValidated(meeting)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO semantic_revisions(
                    object_type, logical_id, revision_id, schema_major, schema_minor,
                    lifecycle_status, validation_state, created_at_ms, published_at_ms,
                    supersedes_revision_id, data_classification, semantic_hash_algorithm,
                    semantic_hash_hex, canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString,
                    Int64(meeting.revision.schemaVersion.major),
                    Int64(meeting.revision.schemaVersion.minor),
                    meeting.revision.lifecycleStatus.encodedValue,
                    meeting.revision.validationState.encodedValue,
                    meeting.revision.createdAt.millisecondsSinceUnixEpoch,
                    meeting.revision.dataClassification.encodedValue,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO revision_current_state(
                    object_type, logical_id, revision_id, currency_state, last_stale_at_ms
                ) VALUES (?, ?, ?, 'current', NULL)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString
                ]
            )
        }
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        let rollbackAnchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(rollbackAnchor.sourceSchemaVersion == 4)
        #expect(
            try migrated.fetch(
                MeetingProfileV1.self,
                revisionID: meeting.revision.revisionID
            ) == meeting
        )
        let migratedFacts = try migrated.databasePool.read { db in
            (
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasAnalysis: try db.tableExists("analysis_coverage_ledgers"),
                hasBriefing: try db.tableExists("briefing_coverage_ledgers"),
                foreignKeyFailures: try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            )
        }
        #expect(migratedFacts.payload == payload)
        #expect(migratedFacts.hasAnalysis)
        #expect(migratedFacts.hasBriefing)
        #expect(migratedFacts.foreignKeyFailures == 0)
        try migrated.close()

        let backupURL = workspace.root.appendingPathComponent(
            rollbackAnchor.artifact.relativePath.rawValue
        )
        let backup = try DatabaseQueue(path: backupURL.path)
        let backupFacts = try backup.read { db in
            (
                version: try UInt32.fetchOne(
                    db,
                    sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
                ),
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasAnalysis: try db.tableExists("analysis_coverage_ledgers"),
                hasBriefing: try db.tableExists("briefing_coverage_ledgers"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check")
            )
        }
        #expect(backupFacts.version == 4)
        #expect(backupFacts.payload == payload)
        #expect(backupFacts.hasAnalysis)
        #expect(!backupFacts.hasBriefing)
        #expect(backupFacts.quickCheck == "ok")
        try backup.close()
    }

    @Test
    func migratesAcceptedVersionFiveWithoutChangingBriefingEraSemanticRows() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v5")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        let migrator = SQLiteDatabaseBootstrap.makeMigrator(
            workspaceID: workspace.descriptor.manifest.workspaceID,
            migrationTimestamp: PersistenceFixtures.createdAt,
            additionalMigrations: []
        )
        try migrator.migrate(queue, upTo: SQLiteSchema.briefingMigrationIdentifier)
        let meeting = try PersistenceFixtures.meetingProfile()
        let payload = try CanonicalJSON.encodeValidated(meeting)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO semantic_revisions(
                    object_type, logical_id, revision_id, schema_major, schema_minor,
                    lifecycle_status, validation_state, created_at_ms, published_at_ms,
                    supersedes_revision_id, data_classification, semantic_hash_algorithm,
                    semantic_hash_hex, canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString,
                    Int64(meeting.revision.schemaVersion.major),
                    Int64(meeting.revision.schemaVersion.minor),
                    meeting.revision.lifecycleStatus.encodedValue,
                    meeting.revision.validationState.encodedValue,
                    meeting.revision.createdAt.millisecondsSinceUnixEpoch,
                    meeting.revision.dataClassification.encodedValue,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO revision_current_state(
                    object_type, logical_id, revision_id, currency_state, last_stale_at_ms
                ) VALUES (?, ?, ?, 'current', NULL)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString
                ]
            )
        }
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == SQLiteSchema.currentVersion)
        let rollbackAnchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(rollbackAnchor.sourceSchemaVersion == 5)
        #expect(
            try migrated.fetch(
                MeetingProfileV1.self,
                revisionID: meeting.revision.revisionID
            ) == meeting
        )
        let migratedFacts = try migrated.databasePool.read { db in
            (
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasPurgeOperations: try db.tableExists("managed_asset_purge_operations"),
                hasPurgeReceipts: try db.tableExists("managed_asset_purge_receipts"),
                foreignKeyFailures: try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            )
        }
        #expect(migratedFacts.payload == payload)
        #expect(migratedFacts.hasPurgeOperations)
        #expect(migratedFacts.hasPurgeReceipts)
        #expect(migratedFacts.foreignKeyFailures == 0)
        try migrated.close()

        let backupURL = workspace.root.appendingPathComponent(
            rollbackAnchor.artifact.relativePath.rawValue
        )
        let backup = try DatabaseQueue(path: backupURL.path)
        let backupFacts = try backup.read { db in
            (
                version: try UInt32.fetchOne(
                    db,
                    sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
                ),
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasPurgeOperations: try db.tableExists("managed_asset_purge_operations"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check")
            )
        }
        #expect(backupFacts.version == 5)
        #expect(backupFacts.payload == payload)
        #expect(!backupFacts.hasPurgeOperations)
        #expect(backupFacts.quickCheck == "ok")
        try backup.close()
    }

    @Test
    func migratesAcceptedVersionSixWithVerifiedV6RollbackAnchorAndUnchangedPayload() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "accepted-v6")
        defer { workspace.cleanup() }
        let queue = try DatabaseQueue(path: workspace.descriptor.layout.databaseFile.path)
        let migrator = SQLiteDatabaseBootstrap.makeMigrator(
            workspaceID: workspace.descriptor.manifest.workspaceID,
            migrationTimestamp: PersistenceFixtures.createdAt,
            additionalMigrations: []
        )
        try migrator.migrate(queue, upTo: SQLiteSchema.hardeningMigrationIdentifier)
        let meeting = try PersistenceFixtures.meetingProfile()
        let payload = try CanonicalJSON.encodeValidated(meeting)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO semantic_revisions(
                    object_type, logical_id, revision_id, schema_major, schema_minor,
                    lifecycle_status, validation_state, created_at_ms, published_at_ms,
                    supersedes_revision_id, data_classification, semantic_hash_algorithm,
                    semantic_hash_hex, canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString,
                    Int64(meeting.revision.schemaVersion.major),
                    Int64(meeting.revision.schemaVersion.minor),
                    meeting.revision.lifecycleStatus.encodedValue,
                    meeting.revision.validationState.encodedValue,
                    meeting.revision.createdAt.millisecondsSinceUnixEpoch,
                    meeting.revision.dataClassification.encodedValue,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO revision_current_state(
                    object_type, logical_id, revision_id, currency_state, last_stale_at_ms
                ) VALUES (?, ?, ?, 'current', NULL)
                """,
                arguments: [
                    meeting.revision.objectType.encodedValue,
                    meeting.meetingID.canonicalString,
                    meeting.revision.revisionID.canonicalString
                ]
            )
        }
        try queue.close()

        let migrated = try SQLitePersistenceStore(
            workspace: workspace.descriptor,
            migrationTimestamp: PersistenceFixtures.publishedAt
        )
        #expect(migrated.migrationOutcome.schemaVersion == 7)
        let anchor = try #require(migrated.migrationOutcome.rollbackAnchor)
        #expect(anchor.sourceSchemaVersion == 6)
        #expect(
            try migrated.databasePool.read { db in
                try db.tableExists("recording_sessions")
                    && db.tableExists("recording_state_events")
                    && db.tableExists("recording_tracks")
                    && db.tableExists("recording_epochs")
                    && db.tableExists("recording_segments")
                    && db.tableExists("recording_gaps")
                    && db.tableExists("recording_checkpoints")
                    && Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty
            }
        )
        #expect(
            try migrated.databasePool.read { db in
                try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                )
            } == payload
        )
        try migrated.close()

        let backupURL = workspace.root.appendingPathComponent(
            anchor.artifact.relativePath.rawValue
        )
        let backup = try DatabaseQueue(path: backupURL.path)
        let backupFacts = try backup.read { db in
            (
                version: try UInt32.fetchOne(
                    db,
                    sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
                ),
                payload: try Data.fetchOne(
                    db,
                    sql: "SELECT canonical_payload FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                ),
                hasRecording: try db.tableExists("recording_sessions"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check"),
                foreignKeyFailures: try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            )
        }
        #expect(backupFacts.version == 6)
        #expect(backupFacts.payload == payload)
        #expect(!backupFacts.hasRecording)
        #expect(backupFacts.quickCheck == "ok")
        #expect(backupFacts.foreignKeyFailures == 0)
        try backup.close()
    }

    @Test
    func rejectsTraversalSymlinksAndUnownedRoots() throws {
        for raw in ["/absolute", "../escape", "a/../escape", "a//b", "~/home", "a\\b", "a\u{0000}b"] {
            #expect(throws: WorkspaceContractError.self) {
                _ = try WorkspaceRelativePath(raw)
            }
        }

        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingbuddy-workspace-guards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let nonempty = container.appendingPathComponent("nonempty", isDirectory: true)
        try FileManager.default.createDirectory(at: nonempty, withIntermediateDirectories: true)
        try Data("not-a-workspace".utf8).write(to: nonempty.appendingPathComponent("foreign.txt"))
        #expect(throws: WorkspaceContractError.self) {
            _ = try LocalWorkspaceService().createWorkspace(
                at: nonempty,
                workspaceID: PersistenceFixtures.workspaceID,
                createdAt: PersistenceFixtures.createdAt
            )
        }

        let target = container.appendingPathComponent("target", isDirectory: true)
        let link = container.appendingPathComponent("workspace-link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: WorkspaceContractError.self) {
            _ = try LocalWorkspaceService().createWorkspace(
                at: link,
                workspaceID: PersistenceFixtures.workspaceID,
                createdAt: PersistenceFixtures.createdAt
            )
        }
    }

    @Test
    func rejectsNestedAuthorityAndBackupSymlinkSubstitution() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let outsideManifest = workspace.container.appendingPathComponent("outside-manifest.json")
        let manifestBytes = try Data(contentsOf: workspace.descriptor.layout.workspaceManifest)
        try manifestBytes.write(to: outsideManifest)
        try FileManager.default.removeItem(at: workspace.descriptor.layout.workspaceManifest)
        try FileManager.default.createSymbolicLink(
            at: workspace.descriptor.layout.workspaceManifest,
            withDestinationURL: outsideManifest
        )
        #expect(throws: WorkspaceContractError.self) {
            _ = try LocalWorkspaceService().openWorkspace(at: workspace.root)
        }
        #expect(try Data(contentsOf: outsideManifest) == manifestBytes)

        try FileManager.default.removeItem(at: workspace.descriptor.layout.workspaceManifest)
        try Data(repeating: 0x20, count: 65_537).write(
            to: workspace.descriptor.layout.workspaceManifest
        )
        #expect(throws: WorkspaceContractError.self) {
            _ = try LocalWorkspaceService().openWorkspace(at: workspace.root)
        }

        try FileManager.default.removeItem(at: workspace.descriptor.layout.workspaceManifest)
        try manifestBytes.write(to: workspace.descriptor.layout.workspaceManifest)
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let outsideBackups = workspace.container.appendingPathComponent("outside-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideBackups, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: workspace.descriptor.layout.backups)
        try FileManager.default.createSymbolicLink(
            at: workspace.descriptor.layout.backups,
            withDestinationURL: outsideBackups
        )
        let recovery = SQLiteRecoveryService(store: store, storage: workspace.storage)
        #expect(throws: WorkspaceContractError.self) {
            _ = try recovery.createRecoverySnapshot(createdAt: PersistenceFixtures.publishedAt)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outsideBackups.path).isEmpty)
    }

    @Test
    func rejectsDatabaseFromAnotherWorkspaceBeforeWriting() throws {
        let first = try DisposableMeetingBuddyWorkspace(suffix: "identity-first")
        let secondWorkspaceID = PersistenceFixtures.id(101, WorkspaceID.self)
        let second = try DisposableMeetingBuddyWorkspace(
            suffix: "identity-second",
            workspaceID: secondWorkspaceID
        )
        defer {
            first.cleanup()
            second.cleanup()
        }
        let firstStore = try first.makeStore()
        let portableCopy = try DatabaseQueue(path: second.descriptor.layout.databaseFile.path)
        try firstStore.databasePool.backup(to: portableCopy)
        try SQLiteDatabaseBootstrap.makeBackupReadOnlyPortable(portableCopy)
        try portableCopy.close()
        try SQLiteDatabaseBootstrap.removeObsoleteBackupSidecars(
            at: second.descriptor.layout.databaseFile
        )
        try firstStore.close()
        let before = try Data(contentsOf: second.descriptor.layout.databaseFile)
        #expect(throws: PersistenceContractError.self) {
            _ = try second.makeStore()
        }
        #expect(try Data(contentsOf: second.descriptor.layout.databaseFile) == before)
    }

    @Test
    func failedMigrationRollsBackAndLeavesVerifiedBackup() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let initial = try workspace.makeStore()
        try initial.close()

        let failing = SQLiteMigrationDefinition(identifier: "003_test_failure") { db in
            try db.create(table: "must_rollback") { table in
                table.column("id", .integer).primaryKey()
            }
            throw MigrationProbeError.intentional
        }

        var failureDescription = ""
        do {
            _ = try SQLitePersistenceStore(
                workspace: workspace.descriptor,
                migrationTimestamp: PersistenceFixtures.publishedAt,
                additionalMigrations: [failing]
            )
            Issue.record("The intentionally failing migration unexpectedly succeeded.")
        } catch {
            failureDescription = String(describing: error)
        }
        #expect(failureDescription.contains("rolled back"))
        #expect(failureDescription.contains("Backups/Migrations/"))

        let backupDirectory = workspace.descriptor.layout.backups
            .appendingPathComponent("Migrations", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "sqlite" }
        #expect(backups.count == 1)

        let backup = try #require(backups.first)
        let backupQueue = try DatabaseQueue(path: backup.path)
        let backupFacts = try backupQueue.read { db in
            (
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check"),
                journalMode: try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(),
                foreignKeyFailures: try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count,
                hasProbeTable: try db.tableExists("must_rollback")
            )
        }
        #expect(backupFacts.quickCheck == "ok")
        #expect(backupFacts.journalMode == "delete")
        #expect(backupFacts.foreignKeyFailures == 0)
        #expect(!backupFacts.hasProbeTable)
        #expect(try posixMode(at: backupDirectory) == 0o700)
        #expect(try posixMode(at: backup) == 0o600)
        try backupQueue.close()
        for suffix in ["-wal", "-shm", "-journal"] {
            #expect(!FileManager.default.fileExists(atPath: backup.path + suffix))
        }

        let reopened = try workspace.makeStore()
        let reopenedFacts = try reopened.databasePool.read { db in
            (
                hasProbeTable: try db.tableExists("must_rollback"),
                quickCheck: try String.fetchOne(db, sql: "PRAGMA quick_check")
            )
        }
        #expect(!reopenedFacts.hasProbeTable)
        #expect(reopenedFacts.quickCheck == "ok")
        try reopened.close()
    }
}

private enum MigrationProbeError: Error, Sendable {
    case intentional
}
