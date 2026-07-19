import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct BriefingGenerationInputs: Sendable {
    public let source: BriefingSourceBundle
    public let graph: IssuePositionGraphV1
    public let requests: [BriefingSectionType: BriefingSectionRequest]

    public init(
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        requests: [BriefingSectionType: BriefingSectionRequest]
    ) {
        self.source = source
        self.graph = graph
        self.requests = requests
    }
}

public enum BriefingSemanticFactory {
    /// The content-free built-in v1 template has one immutable release
    /// timestamp. Call time must never change bytes behind its fixed revision ID.
    public static func builtInTemplate(createdAt _: UTCInstant) throws -> MeetingTemplateV1 {
        let templateReleaseAt = try UTCInstant(
            millisecondsSinceUnixEpoch: 1_784_347_200_000
        )
        let sections = try [
            TemplateSectionDefinition(
                key: "meeting-overview",
                sectionType: .meetingOverview,
                order: 1,
                title: "Meeting Overview",
                targetLengthUTF8Bytes: 16_384,
                requiredInputObjectTypes: [.meetingProfile, .interventionCard],
                promptModules: DiplomaticBriefingPrompt.overviewModules
            ),
            TemplateSectionDefinition(
                key: "major-issues",
                sectionType: .majorIssues,
                order: 2,
                title: "Major Issues",
                targetLengthUTF8Bytes: 32_768,
                requiredInputObjectTypes: [.issuePositionGraph, .issue],
                promptModules: DiplomaticBriefingPrompt.issueModules
            ),
            TemplateSectionDefinition(
                key: "major-delegations",
                sectionType: .majorDelegations,
                order: 3,
                title: "Major Countries / Delegations",
                targetLengthUTF8Bytes: 49_152,
                requiredInputObjectTypes: [
                    .issuePositionGraph, .position, .participant, .organization
                ],
                promptModules: DiplomaticBriefingPrompt.delegationModules
            )
        ]
        let rules = try BriefingValidationRuleKind.allTask006BRules.map {
            try BriefingValidationRule(kind: $0)
        }
        let logicalID = BriefingTemplateID(deterministicUUID("task006b-template-v1:logical"))
        let revisionID = RevisionID(deterministicUUID("task006b-template-v1:revision"))
        let draft = try MeetingTemplateV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: templateReleaseAt,
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
            validationRules: rules,
            rendererModules: [DiplomaticBriefingPrompt.renderer],
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try MeetingTemplateV1(
            revision: publishedEnvelope(
                draft.revision,
                hash: try draft.calculatedSemanticContentHash(),
                at: templateReleaseAt
            ),
            templateKey: draft.templateKey,
            displayName: draft.displayName,
            meetingType: draft.meetingType,
            requiredSemanticObjectTypes: draft.requiredSemanticObjectTypes,
            compatibleInputSchemaVersions: draft.compatibleInputSchemaVersions,
            sections: draft.sections,
            validationRules: draft.validationRules,
            rendererModules: draft.rendererModules,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    public static func generationInputs(
        source: BriefingSourceBundle,
        createdAt: UTCInstant
    ) throws -> BriefingGenerationInputs {
        let graph = try makeGraph(source: source, createdAt: createdAt)
        let templateReference = try reference(source.template)
        let graphReference = try reference(graph)
        let classification = inheritedClassification(source)
        var requests: [BriefingSectionType: BriefingSectionRequest] = [:]
        for definition in source.template.sections {
            let claims = try sourceClaims(
                for: definition.sectionType,
                source: source,
                graph: graph
            )
            requests[definition.sectionType] = try BriefingSectionRequest(
                packageIdentifier: "section_\(definition.sectionType.encodedValue)",
                templateRevision: templateReference,
                graphRevision: graphReference,
                sectionDefinition: definition,
                outputLanguage: source.meeting.outputLanguage,
                sourceClaims: claims,
                dataClassification: classification,
                localeIdentifier: source.meeting.outputLanguage.value
            )
        }
        return BriefingGenerationInputs(source: source, graph: graph, requests: requests)
    }

    public static func makeGraph(
        source: BriefingSourceBundle,
        createdAt: UTCInstant
    ) throws -> IssuePositionGraphV1 {
        let meetingReference = try reference(source.meeting)
        let templateReference = try reference(source.template)
        let cards = source.analysis.delegationPositionCards
        let groupedByIssue = Dictionary(grouping: source.analysis.positions) {
            $0.issueRevision
        }
        let rows = try groupedByIssue.keys.sorted().map { issueReference in
            let positions = groupedByIssue[issueReference]!.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            }
            let byEntity = Dictionary(grouping: positions) { $0.representedEntityRevision }
            let cells = try byEntity.keys.sorted().map { entityReference in
                let entityPositions = byEntity[entityReference]!.sorted {
                    $0.revision.revisionID < $1.revision.revisionID
                }
                let positionReferences = try entityPositions.map(reference)
                let matchingCards = cards.filter { card in
                    card.issueRevision == issueReference
                        && card.representedEntityRevision == entityReference
                        && Set(card.positionRevisions) == Set(positionReferences)
                }
                guard matchingCards.count <= 1 else {
                    throw AIProviderContractError.invalidResponse(
                        "Multiple delegation cards claim the same exact matrix cell."
                    )
                }
                return try IssuePositionMatrixCell(
                    itemID: BriefingItemID(deterministicUUID(
                        "task006b-cell-v1:\(issueReference.logicalID.canonicalString):\(entityReference.logicalID.canonicalString)"
                    )),
                    representedEntityRevision: entityReference,
                    positionRevisions: positionReferences,
                    delegationCardRevision: try matchingCards.first.map(reference),
                    positionTypes: entityPositions.map(\.positionType),
                    statements: try entityPositions.map {
                        try matrixClaim(from: $0.statement)
                    },
                    reservations: try entityPositions.flatMap { position in
                        try position.reservations.map(matrixClaim)
                    },
                    conditions: try entityPositions.flatMap { position in
                        try position.conditions.map(matrixClaim)
                    }
                )
            }
            return try IssuePositionMatrixRow(
                issueRevision: issueReference,
                cells: cells
            )
        }
        let inputs = uniqueReferences(
            [meetingReference, templateReference]
                + rows.flatMap { row in
                    [row.issueRevision]
                        + row.cells.flatMap { cell in
                            [cell.representedEntityRevision]
                                + cell.positionRevisions
                                + [cell.delegationCardRevision].compactMap { $0 }
                        }
                }
        )
        let evidence = uniqueReferences(rows.flatMap(\.cells).flatMap(\.materialClaims).flatMap(\.evidenceRevisions))
        let classification = inheritedClassification(source)
        let seed = "task006b-graph-v1:\(source.meeting.meetingID.canonicalString):\(source.analysis.ledger.contentHash.lowercaseHex):\(templateReference.revisionID.canonicalString)"
        let exactInputSeed = inputs.map {
            "\($0.objectType.encodedValue):\($0.logicalID.canonicalString):\($0.revisionID.canonicalString)"
        }.joined(separator: ",")
        let draft = try IssuePositionGraphV1(
            revision: RevisionEnvelope(
                logicalID: IssuePositionGraphID(deterministicUUID(seed + ":logical")),
                revisionID: RevisionID(deterministicUUID(seed + ":\(exactInputSeed):revision")),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .application,
                inputRevisions: inputs,
                sourceAssetRevisions: sourceAssetReferences(source),
                evidenceRevisions: evidence,
                dataClassification: classification
            ),
            meetingID: source.meeting.meetingID,
            templateRevision: templateReference,
            analysisLedgerID: source.analysis.ledger.ledgerID,
            analysisLedgerHash: source.analysis.ledger.contentHash,
            rows: rows,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        let graph = try IssuePositionGraphV1(
            revision: publishedEnvelope(
                draft.revision,
                hash: try draft.calculatedSemanticContentHash(),
                at: createdAt
            ),
            meetingID: draft.meetingID,
            templateRevision: draft.templateRevision,
            analysisLedgerID: draft.analysisLedgerID,
            analysisLedgerHash: draft.analysisLedgerHash,
            rows: draft.rows,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
        try validateGraph(graph, against: source)
        return graph
    }

    private static func validateGraph(
        _ graph: IssuePositionGraphV1,
        against source: BriefingSourceBundle
    ) throws {
        let positionsByReference = try Dictionary(
            uniqueKeysWithValues: source.analysis.positions.map { (try reference($0), $0) }
        )
        for row in graph.rows {
            for cell in row.cells {
                let exactPositions = cell.positionRevisions.compactMap {
                    positionsByReference[$0]
                }
                guard exactPositions.count == cell.positionRevisions.count,
                      exactPositions.allSatisfy({
                          $0.issueRevision == row.issueRevision
                              && $0.representedEntityRevision
                                  == cell.representedEntityRevision
                      }),
                      exactPositions.map(\.positionType) == cell.positionTypes,
                      (try exactPositions.map { try matrixClaim(from: $0.statement) })
                        == cell.statements,
                      (try exactPositions.flatMap { position in
                          try position.reservations.map(matrixClaim)
                      }) == cell.reservations,
                      (try exactPositions.flatMap { position in
                          try position.conditions.map(matrixClaim)
                      }) == cell.conditions
                else {
                    throw AIProviderContractError.invalidResponse(
                        "A matrix cell changed issue, entity, type, or exact Position content."
                    )
                }
                for position in exactPositions {
                    if position.positionType == .noStatedPosition,
                       !(position.revision.createdBy == .user
                            && position.reviewStatus == .confirmed
                            && position.userConfirmed)
                    {
                        throw AIProviderContractError.invalidResponse(
                            "Silence cannot create a matrix position."
                        )
                    }
                }
            }
        }
    }

    static func matrixClaim(
        from source: EvidenceLinkedClaim
    ) throws -> EvidenceLinkedClaim {
        try EvidenceLinkedClaim(
            text: source.text,
            taxonomy: .meetingBuddyExtraction,
            supportStatus: source.supportStatus,
            evidenceRevisions: source.evidenceRevisions,
            confidence: source.confidence
        )
    }
}

private extension BriefingValidationRuleKind {
    static let allTask006BRules: [BriefingValidationRuleKind] = [
        .evidenceClosure, .entityResolution, .sourceCoverage, .contradiction,
        .lengthLimit, .prohibitHistoricalChange, .prohibitGroupInference
    ]
}

extension BriefingSemanticFactory {
    static func sourceClaims(
        for section: BriefingSectionType,
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1
    ) throws -> [BriefingSourceClaim] {
        switch section {
        case .meetingOverview:
            return try source.analysis.interventionCards.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            }.map { card in
                try BriefingSourceClaim(
                    sourceKey: "intervention_\(card.revision.revisionID.canonicalString)",
                    sourceRevision: reference(card),
                    claim: card.shortSummary
                )
            }
        case .majorIssues:
            return try source.analysis.issues.sorted {
                $0.revision.revisionID < $1.revision.revisionID
            }.map { issue in
                try BriefingSourceClaim(
                    sourceKey: "issue_\(issue.revision.revisionID.canonicalString)",
                    sourceRevision: reference(issue),
                    claim: issue.summary ?? issue.title
                )
            }
        case .majorDelegations:
            var claims: [BriefingSourceClaim] = []
            let positionsByReference = try Dictionary(
                uniqueKeysWithValues: source.analysis.positions.map { (try reference($0), $0) }
            )
            for row in graph.rows {
                for cell in row.cells {
                    let positions = cell.positionRevisions.compactMap { positionsByReference[$0] }
                    guard positions.count == cell.positionRevisions.count else {
                        throw AIProviderContractError.invalidRequest(
                            "A delegation section source could not resolve its exact Position revisions."
                        )
                    }
                    for position in positions {
                        let parts: [String] = {
                        var values = [position.statement.text]
                        values += position.reservations.map { "Reservation: \($0.text)" }
                        values += position.conditions.map { "Condition: \($0.text)" }
                        return values
                        }()
                        let zeroConfidence = try ConfidenceScore(millionths: 0)
                        let confidence = position.materialClaims.map(\.confidence).min()
                            ?? zeroConfidence
                        let support: EvidenceSupportStatus = position.materialClaims
                            .contains(where: { $0.supportStatus == .uncertain })
                            ? .uncertain : .supported
                        claims.append(try BriefingSourceClaim(
                            sourceKey: "delegation_\(cell.itemID.canonicalString)_\(position.revision.revisionID.canonicalString)",
                            sourceRevision: reference(position),
                            claim: EvidenceLinkedClaim(
                                text: parts.joined(separator: " | "),
                                taxonomy: .meetingBuddyExtraction,
                                supportStatus: support,
                                evidenceRevisions: position.revision.evidenceRevisions,
                                confidence: confidence
                            )
                        ))
                    }
                }
            }
            return claims.sorted()
        case .unrecognized:
            throw AIProviderContractError.invalidRequest(
                "An unsupported template section cannot create a request."
            )
        }
    }

    static func inheritedClassification(_ source: BriefingSourceBundle) -> DataClassification {
        let classifications = [source.meeting.revision.dataClassification]
            + source.analysis.evidence.map(\.revision.dataClassification)
            + source.analysis.participants.map(\.revision.dataClassification)
            + source.analysis.organizations.map(\.revision.dataClassification)
            + source.analysis.issues.map(\.revision.dataClassification)
            + source.analysis.positions.map(\.revision.dataClassification)
            + source.analysis.commitments.map(\.revision.dataClassification)
            + source.analysis.decisions.map(\.revision.dataClassification)
            + source.analysis.interventionCards.map(\.revision.dataClassification)
            + source.analysis.delegationPositionCards.map(\.revision.dataClassification)
        return DataClassification.mostRestrictive(classifications) ?? .restricted
    }

    static func sourceAssetReferences(_ source: BriefingSourceBundle) -> [SemanticRevisionReference] {
        uniqueReferences(
            source.analysis.evidence.flatMap(\.revision.sourceAssetRevisions)
                + source.analysis.positions.flatMap(\.revision.sourceAssetRevisions)
                + source.analysis.interventionCards.flatMap(\.revision.sourceAssetRevisions)
        )
    }

    static func uniqueReferences(
        _ values: [SemanticRevisionReference]
    ) -> [SemanticRevisionReference] {
        Array(Set(values)).sorted()
    }

    static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    static func deterministicUUID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func publishedEnvelope<Tag: LogicalObjectIDScope>(
        _ draft: RevisionEnvelope<Tag>,
        hash: ContentDigest,
        at createdAt: UTCInstant
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: draft.logicalID,
            revisionID: draft.revisionID,
            schemaVersion: draft.schemaVersion,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: draft.createdAt,
            createdBy: draft.createdBy,
            publishedAt: createdAt,
            supersedesRevisionID: draft.supersedesRevisionID,
            inputRevisions: draft.inputRevisions,
            sourceAssetRevisions: draft.sourceAssetRevisions,
            evidenceRevisions: draft.evidenceRevisions,
            dataClassification: draft.dataClassification,
            generationMetadata: draft.generationMetadata,
            semanticContentHash: hash
        )
    }
}
