import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct SecurityPolicyPersistenceTests {
    @Test
    func exactSecurityPoliciesRoundTripActivateAndRecoverCanonically() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "security-policy")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let meeting = try PersistenceFixtures.meetingProfile()
        try store.insert(meeting)

        let labelID = try SensitivityLabelID(validating: meeting.meetingID.canonicalString)
        let policyID = try AccessPolicyID(validating: meeting.meetingID.canonicalString)
        let bundle = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: labelID,
            sensitivityLabelRevisionID: PersistenceFixtures.id(101, RevisionID.self),
            accessPolicyID: policyID,
            accessPolicyRevisionID: PersistenceFixtures.id(102, RevisionID.self),
            createdAt: PersistenceFixtures.createdAt
        )
        try store.insert(bundle.sensitivityLabel)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: labelID,
                revisionID: bundle.sensitivityLabel.revision.revisionID
            ),
            as: SensitivityLabelV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.createdAt
        )
        try store.insert(bundle.accessPolicy)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: policyID,
                revisionID: bundle.accessPolicy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: PersistenceFixtures.createdAt
        )

        #expect(
            try store.fetch(
                SensitivityLabelV1.self,
                revisionID: bundle.sensitivityLabel.revision.revisionID
            ) == bundle.sensitivityLabel
        )
        #expect(
            try store.activeRevisionState(
                AccessPolicyV1.self,
                logicalID: policyID
            )?.revision == bundle.accessPolicy
        )
        let snapshot = try bundle.modelSnapshot
        #expect(snapshot.noOutboundMode)
        #expect(snapshot.effectiveClassification == meeting.revision.dataClassification)
        #expect(snapshot.approvedExternalProviderIdentifiers.isEmpty)

        let recovery = SQLiteRecoveryService(store: store, storage: workspace.storage)
        let descriptor = try recovery.createRecoverySnapshot(
            createdAt: PersistenceFixtures.publishedAt
        )
        try recovery.verifyRecoverySnapshot(descriptor)
        #expect(descriptor.schemaVersion == SQLiteSchema.currentVersion)
    }
}
