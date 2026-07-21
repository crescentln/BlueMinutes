import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

extension SQLitePersistenceStore: HistoricalReviewRepository {
    public func historicalIndexStatus() throws -> HistoricalIndexStatus {
        try databasePool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM historical_index_state WHERE singleton = 1"
            ) else {
                throw HistoricalReviewError.indexRebuildRequired
            }
            let enabled = (row["enabled"] as Int) == 1
            let current = (row["is_current"] as Int) == 1
            let isReady = enabled && current
            let digest: String? = row["source_fingerprint_sha256"]
            return HistoricalIndexStatus(
                availability: enabled ? (current ? .ready : .rebuildRequired) : .disabled,
                generation: UInt64(row["generation"] as Int64),
                normalizerVersion: UInt32(row["normalizer_version"] as Int64),
                indexedPositionCount: isReady ? UInt64(row["row_count"] as Int64) : 0,
                rebuiltAt: try (isReady ? row["rebuilt_at_ms"] as Int64? : nil).map {
                    try UTCInstant(millisecondsSinceUnixEpoch: $0)
                },
                sourceFingerprint: try (isReady ? digest : nil).map {
                    try ContentDigest(algorithm: .sha256, lowercaseHex: $0)
                }
            )
        }
    }

    public func rebuildHistoricalIndex(
        at completedAt: UTCInstant,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> HistoricalIndexRebuildReport {
        try cancellationCheck()
        let source = try historicalIndexCandidates(cancellationCheck: cancellationCheck)
        let fingerprint = try Self.historicalFingerprint(source.rows)
        return try databasePool.write { db in
            let state = try Row.fetchOne(
                db,
                sql: "SELECT * FROM historical_index_state WHERE singleton = 1"
            )
            guard let state else { throw HistoricalReviewError.indexRebuildRequired }
            let previousGeneration = UInt64(state["generation"] as Int64)
            let nextGeneration = previousGeneration + 1

            for row in source.rows {
                try cancellationCheck()
                guard try Self.isActiveCurrent(
                    objectType: .position,
                    logicalID: row.positionLogicalID,
                    revisionID: row.positionRevisionID,
                    in: db
                ), try Self.isActiveCurrent(
                    objectType: .meetingProfile,
                    logicalID: row.meetingLogicalID,
                    revisionID: row.meetingRevisionID,
                    in: db
                ), try Self.isActiveCurrent(
                    objectType: .actor,
                    logicalID: row.actorLogicalID,
                    revisionID: row.actorRevisionID,
                    in: db
                ), try Self.isActiveCurrent(
                    objectType: .issue,
                    logicalID: row.issueLogicalID,
                    revisionID: row.issueRevisionID,
                    in: db
                ), try Self.isActiveCurrent(
                    objectType: .sensitivityLabel,
                    logicalID: row.labelLogicalID,
                    revisionID: row.labelRevisionID,
                    in: db
                ), try Self.isActiveCurrent(
                    objectType: .accessPolicy,
                    logicalID: row.policyLogicalID,
                    revisionID: row.policyRevisionID,
                    in: db
                ), try row.evidenceRevisionIDs.allSatisfy({ evidence in
                    try Self.isActiveCurrent(
                        objectType: .evidenceRef,
                        logicalID: evidence.logicalID,
                        revisionID: evidence.revisionID,
                        in: db
                    )
                }) else {
                    throw HistoricalReviewError.indexRebuildRequired
                }
            }

            try db.execute(sql: "DELETE FROM historical_evidence_index")
            try db.execute(sql: "DELETE FROM historical_topic_terms")
            try db.execute(sql: "DELETE FROM historical_position_index")
            for row in source.rows {
                try cancellationCheck()
                try db.execute(
                    sql: """
                    INSERT INTO historical_position_index(
                        generation, position_logical_id, position_revision_id,
                        meeting_logical_id, meeting_revision_id,
                        actor_logical_id, actor_revision_id,
                        issue_logical_id, issue_revision_id,
                        sensitivity_label_logical_id, sensitivity_label_revision_id,
                        access_policy_logical_id, access_policy_revision_id,
                        effective_date_key, media_start_ms, actor_normalized,
                        country_normalized, topic_normalized, organization_normalized,
                        body_normalized, meeting_type, review_status,
                        data_classification, evidence_count
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        Int64(nextGeneration),
                        row.positionLogicalID,
                        row.positionRevisionID,
                        row.meetingLogicalID,
                        row.meetingRevisionID,
                        row.actorLogicalID,
                        row.actorRevisionID,
                        row.issueLogicalID,
                        row.issueRevisionID,
                        row.labelLogicalID,
                        row.labelRevisionID,
                        row.policyLogicalID,
                        row.policyRevisionID,
                        row.effectiveDateKey,
                        row.mediaStartMilliseconds,
                        row.actorNormalized,
                        row.countryNormalized,
                        row.topicNormalized,
                        row.organizationNormalized,
                        row.bodyNormalized,
                        row.meetingType,
                        row.reviewStatus,
                        row.dataClassification,
                        row.evidenceRevisionIDs.count
                    ]
                )
                for termKind in ["topic", "issue"] {
                    try db.execute(
                        sql: """
                        INSERT INTO historical_topic_terms(
                            generation, position_revision_id, term_kind, normalized_term
                        ) VALUES (?, ?, ?, ?)
                        """,
                        arguments: [
                            Int64(nextGeneration), row.positionRevisionID,
                            termKind, row.topicNormalized
                        ]
                    )
                }
                for evidence in row.evidenceRevisionIDs {
                    try db.execute(
                        sql: """
                        INSERT INTO historical_evidence_index(
                            generation, position_revision_id,
                            evidence_logical_id, evidence_revision_id
                        ) VALUES (?, ?, ?, ?)
                        """,
                        arguments: [
                            Int64(nextGeneration), row.positionRevisionID,
                            evidence.logicalID, evidence.revisionID
                        ]
                    )
                }
            }
            try db.execute(
                sql: """
                UPDATE historical_index_state
                SET is_current = 1,
                    generation = ?,
                    normalizer_version = 1,
                    rebuilt_at_ms = ?,
                    source_fingerprint_sha256 = ?,
                    row_count = ?
                WHERE singleton = 1
                """,
                arguments: [
                    Int64(nextGeneration),
                    completedAt.millisecondsSinceUnixEpoch,
                    fingerprint.lowercaseHex,
                    source.rows.count
                ]
            )
            return HistoricalIndexRebuildReport(
                previousGeneration: previousGeneration,
                replacementGeneration: nextGeneration,
                indexedPositionCount: UInt64(source.rows.count),
                skippedUnconfirmedPositionCount: source.skippedUnconfirmed,
                skippedUnsafePositionCount: source.skippedUnsafe,
                sourceFingerprint: fingerprint,
                completedAt: completedAt
            )
        }
    }

    public func setHistoricalIndexEnabled(
        _ enabled: Bool,
        changedAt _: UTCInstant
    ) throws {
        try databasePool.write { db in
            try db.execute(
                sql: "UPDATE historical_index_state SET enabled = ? WHERE singleton = 1",
                arguments: [enabled ? 1 : 0]
            )
        }
    }

    public func searchHistory(_ query: HistoricalSearchQuery) throws -> HistoricalSearchPage {
        let status = try historicalIndexStatus()
        switch status.availability {
        case .disabled: throw HistoricalReviewError.indexDisabled
        case .rebuildRequired: throw HistoricalReviewError.indexRebuildRequired
        case .ready: break
        }
        if let cursor = query.cursor, cursor.indexGeneration != status.generation {
            throw HistoricalReviewError.invalidQuery(
                "The search cursor belongs to a different index generation."
            )
        }

        var sql = """
        SELECT * FROM historical_position_index
        WHERE generation = ?
        """
        var arguments: StatementArguments = [Int64(status.generation)]
        func addLike(_ column: String, _ value: String?) {
            guard let value else { return }
            sql += " AND \(column) LIKE ? ESCAPE '\\'"
            arguments += ["%\(Self.escapeLike(Self.normalize(value)))%"]
        }
        if let value = query.actorOrCountry {
            let pattern = "%\(Self.escapeLike(Self.normalize(value)))%"
            sql += " AND (actor_normalized LIKE ? ESCAPE '\\' OR country_normalized LIKE ? ESCAPE '\\')"
            arguments += [pattern, pattern]
        }
        addLike("topic_normalized", query.topic)
        addLike("organization_normalized", query.organization)
        addLike("body_normalized", query.meetingBody)
        addLike("meeting_type", query.meetingType)
        if let issue = query.issue {
            sql += """
             AND EXISTS (
                 SELECT 1 FROM historical_topic_terms AS term
                 WHERE term.generation = historical_position_index.generation
                   AND term.position_revision_id = historical_position_index.position_revision_id
                   AND term.term_kind = 'issue'
                   AND term.normalized_term LIKE ? ESCAPE '\\'
             )
            """
            arguments += ["%\(Self.escapeLike(Self.normalize(issue)))%"]
        }
        if let startDate = query.startDate {
            sql += " AND effective_date_key >= ?"
            arguments += [Self.dateKey(startDate)]
        }
        if let endDate = query.endDate {
            sql += " AND effective_date_key <= ?"
            arguments += [Self.dateKey(endDate)]
        }
        if let reviewStatus = query.reviewStatus {
            sql += " AND review_status = ?"
            arguments += [reviewStatus.encodedValue]
        }
        sql += """
         ORDER BY effective_date_key IS NULL ASC,
                  effective_date_key DESC,
                  media_start_ms IS NULL ASC,
                  media_start_ms DESC,
                  position_revision_id DESC
        """
        let rows = try databasePool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments)
        }
        var results: [HistoricalPositionResult] = []
        var reachedCursor = query.cursor == nil
        for row in rows {
            if !reachedCursor {
                reachedCursor = Self.row(row, follows: query.cursor!)
                if !reachedCursor { continue }
            }
            guard let result = try hydrateHistoricalResult(
                row,
                generation: status.generation,
                maximumClassification: query.maximumClassification
            ) else { continue }
            results.append(result)
            if results.count == Int(query.pageSize) { break }
        }
        let nextCursor = results.count == Int(query.pageSize)
            ? results.last?.cursor(indexGeneration: status.generation) : nil
        return HistoricalSearchPage(
            results: results,
            nextCursor: nextCursor,
            indexGeneration: status.generation
        )
    }

    public func publishHistoricalComparison(
        _ comparison: HistoricalComparisonV1,
        expectedCurrentRevisionID: RevisionID?,
        changedAt: UTCInstant
    ) throws {
        try databasePool.write { db in
            try validateHistoricalComparisonAuthority(
                comparison,
                expectedCurrentRevisionID: expectedCurrentRevisionID,
                in: db
            )
            try insertPublicationObject(comparison, in: db)
            if expectedCurrentRevisionID == nil {
                try initializeActivePointer(for: comparison, at: changedAt, in: db)
            } else {
                _ = try moveActivePointer(
                    for: comparison,
                    expectedCurrentRevisionID: expectedCurrentRevisionID,
                    handlingPolicies: [],
                    markedAt: changedAt,
                    in: db
                )
            }
        }
    }

    public func learnedPreferenceState(
        maximumEvents: UInt32 = 100
    ) throws -> LearnedPreferenceState {
        guard maximumEvents <= 1_000 else {
            throw HistoricalReviewError.invalidPreference("Too many preference events were requested.")
        }
        return try databasePool.read { db in
            guard let settings = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preference_settings WHERE singleton = 1"
            ) else { throw HistoricalReviewError.invalidPreference("Preference settings are missing.") }
            let preferences = try Row.fetchAll(
                db,
                sql: "SELECT * FROM learned_preferences ORDER BY preference_id"
            ).map(Self.preferenceRecord)
            let events = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM learned_preference_events
                ORDER BY recorded_at_ms DESC, event_id DESC LIMIT ?
                """,
                arguments: [Int64(maximumEvents)]
            ).map(Self.preferenceEvent)
            return LearnedPreferenceState(
                globallyEnabled: (settings["globally_enabled"] as Int) == 1,
                settingsVersion: UInt64(settings["version"] as Int64),
                preferences: preferences,
                recentEvents: events
            )
        }
    }

    public func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceRecord {
        try value.validate()
        try Self.validateSourceAction(sourceAction)
        let payload = try Self.canonicalPreferenceData(value)
        let digest = SQLitePayloadCodec.sha256(payload)
        return try databasePool.write { db in
            let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preferences WHERE preference_id = ?",
                arguments: [preferenceID.canonicalString]
            )
            if let current {
                let currentVersion = UInt64(current["version"] as Int64)
                guard expectedVersion == currentVersion else {
                    throw HistoricalReviewError.preferenceConflict(preferenceID)
                }
                guard (current["kind"] as String) == value.kind.rawValue else {
                    throw HistoricalReviewError.invalidPreference(
                        "A learned preference cannot change type in place."
                    )
                }
                let priorDigest: String = current["value_sha256"]
                try db.execute(
                    sql: """
                    UPDATE learned_preferences
                    SET kind = ?, version = ?, enabled = ?, source_action = ?,
                        updated_at_ms = ?, canonical_value = ?, value_sha256 = ?
                    WHERE preference_id = ? AND version = ?
                    """,
                    arguments: [
                        value.kind.rawValue, Int64(currentVersion + 1), enabled ? 1 : 0,
                        sourceAction, changedAt.millisecondsSinceUnixEpoch, payload, digest,
                        preferenceID.canonicalString, Int64(currentVersion)
                    ]
                )
                try Self.insertPreferenceEvent(
                    action: .edited,
                    preferenceID: preferenceID,
                    kind: value.kind,
                    priorDigest: priorDigest,
                    replacementDigest: digest,
                    sourceAction: sourceAction,
                    recordedAt: changedAt,
                    in: db
                )
            } else {
                guard expectedVersion == nil else {
                    throw HistoricalReviewError.preferenceConflict(preferenceID)
                }
                try db.execute(
                    sql: """
                    INSERT INTO learned_preferences(
                        preference_id, kind, version, enabled, source_action,
                        created_at_ms, updated_at_ms, canonical_value, value_sha256
                    ) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        preferenceID.canonicalString, value.kind.rawValue, enabled ? 1 : 0,
                        sourceAction, changedAt.millisecondsSinceUnixEpoch,
                        changedAt.millisecondsSinceUnixEpoch, payload, digest
                    ]
                )
                try Self.insertPreferenceEvent(
                    action: .created,
                    preferenceID: preferenceID,
                    kind: value.kind,
                    priorDigest: nil,
                    replacementDigest: digest,
                    sourceAction: sourceAction,
                    recordedAt: changedAt,
                    in: db
                )
            }
            try Self.advancePreferenceSettings(changedAt: changedAt, in: db)
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preferences WHERE preference_id = ?",
                arguments: [preferenceID.canonicalString]
            ) else { throw HistoricalReviewError.preferenceNotFound(preferenceID) }
            return try Self.preferenceRecord(row)
        }
    }

    public func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceRecord {
        try Self.validateSourceAction(sourceAction)
        return try databasePool.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preferences WHERE preference_id = ?",
                arguments: [preferenceID.canonicalString]
            ) else { throw HistoricalReviewError.preferenceNotFound(preferenceID) }
            let version = UInt64(current["version"] as Int64)
            guard version == expectedVersion else {
                throw HistoricalReviewError.preferenceConflict(preferenceID)
            }
            let digest: String = current["value_sha256"]
            let kindValue: String = current["kind"]
            guard let kind = LearnedPreferenceKind(rawValue: kindValue) else {
                throw HistoricalReviewError.invalidPreference("A stored preference kind is unsupported.")
            }
            try db.execute(
                sql: """
                UPDATE learned_preferences
                SET enabled = ?, version = ?, source_action = ?, updated_at_ms = ?
                WHERE preference_id = ? AND version = ?
                """,
                arguments: [
                    enabled ? 1 : 0, Int64(version + 1), sourceAction,
                    changedAt.millisecondsSinceUnixEpoch,
                    preferenceID.canonicalString, Int64(version)
                ]
            )
            try Self.insertPreferenceEvent(
                action: enabled ? .enabled : .disabled,
                preferenceID: preferenceID,
                kind: kind,
                priorDigest: digest,
                replacementDigest: digest,
                sourceAction: sourceAction,
                recordedAt: changedAt,
                in: db
            )
            try Self.advancePreferenceSettings(changedAt: changedAt, in: db)
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preferences WHERE preference_id = ?",
                arguments: [preferenceID.canonicalString]
            ) else { throw HistoricalReviewError.preferenceNotFound(preferenceID) }
            return try Self.preferenceRecord(row)
        }
    }

    public func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws {
        try Self.validateSourceAction(sourceAction)
        try databasePool.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM learned_preferences WHERE preference_id = ?",
                arguments: [preferenceID.canonicalString]
            ) else { throw HistoricalReviewError.preferenceNotFound(preferenceID) }
            let version = UInt64(current["version"] as Int64)
            guard version == expectedVersion else {
                throw HistoricalReviewError.preferenceConflict(preferenceID)
            }
            let digest: String = current["value_sha256"]
            let kindValue: String = current["kind"]
            guard let kind = LearnedPreferenceKind(rawValue: kindValue) else {
                throw HistoricalReviewError.invalidPreference("A stored preference kind is unsupported.")
            }
            try db.execute(
                sql: "DELETE FROM learned_preferences WHERE preference_id = ? AND version = ?",
                arguments: [preferenceID.canonicalString, Int64(version)]
            )
            try Self.insertPreferenceEvent(
                action: .removed,
                preferenceID: preferenceID,
                kind: kind,
                priorDigest: digest,
                replacementDigest: nil,
                sourceAction: sourceAction,
                recordedAt: changedAt,
                in: db
            )
            try Self.advancePreferenceSettings(changedAt: changedAt, in: db)
        }
    }

    public func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceState {
        try Self.validateSourceAction(sourceAction)
        try databasePool.write { db in
            let version = try UInt64.fetchOne(
                db,
                sql: "SELECT version FROM learned_preference_settings WHERE singleton = 1"
            )
            guard version == expectedVersion else {
                throw HistoricalReviewError.invalidPreference("Preference settings changed concurrently.")
            }
            try db.execute(
                sql: """
                UPDATE learned_preference_settings
                SET globally_enabled = ?, version = ?, updated_at_ms = ?
                WHERE singleton = 1 AND version = ?
                """,
                arguments: [
                    enabled ? 1 : 0, Int64(expectedVersion + 1),
                    changedAt.millisecondsSinceUnixEpoch, Int64(expectedVersion)
                ]
            )
            try Self.insertPreferenceEvent(
                action: enabled ? .globallyEnabled : .globallyDisabled,
                preferenceID: nil,
                kind: nil,
                priorDigest: nil,
                replacementDigest: nil,
                sourceAction: sourceAction,
                recordedAt: changedAt,
                in: db
            )
        }
        return try learnedPreferenceState(maximumEvents: 100)
    }

    public func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceState {
        try Self.validateSourceAction(sourceAction)
        try databasePool.write { db in
            let version = try UInt64.fetchOne(
                db,
                sql: "SELECT version FROM learned_preference_settings WHERE singleton = 1"
            )
            guard version == expectedSettingsVersion else {
                throw HistoricalReviewError.invalidPreference("Preference settings changed concurrently.")
            }
            try db.execute(sql: "DELETE FROM learned_preferences")
            try db.execute(
                sql: """
                UPDATE learned_preference_settings
                SET globally_enabled = 1, version = ?, updated_at_ms = ?
                WHERE singleton = 1 AND version = ?
                """,
                arguments: [
                    Int64(expectedSettingsVersion + 1),
                    changedAt.millisecondsSinceUnixEpoch,
                    Int64(expectedSettingsVersion)
                ]
            )
            try Self.insertPreferenceEvent(
                action: .resetAll,
                preferenceID: nil,
                kind: nil,
                priorDigest: nil,
                replacementDigest: nil,
                sourceAction: sourceAction,
                recordedAt: changedAt,
                in: db
            )
        }
        return try learnedPreferenceState(maximumEvents: 100)
    }
}

private extension SQLitePersistenceStore {
    struct HistoricalIndexEvidenceID: Hashable, Sendable {
        let logicalID: String
        let revisionID: String
    }

    struct HistoricalIndexRow: Hashable, Sendable {
        let positionLogicalID: String
        let positionRevisionID: String
        let meetingLogicalID: String
        let meetingRevisionID: String
        let actorLogicalID: String
        let actorRevisionID: String
        let issueLogicalID: String
        let issueRevisionID: String
        let labelLogicalID: String
        let labelRevisionID: String
        let policyLogicalID: String
        let policyRevisionID: String
        let effectiveDateKey: String?
        let mediaStartMilliseconds: Int64?
        let actorNormalized: String
        let countryNormalized: String?
        let topicNormalized: String
        let organizationNormalized: String?
        let bodyNormalized: String?
        let meetingType: String?
        let reviewStatus: String
        let dataClassification: String
        let evidenceRevisionIDs: [HistoricalIndexEvidenceID]
    }

    struct HistoricalIndexSource: Sendable {
        let rows: [HistoricalIndexRow]
        let skippedUnconfirmed: UInt64
        let skippedUnsafe: UInt64
    }

    func historicalIndexCandidates(
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> HistoricalIndexSource {
        let positionRows = try databasePool.read { db in
            try Self.activeRows(objectType: .position, in: db)
        }
        let activeMeetingRevisionIDs = try activeRevisionIDs(.meetingProfile)
        let activeActorRevisionIDs = try activeRevisionIDs(.actor)
        let activeIssueRevisionIDs = try activeRevisionIDs(.issue)
        let activeEvidenceRevisionIDs = try activeRevisionIDs(.evidenceRef)
        let labels: [SensitivityLabelV1] = try activeSemanticObjects(.sensitivityLabel)
        let policies: [AccessPolicyV1] = try activeSemanticObjects(.accessPolicy)
        let labelsByRevisionID = Dictionary(
            uniqueKeysWithValues: labels.map { ($0.revision.revisionID, $0) }
        )
        var meetingsByRevisionID: [RevisionID: MeetingProfileV1] = [:]
        var actorsByRevisionID: [RevisionID: ActorV1] = [:]
        var issuesByRevisionID: [RevisionID: IssueV1] = [:]
        var evidenceByRevisionID: [RevisionID: EvidenceRefV1] = [:]
        var safePolicyByMeetingID: [MeetingID: (SensitivityLabelV1, AccessPolicyV1)] = [:]
        var organizationByMeetingRevisionID: [RevisionID: String] = [:]
        var rows: [HistoricalIndexRow] = []
        var skippedUnconfirmed: UInt64 = 0
        var skippedUnsafe: UInt64 = 0

        for stored in positionRows {
            try cancellationCheck()
            let position: PositionV1 = try Self.decodeSemantic(stored)
            guard position.revision.lifecycleStatus == .published,
                  position.revision.validationState == .valid,
                  position.reviewStatus == .confirmed,
                  position.userConfirmed
            else {
                skippedUnconfirmed += 1
                continue
            }
            do {
                guard let meetingReference = position.revision.inputRevisions.first(where: {
                    $0.objectType == .meetingProfile
                        && $0.logicalID.canonicalString == position.meetingID.canonicalString
                }), activeMeetingRevisionIDs.contains(meetingReference.revisionID)
                else {
                    throw HistoricalReviewError.sourceUnavailable(position.revision.revisionID)
                }
                guard activeActorRevisionIDs.contains(position.actorRevision.revisionID),
                      activeIssueRevisionIDs.contains(position.issueRevision.revisionID),
                      position.revision.evidenceRevisions.allSatisfy({
                          activeEvidenceRevisionIDs.contains($0.revisionID)
                      })
                else { throw HistoricalReviewError.accessDenied }
                let meeting: MeetingProfileV1
                if let cached = meetingsByRevisionID[meetingReference.revisionID] {
                    meeting = cached
                } else if let loaded = try fetch(
                    MeetingProfileV1.self,
                    revisionID: meetingReference.revisionID
                ) {
                    meetingsByRevisionID[meetingReference.revisionID] = loaded
                    meeting = loaded
                } else {
                    throw HistoricalReviewError.sourceUnavailable(meetingReference.revisionID)
                }
                guard
                    meeting.revision.lifecycleStatus == .published,
                    meeting.revision.validationState == .valid,
                    meeting.meetingID == position.meetingID
                else { throw HistoricalReviewError.sourceUnavailable(meetingReference.revisionID) }

                let actor: ActorV1
                if let cached = actorsByRevisionID[position.actorRevision.revisionID] {
                    actor = cached
                } else if let loaded = try fetch(
                    ActorV1.self,
                    revisionID: position.actorRevision.revisionID
                ) {
                    actorsByRevisionID[position.actorRevision.revisionID] = loaded
                    actor = loaded
                } else {
                    throw HistoricalReviewError.sourceUnavailable(position.actorRevision.revisionID)
                }
                let issue: IssueV1
                if let cached = issuesByRevisionID[position.issueRevision.revisionID] {
                    issue = cached
                } else if let loaded = try fetch(
                    IssueV1.self,
                    revisionID: position.issueRevision.revisionID
                ) {
                    issuesByRevisionID[position.issueRevision.revisionID] = loaded
                    issue = loaded
                } else {
                    throw HistoricalReviewError.sourceUnavailable(position.issueRevision.revisionID)
                }

                let label: SensitivityLabelV1
                let policy: AccessPolicyV1
                if let cached = safePolicyByMeetingID[meeting.meetingID] {
                    (label, policy) = cached
                } else {
                    let policyCandidates = policies.filter { $0.meetingID == meeting.meetingID }
                    let safeBundles = policyCandidates.compactMap {
                        candidate -> (SensitivityLabelV1, AccessPolicyV1)? in
                        guard let candidateLabel = labelsByRevisionID[
                            candidate.sensitivityLabelRevision.revisionID
                        ], candidateLabel.labelID.canonicalString
                            == candidate.sensitivityLabelRevision.logicalID.canonicalString
                        else { return nil }
                        do {
                            try SecurityPolicyGraphValidator.validate(
                                meeting: meeting,
                                sensitivityLabel: candidateLabel,
                                accessPolicy: candidate
                            )
                            guard candidate.localProcessingAllowed,
                                  candidate.manualLocalReviewAllowed,
                                  candidate.noOutboundMode,
                                  !candidate.externalProcessingAllowed
                            else { return nil }
                            return (candidateLabel, candidate)
                        } catch { return nil }
                    }
                    guard safeBundles.count == 1, let bundle = safeBundles.first else {
                        throw HistoricalReviewError.accessDenied
                    }
                    safePolicyByMeetingID[meeting.meetingID] = bundle
                    (label, policy) = bundle
                }
                let evidence = try position.revision.evidenceRevisions.map { reference -> EvidenceRefV1 in
                    let value: EvidenceRefV1
                    if let cached = evidenceByRevisionID[reference.revisionID] {
                        value = cached
                    } else if let loaded = try fetch(
                        EvidenceRefV1.self,
                        revisionID: reference.revisionID
                    ) {
                        evidenceByRevisionID[reference.revisionID] = loaded
                        value = loaded
                    } else {
                        throw HistoricalReviewError.sourceUnavailable(reference.revisionID)
                    }
                    guard value.revision.lifecycleStatus == .published,
                          value.revision.validationState == .valid
                    else { throw HistoricalReviewError.sourceUnavailable(reference.revisionID) }
                    return value
                }
                guard !evidence.isEmpty else {
                    throw HistoricalReviewError.sourceUnavailable(position.revision.revisionID)
                }
                let organization: String?
                if let cached = organizationByMeetingRevisionID[meeting.revision.revisionID] {
                    organization = cached
                } else {
                    organization = try organizationLabel(for: meeting)
                    if let organization {
                        organizationByMeetingRevisionID[meeting.revision.revisionID] = organization
                    }
                }
                let templateType = try meetingType(for: meeting)
                let classification = DataClassification.mostRestrictive(
                    [
                        position.revision.dataClassification,
                        meeting.revision.dataClassification,
                        actor.revision.dataClassification,
                        issue.revision.dataClassification,
                        label.effectiveClassification,
                        policy.effectiveClassification
                    ] + evidence.map(\.revision.dataClassification)
                ) ?? .restricted
                let actorSearch = ([actor.displayName] + actor.canonicalAliases)
                    .map(Self.normalize).joined(separator: " ")
                rows.append(
                    HistoricalIndexRow(
                        positionLogicalID: position.positionID.canonicalString,
                        positionRevisionID: position.revision.revisionID.canonicalString,
                        meetingLogicalID: meeting.meetingID.canonicalString,
                        meetingRevisionID: meeting.revision.revisionID.canonicalString,
                        actorLogicalID: position.actorRevision.logicalID.canonicalString,
                        actorRevisionID: position.actorRevision.revisionID.canonicalString,
                        issueLogicalID: position.issueRevision.logicalID.canonicalString,
                        issueRevisionID: position.issueRevision.revisionID.canonicalString,
                        labelLogicalID: label.labelID.canonicalString,
                        labelRevisionID: label.revision.revisionID.canonicalString,
                        policyLogicalID: policy.policyID.canonicalString,
                        policyRevisionID: policy.revision.revisionID.canonicalString,
                        effectiveDateKey: meeting.meetingDate.map(Self.dateKey),
                        mediaStartMilliseconds: position.effectiveTimeRange?.startMilliseconds,
                        actorNormalized: actorSearch,
                        countryNormalized: actor.identity.countryCode.map { Self.normalize($0.value) },
                        topicNormalized: Self.normalize(issue.title.text),
                        organizationNormalized: organization.map(Self.normalize),
                        bodyNormalized: organization.map(Self.normalize),
                        meetingType: templateType?.encodedValue,
                        reviewStatus: position.reviewStatus.encodedValue,
                        dataClassification: classification.encodedValue,
                        evidenceRevisionIDs: evidence.map {
                            HistoricalIndexEvidenceID(
                                logicalID: $0.evidenceID.canonicalString,
                                revisionID: $0.revision.revisionID.canonicalString
                            )
                        }.sorted { $0.revisionID < $1.revisionID }
                    )
                )
            } catch {
                skippedUnsafe += 1
            }
        }
        return HistoricalIndexSource(
            rows: rows.sorted { $0.positionRevisionID < $1.positionRevisionID },
            skippedUnconfirmed: skippedUnconfirmed,
            skippedUnsafe: skippedUnsafe
        )
    }

    func activeSemanticObjects<Object: SemanticRevisionContract>(
        _ objectType: SemanticObjectType
    ) throws -> [Object] {
        try databasePool.read { db in
            try Self.activeRows(objectType: objectType, in: db).map(Self.decodeSemantic)
        }
    }

    func activeRevisionIDs(
        _ objectType: SemanticObjectType
    ) throws -> Set<RevisionID> {
        try databasePool.read { db in
            try Set(Self.activeRows(objectType: objectType, in: db).map { row in
                try RevisionID(validating: row["revision_id"] as String)
            })
        }
    }

    static func activeRows(objectType: SemanticObjectType, in db: Database) throws -> [Row] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT revision.* FROM semantic_revisions AS revision
            JOIN active_published_revisions AS active
              ON active.object_type = revision.object_type
             AND active.logical_id = revision.logical_id
             AND active.revision_id = revision.revision_id
            JOIN revision_current_state AS state
              ON state.object_type = revision.object_type
             AND state.logical_id = revision.logical_id
             AND state.revision_id = revision.revision_id
            WHERE revision.object_type = ?
              AND state.currency_state = 'current'
              AND NOT EXISTS (
                  SELECT 1 FROM stale_events AS stale
                  WHERE stale.affected_object_type = revision.object_type
                    AND stale.affected_logical_id = revision.logical_id
                    AND stale.affected_revision_id = revision.revision_id
              )
            ORDER BY revision.logical_id, revision.revision_id
            """,
            arguments: [objectType.encodedValue]
        )
    }

    static func decodeSemantic<Object: SemanticRevisionContract>(_ row: Row) throws -> Object {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        let size: Int = row["payload_byte_size"]
        guard payload.count == size, SQLitePayloadCodec.sha256(payload) == digest else {
            throw HistoricalReviewError.indexRebuildRequired
        }
        let object = try CanonicalJSON.decodeValidated(Object.self, from: payload)
        guard try CanonicalJSON.encodeValidated(object) == payload,
              object.revision.objectType.encodedValue == (row["object_type"] as String),
              object.revision.logicalID.canonicalString == (row["logical_id"] as String),
              object.revision.revisionID.canonicalString == (row["revision_id"] as String)
        else { throw HistoricalReviewError.indexRebuildRequired }
        return object
    }

    func organizationLabel(for meeting: MeetingProfileV1) throws -> String? {
        guard let organization = meeting.organizationOrUNBody else { return nil }
        switch organization {
        case let .unresolved(label): return label
        case let .resolved(reference):
            return try fetch(ActorV1.self, revisionID: reference.revisionID)?.displayName
        }
    }

    func meetingType(for meeting: MeetingProfileV1) throws -> MeetingTemplateType? {
        guard let templateID = meeting.briefingTemplateID,
              let reference = meeting.revision.inputRevisions.first(where: {
                  $0.objectType == .meetingTemplate
                      && $0.logicalID.canonicalString == templateID.canonicalString
              }),
              let template = try fetch(MeetingTemplateV1.self, revisionID: reference.revisionID)
        else { return nil }
        return template.meetingType
    }

    func hydrateHistoricalResult(
        _ row: Row,
        generation: UInt64,
        maximumClassification: DataClassification
    ) throws -> HistoricalPositionResult? {
        let classification = DataClassification(encodedValue: row["data_classification"] as String)
        guard classification.isKnown,
              classification.restrictionRank <= maximumClassification.restrictionRank
        else { return nil }
        let positionRevisionID = try RevisionID(validating: row["position_revision_id"] as String)
        let meetingRevisionID = try RevisionID(validating: row["meeting_revision_id"] as String)
        let actorRevisionID = try RevisionID(validating: row["actor_revision_id"] as String)
        let issueRevisionID = try RevisionID(validating: row["issue_revision_id"] as String)
        let labelRevisionID = try RevisionID(validating: row["sensitivity_label_revision_id"] as String)
        let policyRevisionID = try RevisionID(validating: row["access_policy_revision_id"] as String)

        let isAuthorized = try databasePool.read { db in
            try Self.isActiveCurrent(
                objectType: .position,
                logicalID: row["position_logical_id"],
                revisionID: row["position_revision_id"],
                in: db
            ) && Self.isActiveCurrent(
                objectType: .meetingProfile,
                logicalID: row["meeting_logical_id"],
                revisionID: row["meeting_revision_id"],
                in: db
            ) && Self.isActiveCurrent(
                objectType: .actor,
                logicalID: row["actor_logical_id"],
                revisionID: row["actor_revision_id"],
                in: db
            ) && Self.isActiveCurrent(
                objectType: .issue,
                logicalID: row["issue_logical_id"],
                revisionID: row["issue_revision_id"],
                in: db
            ) && Self.isActiveCurrent(
                objectType: .sensitivityLabel,
                logicalID: row["sensitivity_label_logical_id"],
                revisionID: row["sensitivity_label_revision_id"],
                in: db
            ) && Self.isActiveCurrent(
                objectType: .accessPolicy,
                logicalID: row["access_policy_logical_id"],
                revisionID: row["access_policy_revision_id"],
                in: db
            )
        }
        guard isAuthorized,
              let position = try fetch(PositionV1.self, revisionID: positionRevisionID),
              let meeting = try fetch(MeetingProfileV1.self, revisionID: meetingRevisionID),
              let actor = try fetch(ActorV1.self, revisionID: actorRevisionID),
              let issue = try fetch(IssueV1.self, revisionID: issueRevisionID),
              let label = try fetch(SensitivityLabelV1.self, revisionID: labelRevisionID),
              let policy = try fetch(AccessPolicyV1.self, revisionID: policyRevisionID),
              position.reviewStatus == .confirmed,
              position.userConfirmed,
              policy.localProcessingAllowed,
              policy.manualLocalReviewAllowed,
              policy.noOutboundMode,
              !policy.externalProcessingAllowed
        else { return nil }
        do {
            try SecurityPolicyGraphValidator.validate(
                meeting: meeting,
                sensitivityLabel: label,
                accessPolicy: policy
            )
        } catch { return nil }
        guard position.meetingID == meeting.meetingID,
              position.actorRevision.revisionID == actor.revision.revisionID,
              position.issueRevision.revisionID == issue.revision.revisionID,
              label.effectiveClassification.restrictionRank <= classification.restrictionRank,
              policy.effectiveClassification.restrictionRank <= classification.restrictionRank
        else { return nil }

        let evidenceRows = try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT evidence_logical_id, evidence_revision_id
                FROM historical_evidence_index
                WHERE generation = ? AND position_revision_id = ?
                ORDER BY evidence_revision_id
                """,
                arguments: [Int64(generation), positionRevisionID.canonicalString]
            )
        }
        let evidence = try evidenceRows.compactMap { evidenceRow -> EvidenceRefV1? in
            let revisionID = try RevisionID(
                validating: evidenceRow["evidence_revision_id"] as String
            )
            guard try databasePool.read({ db in
                try Self.isActiveCurrent(
                    objectType: .evidenceRef,
                    logicalID: evidenceRow["evidence_logical_id"],
                    revisionID: evidenceRow["evidence_revision_id"],
                    in: db
                )
            }) else { return nil }
            guard let value = try fetch(EvidenceRefV1.self, revisionID: revisionID),
                  value.revision.lifecycleStatus == .published,
                  value.revision.validationState == .valid
            else { return nil }
            return value
        }
        guard evidence.count == position.revision.evidenceRevisions.count,
              Set(evidence.map(\.revision.revisionID))
                == Set(position.revision.evidenceRevisions.map(\.revisionID)),
              let currentClassification = DataClassification.mostRestrictive(
                  [
                      position.revision.dataClassification,
                      meeting.revision.dataClassification,
                      actor.revision.dataClassification,
                      issue.revision.dataClassification,
                      label.effectiveClassification,
                      policy.effectiveClassification
                  ] + evidence.map(\.revision.dataClassification)
              ),
              currentClassification.restrictionRank <= classification.restrictionRank
        else { return nil }
        let labelReference = try SemanticRevisionReference(
            logicalID: label.labelID,
            revisionID: label.revision.revisionID
        )
        let policyReference = try SemanticRevisionReference(
            logicalID: policy.policyID,
            revisionID: policy.revision.revisionID
        )
        return HistoricalPositionResult(
            position: position,
            meeting: meeting,
            actor: actor,
            issue: issue,
            evidence: evidence,
            sensitivityLabelRevision: labelReference,
            accessPolicyRevision: policyReference,
            organizationLabel: try organizationLabel(for: meeting),
            meetingType: try meetingType(for: meeting),
            effectiveClassification: classification
        )
    }

    func validateHistoricalComparisonAuthority(
        _ comparison: HistoricalComparisonV1,
        expectedCurrentRevisionID: RevisionID?,
        in db: Database
    ) throws {
        struct Side {
            let positionReference: SemanticRevisionReference
            let meetingReference: SemanticRevisionReference
            let actorReference: SemanticRevisionReference
            let issueReference: SemanticRevisionReference
            let labelReference: SemanticRevisionReference
            let policyReference: SemanticRevisionReference
            let effectiveDate: CalendarDate?
            let effectiveTimeRange: MediaTimeRange?
            let confidence: ConfidenceScore
            let evidenceReferences: [SemanticRevisionReference]
        }

        let sides = [
            Side(
                positionReference: comparison.currentPositionRevision,
                meetingReference: comparison.currentMeetingRevision,
                actorReference: comparison.currentActorRevision,
                issueReference: comparison.currentIssueRevision,
                labelReference: comparison.currentSensitivityLabelRevision,
                policyReference: comparison.currentAccessPolicyRevision,
                effectiveDate: comparison.currentEffectiveDate,
                effectiveTimeRange: comparison.currentEffectiveTimeRange,
                confidence: comparison.currentConfidence,
                evidenceReferences: comparison.currentEvidenceRevisions
            ),
            Side(
                positionReference: comparison.historicalPositionRevision,
                meetingReference: comparison.historicalMeetingRevision,
                actorReference: comparison.historicalActorRevision,
                issueReference: comparison.historicalIssueRevision,
                labelReference: comparison.historicalSensitivityLabelRevision,
                policyReference: comparison.historicalAccessPolicyRevision,
                effectiveDate: comparison.historicalEffectiveDate,
                effectiveTimeRange: comparison.historicalEffectiveTimeRange,
                confidence: comparison.historicalConfidence,
                evidenceReferences: comparison.historicalEvidenceRevisions
            )
        ]
        var results: [HistoricalPositionResult] = []
        var inheritedClassifications: [DataClassification] = []
        for side in sides {
            guard try Self.isActiveCurrent(side.positionReference, in: db),
                  try Self.isActiveCurrent(side.meetingReference, in: db),
                  try Self.isActiveCurrent(side.actorReference, in: db),
                  try Self.isActiveCurrent(side.issueReference, in: db),
                  try Self.isActiveCurrent(side.labelReference, in: db),
                  try Self.isActiveCurrent(side.policyReference, in: db),
                  let position: PositionV1 = try Self.semanticObject(
                      revisionID: side.positionReference.revisionID,
                      in: db
                  ),
                  let meeting: MeetingProfileV1 = try Self.semanticObject(
                      revisionID: side.meetingReference.revisionID,
                      in: db
                  ),
                  let actor: ActorV1 = try Self.semanticObject(
                      revisionID: side.actorReference.revisionID,
                      in: db
                  ),
                  let issue: IssueV1 = try Self.semanticObject(
                      revisionID: side.issueReference.revisionID,
                      in: db
                  ),
                  let label: SensitivityLabelV1 = try Self.semanticObject(
                      revisionID: side.labelReference.revisionID,
                      in: db
                  ),
                  let policy: AccessPolicyV1 = try Self.semanticObject(
                      revisionID: side.policyReference.revisionID,
                      in: db
                  ),
                  position.meetingID == meeting.meetingID,
                  position.actorRevision == side.actorReference,
                  position.issueRevision == side.issueReference,
                  meeting.meetingDate == side.effectiveDate,
                  position.effectiveTimeRange == side.effectiveTimeRange,
                  position.statement.confidence == side.confidence,
                  position.revision.evidenceRevisions == side.evidenceReferences,
                  position.revision.lifecycleStatus == .published,
                  position.revision.validationState == .valid,
                  position.reviewStatus == .confirmed,
                  position.userConfirmed,
                  policy.localProcessingAllowed,
                  policy.manualLocalReviewAllowed,
                  policy.noOutboundMode,
                  !policy.externalProcessingAllowed
            else { throw HistoricalReviewError.accessDenied }
            try SecurityPolicyGraphValidator.validate(
                meeting: meeting,
                sensitivityLabel: label,
                accessPolicy: policy
            )
            var evidenceValues: [EvidenceRefV1] = []
            for evidenceReference in side.evidenceReferences {
                guard try Self.isActiveCurrent(evidenceReference, in: db),
                      let evidence: EvidenceRefV1 = try Self.semanticObject(
                          revisionID: evidenceReference.revisionID,
                          in: db
                      ),
                      evidence.revision.lifecycleStatus == .published,
                      evidence.revision.validationState == .valid
                else { throw HistoricalReviewError.accessDenied }
                evidenceValues.append(evidence)
            }
            let sideClassifications = [
                position.revision.dataClassification,
                meeting.revision.dataClassification,
                actor.revision.dataClassification,
                issue.revision.dataClassification,
                label.effectiveClassification,
                policy.effectiveClassification
            ] + evidenceValues.map(\.revision.dataClassification)
            guard let sideClassification = DataClassification.mostRestrictive(
                sideClassifications
            ) else { throw HistoricalReviewError.accessDenied }
            inheritedClassifications += sideClassifications
            results.append(
                HistoricalPositionResult(
                    position: position,
                    meeting: meeting,
                    actor: actor,
                    issue: issue,
                    evidence: evidenceValues,
                    sensitivityLabelRevision: side.labelReference,
                    accessPolicyRevision: side.policyReference,
                    organizationLabel: nil,
                    meetingType: nil,
                    effectiveClassification: sideClassification
                )
            )
        }
        guard let required = DataClassification.mostRestrictive(inheritedClassifications),
              comparison.revision.dataClassification.restrictionRank >= required.restrictionRank,
              results.count == 2
        else { throw HistoricalReviewError.accessDenied }

        let evaluation = HistoricalComparisonEvaluator.evaluate(
            current: results[0],
            historical: results[1]
        )
        let candidateReference = comparison.confirmationOfRevision
        var exactInputs = Set([
            comparison.currentPositionRevision,
            comparison.historicalPositionRevision,
            comparison.currentMeetingRevision,
            comparison.historicalMeetingRevision,
            comparison.currentActorRevision,
            comparison.historicalActorRevision,
            comparison.currentIssueRevision,
            comparison.historicalIssueRevision,
            comparison.currentSensitivityLabelRevision,
            comparison.historicalSensitivityLabelRevision,
            comparison.currentAccessPolicyRevision,
            comparison.historicalAccessPolicyRevision
        ])
        let exactEvidence = Set(
            comparison.currentEvidenceRevisions + comparison.historicalEvidenceRevisions
        )

        if comparison.differenceState == .userConfirmedDifference {
            guard let candidateReference,
                  expectedCurrentRevisionID == candidateReference.revisionID,
                  comparison.revision.supersedesRevisionID == candidateReference.revisionID,
                  try Self.isActiveCurrent(candidateReference, in: db),
                  let candidate: HistoricalComparisonV1 = try Self.semanticObject(
                      revisionID: candidateReference.revisionID,
                      in: db
                  ),
                  candidate.comparisonID == comparison.comparisonID,
                  candidate.differenceState == .possibleDifference,
                  candidate.finding == evaluation.finding,
                  candidate.differenceState == evaluation.differenceState,
                  candidate.revision.createdBy == .application,
                  candidate.reviewStatus == .needsReview,
                  !candidate.userConfirmed,
                  candidate.confirmationOfRevision == nil,
                  Self.sameHistoricalSourceSnapshot(candidate, comparison)
            else {
                throw HistoricalReviewError.comparisonNotAllowed(
                    "A confirmed change must supersede the active exact possible-difference candidate."
                )
            }
            exactInputs.insert(candidateReference)
        } else {
            guard expectedCurrentRevisionID == nil,
                  comparison.revision.supersedesRevisionID == nil,
                  candidateReference == nil,
                  comparison.differenceState == evaluation.differenceState,
                  comparison.finding == evaluation.finding
            else {
                throw HistoricalReviewError.comparisonNotAllowed(
                    "The stored comparison must match the deterministic evidence evaluation."
                )
            }
        }
        guard Set(comparison.revision.inputRevisions) == exactInputs,
              Set(comparison.revision.evidenceRevisions) == exactEvidence
        else {
            throw HistoricalReviewError.comparisonNotAllowed(
                "Comparison provenance must contain exactly the reviewed inputs and evidence."
            )
        }
    }

    static func sameHistoricalSourceSnapshot(
        _ lhs: HistoricalComparisonV1,
        _ rhs: HistoricalComparisonV1
    ) -> Bool {
        lhs.currentPositionRevision == rhs.currentPositionRevision
            && lhs.historicalPositionRevision == rhs.historicalPositionRevision
            && lhs.currentMeetingRevision == rhs.currentMeetingRevision
            && lhs.historicalMeetingRevision == rhs.historicalMeetingRevision
            && lhs.currentActorRevision == rhs.currentActorRevision
            && lhs.historicalActorRevision == rhs.historicalActorRevision
            && lhs.currentIssueRevision == rhs.currentIssueRevision
            && lhs.historicalIssueRevision == rhs.historicalIssueRevision
            && lhs.currentSensitivityLabelRevision == rhs.currentSensitivityLabelRevision
            && lhs.historicalSensitivityLabelRevision == rhs.historicalSensitivityLabelRevision
            && lhs.currentAccessPolicyRevision == rhs.currentAccessPolicyRevision
            && lhs.historicalAccessPolicyRevision == rhs.historicalAccessPolicyRevision
            && lhs.currentEffectiveDate == rhs.currentEffectiveDate
            && lhs.historicalEffectiveDate == rhs.historicalEffectiveDate
            && lhs.currentEffectiveTimeRange == rhs.currentEffectiveTimeRange
            && lhs.historicalEffectiveTimeRange == rhs.historicalEffectiveTimeRange
            && lhs.currentConfidence == rhs.currentConfidence
            && lhs.historicalConfidence == rhs.historicalConfidence
            && lhs.currentEvidenceRevisions == rhs.currentEvidenceRevisions
            && lhs.historicalEvidenceRevisions == rhs.historicalEvidenceRevisions
            && lhs.revision.dataClassification == rhs.revision.dataClassification
    }

    static func isActiveCurrent(
        objectType: SemanticObjectType,
        logicalID: String,
        revisionID: String,
        in db: Database
    ) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1 FROM active_published_revisions AS active
                JOIN revision_current_state AS state
                  ON state.object_type = active.object_type
                 AND state.logical_id = active.logical_id
                 AND state.revision_id = active.revision_id
                WHERE active.object_type = ? AND active.logical_id = ?
                  AND active.revision_id = ? AND state.currency_state = 'current'
                  AND NOT EXISTS (
                      SELECT 1 FROM stale_events AS stale
                      WHERE stale.affected_object_type = active.object_type
                        AND stale.affected_logical_id = active.logical_id
                        AND stale.affected_revision_id = active.revision_id
                  )
            )
            """,
            arguments: [objectType.encodedValue, logicalID, revisionID]
        ) ?? false
    }

    static func isActiveCurrent(
        _ reference: SemanticRevisionReference,
        in db: Database
    ) throws -> Bool {
        try isActiveCurrent(
            objectType: reference.objectType,
            logicalID: reference.logicalID.canonicalString,
            revisionID: reference.revisionID.canonicalString,
            in: db
        )
    }

    static func semanticObject<Object: SemanticRevisionContract>(
        revisionID: RevisionID,
        in db: Database
    ) throws -> Object? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM semantic_revisions WHERE revision_id = ?",
            arguments: [revisionID.canonicalString]
        ) else { return nil }
        return try decodeSemantic(row)
    }

    static func historicalFingerprint(
        _ rows: [HistoricalIndexRow]
    ) throws -> ContentDigest {
        let text = rows.map { row in
            [
                row.positionRevisionID, row.meetingRevisionID, row.actorRevisionID,
                row.issueRevisionID, row.labelRevisionID, row.policyRevisionID,
                row.evidenceRevisionIDs.map(\.revisionID).joined(separator: ",")
            ].joined(separator: ":")
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    static func normalize(_ value: String) -> String {
        HistoricalComparisonEvaluator.normalize(value)
    }

    static func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func dateKey(_ date: CalendarDate) -> String {
        String(format: "%04d-%02d-%02d", Int(date.year), Int(date.month), Int(date.day))
    }

    static func row(_ row: Row, follows cursor: HistoricalSearchCursor) -> Bool {
        let rowDate: String? = row["effective_date_key"]
        let cursorDate = cursor.effectiveDate.map(dateKey)
        switch (rowDate, cursorDate) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(lhs), .some(rhs)):
            if lhs != rhs { return lhs < rhs }
        case (nil, nil): break
        }
        let rowMedia: Int64? = row["media_start_ms"]
        let cursorMedia = cursor.mediaStartMilliseconds
        switch (rowMedia, cursorMedia) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(lhs), .some(rhs)):
            if lhs != rhs { return lhs < rhs }
        case (nil, nil): break
        }
        let rowRevision: String = row["position_revision_id"]
        return rowRevision < cursor.positionRevisionID.canonicalString
    }

    static func canonicalPreferenceData(_ value: LearnedPreferenceValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func preferenceRecord(_ row: Row) throws -> LearnedPreferenceRecord {
        let preferenceID = try LearnedPreferenceID(validating: row["preference_id"] as String)
        let payload: Data = row["canonical_value"]
        let digest: String = row["value_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest else {
            throw HistoricalReviewError.invalidPreference("A stored preference digest is invalid.")
        }
        let value = try JSONDecoder().decode(LearnedPreferenceValue.self, from: payload)
        guard try canonicalPreferenceData(value) == payload,
              value.kind.rawValue == (row["kind"] as String)
        else { throw HistoricalReviewError.invalidPreference("A stored preference is non-canonical.") }
        return try LearnedPreferenceRecord(
            preferenceID: preferenceID,
            value: value,
            enabled: (row["enabled"] as Int) == 1,
            version: UInt64(row["version"] as Int64),
            sourceAction: row["source_action"],
            createdAt: UTCInstant(millisecondsSinceUnixEpoch: row["created_at_ms"]),
            updatedAt: UTCInstant(millisecondsSinceUnixEpoch: row["updated_at_ms"])
        )
    }

    static func preferenceEvent(_ row: Row) throws -> LearnedPreferenceEvent {
        guard let action = LearnedPreferenceEventAction(rawValue: row["action"] as String) else {
            throw HistoricalReviewError.invalidPreference("A stored preference event is unsupported.")
        }
        let preferenceIDValue: String? = row["preference_id"]
        let kindValue: String? = row["kind"]
        let priorDigest: String? = row["prior_value_sha256"]
        let replacementDigest: String? = row["replacement_value_sha256"]
        return LearnedPreferenceEvent(
            eventID: try LearnedPreferenceEventID(validating: row["event_id"] as String),
            action: action,
            preferenceID: try preferenceIDValue.map(LearnedPreferenceID.init(validating:)),
            kind: kindValue.flatMap(LearnedPreferenceKind.init(rawValue:)),
            priorValueDigest: try priorDigest.map { try ContentDigest(algorithm: .sha256, lowercaseHex: $0) },
            replacementValueDigest: try replacementDigest.map { try ContentDigest(algorithm: .sha256, lowercaseHex: $0) },
            sourceAction: row["source_action"],
            recordedAt: try UTCInstant(millisecondsSinceUnixEpoch: row["recorded_at_ms"])
        )
    }

    static func insertPreferenceEvent(
        action: LearnedPreferenceEventAction,
        preferenceID: LearnedPreferenceID?,
        kind: LearnedPreferenceKind?,
        priorDigest: String?,
        replacementDigest: String?,
        sourceAction: String,
        recordedAt: UTCInstant,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO learned_preference_events(
                event_id, action, preference_id, kind, prior_value_sha256,
                replacement_value_sha256, source_action, recorded_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(), action.rawValue,
                preferenceID?.canonicalString, kind?.rawValue, priorDigest,
                replacementDigest, sourceAction, recordedAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    static func validateSourceAction(_ value: String) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= 128,
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw HistoricalReviewError.invalidPreference("Preference provenance must be bounded text.")
        }
    }

    static func advancePreferenceSettings(
        changedAt: UTCInstant,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            UPDATE learned_preference_settings
            SET version = version + 1, updated_at_ms = ?
            WHERE singleton = 1
            """,
            arguments: [changedAt.millisecondsSinceUnixEpoch]
        )
    }
}
