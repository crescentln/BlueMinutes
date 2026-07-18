import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class SQLiteJobRepository: JobRepository, @unchecked Sendable {
    private let store: SQLitePersistenceStore

    public init(store: SQLitePersistenceStore) {
        self.store = store
    }

    public func create(_ record: JobRecord) async throws {
        try record.validate()
        guard record.state == .queued, record.recordVersion == 1 else {
            throw JobContractError.invalidState("A new persisted job must be queued at version 1.")
        }
        let payload = try canonicalPayload(record)
        try await store.databasePool.write { db in
            if let existing = try fetch(jobID: record.jobID, in: db) {
                guard existing == record else {
                    throw JobContractError.optimisticLockFailed(record.jobID)
                }
                return
            }
            if try String.fetchOne(
                db,
                sql: "SELECT job_id FROM jobs WHERE job_type = ? AND idempotency_key = ?",
                arguments: [record.jobType.rawValue, record.idempotencyKey.lowercaseHex]
            ) != nil {
                throw JobContractError.duplicateIdempotencyKey
            }
            for dependencyID in record.dependencyJobIDs {
                guard try String.fetchOne(
                    db,
                    sql: "SELECT job_id FROM jobs WHERE job_id = ?",
                    arguments: [dependencyID.canonicalString]
                ) != nil else {
                    throw TaskRuntimeError.dependencyMissing(dependencyID)
                }
            }
            try validateReferencesExist(record.inputRevisionIDs, in: db)
            try insertJob(record, payload: payload, in: db)
            try insertDependencies(for: record, in: db)
            try insertReferences(
                record.inputRevisionIDs,
                table: "job_input_revisions",
                jobID: record.jobID,
                in: db
            )
            try insertStateEvent(
                record: record,
                previousState: nil,
                sequence: 1,
                occurredAt: record.createdAt,
                payload: payload,
                in: db
            )
        }
    }

    public func job(id: JobID) async throws -> JobRecord? {
        try await store.databasePool.read { db in try fetch(jobID: id, in: db) }
    }

    public func job(
        jobType: JobType,
        idempotencyKey: JobIdempotencyKey
    ) async throws -> JobRecord? {
        try await store.databasePool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM jobs WHERE job_type = ? AND idempotency_key = ?",
                arguments: [jobType.rawValue, idempotencyKey.lowercaseHex]
            ) else {
                return nil
            }
            let record = try decode(row: row)
            try validateIndexedCollections(for: record, in: db)
            return record
        }
    }

    public func jobs(states: Set<JobState>?) async throws -> [JobRecord] {
        try await store.databasePool.read { db in
            let rows: [Row]
            if let states {
                guard !states.isEmpty else { return [] }
                let values = states.map(\.rawValue).sorted()
                let placeholders = Array(repeating: "?", count: values.count).joined(separator: ",")
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM jobs
                    WHERE state IN (\(placeholders))
                    ORDER BY created_at_ms, job_id
                    """,
                    arguments: StatementArguments(values)
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM jobs ORDER BY created_at_ms, job_id"
                )
            }
            return try rows.map { row in
                let record = try decode(row: row)
                try validateIndexedCollections(for: record, in: db)
                return record
            }
        }
    }

    public func replace(
        _ record: JobRecord,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) async throws {
        try record.validate()
        guard expectedVersion < UInt64(Int64.max),
              record.recordVersion == expectedVersion + 1
        else {
            throw JobContractError.optimisticLockFailed(record.jobID)
        }
        let payload = try canonicalPayload(record)
        try await store.databasePool.write { db in
            guard let previous = try fetch(jobID: record.jobID, in: db) else {
                throw JobContractError.jobNotFound(record.jobID)
            }
            guard previous.recordVersion == expectedVersion else {
                throw JobContractError.optimisticLockFailed(record.jobID)
            }
            try validateImmutableFields(previous: previous, replacement: record)
            try validateMutation(previous: previous, replacement: record)
            if record.state == .succeeded {
                try validateCurrentReferences(record.inputRevisionIDs, in: db)
                try validateReferencesExist(record.outputRevisionIDs, in: db)
            }

            try db.execute(
                sql: """
                UPDATE jobs
                SET state = ?,
                    started_at_ms = ?,
                    finished_at_ms = ?,
                    retry_count = ?,
                    record_version = ?,
                    record_payload = ?,
                    record_sha256 = ?,
                    record_byte_size = ?
                WHERE job_id = ? AND record_version = ?
                """,
                arguments: [
                    record.state.rawValue,
                    record.startedAt?.millisecondsSinceUnixEpoch,
                    record.finishedAt?.millisecondsSinceUnixEpoch,
                    Int64(record.retryCount),
                    Int64(record.recordVersion),
                    payload.data,
                    payload.sha256,
                    payload.data.count,
                    record.jobID.canonicalString,
                    Int64(expectedVersion)
                ]
            )
            guard db.changesCount == 1 else {
                throw JobContractError.optimisticLockFailed(record.jobID)
            }
            if previous.outputRevisionIDs.isEmpty, !record.outputRevisionIDs.isEmpty {
                try insertReferences(
                    record.outputRevisionIDs,
                    table: "job_output_revisions",
                    jobID: record.jobID,
                    in: db
                )
            }
            if previous.state != record.state {
                let sequence = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM job_state_events WHERE job_id = ?",
                    arguments: [record.jobID.canonicalString]
                ) ?? 1
                try insertStateEvent(
                    record: record,
                    previousState: previous.state,
                    sequence: sequence,
                    occurredAt: changedAt,
                    payload: payload,
                    in: db
                )
            }
        }
    }

    public func validateInputRevisionsAreCurrent(
        _ revisions: [SemanticRevisionReference]
    ) async throws {
        try await store.databasePool.read { db in
            try validateCurrentReferences(revisions, in: db)
        }
    }

    public func databaseHealth() async throws -> TaskDatabaseHealth {
        try await store.databasePool.read { db in
            let version = try Int64.fetchOne(
                db,
                sql: "SELECT database_schema_version FROM workspace_metadata WHERE singleton = 1"
            ) ?? -1
            let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "unknown"
            let quickCheck = try String.fetchOne(db, sql: "PRAGMA quick_check(1)")
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            return TaskDatabaseHealth(
                schemaVersion: version >= 0 ? UInt32(version) : 0,
                expectedSchemaVersion: SQLiteSchema.currentVersion,
                journalMode: journalMode.lowercased(),
                quickCheckPassed: quickCheck == "ok",
                foreignKeyFailureCount: UInt32(clamping: foreignKeyFailures)
            )
        }
    }

    private func insertJob(
        _ record: JobRecord,
        payload: EncodedPayload,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO jobs(
                job_id,
                job_type,
                meeting_id,
                state,
                created_at_ms,
                started_at_ms,
                finished_at_ms,
                retry_count,
                maximum_retry_count,
                record_version,
                idempotency_key,
                temporary_directory,
                disk_budget_bytes_decimal,
                privacy_route,
                data_classification,
                resume_capability,
                record_payload,
                record_sha256,
                record_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                record.jobID.canonicalString,
                record.jobType.rawValue,
                record.meetingID?.canonicalString,
                record.state.rawValue,
                record.createdAt.millisecondsSinceUnixEpoch,
                record.startedAt?.millisecondsSinceUnixEpoch,
                record.finishedAt?.millisecondsSinceUnixEpoch,
                Int64(record.retryCount),
                Int64(record.maximumRetryCount),
                Int64(record.recordVersion),
                record.idempotencyKey.lowercaseHex,
                record.temporaryDirectory.relativePath.rawValue,
                String(record.temporaryDirectory.diskBudgetBytes),
                record.privacyRoute.encodedValue,
                record.dataClassification.encodedValue,
                record.resumeCapability.rawValue,
                payload.data,
                payload.sha256,
                payload.data.count
            ]
        )
    }

    private func insertDependencies(for record: JobRecord, in db: Database) throws {
        for (ordinal, dependencyID) in record.dependencyJobIDs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO job_dependencies(job_id, dependency_job_id, ordinal)
                VALUES (?, ?, ?)
                """,
                arguments: [record.jobID.canonicalString, dependencyID.canonicalString, ordinal]
            )
        }
    }

    private func insertReferences(
        _ references: [SemanticRevisionReference],
        table: String,
        jobID: JobID,
        in db: Database
    ) throws {
        precondition(table == "job_input_revisions" || table == "job_output_revisions")
        for (ordinal, reference) in references.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO \(table)(job_id, ordinal, object_type, logical_id, revision_id)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    jobID.canonicalString,
                    ordinal,
                    reference.objectType.encodedValue,
                    reference.logicalID.canonicalString,
                    reference.revisionID.canonicalString
                ]
            )
        }
    }

    private func insertStateEvent(
        record: JobRecord,
        previousState: JobState?,
        sequence: Int64,
        occurredAt: UTCInstant,
        payload: EncodedPayload,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO job_state_events(
                event_id,
                job_id,
                sequence,
                previous_state,
                replacement_state,
                record_version,
                occurred_at_ms,
                record_payload,
                record_sha256
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(),
                record.jobID.canonicalString,
                sequence,
                previousState?.rawValue,
                record.state.rawValue,
                Int64(record.recordVersion),
                occurredAt.millisecondsSinceUnixEpoch,
                payload.data,
                payload.sha256
            ]
        )
    }

    private func fetch(jobID: JobID, in db: Database) throws -> JobRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM jobs WHERE job_id = ?",
            arguments: [jobID.canonicalString]
        ) else {
            return nil
        }
        let record = try decode(row: row)
        try validateIndexedCollections(for: record, in: db)
        return record
    }

    private func decode(row: Row) throws -> JobRecord {
        let payload: Data = row["record_payload"]
        let storedHash: String = row["record_sha256"]
        let storedSize: Int = row["record_byte_size"]
        guard payload.count == storedSize,
              digest(payload) == storedHash,
              payload.count <= SQLiteSchema.maximumJobPayloadBytes
        else {
            throw JobContractError.invalidState("A stored job payload failed integrity checks.")
        }
        let record = try JSONDecoder().decode(JobRecord.self, from: payload)
        try record.validate()
        guard try canonicalPayload(record).data == payload,
              record.jobID.canonicalString == (row["job_id"] as String),
              record.jobType.rawValue == (row["job_type"] as String),
              record.meetingID?.canonicalString == (row["meeting_id"] as String?),
              record.state.rawValue == (row["state"] as String),
              record.createdAt.millisecondsSinceUnixEpoch == (row["created_at_ms"] as Int64),
              record.startedAt?.millisecondsSinceUnixEpoch == (row["started_at_ms"] as Int64?),
              record.finishedAt?.millisecondsSinceUnixEpoch == (row["finished_at_ms"] as Int64?),
              Int64(record.retryCount) == (row["retry_count"] as Int64),
              Int64(record.maximumRetryCount) == (row["maximum_retry_count"] as Int64),
              Int64(record.recordVersion) == (row["record_version"] as Int64),
              record.idempotencyKey.lowercaseHex == (row["idempotency_key"] as String),
              record.temporaryDirectory.relativePath.rawValue
                == (row["temporary_directory"] as String),
              String(record.temporaryDirectory.diskBudgetBytes)
                == (row["disk_budget_bytes_decimal"] as String),
              record.privacyRoute.encodedValue == (row["privacy_route"] as String),
              record.dataClassification.encodedValue == (row["data_classification"] as String),
              record.resumeCapability.rawValue == (row["resume_capability"] as String)
        else {
            throw JobContractError.invalidState("Stored job indexes disagree with the payload.")
        }
        return record
    }

    private func validateReferencesExist(
        _ references: [SemanticRevisionReference],
        in db: Database
    ) throws {
        for reference in references {
            guard try String.fetchOne(
                db,
                sql: """
                SELECT revision_id FROM semantic_revisions
                WHERE object_type = ? AND logical_id = ? AND revision_id = ?
                """,
                arguments: [
                    reference.objectType.encodedValue,
                    reference.logicalID.canonicalString,
                    reference.revisionID.canonicalString
                ]
            ) != nil else {
                throw PersistenceContractError.revisionNotFound(reference.revisionID)
            }
        }
    }

    private func validateIndexedCollections(
        for record: JobRecord,
        in db: Database
    ) throws {
        let dependencyValues = try String.fetchAll(
            db,
            sql: """
            SELECT dependency_job_id FROM job_dependencies
            WHERE job_id = ? ORDER BY ordinal
            """,
            arguments: [record.jobID.canonicalString]
        )
        let dependencies = try dependencyValues.map(JobID.init(validating:))
        let inputs = try indexedReferences(
            table: "job_input_revisions",
            jobID: record.jobID,
            in: db
        )
        let outputs = try indexedReferences(
            table: "job_output_revisions",
            jobID: record.jobID,
            in: db
        )
        guard dependencies == record.dependencyJobIDs,
              inputs == record.inputRevisionIDs,
              outputs == record.outputRevisionIDs
        else {
            throw JobContractError.invalidState(
                "Stored job dependency or revision indexes disagree with the payload."
            )
        }
    }

    private func indexedReferences(
        table: String,
        jobID: JobID,
        in db: Database
    ) throws -> [SemanticRevisionReference] {
        precondition(table == "job_input_revisions" || table == "job_output_revisions")
        return try Row.fetchAll(
            db,
            sql: """
            SELECT object_type, logical_id, revision_id FROM \(table)
            WHERE job_id = ? ORDER BY ordinal
            """,
            arguments: [jobID.canonicalString]
        ).map { row in
            try SQLiteReferenceCodec.reference(
                objectTypeValue: row["object_type"],
                logicalIDValue: row["logical_id"],
                revisionIDValue: row["revision_id"]
            )
        }
    }

    private func validateCurrentReferences(
        _ revisions: [SemanticRevisionReference],
        in db: Database
    ) throws {
        for revision in revisions {
            let state = try String.fetchOne(
                db,
                sql: """
                SELECT currency_state FROM revision_current_state
                WHERE object_type = ? AND logical_id = ? AND revision_id = ?
                """,
                arguments: [
                    revision.objectType.encodedValue,
                    revision.logicalID.canonicalString,
                    revision.revisionID.canonicalString
                ]
            )
            guard state == "current" else {
                throw JobContractError.staleInput(revision.revisionID)
            }
            if let active = try String.fetchOne(
                db,
                sql: """
                SELECT revision_id FROM active_published_revisions
                WHERE object_type = ? AND logical_id = ?
                """,
                arguments: [
                    revision.objectType.encodedValue,
                    revision.logicalID.canonicalString
                ]
            ), active != revision.revisionID.canonicalString {
                throw JobContractError.staleInput(revision.revisionID)
            }
        }
    }

    private func validateImmutableFields(
        previous: JobRecord,
        replacement: JobRecord
    ) throws {
        guard previous.jobID == replacement.jobID,
              previous.jobType == replacement.jobType,
              previous.meetingID == replacement.meetingID,
              previous.origin == replacement.origin,
              previous.requestedBy == replacement.requestedBy,
              previous.createdAt == replacement.createdAt,
              previous.inputRevisionIDs == replacement.inputRevisionIDs,
              previous.dependencyJobIDs == replacement.dependencyJobIDs,
              previous.privacyRoute == replacement.privacyRoute,
              previous.dataClassification == replacement.dataClassification,
              previous.maximumRetryCount == replacement.maximumRetryCount,
              previous.idempotencyKey == replacement.idempotencyKey,
              previous.temporaryDirectory == replacement.temporaryDirectory,
              previous.resumeCapability == replacement.resumeCapability,
              previous.progress.totalUnitCount == replacement.progress.totalUnitCount
        else {
            throw JobContractError.invalidState("Immutable job fields cannot change.")
        }
    }

    private func validateMutation(previous: JobRecord, replacement: JobRecord) throws {
        if previous.state == replacement.state {
            guard replacement.retryCount == previous.retryCount,
                  replacement.progress.completedUnitCount
                    >= previous.progress.completedUnitCount
            else {
                throw JobContractError.invalidState("A same-state update must be monotonic.")
            }
            return
        }
        let isRetry = replacement.state == .queued
            && (previous.state == .failed
                || previous.state == .cancelled
                || previous.state == .interrupted)
            && replacement.retryCount == previous.retryCount + 1
        guard isRetry || JobStateMachine.allows(from: previous.state, to: replacement.state) else {
            throw JobContractError.transitionNotAllowed(
                from: previous.state,
                to: replacement.state
            )
        }
        if !isRetry, replacement.retryCount != previous.retryCount {
            throw JobContractError.invalidState("Only retry may increment the retry counter.")
        }
    }

    private func canonicalPayload(_ record: JobRecord) throws -> EncodedPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard !data.isEmpty, data.count <= SQLiteSchema.maximumJobPayloadBytes else {
            throw JobContractError.invalidState("The job payload exceeds its bounded storage budget.")
        }
        return EncodedPayload(data: data, sha256: digest(data))
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct EncodedPayload {
    let data: Data
    let sha256: String
}
