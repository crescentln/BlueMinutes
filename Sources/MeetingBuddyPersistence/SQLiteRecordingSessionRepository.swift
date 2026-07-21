import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

extension SQLitePersistenceStore: RecordingSessionRepository {
    public func createIntent(_ intent: RecordingIntent) async throws -> RecordingSessionSnapshot {
        let payload = try SQLitePayloadCodec.canonicalData(intent)
        let digest = SQLitePayloadCodec.sha256(payload)
        guard payload.count <= JobCheckpoint.maximumPayloadBytes else {
            throw RecordingContractError.invalidIntent("The durable recording intent is too large.")
        }
        do {
            return try await databasePool.write { db in
                if let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT intent_payload, intent_sha256 FROM recording_sessions WHERE session_id = ?",
                    arguments: [intent.sessionID.canonicalString]
                ) {
                    let existingPayload: Data = existing["intent_payload"]
                    let existingDigest: String = existing["intent_sha256"]
                    guard existingPayload == payload, existingDigest == digest else {
                        throw RecordingContractError.integrityFailure("The recording session ID is already bound to another intent.")
                    }
                    return try recordingSnapshot(sessionID: intent.sessionID, in: db)
                }

                try db.execute(
                    sql: """
                    INSERT INTO recording_sessions(
                        session_id, job_id, meeting_id, intent_format_version, capture_mode,
                        requested_track_count, sensitivity_label_revision_id,
                        access_policy_revision_id, data_classification, no_outbound_mode,
                        authorization_event_id, state, state_version, created_at_ms,
                        updated_at_ms, terminal_reason, final_manifest_logical_id,
                        final_manifest_revision_id, intent_payload, intent_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'preparing', 1, ?, ?, NULL, NULL, NULL, ?, ?)
                    """,
                    arguments: [
                        intent.sessionID.canonicalString,
                        intent.jobID.canonicalString,
                        intent.meetingID.canonicalString,
                        intent.formatVersion,
                        intent.mode.rawValue,
                        intent.requestedTracks.count,
                        intent.policy.sensitivityLabelRevision.revisionID.canonicalString,
                        intent.policy.accessPolicyRevision.revisionID.canonicalString,
                        intent.policy.dataClassification.encodedValue,
                        intent.policy.noOutboundMode,
                        intent.authorization.eventID.canonicalString,
                        intent.createdAt.millisecondsSinceUnixEpoch,
                        intent.createdAt.millisecondsSinceUnixEpoch,
                        payload,
                        digest
                    ]
                )
                for track in intent.requestedTracks {
                    try db.execute(
                        sql: """
                        INSERT INTO recording_tracks(
                            track_id, session_id, source_kind, is_required, created_at_ms
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            track.trackID.canonicalString,
                            intent.sessionID.canonicalString,
                            track.kind.rawValue,
                            track.required,
                            intent.createdAt.millisecondsSinceUnixEpoch
                        ]
                    )
                }
                return try recordingSnapshot(sessionID: intent.sessionID, in: db)
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure("The recording intent could not be committed atomically.")
        }
    }

    public func session(_ sessionID: RecordingSessionID) async throws -> RecordingSessionSnapshot? {
        try await databasePool.read { db in
            guard try Row.fetchOne(
                db,
                sql: "SELECT session_id FROM recording_sessions WHERE session_id = ?",
                arguments: [sessionID.canonicalString]
            ) != nil else { return nil }
            return try recordingSnapshot(sessionID: sessionID, in: db)
        }
    }

    public func session(jobID: JobID) async throws -> RecordingSessionSnapshot? {
        do {
            return try await databasePool.read { db in
                guard let sessionID: String = try String.fetchOne(
                    db,
                    sql: "SELECT session_id FROM recording_sessions WHERE job_id = ?",
                    arguments: [jobID.canonicalString]
                ) else { return nil }
                return try recordingSnapshot(
                    sessionID: RecordingSessionID(validating: sessionID),
                    in: db
                )
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure(
                "The recording job lookup failed closed."
            )
        }
    }

    public func nonterminalSessions() async throws -> [RecordingSessionSnapshot] {
        try await databasePool.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT session_id FROM recording_sessions
                WHERE state NOT IN ('completed', 'incomplete', 'failed')
                ORDER BY created_at_ms, session_id
                """
            ).map { try recordingSnapshot(sessionID: RecordingSessionID(validating: $0), in: db) }
        }
    }

    public func transition(_ transition: RecordingTransition) async throws -> RecordingSessionSnapshot {
        let payload = try SQLitePayloadCodec.canonicalData(transition)
        let digest = SQLitePayloadCodec.sha256(payload)
        do {
            return try await databasePool.write { db in
                if let event = try Row.fetchOne(
                    db,
                    sql: "SELECT event_payload, event_sha256 FROM recording_state_events WHERE event_id = ?",
                    arguments: [transition.eventID.canonicalString]
                ) {
                    let existingPayload: Data = event["event_payload"]
                    let existingDigest: String = event["event_sha256"]
                    guard existingPayload == payload, existingDigest == digest else {
                        throw RecordingContractError.integrityFailure("A transition event ID was reused with different bytes.")
                    }
                    return try recordingSnapshot(sessionID: transition.sessionID, in: db)
                }

                let current = try recordingSnapshot(sessionID: transition.sessionID, in: db)
                guard current.state == transition.from,
                      current.stateVersion == transition.expectedStateVersion,
                      !current.state.isTerminal
                else {
                    throw RecordingContractError.optimisticLockFailed(transition.sessionID)
                }

                let replacementVersion = transition.expectedStateVersion + 1
                try db.execute(
                    sql: """
                    UPDATE recording_sessions
                    SET state = ?, state_version = ?, updated_at_ms = ?, terminal_reason = ?,
                        final_manifest_logical_id = ?, final_manifest_revision_id = ?
                    WHERE session_id = ? AND state = ? AND state_version = ?
                    """,
                    arguments: [
                        transition.to.rawValue,
                        replacementVersion,
                        transition.occurredAt.millisecondsSinceUnixEpoch,
                        transition.to.isTerminal ? transition.reason.rawValue : nil,
                        transition.finalManifestRevision?.logicalID.canonicalString,
                        transition.finalManifestRevision?.revisionID.canonicalString,
                        transition.sessionID.canonicalString,
                        transition.from.rawValue,
                        transition.expectedStateVersion
                    ]
                )
                guard db.changesCount == 1 else {
                    throw RecordingContractError.optimisticLockFailed(transition.sessionID)
                }
                try db.execute(
                    sql: """
                    INSERT INTO recording_state_events(
                        event_id, session_id, prior_state, replacement_state,
                        prior_version, replacement_version, reason, actor,
                        occurred_at_ms, event_payload, event_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        transition.eventID.canonicalString,
                        transition.sessionID.canonicalString,
                        transition.from.rawValue,
                        transition.to.rawValue,
                        transition.expectedStateVersion,
                        replacementVersion,
                        transition.reason.rawValue,
                        transition.actor.rawValue,
                        transition.occurredAt.millisecondsSinceUnixEpoch,
                        payload,
                        digest
                    ]
                )
                return try recordingSnapshot(sessionID: transition.sessionID, in: db)
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure("The recording state transition failed atomically.")
        }
    }

    public func registerEpoch(_ epoch: RecordingEpoch) async throws {
        let payload = try SQLitePayloadCodec.canonicalData(epoch)
        let digest = SQLitePayloadCodec.sha256(payload)
        do {
            try await databasePool.write { db in
                if let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT epoch_payload, epoch_sha256 FROM recording_epochs WHERE epoch_id = ?",
                    arguments: [epoch.epochID.canonicalString]
                ) {
                    let existingPayload: Data = existing["epoch_payload"]
                    let existingDigest: String = existing["epoch_sha256"]
                    guard existingPayload == payload, existingDigest == digest else {
                        throw RecordingContractError.integrityFailure("An epoch ID was reused with different bytes.")
                    }
                    return
                }
                _ = try recordingSnapshot(sessionID: epoch.sessionID, in: db)
                try db.execute(
                    sql: """
                    INSERT INTO recording_epochs(
                        epoch_id, session_id, epoch_sequence, selected_at_ms, source_count,
                        source_set_digest_sha256, start_host_ns_decimal,
                        ended_at_ms, end_reason, epoch_payload, epoch_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?)
                    """,
                    arguments: [
                        epoch.epochID.canonicalString,
                        epoch.sessionID.canonicalString,
                        epoch.sequence,
                        epoch.selectedAt.millisecondsSinceUnixEpoch,
                        epoch.sources.count,
                        epoch.sourceSetDigest.lowercaseHex,
                        String(epoch.startHostNanoseconds),
                        payload,
                        digest
                    ]
                )
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure("The capture epoch could not be registered.")
        }
    }

    public func epochs(
        sessionID: RecordingSessionID
    ) async throws -> [RecordingEpoch] {
        do {
            return try await databasePool.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT epoch_payload, epoch_sha256
                    FROM recording_epochs
                    WHERE session_id = ?
                    ORDER BY epoch_sequence ASC, epoch_id ASC
                    """,
                    arguments: [sessionID.canonicalString]
                )
                return try rows.map { row in
                    let payload: Data = row["epoch_payload"]
                    let digest: String = row["epoch_sha256"]
                    return try decodeRecordingPayload(
                        RecordingEpoch.self,
                        data: payload,
                        digest: digest,
                        context: "recording epoch"
                    )
                }
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure(
                "The recording epochs could not be read safely."
            )
        }
    }

    public func seal(
        _ segment: SealedCaptureSegment,
        checkpoint: RecordingCheckpoint
    ) async throws -> RecordingCheckpoint {
        guard checkpoint.sessionID == segment.sessionID,
              checkpoint.createdAt.millisecondsSinceUnixEpoch >= segment.sealedAt.millisecondsSinceUnixEpoch,
              checkpoint.createdAt.millisecondsSinceUnixEpoch
                - segment.sealedAt.millisecondsSinceUnixEpoch <= 1_000
        else {
            throw RecordingContractError.invalidCheckpoint("A sealed segment checkpoint must commit within one second.")
        }

        let segmentPayload = try SQLitePayloadCodec.canonicalData(segment)
        let segmentDigest = SQLitePayloadCodec.sha256(segmentPayload)
        let checkpointPayload = try checkpoint.canonicalPayload()
        let checkpointDigest = SQLitePayloadCodec.sha256(checkpointPayload)
        let checkpointID = UUID().uuidString.lowercased()

        do {
            return try await databasePool.write { db in
                let session = try recordingSnapshot(sessionID: segment.sessionID, in: db)
                guard session.state == .recording || session.state == .stopping,
                      session.stateVersion == checkpoint.stateVersion,
                      session.intent.jobID == checkpoint.jobID,
                      session.intent.meetingID == checkpoint.meetingID
                else {
                    throw RecordingContractError.optimisticLockFailed(segment.sessionID)
                }

                if let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT segment_payload, segment_sha256 FROM recording_segments WHERE segment_id = ?",
                    arguments: [segment.segmentID.canonicalString]
                ) {
                    let existingPayload: Data = existing["segment_payload"]
                    let existingDigest: String = existing["segment_sha256"]
                    guard existingPayload == segmentPayload, existingDigest == segmentDigest else {
                        throw RecordingContractError.integrityFailure("A segment ID was reused with different bytes.")
                    }
                    return try latestRecordingCheckpoint(sessionID: segment.sessionID, in: db)
                        ?? checkpoint
                }

                let managedRecord = try ManagedAssetRecord(
                    storageObjectID: segment.storageObjectID,
                    meetingID: session.intent.meetingID,
                    relativePath: segment.relativePath,
                    contentHash: segment.contentHash,
                    byteSize: segment.byteSize,
                    createdAt: segment.sealedAt,
                    dataClassification: session.intent.policy.dataClassification,
                    retentionClass: .temporary
                )
                try insertRecordingManagedAsset(managedRecord, in: db)

                try db.execute(
                    sql: """
                    INSERT INTO recording_segments(
                        segment_id, session_id, epoch_id, track_id, segment_sequence,
                        media_start_ns_decimal, media_end_ns_decimal,
                        host_start_ns_decimal, host_end_ns_decimal, frame_count_decimal,
                        storage_object_id, content_hash_sha256, byte_size_decimal,
                        rolling_descriptor_sha256, sealed_at_ms, checkpoint_committed_at_ms,
                        segment_payload, segment_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        segment.segmentID.canonicalString,
                        segment.sessionID.canonicalString,
                        segment.epochID.canonicalString,
                        segment.trackID.canonicalString,
                        segment.sequence,
                        String(segment.mediaRange.startNanoseconds),
                        String(segment.mediaRange.endNanoseconds),
                        String(segment.hostRange.startNanoseconds),
                        String(segment.hostRange.endNanoseconds),
                        String(segment.frameCount),
                        segment.storageObjectID.canonicalString,
                        segment.contentHash.lowercaseHex,
                        String(segment.byteSize),
                        segment.rollingDescriptorDigest.lowercaseHex,
                        segment.sealedAt.millisecondsSinceUnixEpoch,
                        checkpoint.createdAt.millisecondsSinceUnixEpoch,
                        segmentPayload,
                        segmentDigest
                    ]
                )
                try db.execute(
                    sql: """
                    INSERT INTO recording_checkpoints(
                        checkpoint_id, session_id, state_version, format_identifier,
                        format_version, created_at_ms, checkpoint_payload, checkpoint_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        checkpointID,
                        checkpoint.sessionID.canonicalString,
                        checkpoint.stateVersion,
                        checkpoint.formatIdentifier,
                        checkpoint.formatVersion,
                        checkpoint.createdAt.millisecondsSinceUnixEpoch,
                        checkpointPayload,
                        checkpointDigest
                    ]
                )
                return checkpoint
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure("The segment and checkpoint transaction failed.")
        }
    }

    public func recordGap(_ gap: RecordingGap) async throws {
        let payload = try SQLitePayloadCodec.canonicalData(gap)
        let digest = SQLitePayloadCodec.sha256(payload)
        do {
            try await databasePool.write { db in
                if let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT gap_payload, gap_sha256 FROM recording_gaps WHERE gap_id = ?",
                    arguments: [gap.gapID.canonicalString]
                ) {
                    let existingPayload: Data = existing["gap_payload"]
                    let existingDigest: String = existing["gap_sha256"]
                    guard existingPayload == payload, existingDigest == digest else {
                        throw RecordingContractError.integrityFailure("A gap ID was reused with different bytes.")
                    }
                    return
                }
                try db.execute(
                    sql: """
                    INSERT INTO recording_gaps(
                        gap_id, session_id, epoch_id, track_id,
                        media_start_ns_decimal, media_end_ns_decimal,
                        host_start_ns_decimal, host_end_ns_decimal,
                        reason, detected_by, detected_at_ms, user_acknowledged_at_ms,
                        gap_payload, gap_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        gap.gapID.canonicalString,
                        gap.sessionID.canonicalString,
                        gap.epochID?.canonicalString,
                        gap.trackID.canonicalString,
                        gap.mediaRange.map { String($0.startNanoseconds) },
                        gap.mediaRange.map { String($0.endNanoseconds) },
                        gap.hostRange.map { String($0.startNanoseconds) },
                        gap.hostRange.map { String($0.endNanoseconds) },
                        gap.reason.rawValue,
                        gap.detectedBy.rawValue,
                        gap.detectedAt.millisecondsSinceUnixEpoch,
                        gap.userAcknowledgedAt?.millisecondsSinceUnixEpoch,
                        payload,
                        digest
                    ]
                )
            }
        } catch let error as RecordingContractError {
            throw error
        } catch {
            throw RecordingContractError.integrityFailure("The recording gap could not be committed.")
        }
    }

    public func segments(sessionID: RecordingSessionID) async throws -> [SealedCaptureSegment] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT segment_id, segment_payload, segment_sha256
                FROM recording_segments
                WHERE session_id = ?
                ORDER BY track_id, epoch_id, segment_sequence
                """,
                arguments: [sessionID.canonicalString]
            ).map { row in
                try decodeRecordingPayload(
                    SealedCaptureSegment.self,
                    data: row["segment_payload"],
                    digest: row["segment_sha256"],
                    context: "recording segment"
                )
            }
        }
    }

    public func gaps(sessionID: RecordingSessionID) async throws -> [RecordingGap] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT gap_payload, gap_sha256 FROM recording_gaps
                WHERE session_id = ? ORDER BY detected_at_ms, gap_id
                """,
                arguments: [sessionID.canonicalString]
            ).map { row in
                try decodeRecordingPayload(
                    RecordingGap.self,
                    data: row["gap_payload"],
                    digest: row["gap_sha256"],
                    context: "recording gap"
                )
            }
        }
    }

    public func latestCheckpoint(sessionID: RecordingSessionID) async throws -> RecordingCheckpoint? {
        try await databasePool.read { db in try latestRecordingCheckpoint(sessionID: sessionID, in: db) }
    }

    public func stateEventChainDigest(
        sessionID: RecordingSessionID
    ) async throws -> ContentDigest {
        try await databasePool.read { db in
            guard let intent = try Row.fetchOne(
                db,
                sql: "SELECT intent_payload, intent_sha256 FROM recording_sessions WHERE session_id = ?",
                arguments: [sessionID.canonicalString]
            ) else {
                throw RecordingContractError.sessionNotFound(sessionID)
            }
            var hasher = SHA256()
            let intentPayload: Data = intent["intent_payload"]
            let intentDigest: String = intent["intent_sha256"]
            guard SQLitePayloadCodec.sha256(intentPayload) == intentDigest else {
                throw RecordingContractError.integrityFailure("The recording intent failed event-chain verification.")
            }
            hasher.update(data: Data(intentDigest.utf8))
            for row in try Row.fetchAll(
                db,
                sql: """
                SELECT event_payload, event_sha256 FROM recording_state_events
                WHERE session_id = ? ORDER BY replacement_version, event_id
                """,
                arguments: [sessionID.canonicalString]
            ) {
                let payload: Data = row["event_payload"]
                let digest: String = row["event_sha256"]
                guard SQLitePayloadCodec.sha256(payload) == digest else {
                    throw RecordingContractError.integrityFailure("A recording event failed event-chain verification.")
                }
                hasher.update(data: Data(digest.utf8))
            }
            let value = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return try ContentDigest(algorithm: .sha256, lowercaseHex: value)
        }
    }

    private func recordingSnapshot(
        sessionID: RecordingSessionID,
        in db: Database
    ) throws -> RecordingSessionSnapshot {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM recording_sessions WHERE session_id = ?",
            arguments: [sessionID.canonicalString]
        ) else {
            throw RecordingContractError.sessionNotFound(sessionID)
        }
        let intent: RecordingIntent = try decodeRecordingPayload(
            RecordingIntent.self,
            data: row["intent_payload"],
            digest: row["intent_sha256"],
            context: "recording intent"
        )
        let stateValue: String = row["state"]
        guard intent.sessionID == sessionID,
              row["job_id"] == intent.jobID.canonicalString,
              row["meeting_id"] == intent.meetingID.canonicalString,
              row["capture_mode"] == intent.mode.rawValue,
              row["requested_track_count"] == intent.requestedTracks.count,
              row["data_classification"] == intent.policy.dataClassification.encodedValue,
              let state = RecordingState(rawValue: stateValue)
        else {
            throw RecordingContractError.integrityFailure("The recording-session columns do not match its canonical intent.")
        }
        let lastEventValue = try String.fetchOne(
            db,
            sql: """
            SELECT event_id FROM recording_state_events
            WHERE session_id = ? ORDER BY replacement_version DESC LIMIT 1
            """,
            arguments: [sessionID.canonicalString]
        )
        let terminalReasonValue: String? = row["terminal_reason"]
        let manifestLogicalID: String? = row["final_manifest_logical_id"]
        let manifestRevisionID: String? = row["final_manifest_revision_id"]
        let manifest = try manifestLogicalID.map { logicalID in
            try SemanticRevisionReference(
                logicalID: SourceAssetID(validating: logicalID),
                revisionID: RevisionID(validating: manifestRevisionID ?? "")
            )
        }
        return try RecordingSessionSnapshot(
            intent: intent,
            state: state,
            stateVersion: UInt64(row["state_version"] as Int64),
            lastEventID: try lastEventValue.map(RecordingStateEventID.init(validating:)),
            terminalReason: try terminalReasonValue.map { value in
                guard let reason = RecordingTransitionReason(rawValue: value) else {
                    throw RecordingContractError.integrityFailure("The stored terminal reason is unknown to this build.")
                }
                return reason
            },
            finalManifestRevision: manifest,
            updatedAt: UTCInstant(millisecondsSinceUnixEpoch: row["updated_at_ms"])
        )
    }

    private func latestRecordingCheckpoint(
        sessionID: RecordingSessionID,
        in db: Database
    ) throws -> RecordingCheckpoint? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM recording_checkpoints
            WHERE session_id = ? ORDER BY created_at_ms DESC, checkpoint_id DESC LIMIT 1
            """,
            arguments: [sessionID.canonicalString]
        ) else { return nil }
        let checkpoint: RecordingCheckpoint = try decodeRecordingPayload(
            RecordingCheckpoint.self,
            data: row["checkpoint_payload"],
            digest: row["checkpoint_sha256"],
            context: "recording checkpoint"
        )
        guard checkpoint.sessionID == sessionID,
              row["state_version"] == Int64(checkpoint.stateVersion),
              row["format_identifier"] == checkpoint.formatIdentifier,
              row["format_version"] == Int64(checkpoint.formatVersion),
              row["created_at_ms"] == checkpoint.createdAt.millisecondsSinceUnixEpoch
        else {
            throw RecordingContractError.invalidCheckpoint("The checkpoint columns do not match its canonical payload.")
        }
        return checkpoint
    }

