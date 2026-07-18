import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct RepositoryRoundTripTests {
    @Test
    func persistsAllTask003ContractsAndExactDependenciesAcrossRestart() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        var store: SQLitePersistenceStore? = try workspace.makeStore()
        let record = try PersistenceFixtures.managedAssetRecord(workspace: workspace)
        try store?.registerManagedAsset(record)

        let source = try PersistenceFixtures.sourceAsset(record: record)
        let meeting = try PersistenceFixtures.meetingProfile()
        let transcript = try PersistenceFixtures.transcript(source: source)
        let translation = try PersistenceFixtures.translation(transcript: transcript)
        let actor = try PersistenceFixtures.actor()
        let represented = try PersistenceFixtures.actor(
            logicalID: PersistenceFixtures.representedActorID,
            revisionID: PersistenceFixtures.representedActorRevisionID,
            identity: .internationalOrganization(displayName: "Synthetic Organization")
        )
        let capacity = try PersistenceFixtures.capacity(speaker: actor, represented: represented)
        let evidence = try PersistenceFixtures.evidence(transcript: transcript)
        let unresolvedEvidence = try PersistenceFixtures.unresolvedNoteEvidence()
        let assignment = try PersistenceFixtures.assignment(
            transcript: transcript,
            actor: actor,
            capacity: capacity,
            evidence: evidence
        )

        try store?.insert(meeting)
        try store?.insert(source)
        try store?.insert(transcript)
        try store?.insert(translation)
        try store?.insert(actor)
        try store?.insert(represented)
        try store?.insert(capacity)
        try store?.insert(evidence)
        try store?.insert(unresolvedEvidence)
        try store?.insert(assignment)

        let initialEdges = try #require(store).dependencyEdges()
        #expect(initialEdges.contains { $0.upstreamRevision.revisionID == PersistenceFixtures.noteRevisionID })
        #expect(try #require(store).allRevisionReferences().count == 10)

        try #require(store).close()
        store = nil
        store = try workspace.makeStore()
        let reopened = try #require(store)

        #expect(try expectCanonicalRoundTrip(source, from: reopened))
        #expect(try expectCanonicalRoundTrip(meeting, from: reopened))
        #expect(try expectCanonicalRoundTrip(transcript, from: reopened))
        #expect(try expectCanonicalRoundTrip(translation, from: reopened))
        #expect(try expectCanonicalRoundTrip(actor, from: reopened))
        #expect(try expectCanonicalRoundTrip(represented, from: reopened))
        #expect(try expectCanonicalRoundTrip(capacity, from: reopened))
        #expect(try expectCanonicalRoundTrip(evidence, from: reopened))
        #expect(try expectCanonicalRoundTrip(unresolvedEvidence, from: reopened))
        #expect(try expectCanonicalRoundTrip(assignment, from: reopened))
        #expect(try reopened.dependencyEdges() == initialEdges)
        #expect(try reopened.managedAsset(storageObjectID: record.storageObjectID) == record)
        try reopened.close()
    }

    @Test
    func exactReinsertIsIdempotentButRevisionMutationAndDeletionFailClosed() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let meeting = try PersistenceFixtures.meetingProfile()

        try store.insert(meeting)
        try store.insert(meeting)
        #expect(try store.revisions(MeetingProfileV1.self, logicalID: meeting.meetingID).count == 1)

        let conflicting = try PersistenceFixtures.meetingProfile(title: "Mutated bytes under reused ID")
        #expect(throws: PersistenceContractError.self) {
            try store.insert(conflicting)
        }

        #expect(throws: (any Error).self) {
            try store.databasePool.write { db in
                try db.execute(
                    sql: "UPDATE semantic_revisions SET canonical_payload = ? WHERE revision_id = ?",
                    arguments: [Data("{}".utf8), meeting.revision.revisionID.canonicalString]
                )
            }
        }
        #expect(throws: (any Error).self) {
            try store.databasePool.write { db in
                try db.execute(
                    sql: "DELETE FROM semantic_revisions WHERE revision_id = ?",
                    arguments: [meeting.revision.revisionID.canonicalString]
                )
            }
        }
        #expect(try store.fetch(MeetingProfileV1.self, revisionID: meeting.revision.revisionID) == meeting)
    }

    @Test
    func sourceBytesNeverEnterSQLiteFiles() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        let record = try PersistenceFixtures.managedAssetRecord(workspace: workspace)
        try store.registerManagedAsset(record)
        try store.insert(PersistenceFixtures.meetingProfile())
        try store.insert(PersistenceFixtures.sourceAsset(record: record))
        _ = try store.databasePool.writeWithoutTransaction { db in
            try db.checkpoint(.truncate)
        }
        try store.close()

        let databaseDirectory = workspace.descriptor.layout.database
        let files = try FileManager.default.contentsOfDirectory(
            at: databaseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: file)
            #expect(data.range(of: PersistenceFixtures.sourceBytes) == nil)
        }
    }

    @Test
    func meetingProfileMustBelongToTheOpenedWorkspace() throws {
        let foreignWorkspaceID = PersistenceFixtures.id(102, WorkspaceID.self)
        let workspace = try DisposableMeetingBuddyWorkspace(workspaceID: foreignWorkspaceID)
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        #expect(throws: PersistenceContractError.self) {
            try store.insert(PersistenceFixtures.meetingProfile())
        }
        #expect(try store.allRevisionReferences().isEmpty)

        let owned = try PersistenceFixtures.meetingProfile(workspaceID: foreignWorkspaceID)
        try store.insert(owned)
        #expect(try store.fetch(MeetingProfileV1.self, revisionID: owned.revision.revisionID) == owned)
    }
}
