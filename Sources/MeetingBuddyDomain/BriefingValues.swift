import Foundation

public enum MeetingTemplateType: StableStringValue {
    case multilateralDiplomaticMeeting
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "multilateral_diplomatic_meeting": self = .multilateralDiplomaticMeeting
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .multilateralDiplomaticMeeting: "multilateral_diplomatic_meeting"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum BriefingSectionType: StableStringValue, Comparable {
    case meetingOverview
    case majorIssues
    case majorDelegations
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "meeting_overview": self = .meetingOverview
        case "major_issues": self = .majorIssues
        case "major_delegations": self = .majorDelegations
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .meetingOverview: "meeting_overview"
        case .majorIssues: "major_issues"
        case .majorDelegations: "major_delegations"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.encodedValue < rhs.encodedValue
    }
}

public enum TemplateEvidencePolicy: StableStringValue {
    case exactEvidenceRequired
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "exact_evidence_required": self = .exactEvidenceRequired
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .exactEvidenceRequired: "exact_evidence_required"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum BriefingManualEditStatus: StableStringValue {
    case generated
    case userEdited
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "generated": self = .generated
        case "user_edited": self = .userEdited
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .generated: "generated"
        case .userEdited: "user_edited"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum BriefingValidationRuleKind: StableStringValue, Comparable {
    case evidenceClosure
    case entityResolution
    case sourceCoverage
    case contradiction
    case lengthLimit
    case prohibitHistoricalChange
    case prohibitGroupInference
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "evidence_closure": self = .evidenceClosure
        case "entity_resolution": self = .entityResolution
        case "source_coverage": self = .sourceCoverage
        case "contradiction": self = .contradiction
        case "length_limit": self = .lengthLimit
        case "prohibit_historical_change": self = .prohibitHistoricalChange
        case "prohibit_group_inference": self = .prohibitGroupInference
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .evidenceClosure: "evidence_closure"
        case .entityResolution: "entity_resolution"
        case .sourceCoverage: "source_coverage"
        case .contradiction: "contradiction"
        case .lengthLimit: "length_limit"
        case .prohibitHistoricalChange: "prohibit_historical_change"
        case .prohibitGroupInference: "prohibit_group_inference"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.encodedValue < rhs.encodedValue
    }
}

public struct BriefingValidationRule: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let kind: BriefingValidationRuleKind
    public let blocking: Bool