    private func decodeRecordingPayload<Value: Codable>(
        _ type: Value.Type,
        data: Data,
        digest: String,
        context: String
    ) throws -> Value {
        guard data.count <= JobCheckpoint.maximumPayloadBytes,
              SQLitePayloadCodec.sha256(data) == digest
        else {
            throw RecordingContractError.integrityFailure("The \(context) payload failed its size or hash check.")
        }
        let value = try JSONDecoder().decode(type, from: data)
        guard try SQLitePayloadCodec.canonicalData(value) == data else {
            throw RecordingContractError.integrityFailure("The \(context) payload is not canonical.")
        }
        return value
    }

    private func insertRecordingManagedAsset(
        _ record: ManagedAssetRecord,
        in db: Database
    ) throws {
        let payload = try SQLitePayloadCodec.canonicalData(record)
        let digest = SQLitePayloadCodec.sha256(payload)
        if let existing = try Row.fetchOne(
            db,
            sql: "SELECT record_payload, record_sha256 FROM managed_assets WHERE storage_object_id = ?",
            arguments: [record.storageObjectID.canonicalString]
        ) {
            let existingPayload: Data = existing["record_payload"]
            let existingDigest: String = existing["record_sha256"]
            guard existingPayload == payload, existingDigest == digest else {
                throw RecordingContractError.integrityFailure("The recording managed-asset ID is already in use.")
            }
            return
        }
        try db.execute(
            sql: """
            INSERT INTO managed_assets(
                storage_object_id, meeting_id, relative_path, original_relative_path,
                content_hash_algorithm, content_hash_hex, byte_size_decimal,
                created_at_ms, data_classification, retention_class, state,
                trashed_at_ms, record_payload, record_sha256
            ) VALUES (?, ?, ?, ?, 'sha256', ?, ?, ?, ?, 'temporary', 'active', NULL, ?, ?)
            """,
            arguments: [
                record.storageObjectID.canonicalString,
                record.meetingID.canonicalString,
                record.relativePath.rawValue,
                record.originalRelativePath.rawValue,
                record.contentHash.lowercaseHex,
                String(record.byteSize),
                record.createdAt.millisecondsSinceUnixEpoch,
                record.dataClassification.encodedValue,
                payload,
                digest
            ]
        )
        let eventID = UUID().uuidString.lowercased()
        try db.execute(
            sql: """
            INSERT INTO managed_asset_events(
                event_id, storage_object_id, event_kind,
                record_payload, record_sha256, occurred_at_ms
            ) VALUES (?, ?, 'registered', ?, ?, ?)
            """,
            arguments: [
                eventID,
                record.storageObjectID.canonicalString,
                payload,
                digest,
                record.createdAt.millisecondsSinceUnixEpoch
            ]
        )
    }
}
