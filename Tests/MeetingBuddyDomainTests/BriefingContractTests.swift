import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct BriefingContractTests {
    @Test
    func structuredTemplateRoundTripsAndRejectsIncompatibleInputSchema() throws {
        let template = try briefingTemplate()
        let bytes = try CanonicalJSON.encodeValidated(template)
        #expect(
            try CanonicalJSON.decodeValidated(MeetingTemplateV1.self, from: bytes)
                == template
        )
        #expect(template.meetingType == .multilateralDiplomaticMeeting)
        #expect(template.compatibleInputSchemaVersions == [.v1])
        #expect(template.sections.map(\.sectionType) == [
            .meetingOverview, .majorIssues, .majorDelegations
        ])
        #expect(template.validationRules.allSatisfy { $0.blocking })
        #expect(template.rendererModules.count == 1)

        #expect(throws: DomainValidationError.self) {
            _ = try MeetingTemplateV1(
                revision: template.revision,
                templateKey: template.templateKey,
                displayName: template.displayName,
                meetingType: template.meetingType,
                requiredSemanticObjectTypes: template.requiredSemanticObjectTypes,
                compatibleInputSchemaVersions: [
                    .v1,
                    SchemaVersion(major: 2, minor: 0)
                ],
                sections: template.sections,
                validationRules: template.validationRules,
                rendererModules: template.rendererModules,
                reviewStatus: template.reviewStatus,
                userConfirmed: template.userConfirmed
            )
        }
    }

    @Test
    func issuePositionCellPreservesEveryExactPositionAndQualification() throws {
        let evidence = try SemanticRevisionReference(
            logicalID: briefingDomainID(20, EvidenceID.self),
            revisionID: briefingDomainID(21, RevisionID.self)
        )
        let representedEntity = try SemanticRevisionReference(
            logicalID: briefingDomainID(22, OrganizationID.self),
            revisionID: briefingDomainID(23, RevisionID.self)
        )
        let positions = try [24, 26].map { suffix in
            try SemanticRevisionReference(
                logicalID: briefingDomainID(suffix, PositionID.self),
                revisionID: briefingDomainID(suffix + 1, RevisionID.self)
            )
        }
        let supported = try EvidenceLinkedClaim(
            text: "Supports the reporting mechanism.",
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidence],
            confidence: ConfidenceScore(millionths: 800_000)
        )
        let conditional = try EvidenceLinkedClaim(
            text: "Supports only if reporting remains voluntary.",
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidence],
            confidence: ConfidenceScore(millionths: 790_000)
        )
        let reservation = try EvidenceLinkedClaim(
            text: "Without prejudice to domestic review.",
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidence],
            confidence: ConfidenceScore(millionths: 780_000)
        )
        let condition = try EvidenceLinkedClaim(
            text: "Reporting remains voluntary.",
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidence],
            confidence: ConfidenceScore(millionths: 780_000)
        )
        let cell = try IssuePositionMatrixCell(
            itemID: briefingDomainID(28, BriefingItemID.self),
            representedEntityRevision: representedEntity,
            positionRevisions: positions,
            positionTypes: [.supports, .supportsWithConditions],
            statements: [supported, conditional],
            reservations: [reservation],
            conditions: [condition]
        )

        #expect(cell.positionRevisions == positions.sorted())
        #expect(Set(cell.positionTypes) == [.supports, .supportsWithConditions])
        #expect(cell.statements == [supported, conditional])
        #expect(cell.reservations == [reservation])
        #expect(cell.conditions == [condition])
        #expect(cell.materialClaims.count == 4)
        #expect(try CanonicalJSON.decodeValidated(
            IssuePositionMatrixCell.self,
            from: CanonicalJSON.encodeValidated(cell)
        ) == cell)

        #expect(throws: DomainValidationError.self) {
            _ = try IssuePositionMatrixCell(
                itemID: briefingDomainID(29, BriefingItemID.self),
                representedEntityRevision: representedEntity,
                positionRevisions: positions,
                positionTypes: [.supports],
                statements: [supported, conditional]
            )
        }
        #expect(throws: DomainValidationError.self) {
            _ = try IssuePositionMatrixCell(
                itemID: briefingDomainID(30, BriefingItemID.self),
                representedEntityRevision: representedEntity,
                positionRevisions: positions.reversed(),
                positionTypes: [.supportsWithConditions, .supports],
                statements: [conditional, supported],
                reservations: [reservation],
                conditions: [condition]
            )
        }
    }
}

private func briefingTemplate() throws -> MeetingTemplateV1 {
    let modules: [BriefingSectionType: VersionedComponent] = [
        .meetingOverview: try VersionedComponent(
            identifier: "briefing-overview-generator",
            version: "1.0.0"
        ),
        .majorIssues: try VersionedComponent(
            identifier: "briefing-major-issues-generator",
            version: "1.0.0"
        ),
        .majorDelegations: try VersionedComponent(
            identifier: "briefing-delegations-generator",
            version: "1.0.0"
        )
    ]
    let sections = try [
        TemplateSectionDefinition(
            key: "meeting-overview",
            sectionType: .meetingOverview,
            order: 1,
            title: "Meeting Overview",
            targetLengthUTF8Bytes: 4_096,
            requiredInputObjectTypes: [.meetingProfile, .interventionCard],
            promptModules: [modules[.meetingOverview]!]
        ),
        TemplateSectionDefinition(
            key: "major-issues",
            sectionType: .majorIssues,
            order: 2,
            title: "Major Issues",
            targetLengthUTF8Bytes: 8_192,
            requiredInputObjectTypes: [.issuePositionGraph, .issue],
            promptModules: [modules[.majorIssues]!]
        ),
        TemplateSectionDefinition(
            key: "major-delegations",
            sectionType: .majorDelegations,
            order: 3,
            title: "Major Countries / Delegations",
            targetLengthUTF8Bytes: 12_288,
            requiredInputObjectTypes: [
                .issuePositionGraph, .position, .participant, .organization
            ],
            promptModules: [modules[.majorDelegations]!]
        )
    ]
    let ruleKinds: [BriefingValidationRuleKind] = [
        .evidenceClosure, .entityResolution, .sourceCoverage, .contradiction,
        .lengthLimit, .prohibitHistoricalChange, .prohibitGroupInference
    ]
    return try MeetingTemplateV1(
        revision: RevisionEnvelope(
            logicalID: briefingDomainID(1, BriefingTemplateID.self),
            revisionID: briefingDomainID(2, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: UTCInstant(millisecondsSinceUnixEpoch: 1_900_000_000_000),
            createdBy: .application,
            dataClassification: .public
        ),
        templateKey: "multilateral-diplomatic-meeting-v1",
        displayName: "Multilateral Diplomatic Meeting",
        meetingType: .multilateralDiplomaticMeeting,
        requiredSemanticObjectTypes: [
            .meetingProfile, .evidenceRef, .issue, .position,
            .participant, .organization
        ],
        sections: sections,
        validationRules: try ruleKinds.map { try BriefingValidationRule(kind: $0) },
        rendererModules: [
            VersionedComponent(
                identifier: "deterministic-markdown-renderer",
                version: "1.0.0"
            )
        ],
        reviewStatus: .needsReview,
        userConfirmed: false
    )
}

private func briefingDomainID<Tag>(
    _ suffix: Int,
    _ type: StableID<Tag>.Type
) -> StableID<Tag> {
    StableID<Tag>(
        UUID(uuidString: String(format: "70000000-0000-0000-0000-%012d", suffix))!
    )
}
