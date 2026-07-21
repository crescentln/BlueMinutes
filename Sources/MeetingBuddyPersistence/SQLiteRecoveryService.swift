import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class SQLiteRecoveryService: RecoveryService, @unchecked Sendable {
    private let store: SQLitePersistenceStore
    private let storage: LocalStorageService
    private let fileManager: FileManager

    public init(
        store: SQLitePersistenceStore,
        storage: LocalStorageService,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.storage = storage
        self.fileManager = fileManager
    }

    public func createRecoverySnapshot(
        createdAt: UTCInstant
    ) throws -> RecoverySnapshotManifest {
        let snapshotID = UUID()
        let recoveryRoot = store.workspace.layout.backups
            .appendingPathComponent("Recovery", isDirectory: true)
        let directory = recoveryRoot
            .appendingPathComponent(snapshotID.uuidString.lowercased(), isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A generated recovery snapshot destination already exists."
            )
        }
        _ = try WorkspacePathSecurity.createPrivateDirectory(
            recoveryRoot,
            within: store.workspace.layout.root,
            fileManager: fileManager
        )
        let confinedDirectory = try WorkspacePathSecurity.confinedURL(
            directory,
            within: store.workspace.layout.root,
            allowMissingLeaf: true
        )
        try fileManager.createDirectory(at: confinedDirectory, withIntermediateDirectories: false)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: confinedDirectory.path
        )
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: confinedDirectory)
            }
        }

        let workspaceManifestURL = confinedDirectory.appendingPathComponent("workspace_manifest.json")
        let backupURL = confinedDirectory.appendingPathComponent("meetingbuddy.sqlite")
        let semanticURL = confinedDirectory.appendingPathComponent("semantic_snapshot.jsonl")
        let assetURL = confinedDirectory.appendingPathComponent("asset_hashes.json")
        let migrationURL = confinedDirectory.appendingPathComponent("migration_version.json")
        let manifestURL = confinedDirectory.appendingPathComponent("snapshot_manifest.json")

        try canonicalData(store.workspace.manifest).write(
            to: workspaceManifestURL,
            options: [.atomic]
        )

        let counts = try store.databasePool.barrierWriteWithoutTransaction { db in
            let destination = try DatabaseQueue(path: backupURL.path)
            try destination.writeWithoutTransaction { destinationDB in
                try db.backup(to: destinationDB)
            }
            try SQLiteDatabaseBootstrap.makeBackupReadOnlyPortable(destination)
            try destination.close()
            try SQLiteDatabaseBootstrap.removeObsoleteBackupSidecars(at: backupURL)

            let semanticHandle = try makeEmptyFile(at: semanticURL)
            defer { try? semanticHandle.close() }
            let header = SemanticSnapshotLine.header(
                workspaceID: store.workspace.manifest.workspaceID
            )
            try writeJSONLine(header, to: semanticHandle)

            var revisionCount: UInt64 = 0
            let revisionCursor = try Row.fetchCursor(
                db,
                sql: """
                SELECT object_type, logical_id, revision_id, payload_sha256, canonical_payload
                FROM semantic_revisions
                ORDER BY object_type, logical_id, revision_id
                """
            )
            while let row = try revisionCursor.next() {
                let payload: Data = row["canonical_payload"]
                let line = SemanticSnapshotLine.revision(
                    objectType: row["object_type"],
                    logicalID: row["logical_id"],
                    revisionID: row["revision_id"],
                    payloadSHA256: row["payload_sha256"],
                    canonicalPayloadBase64: payload.base64EncodedString()
                )
                try writeJSONLine(line, to: semanticHandle)
                revisionCount += 1
            }
            try semanticHandle.synchronize()

            let assetRows = try Row.fetchAll(
                db,
                sql: "SELECT record_payload, record_sha256 FROM managed_assets ORDER BY storage_object_id"
            )
            let assets = try assetRows.map { row -> ManagedAssetRecord in
                let payload: Data = row["record_payload"]
                let digest: String = row["record_sha256"]
                guard SQLitePayloadCodec.sha256(payload) == digest else {
                    throw WorkspaceContractError.recoveryArtifactInvalid(
                        "Managed-asset metadata failed its persistence digest."
                    )
                }
                return try JSONDecoder().decode(ManagedAssetRecord.self, from: payload)
            }
            try canonicalData(assets).write(to: assetURL, options: [.atomic])

            let migrationIdentifiers = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
            let migration = MigrationVersionArtifact(
                workspaceID: store.workspace.manifest.workspaceID,
                databaseSchemaVersion: SQLiteSchema.currentVersion,
                appliedMigrations: migrationIdentifiers
            )
            try canonicalData(migration).write(to: migrationURL, options: [.atomic])
            return (revisionCount, UInt64(assets.count))
        }

        for url in [workspaceManifestURL, backupURL, semanticURL, assetURL, migrationURL] {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let manifest = try RecoverySnapshotManifest(
            snapshotID: snapshotID,
            workspaceID: store.workspace.manifest.workspaceID,
            createdAt: createdAt,
            schemaVersion: SQLiteSchema.currentVersion,
            workspaceManifest: SQLiteDatabaseBootstrap.recoveryArtifact(
                at: workspaceManifestURL,
                workspaceRoot: store.workspace.layout.root
            ),
            databaseBackup: SQLiteDatabaseBootstrap.recoveryArtifact(
                at: backupURL,
                workspaceRoot: store.workspace.layout.root
            ),
            semanticSnapshot: SQLiteDatabaseBootstrap.recoveryArtifact(
                at: semanticURL,
                workspaceRoot: store.workspace.layout.root
            ),
            assetHashes: SQLiteDatabaseBootstrap.recoveryArtifact(
                at: assetURL,
                workspaceRoot: store.workspace.layout.root
            ),
            migrationVersion: SQLiteDatabaseBootstrap.recoveryArtifact(
                at: migrationURL,
                workspaceRoot: store.workspace.layout.root
            ),
            revisionCount: counts.0,
            managedAssetCount: counts.1,
            semanticSnapshotIsExportOnly: true
        )
        try canonicalData(manifest).write(to: manifestURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        try verifyRecoverySnapshot(manifest)
        completed = true
        return manifest
    }

    public func verifyRecoverySnapshot(_ manifest: RecoverySnapshotManifest) throws {
        guard manifest.workspaceID == store.workspace.manifest.workspaceID,
              manifest.schemaVersion == SQLiteSchema.currentVersion,
              manifest.semanticSnapshotIsExportOnly
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Recovery manifest identity, version, or export boundary is invalid."
            )
        }
        try validateCanonicalArtifactPaths(manifest)
        for artifact in [
            manifest.workspaceManifest,
            manifest.databaseBackup,
            manifest.semanticSnapshot,
            manifest.assetHashes,
            manifest.migrationVersion
        ] {
            try verify(artifact)
        }

        try verifyWorkspaceManifest(manifest.workspaceManifest)
        let databaseInventory = try verifyDatabaseBackup(
            manifest.databaseBackup,
            manifest: manifest
        )
        try verifySemanticSnapshot(
            manifest.semanticSnapshot,
            expectedCount: manifest.revisionCount,
            expectedRevisions: databaseInventory.revisions
        )
        try verifyAssetHashes(
            manifest.assetHashes,
            expectedCount: manifest.managedAssetCount,
            expectedRecords: databaseInventory.managedAssets
        )
        try verifyMigrationVersion(
            manifest.migrationVersion,
            manifest: manifest,
            expectedMigrations: databaseInventory.migrations
        )
    }

    private func validateCanonicalArtifactPaths(_ manifest: RecoverySnapshotManifest) throws {
        let base = "Backups/Recovery/\(manifest.snapshotID.uuidString.lowercased())/"
        let expected: [(RecoveryArtifactDescriptor, String)] = [
            (manifest.workspaceManifest, base + "workspace_manifest.json"),
            (manifest.databaseBackup, base + "meetingbuddy.sqlite"),
            (manifest.semanticSnapshot, base + "semantic_snapshot.jsonl"),
            (manifest.assetHashes, base + "asset_hashes.json"),
            (manifest.migrationVersion, base + "migration_version.json")
        ]
        guard expected.allSatisfy({ $0.0.relativePath.rawValue == $0.1 }) else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Recovery artifacts are not bound to their snapshot ID and canonical filenames."
            )
        }
    }

    private func verify(_ artifact: RecoveryArtifactDescriptor) throws {
        let url = try confinedURL(for: artifact.relativePath)
        let actual = try SQLiteDatabaseBootstrap.recoveryArtifact(
            at: url,
            workspaceRoot: store.workspace.layout.root
        )
        guard actual == artifact else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Recovery artifact size or hash does not match its manifest."
            )
        }
    }

    private func verifyWorkspaceManifest(_ artifact: RecoveryArtifactDescriptor) throws {
        let data = try Data(contentsOf: confinedURL(for: artifact.relativePath))
        let decoded = try JSONDecoder().decode(WorkspaceManifest.self, from: data)
        guard decoded == store.workspace.manifest,
              try canonicalData(decoded) == data
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The recovery workspace manifest is not canonical or does not match the workspace."
            )
        }
    }

    private func verifyDatabaseBackup(
        _ artifact: RecoveryArtifactDescriptor,
        manifest: RecoverySnapshotManifest
    ) throws -> RecoveryDatabaseInventory {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.foreignKeysEnabled = true
        let databaseURL = try confinedURL(for: artifact.relativePath)
        for suffix in ["-wal", "-shm", "-journal"] {
            guard !fileManager.fileExists(atPath: databaseURL.path + suffix) else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A standalone recovery database must not depend on journal sidecars."
                )
            }
        }
        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: configuration
        )
        defer { try? queue.close() }
        return try queue.read { db in
            let quickCheck = try String.fetchOne(db, sql: "PRAGMA quick_check")
            guard quickCheck == "ok" else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database failed SQLite quick_check."
                )
            }
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard foreignKeyFailures.isEmpty else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database failed foreign_key_check."
                )
            }
            let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased()
            guard journalMode == "delete" else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database is not a standalone DELETE-journal backup."
                )
            }
            let workspaceID = try String.fetchOne(
                db,
                sql: "SELECT workspace_id FROM workspace_metadata WHERE singleton = 1"
            )
            let schemaVersion = try Int64.fetchOne(
                db,
                sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
            )
            guard workspaceID == manifest.workspaceID.canonicalString,
                  schemaVersion == Int64(manifest.schemaVersion)
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database metadata does not match its manifest."
                )
            }

            let migrator = SQLiteDatabaseBootstrap.makeMigrator(
                workspaceID: manifest.workspaceID,
                migrationTimestamp: manifest.createdAt,
                additionalMigrations: []
            )
            let storedChecksum = try String.fetchOne(
                db,
                sql: "SELECT checksum_sha256 FROM schema_migrations WHERE identifier = ?",
                arguments: [SQLiteSchema.initialMigrationIdentifier]
            )
            guard try !migrator.hasBeenSuperseded(db),
                  try migrator.hasCompletedMigrations(db),
                  try !migrator.hasSchemaChanges(db),
                  storedChecksum == SQLiteSchema.initialChecksum
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database migration history or schema has drifted."
                )
            }
            let staleProjectionConflicts = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM stale_events AS stale
                JOIN revision_current_state AS state
                  ON state.object_type = stale.affected_object_type
                 AND state.logical_id = stale.affected_logical_id
                 AND state.revision_id = stale.affected_revision_id
                WHERE state.currency_state != 'stale'
                """
            ) ?? 0
            guard staleProjectionConflicts == 0 else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The recovery database stale-event projection is inconsistent."
                )
            }
            try verifyAutomationState(in: db)

            let revisions = try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM semantic_revisions
                ORDER BY object_type, logical_id, revision_id
                """
            ).map { row in
                let reference: SemanticRevisionReference
                do {
                    reference = try store.validateStoredRevisionRow(row)
                } catch {
                    throw WorkspaceContractError.recoveryArtifactInvalid(
                        "A recovery database semantic revision failed repository validation."
                    )
                }
                return RecoveryRevisionInventory(
                    objectType: reference.objectType.encodedValue,
                    logicalID: reference.logicalID.canonicalString,
                    revisionID: reference.revisionID.canonicalString,
                    payloadSHA256: row["payload_sha256"]
                )
            }
            let managedAssets = try Row.fetchAll(
                db,
                sql: "SELECT * FROM managed_assets ORDER BY storage_object_id"
            ).map { row -> ManagedAssetRecord in
                do {
                    return try SQLitePayloadCodec.managedAsset(from: row)
                } catch {
                    throw WorkspaceContractError.recoveryArtifactInvalid(
                        "The recovery database contains inconsistent managed-asset metadata."
                    )
                }
            }
            let migrations = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
            return RecoveryDatabaseInventory(
                revisions: revisions,
                managedAssets: managedAssets,
                migrations: migrations
            )
        }
    }

    private func verifyAutomationState(in db: Database) throws {
        guard try db.tableExists("automation_command_records") else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The recovery database is missing the automation audit schema."
            )
        }
        let commandRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM automation_command_records ORDER BY recorded_at_ms, command_id"
        )
        for row in commandRows {
            let record: AutomationCommandRecord = try decodeAutomationPayload(row)
            guard record.commandID.canonicalString == (row["command_id"] as String),
                  record.replayNonce.canonicalString == (row["replay_nonce"] as String),
                  record.commandName.rawValue == (row["command_name"] as String),
                  record.requestDigest.lowercaseHex == (row["request_sha256"] as String),
                  record.workspaceID.canonicalString == (row["workspace_id"] as String),
                  record.actorID.rawValue == (row["actor_id"] as String),
                  record.decision.rawValue == (row["decision"] as String),
                  record.recordedAt.millisecondsSinceUnixEpoch
                    == (row["recorded_at_ms"] as Int64)
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "An automation command record failed indexed-payload validation."
                )
            }
            let inputs = try Row.fetchAll(
                db,
                sql: """
                SELECT object_type, logical_id, revision_id
                FROM automation_command_input_revisions
                WHERE command_id = ? ORDER BY ordinal
                """,
                arguments: [record.commandID.canonicalString]
            ).map { input in
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: input["object_type"],
                    logicalIDValue: input["logical_id"],
                    revisionIDValue: input["revision_id"]
                )
            }
            let expectedInputs = [
                record.policyEvidence.meetingRevision,
                record.policyEvidence.sensitivityLabelRevision,
                record.policyEvidence.accessPolicyRevision
            ].compactMap { $0 }.sorted()
            guard record.claimsReplayNonce ? inputs == expectedInputs : inputs.isEmpty else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "An automation command input projection is incomplete."
                )
            }
        }

        let resultRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM automation_command_result_events ORDER BY command_id"
        )
        for row in resultRows {
            let event: AutomationCommandResultEvent = try decodeAutomationPayload(row)
            guard event.eventID.canonicalString == (row["event_id"] as String),
                  event.commandID.canonicalString == (row["command_id"] as String),
                  event.outcome.rawValue == (row["outcome"] as String),
                  event.safeCode == (row["safe_code"] as String),
                  event.occurredAt.millisecondsSinceUnixEpoch
                    == (row["occurred_at_ms"] as Int64)
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "An automation result event failed indexed-payload validation."
                )
            }
        }

        let settingsRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM automation_settings_events ORDER BY replacement_version"
        )
        var expectedPrior = VersionedAutomationSettings.compiledDefault
        for row in settingsRows {
            let event: AutomationSettingsEvent = try decodeAutomationPayload(row)
            let expectedCommandName = event.rollbackOfCommandID == nil
                ? AutomationCommandName.updateSettings.rawValue
                : AutomationCommandName.rollbackSettings.rawValue
            let expectedOutcome = event.rollbackOfCommandID == nil
                ? AutomationCommandOutcome.completed.rawValue
                : AutomationCommandOutcome.rolledBack.rawValue
            let commandName = try String.fetchOne(
                db,
                sql: "SELECT command_name FROM automation_command_records WHERE command_id = ?",
                arguments: [event.commandID.canonicalString]
            )
            let resultRow = try Row.fetchOne(
                db,
                sql: """
                SELECT outcome, prior_settings_version, replacement_settings_version,
                       rollback_of_command_id
                FROM automation_command_result_events WHERE command_id = ?
                """,
                arguments: [event.commandID.canonicalString]
            )
            guard event.eventID.canonicalString == (row["event_id"] as String),
                  event.commandID.canonicalString == (row["command_id"] as String),
                  event.prior == expectedPrior,
                  Int64(event.prior.version) == (row["prior_version"] as Int64),
                  Int64(event.replacement.version)
                    == (row["replacement_version"] as Int64),
                  event.occurredAt.millisecondsSinceUnixEpoch
                    == (row["occurred_at_ms"] as Int64),
                  commandName == expectedCommandName,
                  (resultRow?["outcome"] as String?) == expectedOutcome,
                  (resultRow?["prior_settings_version"] as Int64?)
                    == Int64(event.prior.version),
                  (resultRow?["replacement_settings_version"] as Int64?)
                    == Int64(event.replacement.version),
                  (resultRow?["rollback_of_command_id"] as String?)
                    == event.rollbackOfCommandID?.canonicalString
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The automation settings event chain is inconsistent."
                )
            }
            expectedPrior = event.replacement
        }

        let stateRow = try Row.fetchOne(
            db,
            sql: "SELECT * FROM automation_settings_state WHERE singleton = 1"
        )
        if let stateRow {
            let state: VersionedAutomationSettings = try decodeAutomationPayload(stateRow)
            guard !settingsRows.isEmpty,
                  state == expectedPrior,
                  Int64(state.version) == (stateRow["version"] as Int64),
                  Int64(state.values.statusListLimit)
                    == (stateRow["status_list_limit"] as Int64),
                  state.updatedByCommandID?.canonicalString
                    == (stateRow["updated_by_command_id"] as String?),
                  state.updatedAt?.millisecondsSinceUnixEpoch
                    == (stateRow["updated_at_ms"] as Int64?)
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The current automation settings projection is inconsistent."
                )
            }
        } else if !settingsRows.isEmpty {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Automation settings history has no current projection."
            )
        }
    }

    private func decodeAutomationPayload<Value: Codable>(_ row: Row) throws -> Value {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        let byteSize: Int = row["payload_byte_size"]
        guard payload.count == byteSize,
              SQLitePayloadCodec.sha256(payload) == digest
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "An automation recovery payload failed its digest."
            )
        }
        let value = try JSONDecoder().decode(Value.self, from: payload)
        guard try SQLitePayloadCodec.canonicalData(value) == payload else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "An automation recovery payload is not canonical."
            )
        }
        return value
    }

    private func verifySemanticSnapshot(
        _ artifact: RecoveryArtifactDescriptor,
        expectedCount: UInt64,
        expectedRevisions: [RecoveryRevisionInventory]
    ) throws {
        let data = try Data(contentsOf: confinedURL(for: artifact.relativePath))
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard let first = lines.first else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The semantic snapshot has no format record."
            )
        }
        let header = try JSONDecoder().decode(SemanticSnapshotLine.self, from: Data(first))
        guard header.recordKind == "format",
              header.workspaceID == store.workspace.manifest.workspaceID.canonicalString,
              header.formatVersion == 1
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The semantic snapshot format record is invalid."
            )
        }

        var records: [RecoveryRevisionInventory] = []
        for rawLine in lines.dropFirst() {
            let line = try JSONDecoder().decode(SemanticSnapshotLine.self, from: Data(rawLine))
            guard line.recordKind == "semantic_revision",
                  let objectType = line.objectType,
                  let logicalID = line.logicalID,
                  let revisionID = line.revisionID,
                  let payloadDigest = line.payloadSHA256,
                  let payloadBase64 = line.canonicalPayloadBase64,
                  let payload = Data(base64Encoded: payloadBase64),
                  SQLitePayloadCodec.sha256(payload) == payloadDigest
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A semantic snapshot record is malformed or corrupted."
                )
            }
            try validateSemanticPayload(
                payload,
                objectType: objectType,
                logicalID: logicalID,
                revisionID: revisionID
            )
            records.append(
                RecoveryRevisionInventory(
                    objectType: objectType,
                    logicalID: logicalID,
                    revisionID: revisionID,
                    payloadSHA256: payloadDigest
                )
            )
        }
        guard UInt64(records.count) == expectedCount,
              records == expectedRevisions
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The semantic snapshot does not match the authoritative database backup."
            )
        }
    }

    private func verifyAssetHashes(
        _ artifact: RecoveryArtifactDescriptor,
        expectedCount: UInt64,
        expectedRecords: [ManagedAssetRecord]
    ) throws {
        let data = try Data(contentsOf: confinedURL(for: artifact.relativePath))
        let records = try JSONDecoder().decode([ManagedAssetRecord].self, from: data)
        guard UInt64(records.count) == expectedCount,
              try canonicalData(records) == data,
              records == expectedRecords
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The managed-asset recovery inventory is not canonical or complete."
            )
        }
        for record in records {
            try storage.verifyFile(for: record)
        }
    }

    private func verifyMigrationVersion(
        _ artifact: RecoveryArtifactDescriptor,
        manifest: RecoverySnapshotManifest,
        expectedMigrations: [String]
    ) throws {
        let data = try Data(contentsOf: confinedURL(for: artifact.relativePath))
        let migration = try JSONDecoder().decode(MigrationVersionArtifact.self, from: data)
        guard try canonicalData(migration) == data,
              migration.workspaceID == manifest.workspaceID,
              migration.databaseSchemaVersion == manifest.schemaVersion,
              migration.appliedMigrations == expectedMigrations,
              migration.appliedMigrations.first == SQLiteSchema.initialMigrationIdentifier
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The migration-version recovery artifact is invalid."
            )
        }
    }

    private func validateSemanticPayload(
        _ payload: Data,
        objectType: String,
        logicalID: String,
        revisionID: String
    ) throws {
        let reference = try SQLiteReferenceCodec.reference(
            objectTypeValue: objectType,
            logicalIDValue: logicalID,
            revisionIDValue: revisionID
        )
        let canonical: Data
        switch reference.objectType {
        case .sourceAsset:
            canonical = try roundTrip(SourceAssetV1.self, payload, expectedReference: reference)
        case .evidenceRef:
            canonical = try roundTrip(EvidenceRefV1.self, payload, expectedReference: reference)
        case .meetingProfile:
            canonical = try roundTrip(MeetingProfileV1.self, payload, expectedReference: reference)
        case .transcriptSegment:
            canonical = try roundTrip(TranscriptSegmentV1.self, payload, expectedReference: reference)
        case .translationSegment:
            canonical = try roundTrip(TranslationSegmentV1.self, payload, expectedReference: reference)
        case .actor:
            canonical = try roundTrip(ActorV1.self, payload, expectedReference: reference)
        case .speakingCapacity:
            canonical = try roundTrip(SpeakingCapacityV1.self, payload, expectedReference: reference)
        case .speakerAssignment:
            canonical = try roundTrip(SpeakerAssignmentV1.self, payload, expectedReference: reference)
        case .participant:
            canonical = try roundTrip(ParticipantV1.self, payload, expectedReference: reference)
        case .organization:
            canonical = try roundTrip(OrganizationV1.self, payload, expectedReference: reference)
        case .issue:
            canonical = try roundTrip(IssueV1.self, payload, expectedReference: reference)
        case .position:
            canonical = try roundTrip(PositionV1.self, payload, expectedReference: reference)
        case .commitment:
            canonical = try roundTrip(CommitmentV1.self, payload, expectedReference: reference)
        case .decision:
            canonical = try roundTrip(DecisionV1.self, payload, expectedReference: reference)
        case .interventionCard:
            canonical = try roundTrip(InterventionCardV1.self, payload, expectedReference: reference)
        case .delegationPositionCard:
            canonical = try roundTrip(DelegationPositionCardV1.self, payload, expectedReference: reference)
        case .meetingTemplate:
            canonical = try roundTrip(MeetingTemplateV1.self, payload, expectedReference: reference)
        case .issuePositionGraph:
            canonical = try roundTrip(IssuePositionGraphV1.self, payload, expectedReference: reference)
        case .briefingSection:
            canonical = try roundTrip(BriefingSectionV1.self, payload, expectedReference: reference)
        case .validationReport:
            canonical = try roundTrip(ValidationReportV1.self, payload, expectedReference: reference)
        case .finalBriefing:
            canonical = try roundTrip(FinalBriefingV1.self, payload, expectedReference: reference)
        case .sensitivityLabel:
            canonical = try roundTrip(SensitivityLabelV1.self, payload, expectedReference: reference)
        case .accessPolicy:
            canonical = try roundTrip(AccessPolicyV1.self, payload, expectedReference: reference)
        case .historicalComparison:
            canonical = try roundTrip(HistoricalComparisonV1.self, payload, expectedReference: reference)
        case .userConfirmedNote, .unrecognized:
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The semantic snapshot contains an unsupported object payload."
            )
        }
        guard canonical == payload else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The semantic snapshot payload is not canonical."
            )
        }
    }

    private func roundTrip<Value: SemanticRevisionContract>(
        _ type: Value.Type,
        _ payload: Data,
        expectedReference: SemanticRevisionReference
    ) throws -> Data {
        let decoded = try CanonicalJSON.decodeValidated(type, from: payload)
        let actualReference = try SemanticRevisionReference(
            logicalID: decoded.revision.logicalID,
            revisionID: decoded.revision.revisionID
        )
        guard actualReference == expectedReference else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A semantic snapshot index does not match its canonical payload revision."
            )
        }
        return try CanonicalJSON.encodeValidated(decoded)
    }

    private func confinedURL(for relativePath: WorkspaceRelativePath) throws -> URL {
        let candidate = store.workspace.layout.root
            .appendingPathComponent(relativePath.rawValue)
        return try WorkspacePathSecurity.confinedURL(
            candidate,
            within: store.workspace.layout.root
        )
    }

    private func makeEmptyFile(at url: URL) throws -> FileHandle {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A recovery artifact file could not be created."
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try FileHandle(forWritingTo: url)
    }

    private func writeJSONLine<Value: Encodable>(
        _ value: Value,
        to handle: FileHandle
    ) throws {
        var data = try canonicalData(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private struct SemanticSnapshotLine: Codable, Sendable {
    let recordKind: String
    let formatVersion: UInt32?
    let workspaceID: String?
    let objectType: String?
    let logicalID: String?
    let revisionID: String?
    let payloadSHA256: String?
    let canonicalPayloadBase64: String?

    static func header(workspaceID: WorkspaceID) -> Self {
        Self(
            recordKind: "format",
            formatVersion: 1,
            workspaceID: workspaceID.canonicalString,
            objectType: nil,
            logicalID: nil,
            revisionID: nil,
            payloadSHA256: nil,
            canonicalPayloadBase64: nil
        )
    }

    static func revision(
        objectType: String,
        logicalID: String,
        revisionID: String,
        payloadSHA256: String,
        canonicalPayloadBase64: String
    ) -> Self {
        Self(
            recordKind: "semantic_revision",
            formatVersion: nil,
            workspaceID: nil,
            objectType: objectType,
            logicalID: logicalID,
            revisionID: revisionID,
            payloadSHA256: payloadSHA256,
            canonicalPayloadBase64: canonicalPayloadBase64
        )
    }

    private enum CodingKeys: String, CodingKey {
        case recordKind = "record_kind"
        case formatVersion = "format_version"
        case workspaceID = "workspace_id"
        case objectType = "object_type"
        case logicalID = "logical_id"
        case revisionID = "revision_id"
        case payloadSHA256 = "payload_sha256"
        case canonicalPayloadBase64 = "canonical_payload_base64"
    }
}

private struct MigrationVersionArtifact: Codable, Sendable {
    let workspaceID: WorkspaceID
    let databaseSchemaVersion: UInt32
    let appliedMigrations: [String]

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case databaseSchemaVersion = "database_schema_version"
        case appliedMigrations = "applied_migrations"
    }
}

private struct RecoveryRevisionInventory: Equatable, Sendable {
    let objectType: String
    let logicalID: String
    let revisionID: String
    let payloadSHA256: String
}

private struct RecoveryDatabaseInventory: Sendable {
    let revisions: [RecoveryRevisionInventory]
    let managedAssets: [ManagedAssetRecord]
    let migrations: [String]
}
