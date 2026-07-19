import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct BriefingAssemblyPriorState: Sendable {
    public let ledgerID: BriefingCoverageLedgerID
    public let validationReport: ValidationReportV1
    public let finalBriefing: FinalBriefingV1

    public init(
        ledgerID: BriefingCoverageLedgerID,
        validationReport: ValidationReportV1,
        finalBriefing: FinalBriefingV1
    ) {
        self.ledgerID = ledgerID
        self.validationReport = validationReport
        self.finalBriefing = finalBriefing
    }
}

public extension BriefingSemanticFactory {
    static func makeGeneratedSection(
        request: BriefingSectionRequest,
        candidate: BriefingSectionCandidate,
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        provider: ProviderMetadata,
        createdAt: UTCInstant,
        superseding prior: BriefingSectionV1? = nil
    ) throws -> BriefingSectionV1 {
        guard candidate.sectionType == request.sectionDefinition.sectionType,
              request.templateRevision == (try reference(source.template)),
              request.graphRevision == (try reference(graph)),
              request.sectionDefinition == source.template.section(candidate.sectionType),
              request.sectionDefinition.promptModules
                == DiplomaticBriefingPrompt.modules(for: candidate.sectionType),
              prior.map({
                  $0.sectionType == candidate.sectionType
                      && $0.templateRevision == request.templateRevision
                      && $0.graphRevision == request.graphRevision
                      && !$0.locked
                      && $0.manualEditStatus == .generated
              }) ?? true
        else {
            throw AIProviderContractError.invalidResponse(
                "A section candidate does not match the exact template, graph, or regeneration boundary."
            )
        }
        let sourceByKey = Dictionary(
            uniqueKeysWithValues: request.sourceClaims.map { ($0.sourceKey, $0) }
        )
        let usedKeys = candidate.items.flatMap(\.sourceKeys)
        guard usedKeys.count == sourceByKey.count,
              Set(usedKeys) == Set(sourceByKey.keys),
              usedKeys.allSatisfy({ sourceByKey[$0] != nil })
        else {
            throw AIProviderContractError.invalidResponse(
                "Independent section generation omitted or invented a typed source key."
            )
        }
        let sectionLogicalID = prior?.sectionID ?? BriefingSectionID(deterministicUUID(
            "task006b-section-v1:\(source.meeting.meetingID.canonicalString):\(candidate.sectionType.encodedValue):logical"
        ))
        let candidateDigest = try ContentDigest.sha256(
            ofUTF8Text: String(decoding: CanonicalJSON.encode(candidate), as: UTF8.self)
        )
        let seed = "task006b-section-v1:\(sectionLogicalID.canonicalString):\(graph.revision.semanticContentHash!.lowercaseHex):\(candidateDigest.lowercaseHex):\(prior?.revision.revisionID.canonicalString ?? "initial")"
        let items = try candidate.items.enumerated().map { index, generated in
            let sources = generated.sourceKeys.compactMap { sourceByKey[$0] }
            let evidence = uniqueReferences(sources.flatMap(\.claim.evidenceRevisions))
            let zero = try ConfidenceScore(millionths: 0)
            let sourceConfidence = sources.map(\.claim.confidence).min() ?? zero
            let confidence = min(sourceConfidence, generated.confidence)
            let support: EvidenceSupportStatus = sources.contains {
                $0.claim.supportStatus == .uncertain
            } ? .uncertain : .supported
            return try BriefingSectionItem(
                itemID: BriefingItemID(deterministicUUID(
                    "\(sectionLogicalID.canonicalString):\(index):\(generated.sourceKeys.joined(separator: ",")):\(generated.text)"
                )),
                claim: EvidenceLinkedClaim(
                    text: generated.text,
                    taxonomy: .meetingBuddyInference,
                    supportStatus: support,
                    evidenceRevisions: evidence,
                    confidence: confidence
                ),
                sourceObjectRevisions: uniqueReferences(
                    sources.map(\.sourceRevision)
                )
            )
        }
        let totalBytes = items.reduce(0) { $0 + $1.claim.text.utf8.count }
        guard totalBytes <= Int(request.sectionDefinition.targetLengthUTF8Bytes) else {
            throw AIProviderContractError.invalidResponse(
                "The generated section exceeds its template-bounded UTF-8 length."
            )
        }
        let meetingReference = try reference(source.meeting)
        let inputs = uniqueReferences(
            [meetingReference, request.templateRevision, request.graphRevision]
                + items.flatMap(\.sourceObjectRevisions)
        )
        let evidence = uniqueReferences(items.flatMap(\.claim.evidenceRevisions))
        let generation = try GenerationMetadata(
            provider: provider,
            promptModuleVersions: request.sectionDefinition.promptModules,
            outputSchemaVersion: .v1,
            templateVersion: request.templateRevision.revisionID.canonicalString,
            generatedAt: createdAt,
            privacyRoute: .localOnly
        )
        let metadata = candidate.sectionType == .meetingOverview ? [
            try BriefingMetadataEntry(
                label: "Meeting",
                value: source.meeting.title,
                sourceRevision: meetingReference
            )
        ] : []
        let draft = try BriefingSectionV1(
            revision: RevisionEnvelope(
                logicalID: sectionLogicalID,
                revisionID: RevisionID(deterministicUUID(seed + ":revision")),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                supersedesRevisionID: prior?.revision.revisionID,
                inputRevisions: inputs,
                sourceAssetRevisions: sourceAssetReferences(source),
                evidenceRevisions: evidence,
                dataClassification: inheritedClassification(source),
                generationMetadata: generation
            ),
            meetingID: source.meeting.meetingID,
            templateRevision: request.templateRevision,
            graphRevision: request.graphRevision,
            sectionType: candidate.sectionType,
            order: request.sectionDefinition.order,
            title: request.sectionDefinition.title,
            outputLanguage: request.outputLanguage,
            metadata: metadata,
            items: items,
            generatorModules: request.sectionDefinition.promptModules,
            manualEditStatus: .generated,
            locked: false,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try publishedSection(draft, at: createdAt)
    }

    static func makeManualSectionRevision(
        prior: BriefingSectionV1,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool,
        changedAt: UTCInstant
    ) throws -> BriefingSectionV1 {
        try prior.validate()
        guard prior.revision.lifecycleStatus == .published,
              prior.revision.validationState == .valid,
              Set(editedTextByItemID.keys) == Set(prior.items.map(\.itemID))
        else {
            throw AIProviderContractError.invalidRequest(
                "A manual section revision must preserve every stable item and exact prior lineage."
            )
        }
        let confidence = try ConfidenceScore(millionths: 1_000_000)
        let items = try prior.items.map { item in
            guard let text = editedTextByItemID[item.itemID] else {
                throw AIProviderContractError.invalidRequest("A manual edit omitted a section item.")
            }
            return try BriefingSectionItem(
                itemID: item.itemID,
                label: item.label,
                claim: EvidenceLinkedClaim(
                    text: text,
                    taxonomy: .userConfirmedConclusion,
                    supportStatus: item.claim.supportStatus,
                    evidenceRevisions: item.claim.evidenceRevisions,
                    confidence: confidence
                ),
                sourceObjectRevisions: item.sourceObjectRevisions
            )
        }
        let priorReference = try reference(prior)
        let seed = "task006b-manual-section-v1:\(priorReference.revisionID.canonicalString):\(locked):\(try ContentDigest.sha256(ofUTF8Text: items.map(\.claim.text).joined(separator: "\n")).lowercaseHex)"
        let draft = try BriefingSectionV1(
            revision: RevisionEnvelope(
                logicalID: prior.sectionID,
                revisionID: RevisionID(deterministicUUID(seed)),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: changedAt,
                createdBy: .user,
                supersedesRevisionID: prior.revision.revisionID,
                inputRevisions: uniqueReferences(prior.revision.inputRevisions + [priorReference]),
                sourceAssetRevisions: prior.revision.sourceAssetRevisions,
                evidenceRevisions: prior.revision.evidenceRevisions,
                dataClassification: prior.revision.dataClassification
            ),
            meetingID: prior.meetingID,
            templateRevision: prior.templateRevision,
            graphRevision: prior.graphRevision,
            sectionType: prior.sectionType,
            order: prior.order,
            title: prior.title,
            outputLanguage: prior.outputLanguage,
            metadata: prior.metadata,
            items: items,
            generatorModules: prior.generatorModules,
            manualEditStatus: .userEdited,
            locked: locked,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        return try publishedSection(draft, at: changedAt)
    }

    static func makeCoverageLedger(
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1],
        supersedesLedgerID: BriefingCoverageLedgerID? = nil,
        createdAt: UTCInstant
    ) throws -> BriefingCoverageLedger {
        let graphReference = try reference(graph)
        let orderedSections = sections.sorted { $0.order < $1.order }
        let sectionReferences = try orderedSections.map(reference)
        var entries: [BriefingSegmentCoverage] = []
        for analysisSegment in source.analysis.ledger.segments {
            if analysisSegment.disposition == .nonSubstantive {
                entries.append(try BriefingSegmentCoverage(
                    segmentRevision: analysisSegment.segmentRevision,
                    analysisOutputRevisions: [],
                    evidenceRevisions: analysisSegment.evidenceRevisions,
                    conclusionReferences: [],
                    disposition: .nonSubstantive,
                    safeReasonCode: analysisSegment.safeReasonCode ?? "analysis_non_substantive"
                ))
                continue
            }
            guard analysisSegment.disposition == .substantive else {
                entries.append(try BriefingSegmentCoverage(
                    segmentRevision: analysisSegment.segmentRevision,
                    analysisOutputRevisions: [],
                    evidenceRevisions: [],
                    conclusionReferences: [],
                    disposition: .missing
                ))
                continue
            }
            let outputLogicalIDs = Set(
                analysisSegment.outputRevisions.map { $0.logicalID.canonicalString }
            )
            let evidence = Set(analysisSegment.evidenceRevisions)
            var conclusions: Set<BriefingConclusionReference> = []
            for cell in graph.cells where conclusionMatches(
                sources: cell.positionRevisions + [cell.representedEntityRevision],
                claimEvidence: Set(cell.materialClaims.flatMap(\.evidenceRevisions)),
                outputLogicalIDs: outputLogicalIDs,
                segmentEvidence: evidence
            ) {
                conclusions.insert(try BriefingConclusionReference(
                    outputRevision: graphReference,
                    itemID: cell.itemID
                ))
            }
            for (section, sectionReference) in zip(orderedSections, sectionReferences) {
                for item in section.items where conclusionMatches(
                    sources: item.sourceObjectRevisions,
                    claimEvidence: Set(item.claim.evidenceRevisions),
                    outputLogicalIDs: outputLogicalIDs,
                    segmentEvidence: evidence
                ) {
                    conclusions.insert(try BriefingConclusionReference(
                        outputRevision: sectionReference,
                        itemID: item.itemID
                    ))
                }
            }
            let sortedConclusions = conclusions.sorted()
            entries.append(try BriefingSegmentCoverage(
                segmentRevision: analysisSegment.segmentRevision,
                analysisOutputRevisions: analysisSegment.outputRevisions,
                evidenceRevisions: analysisSegment.evidenceRevisions,
                conclusionReferences: sortedConclusions,
                disposition: sortedConclusions.isEmpty ? .reviewedNotRendered : .represented,
                safeReasonCode: sortedConclusions.isEmpty ? "reviewed_not_material_to_template" : nil
            ))
        }
        let ledgerSeed = ([
            "task006b-ledger-v1",
            source.meeting.meetingID.canonicalString,
            source.analysis.ledger.ledgerID.canonicalString,
            source.analysis.ledger.contentHash.lowercaseHex,
            source.template.revision.revisionID.canonicalString,
            graph.revision.revisionID.canonicalString,
            supersedesLedgerID?.canonicalString ?? "initial",
            String(createdAt.millisecondsSinceUnixEpoch)
        ] + sectionReferences.map(\.revisionID.canonicalString)).joined(separator: ":")
        let ledger = try BriefingCoverageLedger(
            ledgerID: BriefingCoverageLedgerID(deterministicUUID(ledgerSeed)),
            supersedesLedgerID: supersedesLedgerID,
            meetingID: source.meeting.meetingID,
            transcriptManifestID: source.analysis.ledger.transcriptManifestID,
            transcriptManifestHash: source.analysis.ledger.transcriptManifestHash,
            analysisLedgerID: source.analysis.ledger.ledgerID,
            analysisLedgerHash: source.analysis.ledger.contentHash,
            eligibleSegmentRevisions: source.analysis.ledger.eligibleSegmentRevisions,
            templateRevision: reference(source.template),
            graphRevision: graphReference,
            sectionRevisions: sectionReferences,
            status: .published,
            segments: entries,
            createdAt: createdAt
        )
        let expected = try expectedConclusionReferences(graph: graph, sections: orderedSections)
        guard Set(ledger.conclusionReferences) == expected else {
            throw BriefingCoverageError.invalidLedger(
                "At least one material conclusion lacks exact segment-to-item traceability."
            )
        }
        return ledger
    }

    static func validationFindings(
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1],
        ledger: BriefingCoverageLedger
    ) throws -> [BriefingValidationFinding] {
        var findings: [BriefingValidationFinding] = []
        let templateReference = try reference(source.template)
        let graphReference = try reference(graph)
        let ordered = sections.sorted { $0.order < $1.order }
        let sectionReferences = try ordered.map(reference)
        func add(
            _ category: BriefingValidationCategory,
            _ code: String,
            _ message: String,
            _ revisions: [SemanticRevisionReference] = []
        ) throws {
            findings.append(try BriefingValidationFinding(
                findingID: ValidationFindingID(deterministicUUID(
                    "task006b-finding:\(category.encodedValue):\(code):\(revisions.map(\.revisionID.canonicalString).joined(separator: ","))"
                )),
                category: category,
                severity: .error,
                code: code,
                message: message,
                affectedRevisions: revisions,
                blocking: true
            ))
        }
        if graph.templateRevision != templateReference
            || ordered.map(\.sectionType) != source.template.sections.map(\.sectionType)
            || ordered.map(\.order) != source.template.sections.map(\.order)
        {
            try add(.templateCompatibility, "template_mismatch", "Sections do not exactly match the current template revision.", sectionReferences)
        }
        if !graph.validationIssues().isEmpty || ordered.contains(where: { !$0.validationIssues().isEmpty }) {
            try add(.schema, "schema_invalid", "A matrix or section failed its versioned domain schema.", [graphReference] + sectionReferences)
        }
        if ordered.flatMap(\.materialClaims).contains(where: { !$0.isPublishable }) {
            try add(.evidence, "evidence_not_publishable", "Every material conclusion requires exact publishable evidence.", sectionReferences)
        }
        let sourcePositions = try Set(source.analysis.positions.map(reference))
        if !Set(graph.cells.flatMap(\.positionRevisions)).isSubset(of: sourcePositions) {
            try add(.entity, "position_entity_mismatch", "A matrix cell is not backed by a current exact Position revision.", [graphReference])
        }
        let expectedConclusions = try expectedConclusionReferences(
            graph: graph,
            sections: ordered
        )
        if (try? ledger.validate()) == nil
            || ledger.graphRevision != graphReference
            || ledger.sectionRevisions != sectionReferences
            || Set(ledger.conclusionReferences) != expectedConclusions
        {
            try add(.sourceCoverage, "coverage_incomplete", "Eligible segment or conclusion coverage is incomplete or duplicated.", [graphReference] + sectionReferences)
        }
        for (section, definition) in zip(ordered, source.template.sections) {
            if section.items.reduce(0, { $0 + $1.claim.text.utf8.count })
                > Int(definition.targetLengthUTF8Bytes)
            {
                try add(.length, "section_too_long", "A section exceeds its exact template byte bound.", [try reference(section)])
            }
            if section.generatorModules != definition.promptModules
                || (section.manualEditStatus == .generated
                    && section.revision.generationMetadata?.promptModuleVersions
                        != definition.promptModules)
            {
                try add(.provenance, "generator_provenance_mismatch", "Section generator provenance differs from the exact template module set.", [try reference(section)])
            }
        }
        for row in graph.rows {
            for cell in row.cells {
                let types = Set(cell.positionTypes)
                if (types.contains(.supports) || types.contains(.supportsWithConditions))
                    && (types.contains(.opposes) || types.contains(.opposesWithQualification))
                {
                    try add(.contradiction, "opposed_position_types", "The same issue/entity cell contains opposed position types requiring review.", [graphReference])
                }
            }
        }
        let prohibited = ["previously", "formerly", "changed its position", "now supports", "now opposes"]
        if ordered.flatMap(\.materialClaims).contains(where: { claim in
            prohibited.contains { claim.text.localizedCaseInsensitiveContains($0) }
        }) {
            try add(.contradiction, "historical_change_prohibited", "Task 006B cannot assert unsupported historical change.", sectionReferences)
        }
        let positionsByReference = try Dictionary(
            uniqueKeysWithValues: source.analysis.positions.map { (try reference($0), $0) }
        )
        let hasPositionContradiction = ordered.flatMap(\.items).contains { item in
            let tokens = Set(
                item.claim.text.lowercased().split(whereSeparator: {
                    !$0.isLetter && !$0.isNumber
                }).map(String.init)
            )
            return item.sourceObjectRevisions.compactMap { positionsByReference[$0] }
                .contains { position in
                    let polarityConflict: Bool = switch position.positionType {
                    case .supports, .supportsWithConditions:
                        !tokens.isDisjoint(with: ["oppose", "opposes", "opposed", "reject", "rejects"])
                    case .opposes, .opposesWithQualification:
                        !tokens.isDisjoint(with: ["support", "supports", "supported", "endorse", "endorses"])
                    case .requests, .proposes, .reservesPosition, .uncertain,
                         .noStatedPosition, .unrecognized:
                        false
                    }
                    let qualifications = position.reservations + position.conditions
                    let omittedQualification = qualifications.contains { qualification in
                        !item.claim.text.localizedCaseInsensitiveContains(
                            qualification.text
                        )
                    }
                    return polarityConflict || omittedQualification
                }
        }
        if hasPositionContradiction {
            try add(
                .contradiction,
                "position_contradiction_or_qualification_omission",
                "A section contradicted an exact Position or omitted a required reservation or condition.",
                sectionReferences
            )
        }
        let allInputReferences = uniqueReferences(
            [try reference(source.meeting), templateReference, graphReference]
                + ordered.flatMap(\.revision.inputRevisions)
        )
        if Set(allInputReferences).count != allInputReferences.count {
            try add(.currentInputs, "input_duplicate", "Exact current input references are duplicated.", sectionReferences)
        }
        let classification = inheritedClassification(source)
        if graph.revision.dataClassification != classification
            || ordered.contains(where: { $0.revision.dataClassification != classification })
        {
            try add(.classification, "classification_mismatch", "Briefing outputs did not inherit the most restrictive input classification.", [graphReference] + sectionReferences)
        }
        return findings.sorted()
    }

