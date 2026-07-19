import Foundation

public enum SensitivityLabelRationale: StableStringValue {
    case userSelected
    case inheritedMostRestrictive
    case organizationPolicy
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "user_selected": self = .userSelected
        case "inherited_most_restrictive": self = .inheritedMostRestrictive
        case "organization_policy": self = .organizationPolicy
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .userSelected: "user_selected"
        case .inheritedMostRestrictive: "inherited_most_restrictive"
        case .organizationPolicy: "organization_policy"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum LocalTelemetryMode: StableStringValue {
    case disabled
    case localDiagnostics
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "disabled": self = .disabled
        case "local_diagnostics": self = .localDiagnostics
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .disabled: "disabled"
        case .localDiagnostics: "local_diagnostics"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// Independently revisioned sensitivity metadata for one exact meeting revision.
public struct SensitivityLabelV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<SensitivityLabelIDTag>
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let inheritedClassifications: [DataClassification]
    public let effectiveClassification: DataClassification
    public let rationale: SensitivityLabelRationale
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<SensitivityLabelIDTag>,
        meetingID: MeetingID,
        meetingRevision: SemanticRevisionReference,
        inheritedClassifications: [DataClassification],
        effectiveClassification: DataClassification,
        rationale: SensitivityLabelRationale,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.meetingRevision = meetingRevision
        self.inheritedClassifications = inheritedClassifications.sorted {
            ($0.restrictionRank, $0.encodedValue) < ($1.restrictionRank, $1.encodedValue)
        }
        self.effectiveClassification = effectiveClassification
        self.rationale = rationale
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var labelID: SensitivityLabelID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(
            revision: revision,
            content: SemanticContent(
                meetingID: meetingID,
                meetingRevision: meetingRevision,
                inheritedClassifications: inheritedClassifications,
                effectiveClassification: effectiveClassification,
                rationale: rationale,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .sensitivityLabel,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "SensitivityLabel.v1"
        )
        issues.append(
            contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                meetingRevision,
                expectedTypes: [.meetingProfile],
                revisionInputs: revision.inputRevisions,
                path: "meeting_revision",
                noun: "MeetingProfile revision"
            )
        )
        if meetingRevision.logicalID.canonicalString != meetingID.canonicalString {
            issues.append(Self.issue(.inconsistentValue, "meeting_revision.logical_id", "The sensitivity label must identify its meeting."))
        }
        if inheritedClassifications.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "inherited_classifications", "A sensitivity label requires at least the meeting classification."))
        }
        if inheritedClassifications.contains(where: { !$0.isKnown }) || !effectiveClassification.isKnown {
            issues.append(Self.issue(.unsupportedValue, "effective_classification", "Sensitivity classifications must be recognized."))
        }
        issues.append(contentsOf: duplicateIssues(in: inheritedClassifications, path: "inherited_classifications"))
        if DataClassification.mostRestrictive(inheritedClassifications) != effectiveClassification {
            issues.append(Self.issue(.inconsistentValue, "effective_classification", "The effective label must be the most restrictive inherited classification."))
        }
        if revision.dataClassification != effectiveClassification {
            issues.append(Self.issue(.inconsistentValue, "revision.data_classification", "The revision classification must match the effective sensitivity label."))
        }
        if !rationale.isKnown {
            issues.append(Self.issue(.unsupportedValue, "rationale", "The sensitivity-label rationale is unsupported."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<SensitivityLabelIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            meetingRevision: container.decode(SemanticRevisionReference.self, forKey: .meetingRevision),
            inheritedClassifications: container.decode([DataClassification].self, forKey: .inheritedClassifications),
            effectiveClassification: container.decode(DataClassification.self, forKey: .effectiveClassification),
            rationale: container.decode(SensitivityLabelRationale.self, forKey: .rationale),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case meetingRevision = "meeting_revision"
        case inheritedClassifications = "inherited_classifications"
        case effectiveClassification = "effective_classification"
        case rationale
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }

    private struct SemanticContent: Encodable {
        let meetingID: MeetingID
        let meetingRevision: SemanticRevisionReference
        let inheritedClassifications: [DataClassification]
        let effectiveClassification: DataClassification
        let rationale: SensitivityLabelRationale
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case meetingRevision = "meeting_revision"
            case inheritedClassifications = "inherited_classifications"
            case effectiveClassification = "effective_classification"
            case rationale
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }
}

/// Independently revisioned enforcement policy linked to an exact sensitivity label.
public struct AccessPolicyV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<AccessPolicyIDTag>
    public let meetingID: MeetingID
    public let sensitivityLabelRevision: SemanticRevisionReference
    public let effectiveClassification: DataClassification
    public let localProcessingAllowed: Bool
    public let manualLocalReviewAllowed: Bool
    public let externalProcessingAllowed: Bool
    public let organizationAllowsExternalProcessing: Bool
    public let deploymentAllowsExternalProcessing: Bool
    public let destinationAllowsExternalProcessing: Bool
    public let retentionAllowsExternalProcessing: Bool
    public let requiresVisibleUserAuthorization: Bool
    public let approvedExternalProviderIdentifiers: [String]
    public let noOutboundMode: Bool
    public let telemetryMode: LocalTelemetryMode
    public let localExportAllowed: Bool
    public let trashAllowed: Bool
    public let minimumTrashRetentionDays: UInt16
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<AccessPolicyIDTag>,
        meetingID: MeetingID,
        sensitivityLabelRevision: SemanticRevisionReference,
        effectiveClassification: DataClassification,
        localProcessingAllowed: Bool,
        manualLocalReviewAllowed: Bool,
        externalProcessingAllowed: Bool,
        organizationAllowsExternalProcessing: Bool,
        deploymentAllowsExternalProcessing: Bool,
        destinationAllowsExternalProcessing: Bool,
        retentionAllowsExternalProcessing: Bool,
        requiresVisibleUserAuthorization: Bool,
        approvedExternalProviderIdentifiers: [String],
        noOutboundMode: Bool,
        telemetryMode: LocalTelemetryMode,
        localExportAllowed: Bool,
        trashAllowed: Bool,
        minimumTrashRetentionDays: UInt16,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.sensitivityLabelRevision = sensitivityLabelRevision
        self.effectiveClassification = effectiveClassification
        self.localProcessingAllowed = localProcessingAllowed
        self.manualLocalReviewAllowed = manualLocalReviewAllowed
        self.externalProcessingAllowed = externalProcessingAllowed
        self.organizationAllowsExternalProcessing = organizationAllowsExternalProcessing
        self.deploymentAllowsExternalProcessing = deploymentAllowsExternalProcessing
        self.destinationAllowsExternalProcessing = destinationAllowsExternalProcessing
        self.retentionAllowsExternalProcessing = retentionAllowsExternalProcessing
        self.requiresVisibleUserAuthorization = requiresVisibleUserAuthorization
        self.approvedExternalProviderIdentifiers = approvedExternalProviderIdentifiers.sorted()
        self.noOutboundMode = noOutboundMode
        self.telemetryMode = telemetryMode
        self.localExportAllowed = localExportAllowed
        self.trashAllowed = trashAllowed
        self.minimumTrashRetentionDays = minimumTrashRetentionDays
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var policyID: AccessPolicyID { revision.logicalID }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(
            revision: revision,
            content: SemanticContent(
                meetingID: meetingID,
                sensitivityLabelRevision: sensitivityLabelRevision,
                effectiveClassification: effectiveClassification,
                localProcessingAllowed: localProcessingAllowed,
                manualLocalReviewAllowed: manualLocalReviewAllowed,
                externalProcessingAllowed: externalProcessingAllowed,
                organizationAllowsExternalProcessing: organizationAllowsExternalProcessing,
                deploymentAllowsExternalProcessing: deploymentAllowsExternalProcessing,
                destinationAllowsExternalProcessing: destinationAllowsExternalProcessing,
                retentionAllowsExternalProcessing: retentionAllowsExternalProcessing,
                requiresVisibleUserAuthorization: requiresVisibleUserAuthorization,
                approvedExternalProviderIdentifiers: approvedExternalProviderIdentifiers,
                noOutboundMode: noOutboundMode,
                telemetryMode: telemetryMode,
                localExportAllowed: localExportAllowed,
                trashAllowed: trashAllowed,
                minimumTrashRetentionDays: minimumTrashRetentionDays,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .accessPolicy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "AccessPolicy.v1"
        )
        issues.append(
            contentsOf: IntelligenceRevisionSupport.exactInputIssues(
                sensitivityLabelRevision,
                expectedTypes: [.sensitivityLabel],
                revisionInputs: revision.inputRevisions,
                path: "sensitivity_label_revision",
                noun: "SensitivityLabel revision"
            )
        )
        if !effectiveClassification.isKnown || revision.dataClassification != effectiveClassification {
            issues.append(Self.issue(.inconsistentValue, "effective_classification", "The access policy and revision must carry the same recognized classification."))
        }
        if !localProcessingAllowed && !manualLocalReviewAllowed {
            issues.append(Self.issue(.missingRequiredValue, "local_processing_allowed", "At least one local or manual fallback must remain available."))
        }
        if noOutboundMode {
            if externalProcessingAllowed
                || organizationAllowsExternalProcessing
                || deploymentAllowsExternalProcessing
                || destinationAllowsExternalProcessing
                || retentionAllowsExternalProcessing
                || !approvedExternalProviderIdentifiers.isEmpty
            {
                issues.append(Self.issue(.inconsistentValue, "no_outbound_mode", "No-outbound mode cannot retain any external-processing authority."))
            }
        }
        if effectiveClassification == .restricted, externalProcessingAllowed {
            issues.append(Self.issue(.inconsistentValue, "external_processing_allowed", "Restricted data cannot use external processing in AccessPolicy.v1."))
        }
        let allExternalGatesAllow = organizationAllowsExternalProcessing
            && deploymentAllowsExternalProcessing
            && destinationAllowsExternalProcessing
            && retentionAllowsExternalProcessing
            && requiresVisibleUserAuthorization
            && !approvedExternalProviderIdentifiers.isEmpty
        if externalProcessingAllowed != allExternalGatesAllow {
            issues.append(Self.issue(.inconsistentValue, "external_processing_allowed", "External processing requires every independent policy gate and an approved provider."))
        }
        issues.append(contentsOf: duplicateIssues(in: approvedExternalProviderIdentifiers, path: "approved_external_provider_identifiers"))
        for identifier in approvedExternalProviderIdentifiers {
            issues.append(contentsOf: boundedLabelIssues(identifier, path: "approved_external_provider_identifiers", maximumUTF8Bytes: 128))
        }
        if !telemetryMode.isKnown {
            issues.append(Self.issue(.unsupportedValue, "telemetry_mode", "The telemetry mode is unsupported."))
        }
        if minimumTrashRetentionDays == 0 || minimumTrashRetentionDays > 3_650 {
            issues.append(Self.issue(.invalidRange, "minimum_trash_retention_days", "Trash retention must be between 1 and 3,650 days."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<AccessPolicyIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            sensitivityLabelRevision: container.decode(SemanticRevisionReference.self, forKey: .sensitivityLabelRevision),
            effectiveClassification: container.decode(DataClassification.self, forKey: .effectiveClassification),
            localProcessingAllowed: container.decode(Bool.self, forKey: .localProcessingAllowed),
            manualLocalReviewAllowed: container.decode(Bool.self, forKey: .manualLocalReviewAllowed),
            externalProcessingAllowed: container.decode(Bool.self, forKey: .externalProcessingAllowed),
            organizationAllowsExternalProcessing: container.decode(Bool.self, forKey: .organizationAllowsExternalProcessing),
            deploymentAllowsExternalProcessing: container.decode(Bool.self, forKey: .deploymentAllowsExternalProcessing),
            destinationAllowsExternalProcessing: container.decode(Bool.self, forKey: .destinationAllowsExternalProcessing),
            retentionAllowsExternalProcessing: container.decode(Bool.self, forKey: .retentionAllowsExternalProcessing),
            requiresVisibleUserAuthorization: container.decode(Bool.self, forKey: .requiresVisibleUserAuthorization),
            approvedExternalProviderIdentifiers: container.decode([String].self, forKey: .approvedExternalProviderIdentifiers),
            noOutboundMode: container.decode(Bool.self, forKey: .noOutboundMode),
            telemetryMode: container.decode(LocalTelemetryMode.self, forKey: .telemetryMode),
            localExportAllowed: container.decode(Bool.self, forKey: .localExportAllowed),
            trashAllowed: container.decode(Bool.self, forKey: .trashAllowed),
            minimumTrashRetentionDays: container.decode(UInt16.self, forKey: .minimumTrashRetentionDays),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case sensitivityLabelRevision = "sensitivity_label_revision"
        case effectiveClassification = "effective_classification"
        case localProcessingAllowed = "local_processing_allowed"
        case manualLocalReviewAllowed = "manual_local_review_allowed"
        case externalProcessingAllowed = "external_processing_allowed"
        case organizationAllowsExternalProcessing = "organization_allows_external_processing"
        case deploymentAllowsExternalProcessing = "deployment_allows_external_processing"
        case destinationAllowsExternalProcessing = "destination_allows_external_processing"
        case retentionAllowsExternalProcessing = "retention_allows_external_processing"
        case requiresVisibleUserAuthorization = "requires_visible_user_authorization"
        case approvedExternalProviderIdentifiers = "approved_external_provider_identifiers"
        case noOutboundMode = "no_outbound_mode"
        case telemetryMode = "telemetry_mode"
        case localExportAllowed = "local_export_allowed"
        case trashAllowed = "trash_allowed"
        case minimumTrashRetentionDays = "minimum_trash_retention_days"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }

    private struct SemanticContent: Encodable {
        let meetingID: MeetingID
        let sensitivityLabelRevision: SemanticRevisionReference
        let effectiveClassification: DataClassification
        let localProcessingAllowed: Bool
        let manualLocalReviewAllowed: Bool
        let externalProcessingAllowed: Bool
        let organizationAllowsExternalProcessing: Bool
        let deploymentAllowsExternalProcessing: Bool
        let destinationAllowsExternalProcessing: Bool
        let retentionAllowsExternalProcessing: Bool
        let requiresVisibleUserAuthorization: Bool
        let approvedExternalProviderIdentifiers: [String]
        let noOutboundMode: Bool
        let telemetryMode: LocalTelemetryMode
        let localExportAllowed: Bool
        let trashAllowed: Bool
        let minimumTrashRetentionDays: UInt16
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case sensitivityLabelRevision = "sensitivity_label_revision"
            case effectiveClassification = "effective_classification"
            case localProcessingAllowed = "local_processing_allowed"
            case manualLocalReviewAllowed = "manual_local_review_allowed"
            case externalProcessingAllowed = "external_processing_allowed"
            case organizationAllowsExternalProcessing = "organization_allows_external_processing"
            case deploymentAllowsExternalProcessing = "deployment_allows_external_processing"
            case destinationAllowsExternalProcessing = "destination_allows_external_processing"
            case retentionAllowsExternalProcessing = "retention_allows_external_processing"
            case requiresVisibleUserAuthorization = "requires_visible_user_authorization"
            case approvedExternalProviderIdentifiers = "approved_external_provider_identifiers"
            case noOutboundMode = "no_outbound_mode"
            case telemetryMode = "telemetry_mode"
            case localExportAllowed = "local_export_allowed"
            case trashAllowed = "trash_allowed"
            case minimumTrashRetentionDays = "minimum_trash_retention_days"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }
}

public enum SecurityPolicyGraphValidator {
    public static func validate(
        meeting: MeetingProfileV1,
        sensitivityLabel: SensitivityLabelV1,
        accessPolicy: AccessPolicyV1
    ) throws {
        var issues: [ValidationIssue] = []
        let meetingReference = try SemanticRevisionReference(
            logicalID: meeting.meetingID,
            revisionID: meeting.revision.revisionID
        )
        let labelReference = try SemanticRevisionReference(
            logicalID: sensitivityLabel.labelID,
            revisionID: sensitivityLabel.revision.revisionID
        )
        if sensitivityLabel.meetingID != meeting.meetingID
            || sensitivityLabel.meetingRevision != meetingReference
        {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "sensitivity_label.meeting_revision", message: "The label must reference the exact meeting revision."))
        }
        let inherited = DataClassification.mostRestrictive(
            sensitivityLabel.inheritedClassifications + [meeting.revision.dataClassification]
        )
        if inherited != sensitivityLabel.effectiveClassification {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "sensitivity_label.effective_classification", message: "The label must inherit the most restrictive meeting input."))
        }
        if accessPolicy.meetingID != meeting.meetingID
            || accessPolicy.sensitivityLabelRevision != labelReference
            || accessPolicy.effectiveClassification != sensitivityLabel.effectiveClassification
        {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "access_policy.sensitivity_label_revision", message: "The access policy must bind the exact label and effective classification."))
        }
        if meeting.cloudProcessingPolicy == .localOnly,
           (!accessPolicy.noOutboundMode || accessPolicy.externalProcessingAllowed)
        {
            issues.append(ValidationIssue(code: .inconsistentValue, path: "access_policy.no_outbound_mode", message: "A local-only meeting requires a no-outbound access policy."))
        }
        guard issues.isEmpty else { throw DomainValidationError(issues: issues) }
    }
}
