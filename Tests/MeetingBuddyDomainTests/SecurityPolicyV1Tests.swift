import Foundation
import Testing
@testable import MeetingBuddyDomain

struct SecurityPolicyV1Tests {
    @Test
    func independentPolicyContractsBindExactRevisionsAndMostRestrictiveLabel() throws {
        let meeting = try Task003BFixtures.meetingProfile()
        let meetingReference = try Task003BFixtures.reference(
            meeting.meetingID,
            meeting.revision.revisionID
        )
        let labelID = Task003BFixtures.id(701, SensitivityLabelID.self)
        let labelRevisionID = Task003BFixtures.id(702, RevisionID.self)
        let label = try SensitivityLabelV1(
            revision: Task003BFixtures.envelope(
                logicalID: labelID,
                revisionID: labelRevisionID,
                inputRevisions: [meetingReference],
                classification: .internal
            ),
            meetingID: meeting.meetingID,
            meetingRevision: meetingReference,
            inheritedClassifications: [.public, .internal],
            effectiveClassification: .internal,
            rationale: .inheritedMostRestrictive,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
        let labelReference = try Task003BFixtures.reference(
            label.labelID,
            label.revision.revisionID
        )
        let policy = try AccessPolicyV1(
            revision: Task003BFixtures.envelope(
                logicalID: Task003BFixtures.id(703, AccessPolicyID.self),
                revisionID: Task003BFixtures.id(704, RevisionID.self),
                inputRevisions: [labelReference],
                classification: .internal
            ),
            meetingID: meeting.meetingID,
            sensitivityLabelRevision: labelReference,
            effectiveClassification: .internal,
            localProcessingAllowed: true,
            manualLocalReviewAllowed: true,
            externalProcessingAllowed: false,
            organizationAllowsExternalProcessing: false,
            deploymentAllowsExternalProcessing: false,
            destinationAllowsExternalProcessing: false,
            retentionAllowsExternalProcessing: false,
            requiresVisibleUserAuthorization: true,
            approvedExternalProviderIdentifiers: [],
            noOutboundMode: true,
            telemetryMode: .disabled,
            localExportAllowed: true,
            trashAllowed: true,
            minimumTrashRetentionDays: 30,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
        try SecurityPolicyGraphValidator.validate(
            meeting: meeting,
            sensitivityLabel: label,
            accessPolicy: policy
        )
        #expect(label.revision.objectType == .sensitivityLabel)
        #expect(policy.revision.objectType == .accessPolicy)
        #expect(policy.noOutboundMode)
        #expect(policy.telemetryMode == .disabled)

        let labelRoundTrip = try CanonicalJSON.decodeValidated(
            SensitivityLabelV1.self,
            from: CanonicalJSON.encodeValidated(label)
        )
        let policyRoundTrip = try CanonicalJSON.decodeValidated(
            AccessPolicyV1.self,
            from: CanonicalJSON.encodeValidated(policy)
        )
        #expect(labelRoundTrip == label)
        #expect(policyRoundTrip == policy)
    }

    @Test
    func policyContractsFailClosedOnDowngradeAndConflictingOutboundAuthority() throws {
        let meetingReference = try Task003BFixtures.reference(
            Task003BFixtures.meetingID,
            Task003BFixtures.meetingRevisionID
        )
        #expect(throws: DomainValidationError.self) {
            _ = try SensitivityLabelV1(
                revision: Task003BFixtures.envelope(
                    logicalID: Task003BFixtures.id(705, SensitivityLabelID.self),
                    revisionID: Task003BFixtures.id(706, RevisionID.self),
                    inputRevisions: [meetingReference],
                    classification: .internal
                ),
                meetingID: Task003BFixtures.meetingID,
                meetingRevision: meetingReference,
                inheritedClassifications: [.internal, .restricted],
                effectiveClassification: .internal,
                rationale: .inheritedMostRestrictive,
                reviewStatus: .unreviewed,
                userConfirmed: false
            )
        }

        let labelReference = try Task003BFixtures.reference(
            Task003BFixtures.id(707, SensitivityLabelID.self),
            Task003BFixtures.id(708, RevisionID.self)
        )
        #expect(throws: DomainValidationError.self) {
            _ = try AccessPolicyV1(
                revision: Task003BFixtures.envelope(
                    logicalID: Task003BFixtures.id(709, AccessPolicyID.self),
                    revisionID: Task003BFixtures.id(710, RevisionID.self),
                    inputRevisions: [labelReference],
                    classification: .internal
                ),
                meetingID: Task003BFixtures.meetingID,
                sensitivityLabelRevision: labelReference,
                effectiveClassification: .internal,
                localProcessingAllowed: true,
                manualLocalReviewAllowed: true,
                externalProcessingAllowed: true,
                organizationAllowsExternalProcessing: true,
                deploymentAllowsExternalProcessing: true,
                destinationAllowsExternalProcessing: true,
                retentionAllowsExternalProcessing: true,
                requiresVisibleUserAuthorization: true,
                approvedExternalProviderIdentifiers: ["synthetic-provider"],
                noOutboundMode: true,
                telemetryMode: .disabled,
                localExportAllowed: true,
                trashAllowed: true,
                minimumTrashRetentionDays: 30,
                reviewStatus: .unreviewed,
                userConfirmed: false
            )
        }
    }
}