    public init(kind: BriefingValidationRuleKind, blocking: Bool = true) throws {
        self.kind = kind
        self.blocking = blocking
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.kind, lhs.blocking ? 1 : 0) < (rhs.kind, rhs.blocking ? 1 : 0)
    }

    public func validationIssues() -> [ValidationIssue] {
        kind.isKnown ? [] : [
            ValidationIssue(
                code: .unsupportedValue,
                path: "validation_rule.kind",
                message: "The template validation rule is unsupported."
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(BriefingValidationRuleKind.self, forKey: .kind),
            blocking: container.decode(Bool.self, forKey: .blocking)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case blocking
    }
}

public struct TemplateSectionDefinition: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let key: String
    public let sectionType: BriefingSectionType
    public let order: UInt16
    public let title: String
    public let targetLengthUTF8Bytes: UInt32
    public let requiredInputObjectTypes: [SemanticObjectType]
    public let promptModules: [VersionedComponent]
    public let outputSchemaVersion: SchemaVersion
    public let evidencePolicy: TemplateEvidencePolicy

    public init(
        key: String,
        sectionType: BriefingSectionType,
        order: UInt16,
        title: String,
        targetLengthUTF8Bytes: UInt32,
        requiredInputObjectTypes: [SemanticObjectType],
        promptModules: [VersionedComponent],
        outputSchemaVersion: SchemaVersion = .v1,
        evidencePolicy: TemplateEvidencePolicy = .exactEvidenceRequired
    ) throws {
        self.key = key
        self.sectionType = sectionType
        self.order = order
        self.title = title
        self.targetLengthUTF8Bytes = targetLengthUTF8Bytes
        self.requiredInputObjectTypes = requiredInputObjectTypes.sorted {
            $0.encodedValue < $1.encodedValue
        }
        self.promptModules = promptModules.sorted()
        self.outputSchemaVersion = outputSchemaVersion
        self.evidencePolicy = evidencePolicy
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.order, lhs.key) < (rhs.order, rhs.key)
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = boundedLabelIssues(key, path: "template_section.key", maximumUTF8Bytes: 96)
        issues += boundedLabelIssues(title, path: "template_section.title", maximumUTF8Bytes: 256)
        if !sectionType.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "template_section.section_type", message: "The section type is unsupported."))
        }
        if order == 0 {
            issues.append(ValidationIssue(code: .invalidRange, path: "template_section.order", message: "Section order starts at one."))
        }
        if !(256...65_536).contains(targetLengthUTF8Bytes) {
            issues.append(ValidationIssue(code: .invalidRange, path: "template_section.target_length_utf8_bytes", message: "The target length must be bounded."))
        }
        if requiredInputObjectTypes.isEmpty || requiredInputObjectTypes.contains(where: { !$0.isKnown }) {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "template_section.required_input_object_types", message: "A section needs known typed inputs."))
        }
        issues += duplicateIssues(in: requiredInputObjectTypes, path: "template_section.required_input_object_types")
        if promptModules.isEmpty {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "template_section.prompt_modules", message: "A section needs a versioned generator module."))
        }
        issues += duplicateIssues(in: promptModules.map(\.identifier), path: "template_section.prompt_modules")
        for module in promptModules { issues += module.validationIssues() }
        issues += outputSchemaVersion.validationIssues()
        if outputSchemaVersion != .v1 {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "template_section.output_schema_version", message: "Task 006B supports section schema v1 only."))
        }
        if !evidencePolicy.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "template_section.evidence_policy", message: "The evidence policy is unsupported."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            sectionType: container.decode(BriefingSectionType.self, forKey: .sectionType),
            order: container.decode(UInt16.self, forKey: .order),
            title: container.decode(String.self, forKey: .title),
            targetLengthUTF8Bytes: container.decode(UInt32.self, forKey: .targetLengthUTF8Bytes),
            requiredInputObjectTypes: container.decode([SemanticObjectType].self, forKey: .requiredInputObjectTypes),
            promptModules: container.decode([VersionedComponent].self, forKey: .promptModules),
            outputSchemaVersion: container.decode(SchemaVersion.self, forKey: .outputSchemaVersion),
            evidencePolicy: container.decode(TemplateEvidencePolicy.self, forKey: .evidencePolicy)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case sectionType = "section_type"
        case order
        case title
        case targetLengthUTF8Bytes = "target_length_utf8_bytes"
        case requiredInputObjectTypes = "required_input_object_types"
        case promptModules = "prompt_modules"
        case outputSchemaVersion = "output_schema_version"
        case evidencePolicy = "evidence_policy"
    }
}

public struct BriefingMetadataEntry: Codable, Hashable, Sendable, DomainValidatable {
    public let label: String
    public let value: String
    public let sourceRevision: SemanticRevisionReference

    public init(label: String, value: String, sourceRevision: SemanticRevisionReference) throws {
        self.label = label
        self.value = value
        self.sourceRevision = sourceRevision
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = boundedLabelIssues(label, path: "briefing_metadata.label", maximumUTF8Bytes: 128)
        issues += preservedSourceTextIssues(value, path: "briefing_metadata.value", maximumUTF8Bytes: 2_048)
        issues += sourceRevision.validationIssues()
        if sourceRevision.objectType != .meetingProfile {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "briefing_metadata.source_revision", message: "Briefing metadata must identify the exact MeetingProfile revision."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            label: container.decode(String.self, forKey: .label),
            value: container.decode(String.self, forKey: .value),
            sourceRevision: container.decode(SemanticRevisionReference.self, forKey: .sourceRevision)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case value
        case sourceRevision = "source_revision"
    }
}

public struct BriefingSectionItem: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let itemID: BriefingItemID
    public let label: String?
    public let claim: EvidenceLinkedClaim
    public let sourceObjectRevisions: [SemanticRevisionReference]

