import Foundation

/// The first immutable structured briefing template. It defines typed inputs,
/// validators and renderers; Markdown is only one derived representation.
public struct MeetingTemplateV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<BriefingTemplateIDTag>
    public let templateKey: String
    public let displayName: String
    public let meetingType: MeetingTemplateType
    public let requiredSemanticObjectTypes: [SemanticObjectType]
    public let compatibleInputSchemaVersions: [SchemaVersion]
    public let sections: [TemplateSectionDefinition]
    public let validationRules: [BriefingValidationRule]
    public let rendererModules: [VersionedComponent]
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<BriefingTemplateIDTag>,
        templateKey: String,
        displayName: String,
        meetingType: MeetingTemplateType,
        requiredSemanticObjectTypes: [SemanticObjectType],
        compatibleInputSchemaVersions: [SchemaVersion] = [.v1],
        sections: [TemplateSectionDefinition],
        validationRules: [BriefingValidationRule],
        rendererModules: [VersionedComponent],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.templateKey = templateKey
        self.displayName = displayName
        self.meetingType = meetingType
        self.requiredSemanticObjectTypes = requiredSemanticObjectTypes.sorted {
            $0.encodedValue < $1.encodedValue
        }
        self.compatibleInputSchemaVersions = compatibleInputSchemaVersions.sorted()
        self.sections = sections.sorted()
        self.validationRules = validationRules.sorted()
        self.rendererModules = rendererModules.sorted()
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var templateID: BriefingTemplateID { revision.logicalID }

    public func section(_ type: BriefingSectionType) -> TemplateSectionDefinition? {
        sections.first { $0.sectionType == type }
    }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .meetingTemplate,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "MeetingTemplate.v1"
        )
        issues += boundedLabelIssues(templateKey, path: "template_key", maximumUTF8Bytes: 96)
        issues += boundedLabelIssues(displayName, path: "display_name", maximumUTF8Bytes: 256)
        if !meetingType.isKnown {
            issues.append(Self.issue(.unsupportedValue, "meeting_type", "The meeting template type is unsupported."))
        }
        issues += duplicateIssues(in: requiredSemanticObjectTypes, path: "required_semantic_object_types")
        let requiredTypes: Set<SemanticObjectType> = [
            .meetingProfile, .evidenceRef, .issue, .position,
            .participant, .organization
        ]
        if !requiredTypes.isSubset(of: Set(requiredSemanticObjectTypes))
            || requiredSemanticObjectTypes.contains(where: { !$0.isKnown })
        {
            issues.append(Self.issue(.missingRequiredValue, "required_semantic_object_types", "The initial template requires meeting, evidence, issue, position, participant, and organization contracts."))
        }
        issues += duplicateIssues(in: compatibleInputSchemaVersions, path: "compatible_input_schema_versions")
        for version in compatibleInputSchemaVersions { issues += version.validationIssues() }
        if compatibleInputSchemaVersions != [.v1] {
            issues.append(Self.issue(.unsupportedValue, "compatible_input_schema_versions", "Task 006B accepts input schema v1 only."))
        }
        let requiredSections: [BriefingSectionType] = [
            .meetingOverview, .majorIssues, .majorDelegations
        ]
        if sections.map(\.sectionType) != requiredSections
            || sections.map(\.order) != [1, 2, 3]
        {
            issues.append(Self.issue(.inconsistentValue, "sections", "The initial template must contain exactly the three approved sections in canonical order."))
        }
        issues += duplicateIssues(in: sections.map(\.key), path: "sections.key")
        issues += duplicateIssues(in: sections.map(\.sectionType), path: "sections.section_type")
        for section in sections { issues += section.validationIssues() }
        let requiredRules: Set<BriefingValidationRuleKind> = [
            .evidenceClosure, .entityResolution, .sourceCoverage, .contradiction,
            .lengthLimit, .prohibitHistoricalChange, .prohibitGroupInference
        ]
        if Set(validationRules.map(\.kind)) != requiredRules
            || validationRules.contains(where: { !$0.blocking })
        {
            issues.append(Self.issue(.inconsistentValue, "validation_rules", "Every protected Task 006B validation rule must be present and blocking."))
        }
        issues += duplicateIssues(in: validationRules.map(\.kind), path: "validation_rules")
        if rendererModules.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "renderer_modules", "A versioned deterministic renderer is required."))
        }
        issues += duplicateIssues(in: rendererModules.map(\.identifier), path: "renderer_modules")
        for renderer in rendererModules { issues += renderer.validationIssues() }
        if !revision.inputRevisions.isEmpty || !revision.evidenceRevisions.isEmpty {
            issues.append(Self.issue(.inconsistentValue, "revision.input_revisions", "The built-in template cannot depend on meeting content."))
        }
        if revision.dataClassification != .public {
            issues.append(Self.issue(.inconsistentValue, "revision.data_classification", "The content-free built-in template is public; outputs inherit meeting classification separately."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<BriefingTemplateIDTag>.self, forKey: .revision),
            templateKey: container.decode(String.self, forKey: .templateKey),
            displayName: container.decode(String.self, forKey: .displayName),
            meetingType: container.decode(MeetingTemplateType.self, forKey: .meetingType),
            requiredSemanticObjectTypes: container.decode([SemanticObjectType].self, forKey: .requiredSemanticObjectTypes),
            compatibleInputSchemaVersions: container.decode([SchemaVersion].self, forKey: .compatibleInputSchemaVersions),
            sections: container.decode([TemplateSectionDefinition].self, forKey: .sections),
            validationRules: container.decode([BriefingValidationRule].self, forKey: .validationRules),
            rendererModules: container.decode([VersionedComponent].self, forKey: .rendererModules),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Content: Codable, Hashable, Sendable {
        let templateKey: String
        let displayName: String
        let meetingType: MeetingTemplateType
        let requiredSemanticObjectTypes: [SemanticObjectType]
        let compatibleInputSchemaVersions: [SchemaVersion]
        let sections: [TemplateSectionDefinition]
        let validationRules: [BriefingValidationRule]
        let rendererModules: [VersionedComponent]
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: MeetingTemplateV1) {
            templateKey = value.templateKey
            displayName = value.displayName
            meetingType = value.meetingType
            requiredSemanticObjectTypes = value.requiredSemanticObjectTypes
            compatibleInputSchemaVersions = value.compatibleInputSchemaVersions
            sections = value.sections
            validationRules = value.validationRules
            rendererModules = value.rendererModules
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case templateKey = "template_key"
            case displayName = "display_name"
            case meetingType = "meeting_type"
            case requiredSemanticObjectTypes = "required_semantic_object_types"
            case compatibleInputSchemaVersions = "compatible_input_schema_versions"
            case sections
            case validationRules = "validation_rules"
            case rendererModules = "renderer_modules"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case templateKey = "template_key"
        case displayName = "display_name"
        case meetingType = "meeting_type"
        case requiredSemanticObjectTypes = "required_semantic_object_types"
        case compatibleInputSchemaVersions = "compatible_input_schema_versions"
        case sections
        case validationRules = "validation_rules"
        case rendererModules = "renderer_modules"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
