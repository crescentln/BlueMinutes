import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class SQLitePersistenceStore: SemanticRevisionRepository, MediaAssetCatalog,
    TranscriptReviewRepository, AnalysisRepository, BriefingRepository,
    BriefingExportRepository, @unchecked Sendable
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

    public func publishTranscript(_ publication: TranscriptPublication) throws {
        try publishTranscript(publication, validatingInputRevisions: [])
    }

    public func publishTranscript(
        _ publication: TranscriptPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws {
        try publication.manifest.validate()
        do {
            try databasePool.write { db in
                try validateCurrentInputRevisions(inputRevisions, in: db)
                guard let source = try fetch(
                    SourceAssetV1.self,
                    revisionID: publication.manifest.canonicalSourceRevision.revisionID,
                    in: db
                ),
                    source.assetID.canonicalString
                        == publication.manifest.canonicalSourceRevision.logicalID.canonicalString,
                    source.meetingID == publication.manifest.meetingID
                else { throw TranscriptCoverageError.publicationConflict }

                for segment in publication.transcriptSegments {
                    try insertPublicationObject(segment, in: db)
                }
                for translation in publication.translations {
                    try insertPublicationObject(translation, in: db)
                }
                for segment in publication.transcriptSegments {
                    try initializeActivePointer(for: segment, at: publication.manifest.createdAt, in: db)
                }
                for translation in publication.translations {
                    try initializeActivePointer(for: translation, at: publication.manifest.createdAt, in: db)
                }
                try insertAndActivateManifest(publication.manifest, in: db)
            }
        } catch let error as TranscriptCoverageError {
            throw error
        } catch let error as PersistenceContractError {
            throw error
        } catch let error as JobContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func recordIncompleteCoverage(_ manifest: TranscriptCoverageManifest) throws {
        guard manifest.status == .incomplete else {
            throw TranscriptCoverageError.publicationConflict
        }
        try manifest.validate()
        try databasePool.write { db in
            let payload = try SQLitePayloadCodec.canonicalData(manifest)
            let payloadDigest = SQLitePayloadCodec.sha256(payload)
            guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
                throw TranscriptCoverageError.publicationConflict
            }
            if let existing = try Row.fetchOne(
                db,
                sql: "SELECT canonical_payload, payload_sha256 FROM transcript_coverage_manifests WHERE manifest_id = ?",
                arguments: [manifest.manifestID.canonicalString]
            ) {
                let existingPayload: Data = existing["canonical_payload"]
                let existingDigest: String = existing["payload_sha256"]
                guard existingPayload == payload, existingDigest == payloadDigest else {
                    throw TranscriptCoverageError.publicationConflict
                }
                return
            }
            try db.execute(
                sql: """
                INSERT INTO transcript_coverage_manifests(
                    manifest_id, transcript_set_id, supersedes_manifest_id, meeting_id,
                    canonical_source_revision_id, status, created_at_ms,
                    content_hash_algorithm, content_hash_hex, canonical_payload,
                    payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    manifest.manifestID.canonicalString,
                    manifest.transcriptSetID.canonicalString,
                    manifest.supersedesManifestID?.canonicalString,
                    manifest.meetingID.canonicalString,
                    manifest.canonicalSourceRevision.revisionID.canonicalString,
                    manifest.status.rawValue,
                    manifest.createdAt.millisecondsSinceUnixEpoch,
                    manifest.contentHash.algorithm.encodedValue,
                    manifest.contentHash.lowercaseHex,
                    payload,
                    payloadDigest,
                    payload.count
                ]
            )
        }
    }

    public func transcriptCoverageManifests(
        meetingID: MeetingID
    ) throws -> [TranscriptCoverageManifest] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM transcript_coverage_manifests
                WHERE meeting_id = ?
                ORDER BY created_at_ms, manifest_id
                """,
                arguments: [meetingID.canonicalString]
            ).map(decodeManifest)
        }
    }

    public func activeTranscriptReview(meetingID: MeetingID) throws -> TranscriptReviewBundle? {
        try databasePool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT manifest.*
                FROM active_transcript_manifests AS active
                JOIN transcript_coverage_manifests AS manifest
                  ON manifest.manifest_id = active.manifest_id
                WHERE active.meeting_id = ?
                """,
                arguments: [meetingID.canonicalString]
            ) else { return nil }
            let manifest = try decodeManifest(row)
            guard manifest.meetingID == meetingID else {
                throw TranscriptCoverageError.publicationConflict
            }
            let segments = try manifest.transcriptRevisionReferences.map { reference -> TranscriptSegmentV1 in
                guard let value = try fetch(TranscriptSegmentV1.self, revisionID: reference.revisionID, in: db),
                      value.segmentID.canonicalString == reference.logicalID.canonicalString
                else { throw TranscriptCoverageError.publicationConflict }
                return value
            }.sorted { lhs, rhs in
                (lhs.timeRange.startMilliseconds, lhs.segmentID.canonicalString)
                    < (rhs.timeRange.startMilliseconds, rhs.segmentID.canonicalString)
            }
            let translations = try manifest.translationRevisionReferences.map { reference -> TranslationSegmentV1 in
                guard let value = try fetch(TranslationSegmentV1.self, revisionID: reference.revisionID, in: db),
                      value.translationID.canonicalString == reference.logicalID.canonicalString
                else { throw TranscriptCoverageError.publicationConflict }
                return value
            }
            let segmentIDs = Set(segments.map { $0.segmentID.canonicalString })
            let assignmentRows = try Row.fetchAll(
                db,
                sql: """
                SELECT revision.*
                FROM active_published_revisions AS active
                JOIN semantic_revisions AS revision
                  ON revision.object_type = active.object_type
                 AND revision.logical_id = active.logical_id
                 AND revision.revision_id = active.revision_id
                WHERE active.object_type = 'speaker_assignment'
                ORDER BY revision.created_at_ms, revision.revision_id
                """
            )
            let assignments = try assignmentRows
                .map { try decode(SpeakerAssignmentV1.self, row: $0) }
                .filter { assignment in
                    assignment.meetingID == meetingID
                        && assignment.transcriptSegmentRevisions.contains {
                            segmentIDs.contains($0.logicalID.canonicalString)
                        }
                }
            return TranscriptReviewBundle(
                manifest: manifest,
                transcriptSegments: segments,
                translations: translations,
                speakerAssignments: assignments
            )
        }
    }

    public func saveTranscriptCorrection(
        _ correction: TranscriptSegmentV1,
        replacing expectedRevisionID: RevisionID,
        updatedManifest: TranscriptCoverageManifest,
        changedAt: UTCInstant
    ) throws {
        guard correction.revision.supersedesRevisionID == expectedRevisionID,
              updatedManifest.status == .published
        else { throw TranscriptCoverageError.publicationConflict }
        try preflightReplacementManifest(updatedManifest, changedReference: try SemanticRevisionReference(
            logicalID: correction.segmentID,
            revisionID: correction.revision.revisionID
        ))
        try insert(correction)
        _ = try activate(
            ActivePublishedRevisionSelection(
                logicalID: correction.segmentID,
                revisionID: correction.revision.revisionID
            ),
            as: TranscriptSegmentV1.self,
            expectedCurrentRevisionID: expectedRevisionID,
            handlingPolicies: [],
            markedAt: changedAt
        )
        try databasePool.write { db in try insertAndActivateManifest(updatedManifest, in: db) }
    }

    public func saveTranslationCorrection(
        _ correction: TranslationSegmentV1,
        replacing expectedRevisionID: RevisionID,
        updatedManifest: TranscriptCoverageManifest,
        changedAt: UTCInstant
    ) throws {
        guard correction.revision.supersedesRevisionID == expectedRevisionID,
              updatedManifest.status == .published
        else { throw TranscriptCoverageError.publicationConflict }
        try preflightReplacementManifest(updatedManifest, changedReference: try SemanticRevisionReference(
            logicalID: correction.translationID,
            revisionID: correction.revision.revisionID
        ))
        try insert(correction)
        _ = try activate(
            ActivePublishedRevisionSelection(
                logicalID: correction.translationID,
                revisionID: correction.revision.revisionID
            ),
            as: TranslationSegmentV1.self,
            expectedCurrentRevisionID: expectedRevisionID,
            handlingPolicies: [],
            markedAt: changedAt
        )
        try databasePool.write { db in try insertAndActivateManifest(updatedManifest, in: db) }
    }

    public func publishSpeakerConfirmation(
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        evidence: EvidenceRefV1,
        assignment: SpeakerAssignmentV1,
        changedAt: UTCInstant
    ) throws {
        do {
            try databasePool.write { db in
                try insertPublicationObject(actor, in: db)
                try insertPublicationObject(capacity, in: db)
                try insertPublicationObject(evidence, in: db)
                try insertPublicationObject(assignment, in: db)
                try initializeActivePointer(for: actor, at: changedAt, in: db)
                try initializeActivePointer(for: capacity, at: changedAt, in: db)
                try initializeActivePointer(for: evidence, at: changedAt, in: db)
                try initializeActivePointer(for: assignment, at: changedAt, in: db)
            }
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func analysisSourceBundle(
        meetingRevision: SemanticRevisionReference,
        transcriptManifestID: TranscriptCoverageManifestID
    ) throws -> AnalysisSourceBundle {
        guard meetingRevision.objectType == .meetingProfile,
              let meeting = try fetch(
                  MeetingProfileV1.self,
                  revisionID: meetingRevision.revisionID
              ),
              meeting.meetingID.canonicalString == meetingRevision.logicalID.canonicalString,
              let review = try activeTranscriptReview(meetingID: meeting.meetingID),
              review.manifest.manifestID == transcriptManifestID
        else { throw AnalysisCoverageError.reviewUnavailable }
        var actorsByRevision: [RevisionID: ActorV1] = [:]
        var capacitiesByRevision: [RevisionID: SpeakingCapacityV1] = [:]
        var sourceAssetsByRevision: [RevisionID: SourceAssetV1] = [:]
        let sourceReferences = Set(
            review.transcriptSegments.flatMap(\.revision.sourceAssetRevisions)
                + review.translations.flatMap(\.revision.sourceAssetRevisions)
        )
        for reference in sourceReferences {
            guard reference.objectType == .sourceAsset,
                  let sourceAsset = try fetch(
                      SourceAssetV1.self,
                      revisionID: reference.revisionID
                  ),
                  sourceAsset.assetID.canonicalString == reference.logicalID.canonicalString
            else { throw AnalysisCoverageError.reviewUnavailable }
            sourceAssetsByRevision[sourceAsset.revision.revisionID] = sourceAsset
        }
        for assignment in review.speakerAssignments {
            guard let actor = try fetch(
                ActorV1.self,
                revisionID: assignment.actorRevision.revisionID
            ),
                let capacity = try fetch(
                    SpeakingCapacityV1.self,
                    revisionID: assignment.speakingCapacityRevision.revisionID
                )
            else { throw AnalysisCoverageError.reviewUnavailable }
            actorsByRevision[actor.revision.revisionID] = actor
            capacitiesByRevision[capacity.revision.revisionID] = capacity
            for relationship in capacity.representationRelationships {
                guard let represented = try fetch(
                    ActorV1.self,
                    revisionID: relationship.entityRevision.revisionID
                ) else { throw AnalysisCoverageError.reviewUnavailable }
                actorsByRevision[represented.revision.revisionID] = represented
            }
        }
        return try AnalysisSourceBundle(
            meeting: meeting,
            transcriptReview: review,
            sourceAssets: sourceAssetsByRevision.values.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            },
            actors: actorsByRevision.values.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            },
            capacities: capacitiesByRevision.values.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            }
        )
    }

    public func recordIncompleteAnalysis(_ ledger: AnalysisCoverageLedger) throws {
        guard ledger.status == .incomplete else {
            throw AnalysisCoverageError.publicationConflict
        }
        try ledger.validate()
        do {
            try databasePool.write { db in
                try insertAnalysisLedger(ledger, activate: false, in: db)
            }
        } catch let error as AnalysisCoverageError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func analysisCoverageLedgers(
        meetingID: MeetingID
    ) throws -> [AnalysisCoverageLedger] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM analysis_coverage_ledgers
                WHERE meeting_id = ?
                ORDER BY created_at_ms, ledger_id
                """,
                arguments: [meetingID.canonicalString]
            ).map { try decodeAnalysisLedger($0, in: db) }
        }
    }

    public func publishAnalysis(
        _ publication: AnalysisPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws {
        try publication.ledger.validate()
        do {
            try databasePool.write { db in
                try validateCurrentInputRevisions(inputRevisions, in: db)
                guard let transcriptRow = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT manifest.*
                    FROM active_transcript_manifests AS active
                    JOIN transcript_coverage_manifests AS manifest
                      ON manifest.manifest_id = active.manifest_id
                    WHERE active.meeting_id = ?
                    """,
                    arguments: [publication.ledger.meetingID.canonicalString]
                ) else {
                    throw AnalysisCoverageError.publicationConflict
                }
                let transcriptManifest = try decodeManifest(transcriptRow)
                guard transcriptManifest.manifestID == publication.ledger.transcriptManifestID,
                      transcriptManifest.contentHash == publication.ledger.transcriptManifestHash,
                      transcriptManifest.transcriptRevisionReferences.sorted()
                        == publication.ledger.eligibleSegmentRevisions
                else {
                    throw AnalysisCoverageError.publicationConflict
                }

                for value in publication.evidence { try insertPublicationObject(value, in: db) }
                for value in publication.organizations { try insertPublicationObject(value, in: db) }
                for value in publication.participants { try insertPublicationObject(value, in: db) }
                for value in publication.issues { try insertPublicationObject(value, in: db) }
                for value in publication.positions { try insertPublicationObject(value, in: db) }
                for value in publication.commitments { try insertPublicationObject(value, in: db) }
                for value in publication.decisions { try insertPublicationObject(value, in: db) }
                for value in publication.interventionCards { try insertPublicationObject(value, in: db) }
                for value in publication.delegationPositionCards { try insertPublicationObject(value, in: db) }

                for value in publication.evidence {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.organizations {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.participants {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.issues {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.positions {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.commitments {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.decisions {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.interventionCards {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                for value in publication.delegationPositionCards {
                    try initializeActivePointer(for: value, at: publication.ledger.createdAt, in: db)
                }
                try insertAnalysisLedger(publication.ledger, activate: true, in: db)
            }
        } catch let error as AnalysisCoverageError {
            throw error
        } catch let error as PersistenceContractError {
            throw error
        } catch let error as JobContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func activeAnalysisReview(meetingID: MeetingID) throws -> AnalysisReviewBundle? {
        try databasePool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT ledger.*
                FROM active_analysis_ledgers AS active
                JOIN analysis_coverage_ledgers AS ledger
                  ON ledger.ledger_id = active.ledger_id
                WHERE active.meeting_id = ?
                """,
                arguments: [meetingID.canonicalString]
            ) else { return nil }
            let ledger = try decodeAnalysisLedger(row, in: db)
            guard ledger.meetingID == meetingID, ledger.status == .published else {
                throw AnalysisCoverageError.publicationConflict
            }

            var evidence: [EvidenceRefV1] = []
            var participants: [ParticipantV1] = []
            var organizations: [OrganizationV1] = []
            var issues: [IssueV1] = []
            var positions: [PositionV1] = []
            var commitments: [CommitmentV1] = []
            var decisions: [DecisionV1] = []
            var interventionCards: [InterventionCardV1] = []
            var delegationCards: [DelegationPositionCardV1] = []

            for reference in ledger.evidenceRevisionReferences {
                guard let value = try fetch(
                    EvidenceRefV1.self,
                    revisionID: reference.revisionID,
                    in: db
                ) else { throw AnalysisCoverageError.publicationConflict }
                evidence.append(value)
            }
            for reference in ledger.outputRevisionReferences {
                switch reference.objectType {
                case .participant:
                    participants.append(try requiredFetch(ParticipantV1.self, reference: reference, in: db))
                case .organization:
                    organizations.append(try requiredFetch(OrganizationV1.self, reference: reference, in: db))
                case .issue:
                    issues.append(try requiredFetch(IssueV1.self, reference: reference, in: db))
                case .position:
                    positions.append(try activeOrExactPosition(reference: reference, in: db))
                case .commitment:
                    commitments.append(try requiredFetch(CommitmentV1.self, reference: reference, in: db))
                case .decision:
                    decisions.append(try requiredFetch(DecisionV1.self, reference: reference, in: db))
                case .interventionCard:
                    interventionCards.append(try requiredFetch(InterventionCardV1.self, reference: reference, in: db))
                case .delegationPositionCard:
                    delegationCards.append(try requiredFetch(DelegationPositionCardV1.self, reference: reference, in: db))
                default:
                    throw AnalysisCoverageError.publicationConflict
                }
            }
            return AnalysisReviewBundle(
                ledger: ledger,
                evidence: evidence,
                participants: participants,
                organizations: organizations,
                issues: issues,
                positions: positions,
                commitments: commitments,
                decisions: decisions,
                interventionCards: interventionCards,
                delegationPositionCards: delegationCards
            )
        }
    }

    public func savePositionCorrection(
        _ correction: PositionV1,
        replacing expectedRevisionID: RevisionID,
        changedAt: UTCInstant
    ) throws {
        guard correction.revision.supersedesRevisionID == expectedRevisionID,
              correction.revision.createdBy == .user,
              correction.reviewStatus == .confirmed,
              correction.userConfirmed
        else { throw AnalysisCoverageError.publicationConflict }
        try insert(correction)
        _ = try activate(
            ActivePublishedRevisionSelection(
                logicalID: correction.positionID,
                revisionID: correction.revision.revisionID
            ),
            as: PositionV1.self,
            expectedCurrentRevisionID: expectedRevisionID,
            handlingPolicies: [],
            markedAt: changedAt
        )
    }

    public func recordIncompleteBriefing(_ ledger: BriefingCoverageLedger) throws {
        guard ledger.status == .incomplete else {
            throw BriefingCoverageError.publicationConflict
        }
        try ledger.validate()
        do {
            try databasePool.write { db in
                try insertBriefingLedger(ledger, activate: false, in: db)
            }
        } catch let error as BriefingCoverageError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func briefingSourceBundle(
        meetingRevision: SemanticRevisionReference,
        template: MeetingTemplateV1,
        analysisLedgerID: AnalysisCoverageLedgerID
    ) throws -> BriefingSourceBundle {
        guard meetingRevision.objectType == .meetingProfile,
              let meeting = try fetch(
                  MeetingProfileV1.self,
                  revisionID: meetingRevision.revisionID
              ),
              meeting.meetingID.canonicalString == meetingRevision.logicalID.canonicalString,
              let transcriptReview = try activeTranscriptReview(meetingID: meeting.meetingID),
              let analysis = try activeAnalysisReview(meetingID: meeting.meetingID),
              analysis.ledger.ledgerID == analysisLedgerID
        else { throw BriefingCoverageError.reviewUnavailable }
        return try BriefingSourceBundle(
            meeting: meeting,
            template: template,
            transcriptReview: transcriptReview,
            analysis: analysis
        )
    }

    public func briefingCoverageLedgers(
        meetingID: MeetingID
    ) throws -> [BriefingCoverageLedger] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM briefing_coverage_ledgers
                WHERE meeting_id = ?
                ORDER BY created_at_ms, ledger_id
                """,
                arguments: [meetingID.canonicalString]
            ).map { try decodeBriefingLedger($0, in: db) }
        }
    }

    public func publishBriefing(
        _ publication: BriefingPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws {
        guard publication.ledger.status == .published,
              publication.ledger.supersedesLedgerID == nil
        else { throw BriefingCoverageError.publicationConflict }
        do {
            try databasePool.write { db in
                try validateCurrentInputRevisions(inputRevisions, in: db)
                try validateBriefingUpstream(publication.ledger, in: db)
                try insertPublicationObject(publication.template, in: db)
                try insertPublicationObject(publication.graph, in: db)
                for section in publication.sections {
                    try insertPublicationObject(section, in: db)
                }
                try insertPublicationObject(publication.validationReport, in: db)
                try insertPublicationObject(publication.finalBriefing, in: db)

                let changedAt = publication.ledger.createdAt
                try initializeActivePointer(for: publication.template, at: changedAt, in: db)
                try initializeActivePointer(for: publication.graph, at: changedAt, in: db)
                for section in publication.sections {
                    try initializeActivePointer(for: section, at: changedAt, in: db)
                }
                try initializeActivePointer(for: publication.validationReport, at: changedAt, in: db)
                try initializeActivePointer(for: publication.finalBriefing, at: changedAt, in: db)
                try insertBriefingLedger(publication.ledger, activate: true, in: db)
            }
        } catch let error as BriefingCoverageError {
            throw error
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func replaceBriefingSection(
        _ publication: BriefingPublication,
        replacing expectedSectionRevisionID: RevisionID,
        changedAt: UTCInstant
    ) throws {
        guard publication.ledger.status == .published,
              publication.ledger.supersedesLedgerID != nil,
              let replacement = publication.sections.first(where: {
                  $0.revision.supersedesRevisionID == expectedSectionRevisionID
              })
        else { throw BriefingCoverageError.publicationConflict }
        do {
            try databasePool.write { db in
                try validateBriefingUpstream(publication.ledger, in: db)
                guard let previous = try fetch(
                    BriefingSectionV1.self,
                    revisionID: expectedSectionRevisionID,
                    in: db
                ),
                    previous.sectionID == replacement.sectionID,
                    previous.meetingID == replacement.meetingID,
                    replacement.templateRevision == previous.templateRevision,
                    replacement.graphRevision == previous.graphRevision
                else { throw BriefingCoverageError.publicationConflict }
                if replacement.manualEditStatus == .generated,
                   previous.locked || previous.manualEditStatus == .userEdited
                {
                    throw BriefingCoverageError.lockedSection
                }
                let activeSectionID = try String.fetchOne(
                    db,
                    sql: """
                    SELECT revision_id FROM active_published_revisions
                    WHERE object_type = 'briefing_section' AND logical_id = ?
                    """,
                    arguments: [replacement.sectionID.canonicalString]
                )
                guard activeSectionID == expectedSectionRevisionID.canonicalString else {
                    throw BriefingCoverageError.publicationConflict
                }
                let unchanged = publication.sections.filter { $0.sectionID != replacement.sectionID }
                for section in unchanged {
                    let activeID = try String.fetchOne(
                        db,
                        sql: """
                        SELECT revision_id FROM active_published_revisions
                        WHERE object_type = 'briefing_section' AND logical_id = ?
                        """,
                        arguments: [section.sectionID.canonicalString]
                    )
                    guard activeID == section.revision.revisionID.canonicalString else {
                        throw BriefingCoverageError.publicationConflict
                    }
                }

                try insertPublicationObject(replacement, in: db)
                try insertPublicationObject(publication.validationReport, in: db)
                try insertPublicationObject(publication.finalBriefing, in: db)
                _ = try moveActivePointer(
                    for: replacement,
                    expectedCurrentRevisionID: expectedSectionRevisionID,
                    handlingPolicies: [],
                    markedAt: changedAt,
                    in: db
                )
                _ = try moveActivePointer(
                    for: publication.validationReport,
                    expectedCurrentRevisionID: publication.validationReport.revision.supersedesRevisionID,
                    handlingPolicies: [],
                    markedAt: changedAt,
                    in: db
                )
                _ = try moveActivePointer(
                    for: publication.finalBriefing,
                    expectedCurrentRevisionID: publication.finalBriefing.revision.supersedesRevisionID,
                    handlingPolicies: [],
                    markedAt: changedAt,
                    in: db
                )
                try insertBriefingLedger(publication.ledger, activate: true, in: db)
            }
        } catch let error as BriefingCoverageError {
            throw error
        } catch let error as PersistenceContractError {
            throw error
        } catch {
            throw PersistenceContractError.dependencyIntegrity(String(describing: error))
        }
    }

    public func activeBriefingReview(
        meetingID: MeetingID
    ) throws -> BriefingReviewBundle? {
        try databasePool.read { db in
            guard let ledgerRow = try Row.fetchOne(
                db,
                sql: """
                SELECT ledger.*
                FROM active_briefing_ledgers AS active
                JOIN briefing_coverage_ledgers AS ledger
                  ON ledger.ledger_id = active.ledger_id
                WHERE active.meeting_id = ?
                """,
                arguments: [meetingID.canonicalString]
            ) else { return nil }
            let ledger = try decodeBriefingLedger(ledgerRow, in: db)
            let template = try requiredFetch(
                MeetingTemplateV1.self,
                reference: ledger.templateRevision,
                in: db
            )
            let graph = try requiredFetch(
                IssuePositionGraphV1.self,
                reference: ledger.graphRevision,
                in: db
            )
            let sections = try ledger.sectionRevisions.map {
                try requiredFetch(BriefingSectionV1.self, reference: $0, in: db)
            }
            let activeFinalRows = try Row.fetchAll(
                db,
                sql: """
                SELECT revision.*
                FROM active_published_revisions AS active
                JOIN semantic_revisions AS revision
                  ON revision.object_type = active.object_type
                 AND revision.logical_id = active.logical_id
                 AND revision.revision_id = active.revision_id
                WHERE active.object_type = 'final_briefing'
                ORDER BY active.logical_id
                """
            )
            let finals = try activeFinalRows.map { try decode(FinalBriefingV1.self, row: $0) }
            guard let final = finals.first(where: {
                $0.meetingID == meetingID && $0.sectionRevisions == ledger.sectionRevisions
            }) else { throw BriefingCoverageError.publicationConflict }
            let report = try requiredFetch(
                ValidationReportV1.self,
                reference: final.validationReportRevision,
                in: db
            )
            let publication = try BriefingPublication(
                template: template,
                graph: graph,
                sections: sections,
                validationReport: report,
                finalBriefing: final,
                ledger: ledger
            )
            let references = [ledger.graphRevision]
                + ledger.sectionRevisions
                + [final.validationReportRevision, try semanticReference(final)]
            let marks = try references.flatMap { try staleMarks(for: $0, in: db) }
            return BriefingReviewBundle(publication: publication, staleMarks: marks)
        }
    }

    public func insertBriefingExportRecord(_ record: BriefingExportRecord) throws {
        let payload = try SQLitePayloadCodec.canonicalData(record)
        let digest = SQLitePayloadCodec.sha256(payload)
        guard payload.count <= 1_048_576 else { throw BriefingExportError.integrityFailure }
        try databasePool.write { db in
            if let existing = try Row.fetchOne(
                db,
                sql: """
                SELECT canonical_payload, payload_sha256
                FROM briefing_export_records WHERE export_id = ?
                """,
                arguments: [record.exportID.canonicalString]
            ) {
                let existingPayload: Data = existing["canonical_payload"]
                let existingDigest: String = existing["payload_sha256"]
                guard existingPayload == payload, existingDigest == digest else {
                    throw BriefingExportError.integrityFailure
                }
                return
            }
            guard let final = try fetch(
                FinalBriefingV1.self,
                revisionID: record.finalBriefingRevision.revisionID,
                in: db
            ),
                final.finalBriefingID.canonicalString
                    == record.finalBriefingRevision.logicalID.canonicalString,
                final.meetingID == record.meetingID,
                final.revision.dataClassification == record.dataClassification
            else { throw BriefingExportError.integrityFailure }
            try db.execute(
                sql: """
                INSERT INTO briefing_export_records(
                    export_id, meeting_id, final_revision_id, relative_path,
                    data_classification, exported_at_ms, canonical_payload,
                    payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.exportID.canonicalString,
                    record.meetingID.canonicalString,
                    record.finalBriefingRevision.revisionID.canonicalString,
                    record.relativePath.rawValue,
                    record.dataClassification.encodedValue,
                    record.exportedAt.millisecondsSinceUnixEpoch,
                    payload,
                    digest,
                    payload.count
                ]
            )
        }
    }

    public func briefingExportRecords(meetingID: MeetingID) throws -> [BriefingExportRecord] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM briefing_export_records
                WHERE meeting_id = ? ORDER BY exported_at_ms, export_id
                """,
                arguments: [meetingID.canonicalString]
            ).map { row in
                let payload: Data = row["canonical_payload"]
                let digest: String = row["payload_sha256"]
                guard SQLitePayloadCodec.sha256(payload) == digest else {
                    throw BriefingExportError.integrityFailure
                }
                let record = try JSONDecoder().decode(BriefingExportRecord.self, from: payload)
                guard try SQLitePayloadCodec.canonicalData(record) == payload,
                      row["export_id"] == record.exportID.canonicalString,
                      row["relative_path"] == record.relativePath.rawValue
                else { throw BriefingExportError.integrityFailure }
                return record
            }
        }
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

    public func managedAsset(storageObjectID: StorageObjectID) throws -> ManagedAssetRecord? {
        try databasePool.read { db in
            try managedAsset(storageObjectID: storageObjectID, in: db)
        }
    }

    public func sourceAsset(revisionID: RevisionID) throws -> SourceAssetV1? {
        try fetch(SourceAssetV1.self, revisionID: revisionID)
    }

    public func insertSourceAsset(_ sourceAsset: SourceAssetV1) throws {
        try insert(sourceAsset)
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
            || type is ParticipantV1.Type
            || type is OrganizationV1.Type
            || type is IssueV1.Type
            || type is PositionV1.Type
            || type is CommitmentV1.Type
            || type is DecisionV1.Type
            || type is InterventionCardV1.Type
            || type is DelegationPositionCardV1.Type
            || type is MeetingTemplateV1.Type
            || type is IssuePositionGraphV1.Type
            || type is BriefingSectionV1.Type
            || type is ValidationReportV1.Type
            || type is FinalBriefingV1.Type
        guard supported else {
            throw PersistenceContractError.unsupportedStoredObjectType(
                Object.ObjectIDTag.semanticObjectType.encodedValue
            )
        }
    }

    private func insertPublicationObject<Object: SemanticRevisionContract>(
        _ object: Object,
        in db: Database
    ) throws {
        try ensureSupported(Object.self)
        try object.validate()
        let payload = try CanonicalJSON.encodeValidated(object)
        guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
            throw PersistenceContractError.revisionConflict(object.revision.revisionID)
        }
        if try existingRevisionMatches(object, payload: payload, in: db) { return }
        try validateWorkspaceOwnership(object, in: db)
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
    }

    private func initializeActivePointer<Object: SemanticRevisionContract>(
        for object: Object,
        at changedAt: UTCInstant,
        in db: Database
    ) throws {
        let revision = object.revision
        guard revision.lifecycleStatus == .published, revision.validationState == .valid else {
            throw TranscriptCoverageError.publicationConflict
        }
        if let current: String = try String.fetchOne(
            db,
            sql: "SELECT revision_id FROM active_published_revisions WHERE object_type = ? AND logical_id = ?",
            arguments: [revision.objectType.encodedValue, revision.logicalID.canonicalString]
        ) {
            guard current == revision.revisionID.canonicalString else {
                throw TranscriptCoverageError.publicationConflict
            }
            return
        }
        let eventID = UUID().uuidString.lowercased()
        try db.execute(
            sql: """
            INSERT INTO active_revision_events(
                event_id, object_type, logical_id, previous_revision_id,
                replacement_revision_id, pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, NULL, ?, 1, ?)
            """,
            arguments: [
                eventID,
                revision.objectType.encodedValue,
                revision.logicalID.canonicalString,
                revision.revisionID.canonicalString,
                changedAt.millisecondsSinceUnixEpoch
            ]
        )
        try db.execute(
            sql: """
            INSERT INTO active_published_revisions(
                object_type, logical_id, revision_id, pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, 1, ?)
            """,
            arguments: [
                revision.objectType.encodedValue,
                revision.logicalID.canonicalString,
                revision.revisionID.canonicalString,
                changedAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    private func semanticReference<Object: SemanticRevisionContract>(
        _ object: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: object.revision.logicalID,
            revisionID: object.revision.revisionID
        )
    }

    private func moveActivePointer<Object: SemanticRevisionContract>(
        for replacement: Object,
        expectedCurrentRevisionID: RevisionID?,
        handlingPolicies: [RevisionHandlingPolicy],
        markedAt: UTCInstant,
        in db: Database
    ) throws -> StalePlan {
        let selection = try ActivePublishedRevisionSelection(
            logicalID: replacement.revision.logicalID,
            revisionID: replacement.revision.revisionID
        )
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
            SELECT revision_id, pointer_version FROM active_published_revisions
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
        let previous = try actualPreviousID.map {
            try ActivePublishedRevisionSelection<Object.ObjectIDTag>(
                logicalID: selection.logicalID,
                revisionID: $0
            )
        }
        let change = try ActivePublishedRevisionChange(
            previous: previous,
            replacement: selection
        )
        let plan = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: dependencyEdges(in: db),
            handlingPolicies: handlingPolicies
        )
        if change.isNoOp { return plan }
        let nextVersion = (pointer?["pointer_version"] as Int64? ?? 0) + 1
        let eventID = UUID().uuidString.lowercased()
        try db.execute(
            sql: """
            INSERT INTO active_revision_events(
                event_id, object_type, logical_id, previous_revision_id,
                replacement_revision_id, pointer_version, changed_at_ms
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
            try insert(staleMark: mark, eventID: eventID, markedAt: markedAt, in: db)
        }
        return plan
    }

    private func validateBriefingUpstream(
        _ ledger: BriefingCoverageLedger,
        in db: Database
    ) throws {
        guard let transcriptRow = try Row.fetchOne(
            db,
            sql: """
            SELECT manifest.*
            FROM active_transcript_manifests AS active
            JOIN transcript_coverage_manifests AS manifest
              ON manifest.manifest_id = active.manifest_id
            WHERE active.meeting_id = ?
            """,
            arguments: [ledger.meetingID.canonicalString]
        ),
            let analysisRow = try Row.fetchOne(
                db,
                sql: """
                SELECT analysis.*
                FROM active_analysis_ledgers AS active
                JOIN analysis_coverage_ledgers AS analysis
                  ON analysis.ledger_id = active.ledger_id
                WHERE active.meeting_id = ?
                """,
                arguments: [ledger.meetingID.canonicalString]
            )
        else { throw BriefingCoverageError.publicationConflict }
        let transcript = try decodeManifest(transcriptRow)
        let analysis = try decodeAnalysisLedger(analysisRow, in: db)
        guard transcript.manifestID == ledger.transcriptManifestID,
              transcript.contentHash == ledger.transcriptManifestHash,
              analysis.ledgerID == ledger.analysisLedgerID,
              analysis.contentHash == ledger.analysisLedgerHash,
              analysis.transcriptManifestID == transcript.manifestID,
              analysis.transcriptManifestHash == transcript.contentHash,
              analysis.eligibleSegmentRevisions == ledger.eligibleSegmentRevisions,
              analysis.status == .published,
              analysis.segments.count == ledger.segments.count
        else { throw BriefingCoverageError.publicationConflict }
        for (analysisSegment, briefingSegment) in zip(analysis.segments, ledger.segments) {
            guard analysisSegment.segmentRevision == briefingSegment.segmentRevision,
                  analysisSegment.evidenceRevisions == briefingSegment.evidenceRevisions,
                  analysisSegment.outputRevisions == briefingSegment.analysisOutputRevisions
            else { throw BriefingCoverageError.publicationConflict }
            switch (analysisSegment.disposition, briefingSegment.disposition) {
            case (.substantive, .represented), (.substantive, .reviewedNotRendered),
                 (.nonSubstantive, .nonSubstantive):
                break
            default:
                throw BriefingCoverageError.publicationConflict
            }
        }
    }

    private func insertAnalysisLedger(
        _ ledger: AnalysisCoverageLedger,
        activate: Bool,
        in db: Database
    ) throws {
        try ledger.validate()
        guard let transcriptRow = try Row.fetchOne(
            db,
            sql: "SELECT meeting_id, content_hash_hex FROM transcript_coverage_manifests WHERE manifest_id = ?",
            arguments: [ledger.transcriptManifestID.canonicalString]
        ),
            transcriptRow["meeting_id"] == ledger.meetingID.canonicalString,
            transcriptRow["content_hash_hex"] == ledger.transcriptManifestHash.lowercaseHex
        else { throw AnalysisCoverageError.publicationConflict }

        let payload = try SQLitePayloadCodec.canonicalData(ledger)
        let digest = SQLitePayloadCodec.sha256(payload)
        guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
            throw AnalysisCoverageError.publicationConflict
        }
        if let existing = try Row.fetchOne(
            db,
            sql: "SELECT canonical_payload, payload_sha256 FROM analysis_coverage_ledgers WHERE ledger_id = ?",
            arguments: [ledger.ledgerID.canonicalString]
        ) {
            let existingPayload: Data = existing["canonical_payload"]
            let existingDigest: String = existing["payload_sha256"]
            guard existingPayload == payload, existingDigest == digest else {
                throw AnalysisCoverageError.publicationConflict
            }
        } else {
            try db.execute(
                sql: """
                INSERT INTO analysis_coverage_ledgers(
                    ledger_id, supersedes_ledger_id, meeting_id, transcript_manifest_id,
                    status, created_at_ms, content_hash_algorithm, content_hash_hex,
                    canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    ledger.supersedesLedgerID?.canonicalString,
                    ledger.meetingID.canonicalString,
                    ledger.transcriptManifestID.canonicalString,
                    ledger.status.rawValue,
                    ledger.createdAt.millisecondsSinceUnixEpoch,
                    ledger.contentHash.algorithm.encodedValue,
                    ledger.contentHash.lowercaseHex,
                    payload,
                    digest,
                    payload.count
                ]
            )
            for (ordinal, segment) in ledger.segments.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO analysis_coverage_entries(
                        ledger_id, ordinal, segment_object_type, segment_logical_id,
                        segment_revision_id, disposition, attempt_count, safe_reason_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        ledger.ledgerID.canonicalString,
                        ordinal,
                        segment.segmentRevision.objectType.encodedValue,
                        segment.segmentRevision.logicalID.canonicalString,
                        segment.segmentRevision.revisionID.canonicalString,
                        segment.disposition.rawValue,
                        segment.attemptCount,
                        segment.safeReasonCode
                    ]
                )
                for evidence in segment.evidenceRevisions {
                    try db.execute(
                        sql: """
                        INSERT INTO analysis_coverage_evidence(
                            ledger_id, segment_revision_id, evidence_object_type,
                            evidence_logical_id, evidence_revision_id
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            ledger.ledgerID.canonicalString,
                            segment.segmentRevision.revisionID.canonicalString,
                            evidence.objectType.encodedValue,
                            evidence.logicalID.canonicalString,
                            evidence.revisionID.canonicalString
                        ]
                    )
                }
                for output in segment.outputRevisions {
                    try db.execute(
                        sql: """
                        INSERT INTO analysis_coverage_outputs(
                            ledger_id, segment_revision_id, output_object_type,
                            output_logical_id, output_revision_id
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            ledger.ledgerID.canonicalString,
                            segment.segmentRevision.revisionID.canonicalString,
                            output.objectType.encodedValue,
                            output.logicalID.canonicalString,
                            output.revisionID.canonicalString
                        ]
                    )
                }
            }
        }
        guard activate else { return }

        let pointer = try Row.fetchOne(
            db,
            sql: "SELECT ledger_id, pointer_version FROM active_analysis_ledgers WHERE meeting_id = ?",
            arguments: [ledger.meetingID.canonicalString]
        )
        let currentID: String? = pointer?["ledger_id"]
        if currentID == ledger.ledgerID.canonicalString { return }
        guard currentID == ledger.supersedesLedgerID?.canonicalString else {
            throw AnalysisCoverageError.publicationConflict
        }
        let nextVersion: Int64 = (pointer?["pointer_version"] as Int64? ?? 0) + 1
        try db.execute(
            sql: """
            INSERT INTO analysis_ledger_events(
                event_id, meeting_id, previous_ledger_id, replacement_ledger_id,
                pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(),
                ledger.meetingID.canonicalString,
                currentID,
                ledger.ledgerID.canonicalString,
                nextVersion,
                ledger.createdAt.millisecondsSinceUnixEpoch
            ]
        )
        try db.execute(
            sql: """
            INSERT INTO active_analysis_ledgers(
                meeting_id, ledger_id, pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(meeting_id) DO UPDATE SET
                ledger_id = excluded.ledger_id,
                pointer_version = excluded.pointer_version,
                changed_at_ms = excluded.changed_at_ms
            """,
            arguments: [
                ledger.meetingID.canonicalString,
                ledger.ledgerID.canonicalString,
                nextVersion,
                ledger.createdAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    private func decodeAnalysisLedger(
        _ row: Row,
        in db: Database
    ) throws -> AnalysisCoverageLedger {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest else {
            throw AnalysisCoverageError.publicationConflict
        }
        let ledger = try JSONDecoder().decode(AnalysisCoverageLedger.self, from: payload)
        try ledger.validate()
        guard try SQLitePayloadCodec.canonicalData(ledger) == payload,
              row["ledger_id"] == ledger.ledgerID.canonicalString,
              row["meeting_id"] == ledger.meetingID.canonicalString,
              row["transcript_manifest_id"] == ledger.transcriptManifestID.canonicalString,
              row["content_hash_hex"] == ledger.contentHash.lowercaseHex
        else { throw AnalysisCoverageError.publicationConflict }
        try validateAnalysisLedgerIndex(ledger, in: db)
        return ledger
    }

    private func validateAnalysisLedgerIndex(
        _ ledger: AnalysisCoverageLedger,
        in db: Database
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT ordinal, segment_object_type, segment_logical_id,
                   segment_revision_id, disposition, attempt_count, safe_reason_code
            FROM analysis_coverage_entries
            WHERE ledger_id = ?
            ORDER BY ordinal
            """,
            arguments: [ledger.ledgerID.canonicalString]
        )
        guard rows.count == ledger.segments.count else {
            throw AnalysisCoverageError.publicationConflict
        }
        for (ordinal, pair) in zip(rows.indices, zip(rows, ledger.segments)) {
            let (row, segment) = pair
            let segmentReference = try SQLiteReferenceCodec.reference(
                objectTypeValue: row["segment_object_type"],
                logicalIDValue: row["segment_logical_id"],
                revisionIDValue: row["segment_revision_id"]
            )
            let disposition: String = row["disposition"]
            let attemptCount: UInt32 = row["attempt_count"]
            let safeReasonCode: String? = row["safe_reason_code"]
            guard (row["ordinal"] as Int) == ordinal,
                  segmentReference == segment.segmentRevision,
                  disposition == segment.disposition.rawValue,
                  attemptCount == segment.attemptCount,
                  safeReasonCode == segment.safeReasonCode
            else { throw AnalysisCoverageError.publicationConflict }

            let evidence = try Row.fetchAll(
                db,
                sql: """
                SELECT evidence_object_type, evidence_logical_id, evidence_revision_id
                FROM analysis_coverage_evidence
                WHERE ledger_id = ? AND segment_revision_id = ?
                ORDER BY evidence_object_type, evidence_logical_id, evidence_revision_id
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    segment.segmentRevision.revisionID.canonicalString
                ]
            ).map {
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: $0["evidence_object_type"],
                    logicalIDValue: $0["evidence_logical_id"],
                    revisionIDValue: $0["evidence_revision_id"]
                )
            }
            let outputs = try Row.fetchAll(
                db,
                sql: """
                SELECT output_object_type, output_logical_id, output_revision_id
                FROM analysis_coverage_outputs
                WHERE ledger_id = ? AND segment_revision_id = ?
                ORDER BY output_object_type, output_logical_id, output_revision_id
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    segment.segmentRevision.revisionID.canonicalString
                ]
            ).map {
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: $0["output_object_type"],
                    logicalIDValue: $0["output_logical_id"],
                    revisionIDValue: $0["output_revision_id"]
                )
            }
            guard evidence == segment.evidenceRevisions.sorted(),
                  outputs == segment.outputRevisions.sorted()
            else { throw AnalysisCoverageError.publicationConflict }
        }
    }

    private func insertBriefingLedger(
        _ ledger: BriefingCoverageLedger,
        activate: Bool,
        in db: Database
    ) throws {
        try ledger.validate()
        guard let transcriptRow = try Row.fetchOne(
            db,
            sql: """
            SELECT meeting_id, content_hash_hex FROM transcript_coverage_manifests
            WHERE manifest_id = ?
            """,
            arguments: [ledger.transcriptManifestID.canonicalString]
        ),
            transcriptRow["meeting_id"] == ledger.meetingID.canonicalString,
            transcriptRow["content_hash_hex"] == ledger.transcriptManifestHash.lowercaseHex,
            let analysisRow = try Row.fetchOne(
                db,
                sql: """
                SELECT meeting_id, content_hash_hex FROM analysis_coverage_ledgers
                WHERE ledger_id = ?
                """,
                arguments: [ledger.analysisLedgerID.canonicalString]
            ),
            analysisRow["meeting_id"] == ledger.meetingID.canonicalString,
            analysisRow["content_hash_hex"] == ledger.analysisLedgerHash.lowercaseHex
        else { throw BriefingCoverageError.publicationConflict }

        let payload = try SQLitePayloadCodec.canonicalData(ledger)
        let digest = SQLitePayloadCodec.sha256(payload)
        guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
            throw BriefingCoverageError.publicationConflict
        }
        if let existing = try Row.fetchOne(
            db,
            sql: """
            SELECT canonical_payload, payload_sha256
            FROM briefing_coverage_ledgers WHERE ledger_id = ?
            """,
            arguments: [ledger.ledgerID.canonicalString]
        ) {
            let existingPayload: Data = existing["canonical_payload"]
            let existingDigest: String = existing["payload_sha256"]
            guard existingPayload == payload, existingDigest == digest else {
                throw BriefingCoverageError.publicationConflict
            }
        } else {
            try db.execute(
                sql: """
                INSERT INTO briefing_coverage_ledgers(
                    ledger_id, supersedes_ledger_id, meeting_id,
                    transcript_manifest_id, analysis_ledger_id, status,
                    created_at_ms, content_hash_algorithm, content_hash_hex,
                    canonical_payload, payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    ledger.supersedesLedgerID?.canonicalString,
                    ledger.meetingID.canonicalString,
                    ledger.transcriptManifestID.canonicalString,
                    ledger.analysisLedgerID.canonicalString,
                    ledger.status.rawValue,
                    ledger.createdAt.millisecondsSinceUnixEpoch,
                    ledger.contentHash.algorithm.encodedValue,
                    ledger.contentHash.lowercaseHex,
                    payload,
                    digest,
                    payload.count
                ]
            )
            for (ordinal, segment) in ledger.segments.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO briefing_coverage_entries(
                        ledger_id, ordinal, segment_object_type, segment_logical_id,
                        segment_revision_id, disposition, safe_reason_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        ledger.ledgerID.canonicalString,
                        ordinal,
                        segment.segmentRevision.objectType.encodedValue,
                        segment.segmentRevision.logicalID.canonicalString,
                        segment.segmentRevision.revisionID.canonicalString,
                        segment.disposition.rawValue,
                        segment.safeReasonCode
                    ]
                )
                for evidence in segment.evidenceRevisions {
                    try db.execute(
                        sql: """
                        INSERT INTO briefing_coverage_evidence(
                            ledger_id, segment_revision_id, evidence_object_type,
                            evidence_logical_id, evidence_revision_id
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            ledger.ledgerID.canonicalString,
                            segment.segmentRevision.revisionID.canonicalString,
                            evidence.objectType.encodedValue,
                            evidence.logicalID.canonicalString,
                            evidence.revisionID.canonicalString
                        ]
                    )
                }
                for output in segment.analysisOutputRevisions {
                    try db.execute(
                        sql: """
                        INSERT INTO briefing_coverage_analysis_outputs(
                            ledger_id, segment_revision_id, output_object_type,
                            output_logical_id, output_revision_id
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            ledger.ledgerID.canonicalString,
                            segment.segmentRevision.revisionID.canonicalString,
                            output.objectType.encodedValue,
                            output.logicalID.canonicalString,
                            output.revisionID.canonicalString
                        ]
                    )
                }
                for conclusion in segment.conclusionReferences {
                    try db.execute(
                        sql: """
                        INSERT INTO briefing_coverage_conclusions(
                            ledger_id, segment_revision_id, output_object_type,
                            output_logical_id, output_revision_id, item_id
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            ledger.ledgerID.canonicalString,
                            segment.segmentRevision.revisionID.canonicalString,
                            conclusion.outputRevision.objectType.encodedValue,
                            conclusion.outputRevision.logicalID.canonicalString,
                            conclusion.outputRevision.revisionID.canonicalString,
                            conclusion.itemID.canonicalString
                        ]
                    )
                }
            }
        }
        guard activate else { return }
        let pointer = try Row.fetchOne(
            db,
            sql: """
            SELECT ledger_id, pointer_version FROM active_briefing_ledgers
            WHERE meeting_id = ?
            """,
            arguments: [ledger.meetingID.canonicalString]
        )
        let currentID: String? = pointer?["ledger_id"]
        if currentID == ledger.ledgerID.canonicalString { return }
        guard currentID == ledger.supersedesLedgerID?.canonicalString else {
            throw BriefingCoverageError.publicationConflict
        }
        let nextVersion = (pointer?["pointer_version"] as Int64? ?? 0) + 1
        try db.execute(
            sql: """
            INSERT INTO briefing_ledger_events(
                event_id, meeting_id, previous_ledger_id, replacement_ledger_id,
                pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(),
                ledger.meetingID.canonicalString,
                currentID,
                ledger.ledgerID.canonicalString,
                nextVersion,
                ledger.createdAt.millisecondsSinceUnixEpoch
            ]
        )
        try db.execute(
            sql: """
            INSERT INTO active_briefing_ledgers(
                meeting_id, ledger_id, pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(meeting_id) DO UPDATE SET
                ledger_id = excluded.ledger_id,
                pointer_version = excluded.pointer_version,
                changed_at_ms = excluded.changed_at_ms
            """,
            arguments: [
                ledger.meetingID.canonicalString,
                ledger.ledgerID.canonicalString,
                nextVersion,
                ledger.createdAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    private func decodeBriefingLedger(
        _ row: Row,
        in db: Database
    ) throws -> BriefingCoverageLedger {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest else {
            throw BriefingCoverageError.publicationConflict
        }
        let ledger = try JSONDecoder().decode(BriefingCoverageLedger.self, from: payload)
        try ledger.validate()
        guard try SQLitePayloadCodec.canonicalData(ledger) == payload,
              row["ledger_id"] == ledger.ledgerID.canonicalString,
              row["meeting_id"] == ledger.meetingID.canonicalString,
              row["transcript_manifest_id"] == ledger.transcriptManifestID.canonicalString,
              row["analysis_ledger_id"] == ledger.analysisLedgerID.canonicalString,
              row["content_hash_hex"] == ledger.contentHash.lowercaseHex
        else { throw BriefingCoverageError.publicationConflict }
        try validateBriefingLedgerIndex(ledger, in: db)
        return ledger
    }

    private func validateBriefingLedgerIndex(
        _ ledger: BriefingCoverageLedger,
        in db: Database
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT ordinal, segment_object_type, segment_logical_id,
                   segment_revision_id, disposition, safe_reason_code
            FROM briefing_coverage_entries
            WHERE ledger_id = ? ORDER BY ordinal
            """,
            arguments: [ledger.ledgerID.canonicalString]
        )
        guard rows.count == ledger.segments.count else {
            throw BriefingCoverageError.publicationConflict
        }
        for (ordinal, pair) in zip(rows.indices, zip(rows, ledger.segments)) {
            let (row, segment) = pair
            let segmentReference = try SQLiteReferenceCodec.reference(
                objectTypeValue: row["segment_object_type"],
                logicalIDValue: row["segment_logical_id"],
                revisionIDValue: row["segment_revision_id"]
            )
            let disposition: String = row["disposition"]
            let safeReasonCode: String? = row["safe_reason_code"]
            guard (row["ordinal"] as Int) == ordinal,
                  segmentReference == segment.segmentRevision,
                  disposition == segment.disposition.rawValue,
                  safeReasonCode == segment.safeReasonCode
            else { throw BriefingCoverageError.publicationConflict }
            let evidence = try Row.fetchAll(
                db,
                sql: """
                SELECT evidence_object_type, evidence_logical_id, evidence_revision_id
                FROM briefing_coverage_evidence
                WHERE ledger_id = ? AND segment_revision_id = ?
                ORDER BY evidence_object_type, evidence_logical_id, evidence_revision_id
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    segment.segmentRevision.revisionID.canonicalString
                ]
            ).map {
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: $0["evidence_object_type"],
                    logicalIDValue: $0["evidence_logical_id"],
                    revisionIDValue: $0["evidence_revision_id"]
                )
            }
            let outputs = try Row.fetchAll(
                db,
                sql: """
                SELECT output_object_type, output_logical_id, output_revision_id
                FROM briefing_coverage_analysis_outputs
                WHERE ledger_id = ? AND segment_revision_id = ?
                ORDER BY output_object_type, output_logical_id, output_revision_id
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    segment.segmentRevision.revisionID.canonicalString
                ]
            ).map {
                try SQLiteReferenceCodec.reference(
                    objectTypeValue: $0["output_object_type"],
                    logicalIDValue: $0["output_logical_id"],
                    revisionIDValue: $0["output_revision_id"]
                )
            }
            let conclusions = try Row.fetchAll(
                db,
                sql: """
                SELECT output_object_type, output_logical_id, output_revision_id, item_id
                FROM briefing_coverage_conclusions
                WHERE ledger_id = ? AND segment_revision_id = ?
                ORDER BY output_object_type, output_logical_id, output_revision_id, item_id
                """,
                arguments: [
                    ledger.ledgerID.canonicalString,
                    segment.segmentRevision.revisionID.canonicalString
                ]
            ).map {
                try BriefingConclusionReference(
                    outputRevision: SQLiteReferenceCodec.reference(
                        objectTypeValue: $0["output_object_type"],
                        logicalIDValue: $0["output_logical_id"],
                        revisionIDValue: $0["output_revision_id"]
                    ),
                    itemID: BriefingItemID(validating: $0["item_id"] as String)
                )
            }
            guard evidence == segment.evidenceRevisions,
                  outputs == segment.analysisOutputRevisions,
                  conclusions == segment.conclusionReferences
            else { throw BriefingCoverageError.publicationConflict }
        }
    }

    private func requiredFetch<Object: SemanticRevisionContract>(
        _ type: Object.Type,
        reference: SemanticRevisionReference,
        in db: Database
    ) throws -> Object {
        guard reference.objectType == Object.ObjectIDTag.semanticObjectType,
              let value = try fetch(type, revisionID: reference.revisionID, in: db),
              value.revision.logicalID.canonicalString == reference.logicalID.canonicalString
        else { throw AnalysisCoverageError.publicationConflict }
        return value
    }

    private func activeOrExactPosition(
        reference: SemanticRevisionReference,
        in db: Database
    ) throws -> PositionV1 {
        let activeID = try String.fetchOne(
            db,
            sql: """
            SELECT revision_id FROM active_published_revisions
            WHERE object_type = 'position' AND logical_id = ?
            """,
            arguments: [reference.logicalID.canonicalString]
        )
        let revisionID = try activeID.map(RevisionID.init(validating:)) ?? reference.revisionID
        return try requiredFetch(
            PositionV1.self,
            reference: try SemanticRevisionReference(
                logicalID: PositionID(
                    UUID(uuidString: reference.logicalID.canonicalString)!
                ),
                revisionID: revisionID
            ),
            in: db
        )
    }

    private func insertAndActivateManifest(
        _ manifest: TranscriptCoverageManifest,
        in db: Database
    ) throws {
        try manifest.validate()
        let payload = try SQLitePayloadCodec.canonicalData(manifest)
        let payloadDigest = SQLitePayloadCodec.sha256(payload)
        if let existing = try Row.fetchOne(
            db,
            sql: "SELECT canonical_payload, payload_sha256 FROM transcript_coverage_manifests WHERE manifest_id = ?",
            arguments: [manifest.manifestID.canonicalString]
        ) {
            let existingPayload: Data = existing["canonical_payload"]
            let existingDigest: String = existing["payload_sha256"]
            guard existingPayload == payload, existingDigest == payloadDigest else {
                throw TranscriptCoverageError.publicationConflict
            }
        } else {
            guard payload.count <= SQLiteSchema.maximumSemanticPayloadBytes else {
                throw TranscriptCoverageError.publicationConflict
            }
            try db.execute(
                sql: """
                INSERT INTO transcript_coverage_manifests(
                    manifest_id, transcript_set_id, supersedes_manifest_id, meeting_id,
                    canonical_source_revision_id, status, created_at_ms,
                    content_hash_algorithm, content_hash_hex, canonical_payload,
                    payload_sha256, payload_byte_size
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    manifest.manifestID.canonicalString,
                    manifest.transcriptSetID.canonicalString,
                    manifest.supersedesManifestID?.canonicalString,
                    manifest.meetingID.canonicalString,
                    manifest.canonicalSourceRevision.revisionID.canonicalString,
                    manifest.status.rawValue,
                    manifest.createdAt.millisecondsSinceUnixEpoch,
                    manifest.contentHash.algorithm.encodedValue,
                    manifest.contentHash.lowercaseHex,
                    payload,
                    payloadDigest,
                    payload.count
                ]
            )
        }

        let pointer = try Row.fetchOne(
            db,
            sql: "SELECT manifest_id, pointer_version FROM active_transcript_manifests WHERE meeting_id = ?",
            arguments: [manifest.meetingID.canonicalString]
        )
        let currentID: String? = pointer?["manifest_id"]
        if currentID == manifest.manifestID.canonicalString { return }
        guard currentID == manifest.supersedesManifestID?.canonicalString else {
            throw TranscriptCoverageError.publicationConflict
        }
        let nextVersion: Int64 = (pointer?["pointer_version"] as Int64? ?? 0) + 1
        try db.execute(
            sql: """
            INSERT INTO transcript_manifest_events(
                event_id, meeting_id, previous_manifest_id, replacement_manifest_id,
                pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString.lowercased(),
                manifest.meetingID.canonicalString,
                currentID,
                manifest.manifestID.canonicalString,
                nextVersion,
                manifest.createdAt.millisecondsSinceUnixEpoch
            ]
        )
        try db.execute(
            sql: """
            INSERT INTO active_transcript_manifests(
                meeting_id, manifest_id, pointer_version, changed_at_ms
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(meeting_id) DO UPDATE SET
                manifest_id = excluded.manifest_id,
                pointer_version = excluded.pointer_version,
                changed_at_ms = excluded.changed_at_ms
            """,
            arguments: [
                manifest.meetingID.canonicalString,
                manifest.manifestID.canonicalString,
                nextVersion,
                manifest.createdAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    private func decodeManifest(_ row: Row) throws -> TranscriptCoverageManifest {
        let payload: Data = row["canonical_payload"]
        let digest: String = row["payload_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest else {
            throw TranscriptCoverageError.publicationConflict
        }
        let manifest = try JSONDecoder().decode(TranscriptCoverageManifest.self, from: payload)
        try manifest.validate()
        guard try SQLitePayloadCodec.canonicalData(manifest) == payload,
              row["manifest_id"] == manifest.manifestID.canonicalString,
              row["meeting_id"] == manifest.meetingID.canonicalString,
              row["canonical_source_revision_id"]
                  == manifest.canonicalSourceRevision.revisionID.canonicalString,
              row["content_hash_hex"] == manifest.contentHash.lowercaseHex
        else { throw TranscriptCoverageError.publicationConflict }
        return manifest
    }

    private func preflightReplacementManifest(
        _ manifest: TranscriptCoverageManifest,
        changedReference: SemanticRevisionReference
    ) throws {
        try manifest.validate()
        guard manifest.transcriptRevisionReferences.contains(changedReference)
                || manifest.translationRevisionReferences.contains(changedReference),
              let current = try activeTranscriptReview(meetingID: manifest.meetingID),
              manifest.supersedesManifestID == current.manifest.manifestID,
              manifest.transcriptSetID == current.manifest.transcriptSetID,
              manifest.canonicalSourceRevision == current.manifest.canonicalSourceRevision,
              manifest.canonicalFrameCount == current.manifest.canonicalFrameCount
        else { throw TranscriptCoverageError.publicationConflict }
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
        case let value as ParticipantV1:
            meetingID = value.meetingID
        case let value as IssueV1:
            meetingID = value.meetingID
        case let value as PositionV1:
            meetingID = value.meetingID
        case let value as CommitmentV1:
            meetingID = value.meetingID
        case let value as DecisionV1:
            meetingID = value.meetingID
        case let value as InterventionCardV1:
            meetingID = value.meetingID
        case let value as DelegationPositionCardV1:
            meetingID = value.meetingID
        case let value as IssuePositionGraphV1:
            meetingID = value.meetingID
        case let value as BriefingSectionV1:
            meetingID = value.meetingID
        case let value as ValidationReportV1:
            meetingID = value.meetingID
        case let value as FinalBriefingV1:
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
        case .participant:
            _ = try decode(ParticipantV1.self, row: row)
        case .organization:
            _ = try decode(OrganizationV1.self, row: row)
        case .issue:
            _ = try decode(IssueV1.self, row: row)
        case .position:
            _ = try decode(PositionV1.self, row: row)
        case .commitment:
            _ = try decode(CommitmentV1.self, row: row)
        case .decision:
            _ = try decode(DecisionV1.self, row: row)
        case .interventionCard:
            _ = try decode(InterventionCardV1.self, row: row)
        case .delegationPositionCard:
            _ = try decode(DelegationPositionCardV1.self, row: row)
        case .meetingTemplate:
            _ = try decode(MeetingTemplateV1.self, row: row)
        case .issuePositionGraph:
            _ = try decode(IssuePositionGraphV1.self, row: row)
        case .briefingSection:
            _ = try decode(BriefingSectionV1.self, row: row)
        case .validationReport:
            _ = try decode(ValidationReportV1.self, row: row)
        case .finalBriefing:
            _ = try decode(FinalBriefingV1.self, row: row)
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

    private func validateCurrentInputRevisions(
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