    static func makeValidationReport(
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1],
        ledger: BriefingCoverageLedger,
        superseding prior: ValidationReportV1? = nil,
        createdAt: UTCInstant
    ) throws -> ValidationReportV1 {
        let findings = try validationFindings(
            source: source,
            graph: graph,
            sections: sections,
            ledger: ledger
        )
        guard findings.isEmpty else {
            throw BriefingCoverageError.invalidLedger(
                "Deterministic briefing validation produced blocking findings."
            )
        }
        let checks = try BriefingValidationCategory.allTask006BCategories.map {
            try BriefingValidationCheck(
                category: $0,
                status: .passed,
                validator: DiplomaticBriefingPrompt.validator
            )
        }
        let ordered = sections.sorted { $0.order < $1.order }
        let meetingReference = try reference(source.meeting)
        let templateReference = try reference(source.template)
        let graphReference = try reference(graph)
        let sectionReferences = try ordered.map(reference)
        let logicalID = prior?.reportID ?? ValidationReportID(deterministicUUID(
            "task006b-report-v1:\(source.meeting.meetingID.canonicalString):logical"
        ))
        let draft = try ValidationReportV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: RevisionID(deterministicUUID(
                    "task006b-report-v1:\(logicalID.canonicalString):\(ledger.contentHash.lowercaseHex):\(prior?.revision.revisionID.canonicalString ?? "initial")"
                )),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .application,
                supersedesRevisionID: prior?.revision.revisionID,
                inputRevisions: [meetingReference, templateReference, graphReference] + sectionReferences,
                sourceAssetRevisions: sourceAssetReferences(source),
                evidenceRevisions: uniqueReferences(ordered.flatMap(\.revision.evidenceRevisions)),
                dataClassification: inheritedClassification(source)
            ),
            meetingID: source.meeting.meetingID,
            templateRevision: templateReference,
            graphRevision: graphReference,
            sectionRevisions: sectionReferences,
            coverageLedgerID: ledger.ledgerID,
            coverageLedgerHash: ledger.contentHash,
            checks: checks,
            findings: [],
            overallStatus: .passed,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try publishedReport(draft, at: createdAt)
    }

    static func makeFinalBriefing(
        source: BriefingSourceBundle,
        sections: [BriefingSectionV1],
        report: ValidationReportV1,
        ledger: BriefingCoverageLedger,
        superseding prior: FinalBriefingV1? = nil,
        createdAt: UTCInstant
    ) throws -> FinalBriefingV1 {
        guard report.passed else { throw BriefingCoverageError.invalidLedger("A failed report cannot assemble a final briefing.") }
        let ordered = sections.sorted { $0.order < $1.order }
        let markdown = try renderMarkdown(
            source: source,
            sections: ordered,
            report: report,
            ledger: ledger
        )
        let markdownDigest = try ContentDigest.sha256(ofUTF8Text: markdown)
        let meetingReference = try reference(source.meeting)
        let templateReference = try reference(source.template)
        let sectionReferences = try ordered.map(reference)
        let reportReference = try reference(report)
        let logicalID = prior?.finalBriefingID ?? FinalBriefingID(deterministicUUID(
            "task006b-final-v1:\(source.meeting.meetingID.canonicalString):logical"
        ))
        let draft = try FinalBriefingV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: RevisionID(deterministicUUID(
                    "task006b-final-v1:\(logicalID.canonicalString):\(report.revision.semanticContentHash!.lowercaseHex):\(markdownDigest.lowercaseHex):\(prior?.revision.revisionID.canonicalString ?? "initial")"
                )),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .application,
                supersedesRevisionID: prior?.revision.revisionID,
                inputRevisions: [meetingReference, templateReference] + sectionReferences + [reportReference],
                sourceAssetRevisions: sourceAssetReferences(source),
                evidenceRevisions: uniqueReferences(ordered.flatMap(\.revision.evidenceRevisions)),
                dataClassification: inheritedClassification(source)
            ),
            meetingID: source.meeting.meetingID,
            templateRevision: templateReference,
            sectionRevisions: sectionReferences,
            validationReportRevision: reportReference,
            outputLanguage: source.meeting.outputLanguage,
            documentTitle: source.meeting.title + " — Briefing",
            renderer: DiplomaticBriefingPrompt.renderer,
            markdown: markdown,
            markdownDigest: markdownDigest,
            manualSectionCount: UInt16(ordered.filter { $0.manualEditStatus == .userEdited }.count),
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try publishedFinal(draft, at: createdAt)
    }

    static func makePublication(
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1],
        prior: BriefingAssemblyPriorState? = nil,
        createdAt: UTCInstant
    ) throws -> BriefingPublication {
        let ledger = try makeCoverageLedger(
            source: source,
            graph: graph,
            sections: sections,
            supersedesLedgerID: prior?.ledgerID,
            createdAt: createdAt
        )
        let report = try makeValidationReport(
            source: source,
            graph: graph,
            sections: sections,
            ledger: ledger,
            superseding: prior?.validationReport,
            createdAt: createdAt
        )
        let final = try makeFinalBriefing(
            source: source,
            sections: sections,
            report: report,
            ledger: ledger,
            superseding: prior?.finalBriefing,
            createdAt: createdAt
        )
        return try BriefingPublication(
            template: source.template,
            graph: graph,
            sections: sections,
            validationReport: report,
            finalBriefing: final,
            ledger: ledger
        )
    }
}

