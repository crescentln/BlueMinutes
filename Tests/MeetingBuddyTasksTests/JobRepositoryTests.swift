import GRDB
import MeetingBuddyApplication
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct JobRepositoryTests {
    @Test
    func jobSnapshotsRoundTripWithOptimisticLockingAndImmutableStateEvents() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let request = try makeTaskRequest(
            suffix: 11,
            jobType: JobType("synthetic-roundtrip"),
            totalUnitCount: 4
        )
        let lease = try await workspace.temporaryStorage.allocateDirectory(
            for: request.jobID,
            diskBudgetBytes: request.diskBudgetBytes
        )
        let created = try JobRecord(
            request: request,
            lease: lease,
            createdAt: testInstant(1_800_000_200_000)
        )
        try await workspace.repository.create(created)
        #expect(try await workspace.repository.job(id: created.jobID) == created)

        let running = try created.transitioning(
            to: .running,
            at: testInstant(1_800_000_200_001)
        )
        try await workspace.repository.replace(
            running,
            expectedVersion: created.recordVersion,
            changedAt: testInstant(1_800_000_200_001)
        )
        let progressed = try running.updatingProgress(
            JobProgress(completedUnitCount: 2, totalUnitCount: 4, currentNode: "halfway"),
            checkpoint: nil
        )
        try await workspace.repository.replace(
            progressed,
            expectedVersion: running.recordVersion,
            changedAt: testInstant(1_800_000_200_002)
        )
        let succeeded = try progressed.transitioning(
            to: .succeeded,
            at: testInstant(1_800_000_200_003)
        )
        try await workspace.repository.replace(
            succeeded,
            expectedVersion: progressed.recordVersion,
            changedAt: testInstant(1_800_000_200_003)
        )
        #expect(try await workspace.repository.job(id: created.jobID) == succeeded)

        await #expect(throws: JobContractError.self) {
            try await workspace.repository.replace(
                succeeded,
                expectedVersion: running.recordVersion,
                changedAt: testInstant(1_800_000_200_004)
            )
        }
        let events = try await workspace.store.databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT previous_state, replacement_state
                FROM job_state_events
                WHERE job_id = ?
                ORDER BY sequence
                """,
                arguments: [created.jobID.canonicalString]
            ).map { row in
                (row["previous_state"] as String?, row["replacement_state"] as String)
            }
        }
        #expect(events.map { $0.0 } == [nil, "queued", "running"])
        #expect(events.map { $0.1 } == ["queued", "running", "succeeded"])
        await #expect(throws: (any Error).self) {
            try await workspace.store.databasePool.write { db in
                try db.execute(
                    sql: """
                    UPDATE job_state_events SET replacement_state = 'failed'
                    WHERE job_id = ? AND sequence = 1
                    """,
                    arguments: [created.jobID.canonicalString]
                )
            }
        }
    }

    @Test
    func dependencyAndIdempotencyIndexesFailClosed() async throws {
        let workspace = try TaskTestWorkspace()
        defer { workspace.cleanup() }
        let jobType = try JobType("indexed-job")
        let firstRequest = try makeTaskRequest(suffix: 21, jobType: jobType)
        let firstLease = try await workspace.temporaryStorage.allocateDirectory(
            for: firstRequest.jobID,
            diskBudgetBytes: firstRequest.diskBudgetBytes
        )
        let first = try JobRecord(
            request: firstRequest,
            lease: firstLease,
            createdAt: testInstant(1_800_000_300_000)
        )
        try await workspace.repository.create(first)

        let dependentRequest = try makeTaskRequest(
            suffix: 22,
            jobType: JobType("dependent-job"),
            dependencies: [first.jobID]
        )
        let dependentLease = try await workspace.temporaryStorage.allocateDirectory(
            for: dependentRequest.jobID,
            diskBudgetBytes: dependentRequest.diskBudgetBytes
        )
        let dependent = try JobRecord(
            request: dependentRequest,
            lease: dependentLease,
            createdAt: testInstant(1_800_000_300_001)
        )
        try await workspace.repository.create(dependent)

        let duplicateRequest = try JobRequest(
            jobID: testJobID(23),
            jobType: firstRequest.jobType,
            origin: .application,
            requestedBy: JobRequester("meetingbuddy-test"),
            dataClassification: .internal,
            idempotencyKey: firstRequest.idempotencyKey,
            diskBudgetBytes: 65_536
        )
        let duplicateLease = try await workspace.temporaryStorage.allocateDirectory(
            for: duplicateRequest.jobID,
            diskBudgetBytes: duplicateRequest.diskBudgetBytes
        )
        let duplicate = try JobRecord(
            request: duplicateRequest,
            lease: duplicateLease,
            createdAt: testInstant(1_800_000_300_002)
        )
        await #expect(throws: JobContractError.self) {
            try await workspace.repository.create(duplicate)
        }
        #expect(
            try await workspace.repository.job(
                jobType: first.jobType,
                idempotencyKey: first.idempotencyKey
            ) == first
        )
    }
}
