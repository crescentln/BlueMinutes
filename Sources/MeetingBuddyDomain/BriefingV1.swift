import Foundation

public struct BriefingSectionV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<BriefingSectionIDTag>
    public let meetingID: MeetingID
    public let templateRevision: SemanticRevisionReference
    public let graphRevision: SemanticRevisionReference
    public let sectionType: BriefingSectionType
    public let order: UInt16
    public let title: String
    public let outputLanguage: LanguageTag
    public let metadata: [BriefingMetadataEntry]
    public let items: [BriefingSectionItem]
    public let generatorModules: [VersionedComponent]
    public let manualEditStatus: BriefingManualEditStatus
    public let locked: Bool
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<BriefingSectionIDTag>,
        meetingID: MeetingID,
        templateRevision: SemanticRevisionReference,
        graphRevision: SemanticRevisionReference,
        sectionType: BriefingSectionType,
        order: UInt16,
        title: String,
        outputLanguage: LanguageTag,
        metadata: [BriefingMetadataEntry] = [],
        items: [BriefingSectionItem],
        generatorModules: [VersionedComponent],
        manualEditStatus: BriefingManualEditStatus,
        locked: Bool,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.templateRevision = templateRevision
        self.graphRevision = graphRevision
        self.sectionType = sectionType
        self.order = order
        self.title = title
        self.outputLanguage = outputLanguage
        self.metadata = metadata
        self.items = items
        self.generatorModules = generatorModules.sorted()
        self.manualEditStatus = manualEditStatus
        self.locked = locked
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var sectionID: BriefingSectionID { revision.logicalID }
    public var materialClaims: [EvidenceLinkedClaim] { items.map(\.claim) }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .briefingSection,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "BriefingSection.v1"
        )
        issues += IntelligenceRevisionSupport.meetingInputIssues(
            meetingID: meetingID,
            revisionInputs: revision.inputRevisions
        )
        issues += IntelligenceRevisionSupport.exactInputIssues(
            templateRevision,
            expectedTypes: [.meetingTemplate],
            revisionInputs: revision.inputRevisions,
            path: "template_revision",
            noun: "MeetingTemplate revision"
        )
        issues += IntelligenceRevisionSupport.exactInputIssues(
            graphRevision,
            expectedTypes: [.issuePositionGraph],
            revisionInputs: revision.inputRevisions,
            path: "graph_revision",
            noun: "IssuePositionGraph revision"
        )
        if !sectionType.isKnown {
            issues.append(Self.issue(.unsupportedValue, "section_type", "The briefing section type is unsupported."))
        }
        if !(1...3).contains(order) {
            issues.append(Self.issue(.invalidRange, "order", "The initial template has section orders one through three."))
        }
        issues += boundedLabelIssues(title, path: "title", maximumUTF8Bytes: 256)
        issues += outputLanguage.validationIssues()
        for entry in metadata {
            issues += entry.validationIssues()
            issues += IntelligenceRevisionSupport.exactInputIssues(
                entry.sourceRevision,
                expectedTypes: [.meetingProfile],
                revisionInputs: revision.inputRevisions,
                path: "metadata.source_revision",
                noun: "MeetingProfile revision"
            )
        }
        if items.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "items", "Every approved briefing section needs at least one evidence-linked item."))
        }
        issues += duplicateIssues(in: items.map(\.itemID), path: "items.item_id")
        for item in items {
            issues += item.validationIssues()
            for source in item.sourceObjectRevisions {
                if !revision.inputRevisions.contains(source) {
                    issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "Every exact briefing item source must appear in the section inputs."))
                }
            }
        }
        if generatorModules.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "generator_modules", "A section records its exact bounded generator modules."))
        }
        issues += duplicateIssues(in: generatorModules.map(\.identifier), path: "generator_modules")
        for module in generatorModules { issues += module.validationIssues() }
        if !manualEditStatus.isKnown {
            issues.append(Self.issue(.unsupportedValue, "manual_edit_status", "The manual-edit state is unsupported."))
        }
        switch manualEditStatus {
        case .generated:
            if revision.createdBy == .user || locked {
                issues.append(Self.issue(.inconsistentValue, "manual_edit_status", "A user-created or locked revision must be represented as a preserved user edit."))
            }
        case .userEdited:
            if revision.createdBy != .user
                || revision.supersedesRevisionID == nil
                || reviewStatus != .confirmed
                || !userConfirmed
            {
                issues.append(Self.issue(.inconsistentValue, "manual_edit_status", "A manual edit or lock is an immutable, confirmed user revision with exact prior lineage."))
            }
        case .unrecognized:
            break
        }
        issues += IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: materialClaims,
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
        if Set(materialClaims.flatMap(\.evidenceRevisions)) != Set(revision.evidenceRevisions) {
            issues.append(Self.issue(.inconsistentValue, "revision.evidence_revisions", "Section evidence must exactly equal material item evidence."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<BriefingSectionIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            templateRevision: container.decode(SemanticRevisionReference.self, forKey: .templateRevision),
            graphRevision: container.decode(SemanticRevisionReference.self, forKey: .graphRevision),
            sectionType: container.decode(BriefingSectionType.self, forKey: .sectionType),
            order: container.decode(UInt16.self, forKey: .order),
            title: container.decode(String.self, forKey: .title),
            outputLanguage: container.decode(LanguageTag.self, forKey: .outputLanguage),
            metadata: container.decodeIfPresent([BriefingMetadataEntry].self, forKey: .metadata) ?? [],
            items: container.decode([BriefingSectionItem].self, forKey: .items),
            generatorModules: container.decode([VersionedComponent].self, forKey: .generatorModules),
            manualEditStatus: container.decode(BriefingManualEditStatus.self, forKey: .manualEditStatus),
            locked: container.decode(Bool.self, forKey: .locked),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let templateRevision: SemanticRevisionReference
        let graphRevision: SemanticRevisionReference
        let sectionType: BriefingSectionType
        let order: UInt16
        let title: String
        let outputLanguage: LanguageTag
        let metadata: [BriefingMetadataEntry]
        let items: [BriefingSectionItem]
        let generatorModules: [VersionedComponent]
        let manualEditStatus: BriefingManualEditStatus
        let locked: Bool
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: BriefingSectionV1) {
            meetingID = value.meetingID
            templateRevision = value.templateRevision
            graphRevision = value.graphRevision
            sectionType = value.sectionType
            order = value.order
            title = value.title
            outputLanguage = value.outputLanguage
            metadata = value.metadata
            items = value.items
            generatorModules = value.generatorModules
            manualEditStatus = value.manualEditStatus
            locked = value.locked
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case templateRevision = "template_revision"
            case graphRevision = "graph_revision"
            case sectionType = "section_type"
            case order
            case title
            case outputLanguage = "output_language"
            case metadata
            case items
            case generatorModules = "generator_modules"
            case manualEditStatus = "manual_edit_status"
            case locked
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case templateRevision = "template_revision"
        case graphRevision = "graph_revision"
        case sectionType = "section_type"
        case order
        case title
        case outputLanguage = "output_language"
        case metadata
        case items
        case generatorModules = "generator_modules"
        case manualEditStatus = "manual_edit_status"
        case locked
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct ValidationReportV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<ValidationReportIDTag>
    public let meetingID: MeetingID
    public let templateRevision: SemanticRevisionReference
    public let graphRevision: SemanticRevisionReference
    public let sectionRevisions: [SemanticRevisionReference]
    public let coverageLedgerID: BriefingCoverageLedgerID
    public let coverageLedgerHash: ContentDigest
    public let checks: [BriefingValidationCheck]
    public let findings: [BriefingValidationFinding]
    public let overallStatus: BriefingValidationCheckStatus
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<ValidationReportIDTag>,
        meetingID: MeetingID,
        templateRevision: SemanticRevisionReference,
        graphRevision: SemanticRevisionReference,
        sectionRevisions: [SemanticRevisionReference],
        coverageLedgerID: BriefingCoverageLedgerID,
        coverageLedgerHash: ContentDigest,
        checks: [BriefingValidationCheck],
        findings: [BriefingValidationFinding] = [],
        overallStatus: BriefingValidationCheckStatus,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.templateRevision = templateRevision
        self.graphRevision = graphRevision
        self.sectionRevisions = sectionRevisions
        self.coverageLedgerID = coverageLedgerID
        self.coverageLedgerHash = coverageLedgerHash
        self.checks = checks.sorted()
        self.findings = findings.sorted()
        self.overallStatus = overallStatus
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var reportID: ValidationReportID { revision.logicalID }
    public var passed: Bool { overallStatus == .passed }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .validationReport,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "ValidationReport.v1"
        )
        issues += IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions)
        let exactTargets: [(SemanticRevisionReference, Set<SemanticObjectType>, String)] = [
            (templateRevision, [.meetingTemplate], "template_revision"),
            (graphRevision, [.issuePositionGraph], "graph_revision")
        ]
        for (reference, types, path) in exactTargets {
            issues += IntelligenceRevisionSupport.exactInputIssues(
                reference,
                expectedTypes: types,
                revisionInputs: revision.inputRevisions,
                path: path,
                noun: path
            )
        }
        if sectionRevisions.count != 3
            || sectionRevisions.contains(where: { $0.objectType != .briefingSection })
        {
            issues.append(Self.issue(.inconsistentValue, "section_revisions", "A report validates exactly the three approved section revisions."))
        }
        issues += duplicateIssues(in: sectionRevisions, path: "section_revisions")
        for section in sectionRevisions {
            issues += IntelligenceRevisionSupport.exactInputIssues(
                section,
                expectedTypes: [.briefingSection],
                revisionInputs: revision.inputRevisions,
                path: "section_revisions",
                noun: "BriefingSection revision"
            )
        }
        issues += coverageLedgerHash.validationIssues()
        let requiredCategories: Set<BriefingValidationCategory> = [
            .templateCompatibility, .schema, .evidence, .entity, .sourceCoverage,
            .length, .provenance, .contradiction, .currentInputs, .classification
        ]
        if Set(checks.map(\.category)) != requiredCategories {
            issues.append(Self.issue(.inconsistentValue, "checks", "Every deterministic Task 006B validation category must be recorded exactly once."))
        }
        issues += duplicateIssues(in: checks.map(\.category), path: "checks.category")
        for check in checks { issues += check.validationIssues() }
        issues += duplicateIssues(in: findings.map(\.findingID), path: "findings.finding_id")
        for finding in findings { issues += finding.validationIssues() }
        if !overallStatus.isKnown {
            issues.append(Self.issue(.unsupportedValue, "overall_status", "The report status is unsupported."))
        }
        let calculatedPassed = checks.allSatisfy { $0.status == .passed }
            && !findings.contains(where: \.blocking)
        if (overallStatus == .passed) != calculatedPassed {
            issues.append(Self.issue(.inconsistentValue, "overall_status", "Overall report status must derive from complete checks and blocking findings."))
        }
        let findingEvidence = Set(findings.flatMap(\.evidenceRevisions))
        if !findingEvidence.isSubset(of: Set(revision.evidenceRevisions)) {
            issues.append(Self.issue(.missingRequiredValue, "revision.evidence_revisions", "Finding evidence must remain in the report envelope."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<ValidationReportIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            templateRevision: container.decode(SemanticRevisionReference.self, forKey: .templateRevision),
            graphRevision: container.decode(SemanticRevisionReference.self, forKey: .graphRevision),
            sectionRevisions: container.decode([SemanticRevisionReference].self, forKey: .sectionRevisions),
            coverageLedgerID: container.decode(BriefingCoverageLedgerID.self, forKey: .coverageLedgerID),
            coverageLedgerHash: container.decode(ContentDigest.self, forKey: .coverageLedgerHash),
            checks: container.decode([BriefingValidationCheck].self, forKey: .checks),
            findings: container.decodeIfPresent([BriefingValidationFinding].self, forKey: .findings) ?? [],
            overallStatus: container.decode(BriefingValidationCheckStatus.self, forKey: .overallStatus),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let templateRevision: SemanticRevisionReference
        let graphRevision: SemanticRevisionReference
        let sectionRevisions: [SemanticRevisionReference]
        let coverageLedgerID: BriefingCoverageLedgerID
        let coverageLedgerHash: ContentDigest
        let checks: [BriefingValidationCheck]
        let findings: [BriefingValidationFinding]
        let overallStatus: BriefingValidationCheckStatus
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: ValidationReportV1) {
            meetingID = value.meetingID
            templateRevision = value.templateRevision
            graphRevision = value.graphRevision
            sectionRevisions = value.sectionRevisions
            coverageLedgerID = value.coverageLedgerID
            coverageLedgerHash = value.coverageLedgerHash
            checks = value.checks
            findings = value.findings
            overallStatus = value.overallStatus
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case templateRevision = "template_revision"
            case graphRevision = "graph_revision"
            case sectionRevisions = "section_revisions"
            case coverageLedgerID = "coverage_ledger_id"
            case coverageLedgerHash = "coverage_ledger_hash"
            case checks
            case findings
            case overallStatus = "overall_status"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case templateRevision = "template_revision"
        case graphRevision = "graph_revision"
        case sectionRevisions = "section_revisions"
        case coverageLedgerID = "coverage_ledger_id"
        case coverageLedgerHash = "coverage_ledger_hash"
        case checks
        case findings
        case overallStatus = "overall_status"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}

public struct FinalBriefingV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<FinalBriefingIDTag>
    public let meetingID: MeetingID
    public let templateRevision: SemanticRevisionReference
    public let sectionRevisions: [SemanticRevisionReference]
    public let validationReportRevision: SemanticRevisionReference
    public let outputLanguage: LanguageTag
    public let documentTitle: String
    public let renderer: VersionedComponent
    public let markdown: String
    public let markdownDigest: ContentDigest
    public let manualSectionCount: UInt16
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<FinalBriefingIDTag>,
        meetingID: MeetingID,
        templateRevision: SemanticRevisionReference,
        sectionRevisions: [SemanticRevisionReference],
        validationReportRevision: SemanticRevisionReference,
        outputLanguage: LanguageTag,
        documentTitle: String,
        renderer: VersionedComponent,
        markdown: String,
        markdownDigest: ContentDigest,
        manualSectionCount: UInt16,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.templateRevision = templateRevision
        self.sectionRevisions = sectionRevisions
        self.validationReportRevision = validationReportRevision
        self.outputLanguage = outputLanguage
        self.documentTitle = documentTitle
        self.renderer = renderer
        self.markdown = markdown
        self.markdownDigest = markdownDigest
        self.manualSectionCount = manualSectionCount
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var finalBriefingID: FinalBriefingID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .finalBriefing,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "FinalBriefing.v1"
        )
        issues += IntelligenceRevisionSupport.meetingInputIssues(meetingID: meetingID, revisionInputs: revision.inputRevisions)
        let targets: [(SemanticRevisionReference, Set<SemanticObjectType>, String)] = [
            (templateRevision, [.meetingTemplate], "template_revision"),
            (validationReportRevision, [.validationReport], "validation_report_revision")
        ]
        for (reference, types, path) in targets {
            issues += IntelligenceRevisionSupport.exactInputIssues(
                reference,
                expectedTypes: types,
                revisionInputs: revision.inputRevisions,
                path: path,
                noun: path
            )
        }
        if sectionRevisions.count != 3
            || sectionRevisions.contains(where: { $0.objectType != .briefingSection })
        {
            issues.append(Self.issue(.inconsistentValue, "section_revisions", "Final briefing assembly requires exactly the current three section revisions."))
        }
        issues += duplicateIssues(in: sectionRevisions, path: "section_revisions")
        for section in sectionRevisions {
            issues += IntelligenceRevisionSupport.exactInputIssues(
                section,
                expectedTypes: [.briefingSection],
                revisionInputs: revision.inputRevisions,
                path: "section_revisions",
                noun: "BriefingSection revision"
            )
        }
        issues += outputLanguage.validationIssues()
        issues += boundedLabelIssues(documentTitle, path: "document_title", maximumUTF8Bytes: 2_048)
        issues += renderer.validationIssues()
        issues += preservedSourceTextIssues(markdown, path: "markdown", maximumUTF8Bytes: 1_048_576)
        issues += markdownDigest.validationIssues()
        if markdownDigest != (try? .sha256(ofUTF8Text: markdown)) {
            issues.append(Self.issue(.inconsistentValue, "markdown_digest", "The stored Markdown digest must match the exact UTF-8 export bytes."))
        }
        if manualSectionCount > 3 {
            issues.append(Self.issue(.invalidRange, "manual_section_count", "Manual section count cannot exceed the approved section count."))
        }
        if revision.evidenceRevisions.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "revision.evidence_revisions", "A final briefing must preserve material evidence navigation references."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<FinalBriefingIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            templateRevision: container.decode(SemanticRevisionReference.self, forKey: .templateRevision),
            sectionRevisions: container.decode([SemanticRevisionReference].self, forKey: .sectionRevisions),
            validationReportRevision: container.decode(SemanticRevisionReference.self, forKey: .validationReportRevision),
            outputLanguage: container.decode(LanguageTag.self, forKey: .outputLanguage),
            documentTitle: container.decode(String.self, forKey: .documentTitle),
            renderer: container.decode(VersionedComponent.self, forKey: .renderer),
            markdown: container.decode(String.self, forKey: .markdown),
            markdownDigest: container.decode(ContentDigest.self, forKey: .markdownDigest),
            manualSectionCount: container.decode(UInt16.self, forKey: .manualSectionCount),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let templateRevision: SemanticRevisionReference
        let sectionRevisions: [SemanticRevisionReference]
        let validationReportRevision: SemanticRevisionReference
        let outputLanguage: LanguageTag
        let documentTitle: String
        let renderer: VersionedComponent
        let markdown: String
        let markdownDigest: ContentDigest
        let manualSectionCount: UInt16
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: FinalBriefingV1) {
            meetingID = value.meetingID
            templateRevision = value.templateRevision
            sectionRevisions = value.sectionRevisions
            validationReportRevision = value.validationReportRevision
            outputLanguage = value.outputLanguage
            documentTitle = value.documentTitle
            renderer = value.renderer
            markdown = value.markdown
            markdownDigest = value.markdownDigest
            manualSectionCount = value.manualSectionCount
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case templateRevision = "template_revision"
            case sectionRevisions = "section_revisions"
            case validationReportRevision = "validation_report_revision"
            case outputLanguage = "output_language"
            case documentTitle = "document_title"
            case renderer
            case markdown
            case markdownDigest = "markdown_digest"
            case manualSectionCount = "manual_section_count"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case templateRevision = "template_revision"
        case sectionRevisions = "section_revisions"
        case validationReportRevision = "validation_report_revision"
        case outputLanguage = "output_language"
        case documentTitle = "document_title"
        case renderer
        case markdown
        case markdownDigest = "markdown_digest"
        case manualSectionCount = "manual_section_count"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