private extension BriefingSemanticFactory {
    static func publishedSection(
        _ draft: BriefingSectionV1,
        at createdAt: UTCInstant
    ) throws -> BriefingSectionV1 {
        try BriefingSectionV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            templateRevision: draft.templateRevision,
            graphRevision: draft.graphRevision,
            sectionType: draft.sectionType,
            order: draft.order,
            title: draft.title,
            outputLanguage: draft.outputLanguage,
            metadata: draft.metadata,
            items: draft.items,
            generatorModules: draft.generatorModules,
            manualEditStatus: draft.manualEditStatus,
            locked: draft.locked,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    static func publishedReport(
        _ draft: ValidationReportV1,
        at createdAt: UTCInstant
    ) throws -> ValidationReportV1 {
        try ValidationReportV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            templateRevision: draft.templateRevision,
            graphRevision: draft.graphRevision,
            sectionRevisions: draft.sectionRevisions,
            coverageLedgerID: draft.coverageLedgerID,
            coverageLedgerHash: draft.coverageLedgerHash,
            checks: draft.checks,
            findings: draft.findings,
            overallStatus: draft.overallStatus,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    static func publishedFinal(
        _ draft: FinalBriefingV1,
        at createdAt: UTCInstant
    ) throws -> FinalBriefingV1 {
        try FinalBriefingV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            templateRevision: draft.templateRevision,
            sectionRevisions: draft.sectionRevisions,
            validationReportRevision: draft.validationReportRevision,
            outputLanguage: draft.outputLanguage,
            documentTitle: draft.documentTitle,
            renderer: draft.renderer,
            markdown: draft.markdown,
            markdownDigest: draft.markdownDigest,
            manualSectionCount: draft.manualSectionCount,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    static func conclusionMatches(
        sources: [SemanticRevisionReference],
        claimEvidence: Set<SemanticRevisionReference>,
        outputLogicalIDs: Set<String>,
        segmentEvidence: Set<SemanticRevisionReference>
    ) -> Bool {
        sources.contains { outputLogicalIDs.contains($0.logicalID.canonicalString) }
            || !claimEvidence.isDisjoint(with: segmentEvidence)
    }

    static func expectedConclusionReferences(
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1]
    ) throws -> Set<BriefingConclusionReference> {
        let graphReference = try reference(graph)
        var results = try Set(graph.cells.map {
            try BriefingConclusionReference(outputRevision: graphReference, itemID: $0.itemID)
        })
        for section in sections {
            let sectionReference = try reference(section)
            for item in section.items {
                results.insert(try BriefingConclusionReference(
                    outputRevision: sectionReference,
                    itemID: item.itemID
                ))
            }
        }
        return results
    }

    static func renderMarkdown(
        source: BriefingSourceBundle,
        sections: [BriefingSectionV1],
        report: ValidationReportV1,
        ledger: BriefingCoverageLedger
    ) throws -> String {
        var lines: [String] = [
            "# \(escapeMarkdown(source.meeting.title)) — Briefing",
            "",
            "- Classification: `\(inheritedClassification(source).encodedValue)`",
            "- Template revision: `\(source.template.revision.revisionID.canonicalString)`",
            "- Analysis ledger: `\(source.analysis.ledger.ledgerID.canonicalString)`",
            "- Briefing coverage ledger: `\(ledger.ledgerID.canonicalString)`",
            "- Validation report revision: `\(report.revision.revisionID.canonicalString)`",
            "- Output language: `\(source.meeting.outputLanguage.value)`",
            ""
        ]
        for section in sections.sorted(by: { $0.order < $1.order }) {
            lines.append("## \(escapeMarkdown(section.title))")
            lines.append("")
            for metadata in section.metadata {
                lines.append("- **\(escapeMarkdown(metadata.label)):** \(escapeMarkdown(metadata.value))")
            }
            if !section.metadata.isEmpty { lines.append("") }
            for item in section.items {
                let links = item.claim.evidenceRevisions.map {
                    "[evidence:\($0.logicalID.canonicalString)](#evidence-\($0.logicalID.canonicalString))"
                }.joined(separator: ", ")
                lines.append("- \(escapeMarkdown(item.claim.text)) (\(links))")
            }
            lines.append("")
        }
        lines.append("## Evidence Appendix")
        lines.append("")
        let evidenceByReference = try Dictionary(
            uniqueKeysWithValues: source.analysis.evidence.map { (try reference($0), $0) }
        )
        let transcriptByReference = try Dictionary(
            uniqueKeysWithValues: source.transcriptReview.transcriptSegments.map {
                (try reference($0), $0)
            }
        )
        let referencedEvidence = uniqueReferences(sections.flatMap(\.revision.evidenceRevisions))
        for reference in referencedEvidence {
            guard let evidence = evidenceByReference[reference] else {
                throw BriefingCoverageError.invalidLedger(
                    "A briefing evidence link could not navigate to its exact source object."
                )
            }
            lines.append("<a id=\"evidence-\(reference.logicalID.canonicalString)\"></a>")
            lines.append("- Evidence `\(reference.logicalID.canonicalString)`; revision `\(reference.revisionID.canonicalString)`; \(evidenceLocation(evidence, transcriptByReference: transcriptByReference))")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func evidenceLocation(
        _ evidence: EvidenceRefV1,
        transcriptByReference: [SemanticRevisionReference: TranscriptSegmentV1]
    ) -> String {
        switch evidence.location {
        case let .transcriptSegment(source, textRange):
            let time = transcriptByReference[source].map {
                "time `\($0.timeRange.startMilliseconds)-\($0.timeRange.endMilliseconds) ms`"
            } ?? "time unavailable"
            let text = textRange.map { "UTF-8 `\($0.startOffset)+\($0.length)`" }
                ?? "full segment"
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; \(time); \(text)"
        case let .mediaTimeRange(source, range):
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; time `\(range.startMilliseconds)-\(range.endMilliseconds) ms`"
        case let .documentLocation(source, location), let .officialStatement(source, location):
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; document locator `\(location.pageNumber.map(String.init) ?? "n/a")`"
        case let .meetingMetadata(source, field):
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; field `\(field)`"
        case let .semanticObjectRevision(source, pointer):
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; pointer `\(pointer ?? "/")`"
        case let .userConfirmedNote(source, textRange):
            return "source `\(source.objectType.encodedValue):\(source.revisionID.canonicalString)`; UTF-8 `\(textRange.map { "\($0.startOffset)+\($0.length)" } ?? "full note")`"
        }
    }

    static func escapeMarkdown(_ value: String) -> String {
        var result = ""
        let punctuation: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!", "<", ">", "|"]
        for character in value {
            if punctuation.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}

private extension BriefingValidationCategory {
    static let allTask006BCategories: [BriefingValidationCategory] = [
        .templateCompatibility, .schema, .evidence, .entity, .sourceCoverage,
        .length, .provenance, .contradiction, .currentInputs, .classification
    ]
}
