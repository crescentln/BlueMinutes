import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

/// SQLite authority for Task 009A command claims, immutable audit events, and
/// the single versioned safe setting. No command transport receives database access.
public final class SQLiteAutomationRepository: AutomationCommandRepository,
    @unchecked Sendable
{
    private let store: SQLitePersistenceStore
    private let storageReporter: LocalWorkspaceStorageReporter

    public init(store: SQLitePersistenceStore) {
        self.store = store
        storageReporter = LocalWorkspaceStorageReporter(
            workspace: store.workspace,
            store: store
        )
    }

    public func claimAutomationCommand(
        _ record: AutomationCommandRecord,
        inputRevisions: [SemanticRevisionReference]
    ) throws -> AutomationCommandClaimResult {
        guard record.claimsReplayNonce,
              record.workspaceID == store.workspace.manifest.workspaceID,
              inputRevisions == inputRevisions.sorted(),
              Set(inputRevisions).count == inputRevisions.count
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_command_claim_invalid"
            )
        }
        return try store.databasePool.write { db in
            if let existingDigest = try String.fetchOne(
                db,
                sql: "SELECT request_sha256 FROM automation_command_records WHERE command_id = ?",
                arguments: [record.commandID.canonicalString]
            ) {
                return .duplicateCommandID(
                    existingDigest: try ContentDigest(
                        algorithm: .sha256,
                        lowercaseHex: existingDigest
                    )
                )
            }
            if let original = try String.fetchOne(
                db,
                sql: """
                SELECT command_id FROM automation_command_records
                WHERE replay_nonce = ? AND claims_replay_nonce = 1
                """,
                arguments: [record.replayNonce.canonicalString]
            ) {
                return .replayed(
                    originalCommandID: try AutomationCommandID(validating: original)
                )
            }
            for reference in inputRevisions {
                guard try isCurrent(reference, in: db) else {
                    throw AutomationContractError.policyDenied(
                        "automation_policy_revision_not_current"
                    )
                }
            }
            try insert(record, in: db)
            try insert(inputRevisions, commandID: record.commandID, in: db)
            return .claimed
        }
    }

    public func recordAutomationReplay(
        _ record: AutomationCommandRecord,
        result: AutomationCommandResultEvent
    ) throws {
        guard !record.claimsReplayNonce,
              record.decision == .replayed,
              result.commandID == record.commandID,
              result.outcome == .rejected,
              record.workspaceID == store.workspace.manifest.workspaceID
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_replay_record_invalid"
            )
        }
        try store.databasePool.write { db in
            guard let originalCommandID = record.replayOfCommandID,
                  try String.fetchOne(
                      db,
                      sql: """
                      SELECT command_id FROM automation_command_records
                      WHERE command_id = ? AND replay_nonce = ? AND claims_replay_nonce = 1
                      """,
                      arguments: [
                          originalCommandID.canonicalString,
                          record.replayNonce.canonicalString
                      ]
                  ) != nil
            else {
                throw AutomationContractError.persistenceFailure(
                    "automation_replay_origin_missing"
                )
            }
            try insert(record, in: db)
            try insert(result, in: db)
        }
    }

    public func appendAutomationResult(_ event: AutomationCommandResultEvent) throws {
        try store.databasePool.write { db in
            try insert(event, in: db)
        }
    }

    public func currentAutomationSettings() throws -> VersionedAutomationSettings {
        try store.databasePool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM automation_settings_state WHERE singleton = 1"
            ) else {
                return .compiledDefault
            }
            return try decodeSettings(row)
        }
    }

    public func automationSettingsEvent(
        commandID: AutomationCommandID
    ) throws -> AutomationSettingsEvent? {
        try store.databasePool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM automation_settings_events WHERE command_id = ?",
                arguments: [commandID.canonicalString]
            ).map(decodeSettingsEvent)
        }
    }

    public func applyAutomationSettings(
        _ replacement: VersionedAutomationSettings,
        event: AutomationSettingsEvent,
        result: AutomationCommandResultEvent,
        expectedVersion: UInt64
    ) throws {
        guard replacement.version == expectedVersion + 1,
              event.replacement == replacement,
              event.prior.version == expectedVersion,
              result.commandID == event.commandID,
              result.priorSettingsVersion == expectedVersion,
              result.replacementSettingsVersion == replacement.version,
              (event.rollbackOfCommandID == nil
                && result.outcome == .completed
                && result.rollbackOfCommandID == nil)
                || (event.rollbackOfCommandID != nil
                    && result.outcome == .rolledBack
                    && result.rollbackOfCommandID == event.rollbackOfCommandID)
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_settings_transaction_invalid"
            )
        }
        try store.databasePool.write { db in
            let expectedCommandName = event.rollbackOfCommandID == nil
                ? AutomationCommandName.updateSettings.rawValue
                : AutomationCommandName.rollbackSettings.rawValue
            guard try String.fetchOne(
                db,
                sql: "SELECT command_name FROM automation_command_records WHERE command_id = ?",
                arguments: [event.commandID.canonicalString]
            ) == expectedCommandName else {
                throw AutomationContractError.persistenceFailure(
                    "automation_settings_command_mismatch"
                )
            }
            let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM automation_settings_state WHERE singleton = 1"
            ).map(decodeSettings) ?? .compiledDefault
            guard current.version == expectedVersion, current == event.prior else {
                throw AutomationContractError.settingsConflict
            }

            try insert(event, in: db)
            let payload = try SQLitePayloadCodec.canonicalData(replacement)
            if expectedVersion == 0 {
                try db.execute(
                    sql: """
                    INSERT INTO automation_settings_state(
                        singleton, version, status_list_limit, updated_by_command_id,
                        updated_at_ms, canonical_payload, payload_sha256, payload_byte_size
                    ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        replacement.version,
                        replacement.values.statusListLimit,
                        replacement.updatedByCommandID!.canonicalString,
                        replacement.updatedAt!.millisecondsSinceUnixEpoch,
                        payload,
                        SQLitePayloadCodec.sha256(payload),
                        payload.count
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                    UPDATE automation_settings_state
                    SET version = ?, status_list_limit = ?, updated_by_command_id = ?,
                        updated_at_ms = ?, canonical_payload = ?, payload_sha256 = ?,
                        payload_byte_size = ?
                    WHERE singleton = 1 AND version = ?
                    """,
                    arguments: [
                        replacement.version,
                        replacement.values.statusListLimit,
                        replacement.updatedByCommandID!.canonicalString,
                        replacement.updatedAt!.millisecondsSinceUnixEpoch,
                        payload,
                        SQLitePayloadCodec.sha256(payload),
                        payload.count,
                        expectedVersion
                    ]
                )
                guard db.changesCount == 1 else {
                    throw AutomationContractError.settingsConflict
                }
            }
            try insert(result, in: db)
        }
    }

    public func automationActivity(
        limit: UInt16,
        excludingCommandID: AutomationCommandID?
    ) throws -> [AutomationAuditTrail] {
        guard (1...200).contains(limit) else {
            throw AutomationContractError.invalidRequest("The activity-list bound is invalid.")
        }
        return try store.databasePool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM automation_command_records
                WHERE (? IS NULL OR command_id != ?)
                ORDER BY recorded_at_ms DESC, command_id DESC
                LIMIT ?
                """,
                arguments: [
                    excludingCommandID?.canonicalString,
                    excludingCommandID?.canonicalString,
                    limit
                ]
            )
            return try rows.map { row in
                let record = try decodeCommandRecord(row)
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
                let results = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM automation_command_result_events
                    WHERE command_id = ? ORDER BY sequence
                    """,
                    arguments: [record.commandID.canonicalString]
                ).map(decodeResultEvent)
                return try AutomationAuditTrail(
                    record: record,
                    inputRevisions: inputs,
                    resultEvents: results
                )
            }
        }
    }

    public func automationWorkspaceStatus(
        excludingCommandID: AutomationCommandID?
    ) throws -> AutomationWorkspaceStatus {
        try store.databasePool.read { db in
            let workspaceID = try requiredString(
                db,
                sql: "SELECT workspace_id FROM workspace_metadata WHERE singleton = 1"
            )
            let schemaVersion = try requiredCount(
                db,
                sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
            )
            return AutomationWorkspaceStatus(
                workspaceID: try WorkspaceID(validating: workspaceID),
                databaseSchemaVersion: UInt32(clamping: schemaVersion),
                semanticRevisionCount: UInt64(clamping: try requiredCount(
                    db,
                    sql: "SELECT COUNT(*) FROM semantic_revisions"
                )),
                jobCount: UInt64(clamping: try requiredCount(
                    db,
                    sql: "SELECT COUNT(*) FROM jobs"
                )),
                activeJobCount: UInt64(clamping: try requiredCount(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM jobs
                    WHERE state NOT IN ('succeeded', 'failed', 'cancelled', 'interrupted')
                    """
                )),
                commandCount: UInt64(clamping: try requiredCount(
                    db,
                    sql: "SELECT COUNT(*) FROM automation_command_records"
                )),
                incompleteCommandCount: UInt64(
                    clamping: try incompleteCommandCount(
                        in: db,
                        excludingCommandID: excludingCommandID
                    )
                )
            )
        }
    }

    public func automationStorageReport(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32
    ) throws -> AutomationStorageReport {
        AutomationStorageReport(
            try storageReporter.storageReport(
                calculatedAt: calculatedAt,
                maximumEntries: maximumEntries
            )
        )
    }

    public func automationDiagnostics(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32,
        usedRestrictedTaskDirectory: Bool,
        excludingCommandID: AutomationCommandID?
    ) throws -> AutomationDiagnosticsReport {
        let health = try store.databasePool.read { db in
            let quickCheck = try String.fetchOne(db, sql: "PRAGMA quick_check(1)") == "ok"
            let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            return (
                quickCheck,
                UInt64(clamping: foreignKeys),
                UInt64(
                    clamping: try incompleteCommandCount(
                        in: db,
                        excludingCommandID: excludingCommandID
                    )
                )
            )
        }
        let storage = try automationStorageReport(
            calculatedAt: calculatedAt,
            maximumEntries: maximumEntries
        )
        return AutomationDiagnosticsReport(
            calculatedAt: calculatedAt,
            databaseQuickCheckPassed: health.0,
            foreignKeyFailureCount: health.1,
            incompleteCommandCount: health.2,
            storagePermissionIssueCount: storage.permissionIssueCount,
            storageScanTruncated: storage.scanTruncated,
            usedRestrictedTaskDirectory: usedRestrictedTaskDirectory
        )
    }

    public func currentAutomationSecurityContext(
        meetingID: MeetingID
    ) throws -> AutomationSecurityContext {
        try store.databasePool.read { db in
            let meetingRows = try activeRows(
                objectType: .meetingProfile,
                logicalID: meetingID.canonicalString,
                upstream: nil,
                in: db
            )
            guard meetingRows.count == 1 else {
                throw AutomationContractError.policyDenied(
                    "current_meeting_revision_unavailable"
                )
            }
            let meeting: MeetingProfileV1 = try decodeSemantic(meetingRows[0])
            guard meeting.workspaceID == store.workspace.manifest.workspaceID else {
                throw AutomationContractError.policyDenied(
                    "meeting_workspace_mismatch"
                )
            }
            let meetingReference = try SemanticRevisionReference(
                logicalID: meeting.meetingID,
                revisionID: meeting.revision.revisionID
            )

            let labelRows = try activeRows(
                objectType: .sensitivityLabel,
                logicalID: nil,
                upstream: meetingReference,
                in: db
            )
            guard labelRows.count == 1 else {
                throw AutomationContractError.policyDenied(
                    "current_sensitivity_label_unavailable"
                )
            }
            let label: SensitivityLabelV1 = try decodeSemantic(labelRows[0])
            let labelReference = try SemanticRevisionReference(
                logicalID: label.labelID,
                revisionID: label.revision.revisionID
            )

            let policyRows = try activeRows(
                objectType: .accessPolicy,
                logicalID: nil,
                upstream: labelReference,
                in: db
            )
            guard policyRows.count == 1 else {
                throw AutomationContractError.policyDenied(
                    "current_access_policy_unavailable"
                )
            }
            let policy: AccessPolicyV1 = try decodeSemantic(policyRows[0])
            return try AutomationSecurityContext(
                meeting: meeting,
                sensitivityLabel: label,
                accessPolicy: policy
            )
        }
    }

    private func insert(_ record: AutomationCommandRecord, in db: Database) throws {
        let payload = try SQLitePayloadCodec.canonicalData(record)
        try db.execute(
            sql: """
            INSERT INTO automation_command_records(
                command_id, replay_nonce, claims_replay_nonce, replay_of_command_id,
                command_name, request_sha256, workspace_id, meeting_id, actor_id,
                origin, adapter_version, granted_permission, required_permission,
                decision, safe_reason_code, confirmation_requirement, root_command_id,
                parent_command_id, hop_count, recorded_at_ms, canonical_payload,
                payload_sha256, payload_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                record.commandID.canonicalString,
                record.replayNonce.canonicalString,
                record.claimsReplayNonce ? 1 : 0,
                record.replayOfCommandID?.canonicalString,
                record.commandName.rawValue,
                record.requestDigest.lowercaseHex,
                record.workspaceID.canonicalString,
                record.meetingID?.canonicalString,
                record.actorID.rawValue,
                record.origin.rawValue,
                record.adapterVersion,
                record.grantedPermission.rawValue,
                record.requiredPermission.rawValue,
                record.decision.rawValue,
                record.safeReasonCode,
                record.confirmationRequirement.rawValue,
                record.rootCommandID?.canonicalString,
                record.parentCommandID?.canonicalString,
                record.hopCount,
                record.recordedAt.millisecondsSinceUnixEpoch,
                payload,
                SQLitePayloadCodec.sha256(payload),
                payload.count
            ]
        )
    }

    private func insert(
        _ revisions: [SemanticRevisionReference],
        commandID: AutomationCommandID,
        in db: Database
    ) throws {
        for (ordinal, revision) in revisions.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO automation_command_input_revisions(
                    command_id, ordinal, object_type, logical_id, revision_id
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    commandID.canonicalString,
                    ordinal,
                    revision.objectType.encodedValue,
                    revision.logicalID.canonicalString,
                    revision.revisionID.canonicalString
                ]
            )
        }
    }

    private func insert(_ event: AutomationCommandResultEvent, in db: Database) throws {
        let payload = try SQLitePayloadCodec.canonicalData(event)
        try db.execute(
            sql: """
            INSERT INTO automation_command_result_events(
                event_id, command_id, sequence, outcome, safe_code, result_sha256,
                prior_settings_version, replacement_settings_version,
                rollback_of_command_id, used_restricted_task_directory, occurred_at_ms,
                canonical_payload, payload_sha256, payload_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                event.eventID.canonicalString,
                event.commandID.canonicalString,
                event.sequence,
                event.outcome.rawValue,
                event.safeCode,
                event.resultDigest?.lowercaseHex,
                event.priorSettingsVersion,
                event.replacementSettingsVersion,
                event.rollbackOfCommandID?.canonicalString,
                event.usedRestrictedTaskDirectory ? 1 : 0,
                event.occurredAt.millisecondsSinceUnixEpoch,
                payload,
                SQLitePayloadCodec.sha256(payload),
                payload.count
            ]
        )
    }

    private func insert(_ event: AutomationSettingsEvent, in db: Database) throws {
        let payload = try SQLitePayloadCodec.canonicalData(event)
        try db.execute(
            sql: """
            INSERT INTO automation_settings_events(
                event_id, command_id, prior_version, replacement_version,
                prior_status_list_limit, replacement_status_list_limit,
                rollback_of_command_id, occurred_at_ms, canonical_payload,
                payload_sha256, payload_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                event.eventID.canonicalString,
                event.commandID.canonicalString,
                event.prior.version,
                event.replacement.version,
                event.prior.values.statusListLimit,
                event.replacement.values.statusListLimit,
                event.rollbackOfCommandID?.canonicalString,
                event.occurredAt.millisecondsSinceUnixEpoch,
                payload,
                SQLitePayloadCodec.sha256(payload),
                payload.count
            ]
        )
    }

    private func decodeCommandRecord(_ row: Row) throws -> AutomationCommandRecord {
        let record: AutomationCommandRecord = try decodePayload(row)
        guard record.commandID.canonicalString == (row["command_id"] as String),
              record.replayNonce.canonicalString == (row["replay_nonce"] as String),
              record.commandName.rawValue == (row["command_name"] as String),
              record.requestDigest.lowercaseHex == (row["request_sha256"] as String),
              record.workspaceID.canonicalString == (row["workspace_id"] as String),
              record.actorID.rawValue == (row["actor_id"] as String),
              record.decision.rawValue == (row["decision"] as String),
              record.recordedAt.millisecondsSinceUnixEpoch == (row["recorded_at_ms"] as Int64)
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_command_record_integrity_failed"
            )
        }
        return record
    }

    private func decodeResultEvent(_ row: Row) throws -> AutomationCommandResultEvent {
        let event: AutomationCommandResultEvent = try decodePayload(row)
        guard event.eventID.canonicalString == (row["event_id"] as String),
              event.commandID.canonicalString == (row["command_id"] as String),
              event.outcome.rawValue == (row["outcome"] as String),
              event.safeCode == (row["safe_code"] as String),
              event.occurredAt.millisecondsSinceUnixEpoch == (row["occurred_at_ms"] as Int64)
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_result_event_integrity_failed"
            )
        }
        return event
    }

    private func decodeSettings(_ row: Row) throws -> VersionedAutomationSettings {
        let settings: VersionedAutomationSettings = try decodePayload(row)
        guard Int64(settings.version) == (row["version"] as Int64),
              Int64(settings.values.statusListLimit) == (row["status_list_limit"] as Int64),
              settings.updatedByCommandID?.canonicalString
                == (row["updated_by_command_id"] as String?),
              settings.updatedAt?.millisecondsSinceUnixEpoch == (row["updated_at_ms"] as Int64?)
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_settings_integrity_failed"
            )
        }
        return settings
    }

    private func decodeSettingsEvent(_ row: Row) throws -> AutomationSettingsEvent {
        let event: AutomationSettingsEvent = try decodePayload(row)
        guard event.eventID.canonicalString == (row["event_id"] as String),
              event.commandID.canonicalString == (row["command_id"] as String),
              Int64(event.prior.version) == (row["prior_version"] as Int64),
              Int64(event.replacement.version) == (row["replacement_version"] as Int64),
              event.occurredAt.millisecondsSinceUnixEpoch == (row["occurred_at_ms"] as Int64)
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_settings_event_integrity_failed"
            )
        }
        return event
    }

    private func decodePayload<Value: Codable>(_ row: Row) throws -> Value {
        let payload: Data = row["canonical_payload"]
        let storedDigest: String = row["payload_sha256"]
        let storedSize: Int = row["payload_byte_size"]
        guard payload.count == storedSize,
              SQLitePayloadCodec.sha256(payload) == storedDigest
        else {
            throw AutomationContractError.persistenceFailure(
                "automation_payload_integrity_failed"
            )
        }
        let value = try JSONDecoder().decode(Value.self, from: payload)
        guard try SQLitePayloadCodec.canonicalData(value) == payload else {
            throw AutomationContractError.persistenceFailure(
                "automation_payload_not_canonical"
            )
        }
        return value
    }

    private func isCurrent(
        _ reference: SemanticRevisionReference,
        in db: Database
    ) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: """
            SELECT 1 FROM semantic_revisions AS revision
            JOIN revision_current_state AS state
              ON state.object_type = revision.object_type
             AND state.logical_id = revision.logical_id
             AND state.revision_id = revision.revision_id
            JOIN active_published_revisions AS active
              ON active.object_type = revision.object_type
             AND active.logical_id = revision.logical_id
             AND active.revision_id = revision.revision_id
            WHERE revision.object_type = ? AND revision.logical_id = ?
              AND revision.revision_id = ? AND state.currency_state = 'current'
              AND NOT EXISTS (
                  SELECT 1 FROM stale_events AS stale
                  WHERE stale.affected_object_type = revision.object_type
                    AND stale.affected_logical_id = revision.logical_id
                    AND stale.affected_revision_id = revision.revision_id
              )
            """,
            arguments: [
                reference.objectType.encodedValue,
                reference.logicalID.canonicalString,
                reference.revisionID.canonicalString
            ]
        ) == 1
    }

    private func activeRows(
        objectType: SemanticObjectType,
        logicalID: String?,
        upstream: SemanticRevisionReference?,
        in db: Database
    ) throws -> [Row] {
        var sql = """
        SELECT DISTINCT revision.* FROM semantic_revisions AS revision
        JOIN active_published_revisions AS active
          ON active.object_type = revision.object_type
         AND active.logical_id = revision.logical_id
         AND active.revision_id = revision.revision_id
        JOIN revision_current_state AS state
          ON state.object_type = revision.object_type
         AND state.logical_id = revision.logical_id
         AND state.revision_id = revision.revision_id
        """
        var arguments: StatementArguments = [objectType.encodedValue]
        if upstream != nil {
            sql += """

            JOIN dependency_edges AS edge
              ON edge.downstream_object_type = revision.object_type
             AND edge.downstream_logical_id = revision.logical_id
             AND edge.downstream_revision_id = revision.revision_id
            """
        }
        sql += """

        WHERE revision.object_type = ? AND state.currency_state = 'current'
          AND NOT EXISTS (
              SELECT 1 FROM stale_events AS stale
              WHERE stale.affected_object_type = revision.object_type
                AND stale.affected_logical_id = revision.logical_id
                AND stale.affected_revision_id = revision.revision_id
          )
        """
        if let logicalID {
            sql += " AND revision.logical_id = ?"
            arguments += [logicalID]
        }
        if let upstream {
            sql += """

              AND edge.upstream_object_type = ?
              AND edge.upstream_logical_id = ?
              AND edge.upstream_revision_id = ?
            """
            arguments += [
                upstream.objectType.encodedValue,
                upstream.logicalID.canonicalString,
                upstream.revisionID.canonicalString
            ]
        }
        sql += " ORDER BY revision.logical_id, revision.revision_id"
        return try Row.fetchAll(db, sql: sql, arguments: arguments)
    }

    private func decodeSemantic<Object: SemanticRevisionContract>(
        _ row: Row
    ) throws -> Object {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        let size: Int = row["payload_byte_size"]
        guard payload.count == size,
              SQLitePayloadCodec.sha256(payload) == digest
        else {
            throw AutomationContractError.policyDenied("policy_payload_integrity_failed")
        }
        let object = try JSONDecoder().decode(Object.self, from: payload)
        try object.validate()
        guard try SQLitePayloadCodec.canonicalData(object) == payload,
              object.revision.objectType.encodedValue == (row["object_type"] as String),
              object.revision.logicalID.canonicalString == (row["logical_id"] as String),
              object.revision.revisionID.canonicalString == (row["revision_id"] as String)
        else {
            throw AutomationContractError.policyDenied("policy_payload_integrity_failed")
        }
        return object
    }

    private func incompleteCommandCount(
        in db: Database,
        excludingCommandID: AutomationCommandID?
    ) throws -> Int64 {
        try requiredCount(
            db,
            sql: """
            SELECT COUNT(*) FROM automation_command_records AS command
            LEFT JOIN automation_command_result_events AS result
              ON result.command_id = command.command_id
            WHERE result.command_id IS NULL
              AND (? IS NULL OR command.command_id != ?)
            """,
            arguments: [
                excludingCommandID?.canonicalString,
                excludingCommandID?.canonicalString
            ]
        )
    }

    private func requiredCount(
        _ db: Database,
        sql: String,
        arguments: StatementArguments = []
    ) throws -> Int64 {
        guard let value = try Int64.fetchOne(
            db,
            sql: sql,
            arguments: arguments
        ), value >= 0 else {
            throw AutomationContractError.persistenceFailure(
                "automation_status_integrity_failed"
            )
        }
        return value
    }

    private func requiredString(
        _ db: Database,
        sql: String
    ) throws -> String {
        guard let value = try String.fetchOne(db, sql: sql) else {
            throw AutomationContractError.persistenceFailure(
                "automation_status_integrity_failed"
            )
        }
        return value
    }
}
