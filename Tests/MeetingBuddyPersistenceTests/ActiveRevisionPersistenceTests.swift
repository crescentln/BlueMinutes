import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct ActiveRevisionPersistenceTests {
    @Test
    func activePointerAndTransitiveStaleMarksSurviveRestart() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        var store: SQLitePersistenceStore? = try workspace.makeStore()
        let repository = try #require(store)

        let record = try PersistenceFixtures.managedAssetRecord(workspace: workspace)
        try repository.registerManagedAsset(record)
        let source = try PersistenceFixtures.sourceAsset(record: record)
        let oldMeeting = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.meetingRevisionID,
            title: "Published baseline",
            publishedAt: PersistenceFixtures.publishedAt
        )
        let oldReference = try PersistenceFixtures.reference(
            oldMeeting.meetingID,
            oldMeeting.revision.revisionID
        )
        let actor = try PersistenceFixtures.actor(extraInputs: [oldReference])
        let represented = try PersistenceFixtures.actor(
            logicalID: PersistenceFixtures.representedActorID,
            revisionID: PersistenceFixtures.representedActorRevisionID,
            identity: .internationalOrganization(displayName: "Synthetic Organization")
        )
        let transcript = try PersistenceFixtures.transcript(source: source, extraInputs: [oldReference])
        let translation = try PersistenceFixtures.translation(transcript: transcript)
        let capacity = try PersistenceFixtures.capacity(speaker: actor, represented: represented)
        let evidence = try PersistenceFixtures.evidence(transcript: transcript)
        let assignment = try PersistenceFixtures.assignment(
            transcript: transcript,
            actor: actor,
            capacity: capacity,
            evidence: evidence
        )

        try repository.insert(oldMeeting)
        try repository.insert(source)
        try repository.insert(actor)
        try repository.insert(represented)
        try repository.insert(transcript)
        try repository.insert(translation)
        try repository.insert(capacity)
        try repository.insert(evidence)
        try repository.insert(assignment)

        let oldSelection = try ActivePublishedRevisionSelection(
            logicalID: oldMeeting.meetingID,
            revisionID: oldMeeting.revision.revisionID
        )
        let initial = try repository.activate(
            oldSelection,
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.publishedAt
        )
        #expect(initial.marks.isEmpty)

        let replacement = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.replacementMeetingRevisionID,
            title: "Published replacement",
            publishedAt: PersistenceFixtures.replacementPublishedAt,
            supersedes: oldMeeting.revision.revisionID
        )
        try repository.insert(replacement)
        let replacementSelection = try ActivePublishedRevisionSelection(
            logicalID: replacement.meetingID,
            revisionID: replacement.revision.revisionID
        )
        let plan = try repository.activate(
            replacementSelection,
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: oldMeeting.revision.revisionID,
            markedAt: PersistenceFixtures.replacementPublishedAt
        )

        let expectedStaleIDs: Set<RevisionID> = [
            actor.revision.revisionID,
            transcript.revision.revisionID,
            translation.revision.revisionID,
            capacity.revision.revisionID,
            evidence.revision.revisionID,
            assignment.revision.revisionID
        ]
        #expect(Set(plan.marks.map { $0.affectedRevision.revisionID }) == expectedStaleIDs)
        #expect(try repository.fetch(MeetingProfileV1.self, revisionID: oldMeeting.revision.revisionID) == oldMeeting)

        #expect(throws: (any Error).self) {
            try repository.databasePool.write { db in
                try db.execute(
                    sql: """
                    UPDATE revision_current_state
                    SET currency_state = 'current', last_stale_at_ms = NULL
                    WHERE revision_id = ?
                    """,
                    arguments: [assignment.revision.revisionID.canonicalString]
                )
            }
        }

        #expect(throws: PersistenceContractError.self) {
            try repository.activate(
                oldSelection,
                as: MeetingProfileV1.self,
                expectedCurrentRevisionID: oldMeeting.revision.revisionID,
                markedAt: PersistenceFixtures.replacementPublishedAt
            )
        }

        try repository.close()
        store = nil
        store = try workspace.makeStore()
        let reopened = try #require(store)
        let activeValue = try reopened.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: replacement.meetingID
        )
        let active = try #require(activeValue)
        #expect(active.revision == replacement)
        #expect(active.staleMarks.isEmpty)

        let assignmentReference = try SemanticRevisionReference(
            logicalID: PersistenceFixtures.assignmentID,
            revisionID: assignment.revision.revisionID
        )
        let assignmentMarks = try reopened.staleMarks(for: assignmentReference)
        #expect(assignmentMarks.count == 1)
        #expect(assignmentMarks.first?.mark.affectedRevision == assignmentReference)
        try reopened.close()
    }

    @Test
    func lateDependentCannotActivateThroughStaleAncestor() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        let oldMeeting = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.meetingRevisionID,
            title: "Late dependency baseline",
            publishedAt: PersistenceFixtures.publishedAt
        )
        let oldMeetingReference = try PersistenceFixtures.reference(
            oldMeeting.meetingID,
            oldMeeting.revision.revisionID
        )
        let staleActor = try PersistenceFixtures.actor(
            logicalID: PersistenceFixtures.id(110, ActorID.self),
            revisionID: PersistenceFixtures.id(111, RevisionID.self),
            extraInputs: [oldMeetingReference]
        )
        try store.insert(oldMeeting)
        try store.insert(staleActor)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: oldMeeting.meetingID,
                revisionID: oldMeeting.revision.revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.publishedAt
        )

        let replacement = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.replacementMeetingRevisionID,
            title: "Late dependency replacement",
            publishedAt: PersistenceFixtures.replacementPublishedAt,
            supersedes: oldMeeting.revision.revisionID
        )
        try store.insert(replacement)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: replacement.meetingID,
                revisionID: replacement.revision.revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: oldMeeting.revision.revisionID,
            markedAt: PersistenceFixtures.replacementPublishedAt
        )
        let staleActorReference = try PersistenceFixtures.reference(
            staleActor.actorID,
            staleActor.revision.revisionID
        )
        #expect(try store.staleMarks(for: staleActorReference).count == 1)

        let intermediate = try PersistenceFixtures.actor(
            logicalID: PersistenceFixtures.id(112, ActorID.self),
            revisionID: PersistenceFixtures.id(113, RevisionID.self),
            extraInputs: [staleActorReference]
        )
        let intermediateReference = try PersistenceFixtures.reference(
            intermediate.actorID,
            intermediate.revision.revisionID
        )
        try store.insert(intermediate)

        let targetLogicalID = PersistenceFixtures.id(114, ActorID.self)
        let targetRevisionID = PersistenceFixtures.id(115, RevisionID.self)
        let draftTarget = try PersistenceFixtures.actor(
            logicalID: targetLogicalID,
            revisionID: targetRevisionID,
            extraInputs: [intermediateReference]
        )
        let publishedTarget = try ActorV1(
            revision: PersistenceFixtures.envelope(
                logicalID: targetLogicalID,
                revisionID: targetRevisionID,
                lifecycle: .published,
                validation: .valid,
                publishedAt: PersistenceFixtures.replacementPublishedAt,
                inputs: [intermediateReference],
                semanticHash: draftTarget.calculatedSemanticContentHash()
            ),
            identity: draftTarget.identity,
            canonicalAliases: draftTarget.canonicalAliases,
            affiliationRevision: draftTarget.affiliationRevision,
            reviewStatus: draftTarget.reviewStatus,
            userConfirmed: draftTarget.userConfirmed
        )
        try store.insert(publishedTarget)
        let targetSelection = try ActivePublishedRevisionSelection(
            logicalID: targetLogicalID,
            revisionID: targetRevisionID
        )

        #expect(throws: PersistenceContractError.self) {
            try store.activate(
                targetSelection,
                as: ActorV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: PersistenceFixtures.replacementPublishedAt
            )
        }
        #expect(throws: (any Error).self) {
            try store.databasePool.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO active_published_revisions(
                        object_type, logical_id, revision_id, pointer_version, changed_at_ms
                    ) VALUES ('actor', ?, ?, 1, ?)
                    """,
                    arguments: [
                        targetLogicalID.canonicalString,
                        targetRevisionID.canonicalString,
                        PersistenceFixtures.replacementPublishedAt.millisecondsSinceUnixEpoch
                    ]
                )
            }
        }
        #expect(
            try store.activeRevisionState(ActorV1.self, logicalID: targetLogicalID) == nil
        )
    }

    @Test
    func staleWriteFailureRollsBackPointerEventAndStateTogether() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        let oldMeeting = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.meetingRevisionID,
            title: "Atomic old",
            publishedAt: PersistenceFixtures.publishedAt
        )
        let oldReference = try PersistenceFixtures.reference(
            oldMeeting.meetingID,
            oldMeeting.revision.revisionID
        )
        let dependent = try PersistenceFixtures.actor(extraInputs: [oldReference])
        try store.insert(oldMeeting)
        try store.insert(dependent)
        let oldSelection = try ActivePublishedRevisionSelection(
            logicalID: oldMeeting.meetingID,
            revisionID: oldMeeting.revision.revisionID
        )
        _ = try store.activate(
            oldSelection,
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.publishedAt
        )

        let replacement = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.replacementMeetingRevisionID,
            title: "Atomic replacement",
            publishedAt: PersistenceFixtures.replacementPublishedAt,
            supersedes: oldMeeting.revision.revisionID
        )
        try store.insert(replacement)
        try store.databasePool.write { db in
            try db.execute(sql: """
                CREATE TRIGGER test_reject_stale_event
                BEFORE INSERT ON stale_events
                BEGIN
                    SELECT RAISE(ABORT, 'intentional atomicity probe');
                END
                """)
        }

        let replacementSelection = try ActivePublishedRevisionSelection(
            logicalID: replacement.meetingID,
            revisionID: replacement.revision.revisionID
        )
        #expect(throws: PersistenceContractError.self) {
            try store.activate(
                replacementSelection,
                as: MeetingProfileV1.self,
                expectedCurrentRevisionID: oldMeeting.revision.revisionID,
                markedAt: PersistenceFixtures.replacementPublishedAt
            )
        }

        let activeValue = try store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: oldMeeting.meetingID
        )
        let active = try #require(activeValue)
        #expect(active.revision == oldMeeting)
        let dependentReference = try PersistenceFixtures.reference(
            dependent.actorID,
            dependent.revision.revisionID
        )
        #expect(try store.staleMarks(for: dependentReference).isEmpty)
        let eventCount = try store.databasePool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM active_revision_events")
        }
        #expect(eventCount == 1)
    }

    @Test
    func jobSuccessAtomicallyRejectsInputSupersededAfterExecutionStarted() async throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "stale-job-publication")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        let original = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.meetingRevisionID,
            title: "Job input baseline",
            publishedAt: PersistenceFixtures.publishedAt
        )
        let replacement = try PersistenceFixtures.publishedMeeting(
            revisionID: PersistenceFixtures.replacementMeetingRevisionID,
            title: "Job input replacement",
            publishedAt: PersistenceFixtures.replacementPublishedAt,
            supersedes: original.revision.revisionID
        )
        try store.insert(original)
        try store.insert(replacement)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: original.meetingID,
                revisionID: original.revision.revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.publishedAt
        )
        let input = try PersistenceFixtures.reference(
            original.meetingID,
            original.revision.revisionID
        )
        let request = try JobRequest(
            jobType: JobType("stale-input-probe"),
            meetingID: original.meetingID,
            origin: .application,
            requestedBy: JobRequester("meetingbuddy-test"),
            inputRevisionIDs: [input],
            dataClassification: .internal,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: String(repeating: "a", count: 64)),
            totalUnitCount: 1,
            diskBudgetBytes: 4_096
        )
        let temporaryStorage = LocalTaskTemporaryStorage(workspace: workspace.descriptor)
        let lease = try await temporaryStorage.allocateDirectory(
            for: request.jobID,
            diskBudgetBytes: request.diskBudgetBytes
        )
        let repository = SQLiteJobRepository(store: store)
        let queued = try JobRecord(
            request: request,
            lease: lease,
            createdAt: PersistenceFixtures.publishedAt
        )
        try await repository.create(queued)
        let running = try queued.transitioning(
            to: .running,
            at: PersistenceFixtures.replacementPublishedAt
        )
        try await repository.replace(
            running,
            expectedVersion: queued.recordVersion,
            changedAt: PersistenceFixtures.replacementPublishedAt
        )

        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: replacement.meetingID,
                revisionID: replacement.revision.revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: original.revision.revisionID,
            markedAt: PersistenceFixtures.replacementPublishedAt
        )
        let finishedAt = try UTCInstant(
            millisecondsSinceUnixEpoch:
                PersistenceFixtures.replacementPublishedAt.millisecondsSinceUnixEpoch + 1
        )
        let succeeded = try running.transitioning(to: .succeeded, at: finishedAt)
        await #expect(throws: JobContractError.self) {
            try await repository.replace(
                succeeded,
                expectedVersion: running.recordVersion,
                changedAt: finishedAt
            )
        }
        await #expect(throws: JobContractError.self) {
            try await repository.validateInputRevisionsAreCurrent([input])
        }
        let persisted = try #require(await repository.job(id: request.jobID))
        #expect(persisted.state == .running)
        let successfulEvents = try await store.databasePool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM job_state_events
                WHERE job_id = ? AND replacement_state = 'succeeded'
                """,
                arguments: [request.jobID.canonicalString]
            )
        }
        #expect(successfulEvents == 0)
    }
}
