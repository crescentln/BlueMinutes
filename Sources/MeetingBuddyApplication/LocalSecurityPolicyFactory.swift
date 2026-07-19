import Foundation
import MeetingBuddyDomain

public struct LocalSecurityPolicyBundle: Sendable, Equatable {
    public let sensitivityLabel: SensitivityLabelV1
    public let accessPolicy: AccessPolicyV1

    public init(
        sensitivityLabel: SensitivityLabelV1,
        accessPolicy: AccessPolicyV1
    ) throws {
        self.sensitivityLabel = sensitivityLabel
        self.accessPolicy = accessPolicy
    }

    public var modelSnapshot: ModelSecurityPolicySnapshot {
        get throws {
            try ModelSecurityPolicySnapshot(
                sensitivityLabelRevision: SemanticRevisionReference(
                    logicalID: sensitivityLabel.labelID,
                    revisionID: sensitivityLabel.revision.revisionID
                ),
                accessPolicyRevision: SemanticRevisionReference(
                    logicalID: accessPolicy.policyID,
                    revisionID: accessPolicy.revision.revisionID
                ),
                effectiveClassification: accessPolicy.effectiveClassification,
                noOutboundMode: accessPolicy.noOutboundMode,
                localProcessingAllowed: accessPolicy.localProcessingAllowed,
                manualLocalReviewAllowed: accessPolicy.manualLocalReviewAllowed,
                externalProcessingAllowed: accessPolicy.externalProcessingAllowed,
                approvedExternalProviderIdentifiers: accessPolicy
                    .approvedExternalProviderIdentifiers
            )
        }
    }
}

/// Constructs the Task 007 default: published policy metadata, local processing,
/// manual fallback, disabled telemetry, and no external authority.
public struct LocalSecurityPolicyFactory: Sendable {
    public static let defaultTrashRetentionDays: UInt16 = 30

    public init() {}

    public func makeDefault(
        meeting: MeetingProfileV1,
        sensitivityLabelID: SensitivityLabelID,
        sensitivityLabelRevisionID: RevisionID,
        accessPolicyID: AccessPolicyID,
        accessPolicyRevisionID: RevisionID,
        createdAt: UTCInstant
    ) throws -> LocalSecurityPolicyBundle {
        let meetingReference = try SemanticRevisionReference(
            logicalID: meeting.meetingID,
            revisionID: meeting.revision.revisionID
        )
        let labelDraftEnvelope = try RevisionEnvelope(
            logicalID: sensitivityLabelID,
            revisionID: sensitivityLabelRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: [meetingReference],
            dataClassification: meeting.revision.dataClassification
        )
        let labelDraft = try SensitivityLabelV1(
            revision: labelDraftEnvelope,
            meetingID: meeting.meetingID,
            meetingRevision: meetingReference,
            inheritedClassifications: [meeting.revision.dataClassification],
            effectiveClassification: meeting.revision.dataClassification,
            rationale: .inheritedMostRestrictive,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
        let labelEnvelope = try RevisionEnvelope(
            logicalID: sensitivityLabelID,
            revisionID: sensitivityLabelRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: createdAt,
            createdBy: .application,
            publishedAt: createdAt,
            inputRevisions: [meetingReference],
            dataClassification: meeting.revision.dataClassification,
            semanticContentHash: labelDraft.calculatedSemanticContentHash()
        )
        let label = try SensitivityLabelV1(
            revision: labelEnvelope,
            meetingID: meeting.meetingID,
            meetingRevision: meetingReference,
            inheritedClassifications: [meeting.revision.dataClassification],
            effectiveClassification: meeting.revision.dataClassification,
            rationale: .inheritedMostRestrictive,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
        let labelReference = try SemanticRevisionReference(
            logicalID: label.labelID,
            revisionID: label.revision.revisionID
        )
        let policyDraftEnvelope = try RevisionEnvelope(
            logicalID: accessPolicyID,
            revisionID: accessPolicyRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: [labelReference],
            dataClassification: label.effectiveClassification
        )
        let policyDraft = try accessPolicy(
            revision: policyDraftEnvelope,
            meetingID: meeting.meetingID,
            labelReference: labelReference,
            classification: label.effectiveClassification
        )
        let policyEnvelope = try RevisionEnvelope(
            logicalID: accessPolicyID,
            revisionID: accessPolicyRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: createdAt,
            createdBy: .application,
            publishedAt: createdAt,
            inputRevisions: [labelReference],
            dataClassification: label.effectiveClassification,
            semanticContentHash: policyDraft.calculatedSemanticContentHash()
        )
        let policy = try accessPolicy(
            revision: policyEnvelope,
            meetingID: meeting.meetingID,
            labelReference: labelReference,
            classification: label.effectiveClassification
        )
        try SecurityPolicyGraphValidator.validate(
            meeting: meeting,
            sensitivityLabel: label,
            accessPolicy: policy
        )
        return try LocalSecurityPolicyBundle(
            sensitivityLabel: label,
            accessPolicy: policy
        )
    }

    private func accessPolicy(
        revision: RevisionEnvelope<AccessPolicyIDTag>,
        meetingID: MeetingID,
        labelReference: SemanticRevisionReference,
        classification: DataClassification
    ) throws -> AccessPolicyV1 {
        try AccessPolicyV1(
            revision: revision,
            meetingID: meetingID,
            sensitivityLabelRevision: labelReference,
            effectiveClassification: classification,
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
            minimumTrashRetentionDays: Self.defaultTrashRetentionDays,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }
}
