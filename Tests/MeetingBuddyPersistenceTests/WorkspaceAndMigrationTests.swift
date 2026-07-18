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
                SQLiteSchema.taskRuntimeMigrationIdentifier
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
                SQLiteSchema.taskRuntimeMigrationIdentifier
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
                SQLiteSchema.taskRuntimeMigrationIdentifier
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
        #expect(migrated.migrationOutcome.schemaVersion == 2)
        #expect(
            migrated.migrationOutcome.appliedMigrations == [
                SQLiteSchema.initialMigrationIdentifier,
                SQLiteSchema.taskRuntimeMigrationIdentifier
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
