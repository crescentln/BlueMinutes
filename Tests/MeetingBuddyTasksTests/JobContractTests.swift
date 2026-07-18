import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

struct JobContractTests {
    @Test
    func stateMachineRejectsSkippedAndReverseTransitions() throws {
        #expect(JobStateMachine.allows(from: .queued, to: .running))
        #expect(JobStateMachine.allows(from: .running, to: .pauseRequested))
        #expect(JobStateMachine.allows(from: .pauseRequested, to: .paused))
        #expect(JobStateMachine.allows(from: .pauseRequested, to: .succeeded))
        #expect(JobStateMachine.allows(from: .paused, to: .running))
        #expect(JobStateMachine.allows(from: .running, to: .succeeded))
        #expect(JobStateMachine.allows(from: .cancellationRequested, to: .succeeded))
        #expect(!JobStateMachine.allows(from: .queued, to: .succeeded))
        #expect(!JobStateMachine.allows(from: .succeeded, to: .running))
        #expect(!JobStateMachine.allows(from: .failed, to: .running))
    }

    @Test
    func jobRequestRejectsUnsafeRoutesPathsAndDuplicateDependencies() throws {
        let jobID = testJobID(1)
        let dependency = testJobID(2)
        #expect(throws: JobContractError.self) {
            _ = try JobRequest(
                jobID: jobID,
                jobType: JobType("transcription"),
                origin: .application,
                requestedBy: JobRequester("meetingbuddy"),
                dependencyJobIDs: [dependency, dependency],
                dataClassification: .internal,
                idempotencyKey: testIdempotencyKey(1),
                diskBudgetBytes: 1_024
            )
        }
        #expect(throws: JobContractError.self) {
            _ = try JobRequest(
                jobID: jobID,
                jobType: JobType("transcription"),
                origin: .application,
                requestedBy: JobRequester("meetingbuddy"),
                privacyRoute: .approvedCloud,
                dataClassification: .restricted,
                idempotencyKey: testIdempotencyKey(2),
                diskBudgetBytes: 1_024
            )
        }
        #expect(throws: JobContractError.self) {
            _ = try JobType("../../feature-task")
        }
    }
}

func testJobID(_ suffix: Int) -> JobID {
    JobID(UUID(uuidString: String(format: "4b000000-0000-0000-0000-%012d", suffix))!)
}

func testIdempotencyKey(_ byte: UInt8) -> JobIdempotencyKey {
    try! JobIdempotencyKey(lowercaseHex: String(repeating: String(format: "%02x", byte), count: 32))
}