    public init(
        itemID: BriefingItemID,
        label: String? = nil,
        claim: EvidenceLinkedClaim,
        sourceObjectRevisions: [SemanticRevisionReference]
    ) throws {
        self.itemID = itemID
        self.label = label
        self.claim = claim
        self.sourceObjectRevisions = sourceObjectRevisions.sorted()
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.itemID < rhs.itemID
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = label.map { boundedLabelIssues($0, path: "briefing_item.label", maximumUTF8Bytes: 512) } ?? []
        issues += claim.validationIssues()
        issues += duplicateIssues(in: sourceObjectRevisions, path: "briefing_item.source_object_revisions")
        if sourceObjectRevisions.isEmpty || sourceObjectRevisions.contains(where: { !Self.allowedSourceTypes.contains($0.objectType) }) {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "briefing_item.source_object_revisions", message: "A material briefing item needs exact typed source objects."))
        }
        if !claim.isPublishable {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "briefing_item.claim", message: "A briefing item must remain evidence-linked and publishable."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(BriefingItemID.self, forKey: .itemID),
            label: container.decodeIfPresent(String.self, forKey: .label),
            claim: container.decode(EvidenceLinkedClaim.self, forKey: .claim),
            sourceObjectRevisions: container.decode([SemanticRevisionReference].self, forKey: .sourceObjectRevisions)
        )
    }

    private static let allowedSourceTypes: Set<SemanticObjectType> = [
        .meetingProfile, .issue, .position, .commitment, .decision,
        .interventionCard, .delegationPositionCard, .issuePositionGraph
    ]

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case label
        case claim
        case sourceObjectRevisions = "source_object_revisions"
    }
}

public struct IssuePositionMatrixCell: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let itemID: BriefingItemID
    public let representedEntityRevision: SemanticRevisionReference
    public let positionRevisions: [SemanticRevisionReference]
    public let delegationCardRevision: SemanticRevisionReference?
    public let positionTypes: [PositionType]
    public let statements: [EvidenceLinkedClaim]
    public let reservations: [EvidenceLinkedClaim]
    public let conditions: [EvidenceLinkedClaim]

    public init(
        itemID: BriefingItemID,
        representedEntityRevision: SemanticRevisionReference,
        positionRevisions: [SemanticRevisionReference],
        delegationCardRevision: SemanticRevisionReference? = nil,
        positionTypes: [PositionType],
        statements: [EvidenceLinkedClaim],
        reservations: [EvidenceLinkedClaim] = [],
        conditions: [EvidenceLinkedClaim] = []
    ) throws {
        self.itemID = itemID
        self.representedEntityRevision = representedEntityRevision
        self.positionRevisions = positionRevisions
        self.delegationCardRevision = delegationCardRevision
        self.positionTypes = positionTypes
        self.statements = statements
        self.reservations = reservations
        self.conditions = conditions
        try validate()
    }

    public var materialClaims: [EvidenceLinkedClaim] { statements + reservations + conditions }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.representedEntityRevision, lhs.itemID)
            < (rhs.representedEntityRevision, rhs.itemID)
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if ![.participant, .organization].contains(representedEntityRevision.objectType) {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "matrix_cell.represented_entity_revision", message: "A matrix entity must be a Participant or Organization revision."))
        }
        if positionRevisions.isEmpty
            || positionRevisions.contains(where: { $0.objectType != .position })
            || positionRevisions != positionRevisions.sorted()
            || positionRevisions.count != positionTypes.count
            || positionRevisions.count != statements.count
        {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "matrix_cell.position_revisions", message: "A matrix cell requires aligned exact Position revisions, types, and statements."))
        }
        if let delegationCardRevision,
           delegationCardRevision.objectType != .delegationPositionCard
        {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "matrix_cell.delegation_card_revision", message: "A matrix cell requires its exact delegation-position card."))
        }
        if positionTypes.contains(where: { !$0.isKnown }) {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "matrix_cell.position_types", message: "A matrix position type is unsupported."))
        }
        issues += duplicateIssues(in: positionRevisions, path: "matrix_cell.position_revisions")
        for claim in materialClaims { issues += claim.validationIssues() }
        issues += duplicateIssues(in: reservations, path: "matrix_cell.reservations")
        issues += duplicateIssues(in: conditions, path: "matrix_cell.conditions")
        if materialClaims.contains(where: { !$0.isPublishable }) {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "matrix_cell.claims", message: "Every matrix conclusion needs exact evidence."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(BriefingItemID.self, forKey: .itemID),
            representedEntityRevision: container.decode(SemanticRevisionReference.self, forKey: .representedEntityRevision),
            positionRevisions: container.decode([SemanticRevisionReference].self, forKey: .positionRevisions),
            delegationCardRevision: container.decodeIfPresent(SemanticRevisionReference.self, forKey: .delegationCardRevision),
            positionTypes: container.decode([PositionType].self, forKey: .positionTypes),
            statements: container.decode([EvidenceLinkedClaim].self, forKey: .statements),
            reservations: container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .reservations) ?? [],
            conditions: container.decodeIfPresent([EvidenceLinkedClaim].self, forKey: .conditions) ?? []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case representedEntityRevision = "represented_entity_revision"
        case positionRevisions = "position_revisions"
        case delegationCardRevision = "delegation_card_revision"
        case positionTypes = "position_types"
        case statements
        case reservations
        case conditions
    }
}

public struct IssuePositionMatrixRow: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let issueRevision: SemanticRevisionReference
    public let cells: [IssuePositionMatrixCell]

    public init(issueRevision: SemanticRevisionReference, cells: [IssuePositionMatrixCell]) throws {
        self.issueRevision = issueRevision
        self.cells = cells.sorted()
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.issueRevision < rhs.issueRevision
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = issueRevision.validationIssues()
        if issueRevision.objectType != .issue {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "matrix_row.issue_revision", message: "A matrix row requires an Issue revision."))
        }
        if cells.isEmpty {
            issues.append(ValidationIssue(code: .missingRequiredValue, path: "matrix_row.cells", message: "A published matrix row needs at least one stated position."))
        }
        issues += duplicateIssues(in: cells.map(\.itemID), path: "matrix_row.cells")
        for cell in cells { issues += cell.validationIssues() }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            issueRevision: container.decode(SemanticRevisionReference.self, forKey: .issueRevision),
            cells: container.decode([IssuePositionMatrixCell].self, forKey: .cells)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case issueRevision = "issue_revision"
        case cells
    }
}

public enum BriefingValidationCategory: StableStringValue, Comparable {
    case templateCompatibility
    case schema
    case evidence
    case entity
    case sourceCoverage
    case length
    case provenance
    case contradiction
    case currentInputs
    case classification
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "template_compatibility": self = .templateCompatibility
        case "schema": self = .schema
        case "evidence": self = .evidence
        case "entity": self = .entity
        case "source_coverage": self = .sourceCoverage
        case "length": self = .length
        case "provenance": self = .provenance
        case "contradiction": self = .contradiction
        case "current_inputs": self = .currentInputs
        case "classification": self = .classification
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .templateCompatibility: "template_compatibility"
        case .schema: "schema"
        case .evidence: "evidence"
        case .entity: "entity"
        case .sourceCoverage: "source_coverage"
        case .length: "length"
        case .provenance: "provenance"
        case .contradiction: "contradiction"
        case .currentInputs: "current_inputs"
        case .classification: "classification"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.encodedValue < rhs.encodedValue
    }
}

public enum BriefingValidationCheckStatus: StableStringValue {
    case passed
    case failed
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "passed": self = .passed
        case "failed": self = .failed
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .passed: "passed"
        case .failed: "failed"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum BriefingFindingSeverity: StableStringValue {
    case warning
    case error
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "warning": self = .warning
        case "error": self = .error
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .warning: "warning"
        case .error: "error"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public struct BriefingValidationCheck: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let category: BriefingValidationCategory
    public let status: BriefingValidationCheckStatus
    public let validator: VersionedComponent

    public init(
        category: BriefingValidationCategory,
        status: BriefingValidationCheckStatus,
        validator: VersionedComponent
    ) throws {
        self.category = category
        self.status = status
        self.validator = validator
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.category < rhs.category
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = validator.validationIssues()
        if !category.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "validation_check.category", message: "The validation category is unsupported."))
        }
        if !status.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "validation_check.status", message: "The validation check status is unsupported."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            category: container.decode(BriefingValidationCategory.self, forKey: .category),
            status: container.decode(BriefingValidationCheckStatus.self, forKey: .status),
            validator: container.decode(VersionedComponent.self, forKey: .validator)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case status
        case validator
    }
}

public struct BriefingValidationFinding: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let findingID: ValidationFindingID
    public let category: BriefingValidationCategory
    public let severity: BriefingFindingSeverity
    public let code: String
    public let message: String
    public let affectedRevisions: [SemanticRevisionReference]
    public let evidenceRevisions: [SemanticRevisionReference]
    public let blocking: Bool

    public init(
        findingID: ValidationFindingID,
        category: BriefingValidationCategory,
        severity: BriefingFindingSeverity,
        code: String,
        message: String,
        affectedRevisions: [SemanticRevisionReference] = [],
        evidenceRevisions: [SemanticRevisionReference] = [],
        blocking: Bool
    ) throws {
        self.findingID = findingID
        self.category = category
        self.severity = severity
        self.code = code
        self.message = message
        self.affectedRevisions = affectedRevisions.sorted()
        self.evidenceRevisions = evidenceRevisions.sorted()
        self.blocking = blocking
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.findingID < rhs.findingID
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = boundedLabelIssues(code, path: "validation_finding.code", maximumUTF8Bytes: 96)
        issues += boundedLabelIssues(message, path: "validation_finding.message", maximumUTF8Bytes: 2_048)
        if !category.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "validation_finding.category", message: "The finding category is unsupported."))
        }
        if !severity.isKnown {
            issues.append(ValidationIssue(code: .unsupportedValue, path: "validation_finding.severity", message: "The finding severity is unsupported."))
        }
        issues += duplicateIssues(in: affectedRevisions, path: "validation_finding.affected_revisions")
        issues += duplicateIssues(in: evidenceRevisions, path: "validation_finding.evidence_revisions")
        if evidenceRevisions.contains(where: { $0.objectType != .evidenceRef }) {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "validation_finding.evidence_revisions", message: "Finding evidence must reference EvidenceRef revisions."))
        }
        if blocking != (severity == .error) {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "validation_finding.blocking", message: "Only error findings block publication."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            findingID: container.decode(ValidationFindingID.self, forKey: .findingID),
            category: container.decode(BriefingValidationCategory.self, forKey: .category),
            severity: container.decode(BriefingFindingSeverity.self, forKey: .severity),
            code: container.decode(String.self, forKey: .code),
            message: container.decode(String.self, forKey: .message),
            affectedRevisions: container.decode([SemanticRevisionReference].self, forKey: .affectedRevisions),
            evidenceRevisions: container.decode([SemanticRevisionReference].self, forKey: .evidenceRevisions),
            blocking: container.decode(Bool.self, forKey: .blocking)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case findingID = "finding_id"
        case category
        case severity
        case code
        case message
        case affectedRevisions = "affected_revisions"
        case evidenceRevisions = "evidence_revisions"
        case blocking
    }
}
