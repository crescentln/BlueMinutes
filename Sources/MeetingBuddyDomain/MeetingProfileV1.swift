import Foundation

public enum MeetingOrganization: Codable, Hashable, Sendable, DomainValidatable {
    case resolved(actorRevision: SemanticRevisionReference)
    case unresolved(label: String)

    private enum Kind: String, Codable {
        case resolvedActor = "resolved_actor"
        case unresolvedLabel = "unresolved_label"
    }

    public var actorRevision: SemanticRevisionReference? {
        guard case let .resolved(actorRevision) = self else { return nil }
        return actorRevision
    }

    public func validationIssues() -> [ValidationIssue] {
        switch self {
        case let .resolved(actorRevision):
            var issues = actorRevision.validationIssues()
            if actorRevision.objectType != .actor {
                issues.append(
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "organization_or_un_body.actor_revision.object_type",
                        message: "A resolved meeting organization must reference an Actor revision."
                    )
                )
            }
            return issues
        case let .unresolved(label):
            return boundedLabelIssues(
                label,
                path: "organization_or_un_body.label",
                maximumUTF8Bytes: 512
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .resolvedActor:
            self = .resolved(
                actorRevision: try container.decode(
                    SemanticRevisionReference.self,
                    forKey: .actorRevision
                )
            )
        case .unresolvedLabel:
            self = .unresolved(label: try container.decode(String.self, forKey: .label))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .resolved(actorRevision):
            try container.encode(Kind.resolvedActor, forKey: .kind)
            try container.encode(actorRevision, forKey: .actorRevision)
        case let .unresolved(label):
            try container.encode(Kind.unresolvedLabel, forKey: .kind)
            try container.encode(label, forKey: .label)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case actorRevision = "actor_revision"
        case label
    }
}

public struct AgendaItem: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let itemID: AgendaItemID
    public let ordinal: UInt32
    public let title: String

    public init(itemID: AgendaItemID, ordinal: UInt32, title: String) throws {
        self.itemID = itemID
        self.ordinal = ordinal
        self.title = title
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.ordinal != rhs.ordinal { return lhs.ordinal < rhs.ordinal }
        return lhs.itemID < rhs.itemID
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if ordinal == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "agenda_item.ordinal",
                    message: "Agenda-item ordinals are one-based."
                )
            )
        }
        issues.append(
            contentsOf: boundedLabelIssues(
                title,
                path: "agenda_item.title",
                maximumUTF8Bytes: 1_024
            )
        )
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decode(AgendaItemID.self, forKey: .itemID)
        ordinal = try container.decode(UInt32.self, forKey: .ordinal)
        title = try container.decode(String.self, forKey: .title)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case ordinal
        case title
    }
}

public enum MeetingSpeechToTextRouteKind:
    String,
    Codable,
    Hashable,
    Sendable
{
    case recordOnly = "record_only"
    case local
    case approvedRemote = "approved_remote"
}

/// Meeting-owned STT intent. Credentials and one-time upload authorization are
/// deliberately excluded; this stores only the exact route identity needed to
/// explain and restore the meeting workflow.
public struct MeetingSpeechToTextRouteV1:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let kind: MeetingSpeechToTextRouteKind
    public let providerIdentifier: String?
    public let modelIdentifier: String?
    public let intelligenceConfigurationRevision: UInt64?

    public init(
        kind: MeetingSpeechToTextRouteKind,
        providerIdentifier: String? = nil,
        modelIdentifier: String? = nil,
        intelligenceConfigurationRevision: UInt64? = nil
    ) throws {
        self.kind = kind
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
        self.intelligenceConfigurationRevision =
            intelligenceConfigurationRevision
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        let hasProvider = providerIdentifier.map(Self.isOpaqueIdentifier) ?? false
        let hasModel = modelIdentifier.map(Self.isOpaqueIdentifier) ?? false
        let validShape = switch kind {
        case .recordOnly:
            providerIdentifier == nil
                && modelIdentifier == nil
                && intelligenceConfigurationRevision == nil
        case .local:
            hasProvider
                && hasModel
                && intelligenceConfigurationRevision == nil
        case .approvedRemote:
            hasProvider
                && hasModel
                && (intelligenceConfigurationRevision ?? 0) > 0
        }
        guard validShape else {
            return [
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "speech_to_text_route",
                    message:
                        "A meeting STT route must be record-only, one exact local provider/model, or one exact approved remote provider/model and configuration revision."
                )
            ]
        }
        return []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            kind: container.decode(
                MeetingSpeechToTextRouteKind.self,
                forKey: .kind
            ),
            providerIdentifier:
                container.decodeIfPresent(
                    String.self,
                    forKey: .providerIdentifier
                ),
            modelIdentifier:
                container.decodeIfPresent(
                    String.self,
                    forKey: .modelIdentifier
                ),
            intelligenceConfigurationRevision:
                container.decodeIfPresent(
                    UInt64.self,
                    forKey:
                        .intelligenceConfigurationRevision
                )
        )
    }

    private static func isOpaqueIdentifier(
        _ value: String
    ) -> Bool {
        value == value.meetingBuddyTrimmed
            && !value.isEmpty
            && value.utf8.count <= 128
            && !value.meetingBuddyContainsControlCharacter
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains(" ")
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case providerIdentifier =
            "provider_identifier"
        case modelIdentifier = "model_identifier"
        case intelligenceConfigurationRevision =
            "intelligence_configuration_revision"
    }
}

/// MeetingProfile.v1 supports deterministic, AI-free meeting intake.
public struct MeetingProfileV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<MeetingIDTag>
    public let title: String
    public let meetingNumber: String?
    public let meetingDate: CalendarDate?
    public let organizationOrUNBody: MeetingOrganization?
    public let agendaItems: [AgendaItem]
    public let sourceLanguages: [LanguageTag]
    public let outputLanguage: LanguageTag
    public let priorityActorIDs: [ActorID]
    public let briefingTemplateID: BriefingTemplateID?
    public let cloudProcessingPolicy: MeetingCloudProcessingPolicy
    public let speechToTextRoute:
        MeetingSpeechToTextRouteV1?
    public let workspaceID: WorkspaceID?
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<MeetingIDTag>,
        title: String,
        meetingNumber: String? = nil,
        meetingDate: CalendarDate? = nil,
        organizationOrUNBody: MeetingOrganization? = nil,
        agendaItems: [AgendaItem] = [],
        sourceLanguages: [LanguageTag] = [],
        outputLanguage: LanguageTag,
        priorityActorIDs: [ActorID] = [],
        briefingTemplateID: BriefingTemplateID? = nil,
        cloudProcessingPolicy: MeetingCloudProcessingPolicy,
        speechToTextRoute:
            MeetingSpeechToTextRouteV1? = nil,
        workspaceID: WorkspaceID? = nil,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.title = title
        self.meetingNumber = meetingNumber
        self.meetingDate = meetingDate
        self.organizationOrUNBody = organizationOrUNBody
        self.agendaItems = agendaItems.sorted()
        self.sourceLanguages = sourceLanguages.sorted()
        self.outputLanguage = outputLanguage
        self.priorityActorIDs = priorityActorIDs
        self.briefingTemplateID = briefingTemplateID
        self.cloudProcessingPolicy = cloudProcessingPolicy
        self.speechToTextRoute = speechToTextRoute
        self.workspaceID = workspaceID
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var meetingID: MeetingID { revision.logicalID }
    public var sourceAssetRevisions: [SemanticRevisionReference] {
        revision.sourceAssetRevisions
    }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try SemanticHash.sha256(
            of: SemanticProjection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                title: title,
                meetingNumber: meetingNumber,
                meetingDate: meetingDate,
                organizationOrUNBody: organizationOrUNBody,
                agendaItems: agendaItems,
                sourceLanguages: sourceLanguages,
                outputLanguage: outputLanguage,
                priorityActorIDs: priorityActorIDs,
                briefingTemplateID: briefingTemplateID,
                cloudProcessingPolicy: cloudProcessingPolicy,
                speechToTextRoute: speechToTextRoute,
                reviewStatus: reviewStatus,
                userConfirmed: userConfirmed
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .meetingProfile {
            issues.append(Self.issue(.inconsistentValue, "revision.object_type", "MeetingProfile.v1 requires the meeting_profile object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(Self.issue(.unsupportedValue, "revision.schema_version", "MeetingProfile.v1 supports schema version 1.0 only."))
        }
        issues.append(contentsOf: boundedLabelIssues(title, path: "title", maximumUTF8Bytes: 2_048))
        if let meetingNumber {
            issues.append(contentsOf: boundedLabelIssues(meetingNumber, path: "meeting_number", maximumUTF8Bytes: 128))
        }
        if let meetingDate { issues.append(contentsOf: meetingDate.validationIssues()) }
        if let organizationOrUNBody {
            issues.append(contentsOf: organizationOrUNBody.validationIssues())
            if let actorRevision = organizationOrUNBody.actorRevision,
               !revision.inputRevisions.contains(actorRevision)
            {
                issues.append(Self.issue(.missingRequiredValue, "revision.input_revisions", "A resolved meeting organization must appear in input revisions."))
            }
        }
        for item in agendaItems { issues.append(contentsOf: item.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: agendaItems.map(\.itemID), path: "agenda_items.item_id"))
        issues.append(contentsOf: duplicateIssues(in: agendaItems.map(\.ordinal), path: "agenda_items.ordinal"))
        for language in sourceLanguages { issues.append(contentsOf: language.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: sourceLanguages, path: "source_languages"))
        issues.append(contentsOf: outputLanguage.validationIssues())
        issues.append(contentsOf: duplicateIssues(in: priorityActorIDs, path: "priority_actor_ids"))
        if !cloudProcessingPolicy.isKnown {
            issues.append(Self.issue(.unsupportedValue, "cloud_processing_policy", "The meeting cloud-processing policy is not supported by this contract version."))
        }
        if let speechToTextRoute {
            issues.append(
                contentsOf:
                    speechToTextRoute
                    .validationIssues()
            )
            if speechToTextRoute.kind
                == .approvedRemote
            {
                if revision.dataClassification
                    .restrictionRank
                    >= DataClassification.sensitive
                    .restrictionRank
                {
                    issues.append(
                        Self.issue(
                            .inconsistentValue,
                            "speech_to_text_route.kind",
                            "Sensitive and Restricted meetings cannot store a remote STT route."
                        )
                    )
                }
                if cloudProcessingPolicy
                    != .approvedCloudAllowed
                {
                    issues.append(
                        Self.issue(
                            .inconsistentValue,
                            "cloud_processing_policy",
                            "An approved remote STT route requires the meeting cloud-processing policy to allow approved providers."
                        )
                    )
                }
            }
        }
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if userConfirmed, revision.createdBy != .user {
            issues.append(Self.issue(.inconsistentValue, "revision.created_by", "A user-confirmed meeting revision must be created by the user."))
        }
        issues.append(contentsOf: semanticHashIssues(storedHash: revision.semanticContentHash, calculatedHash: calculatedSemanticContentHash, objectName: "MeetingProfile.v1"))
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<MeetingIDTag>.self, forKey: .revision)
        title = try container.decode(String.self, forKey: .title)
        meetingNumber = try container.decodeIfPresent(String.self, forKey: .meetingNumber)
        meetingDate = try container.decodeIfPresent(CalendarDate.self, forKey: .meetingDate)
        organizationOrUNBody = try container.decodeIfPresent(MeetingOrganization.self, forKey: .organizationOrUNBody)
        agendaItems = try container.decodeIfPresent([AgendaItem].self, forKey: .agendaItems)?.sorted() ?? []
        sourceLanguages = try container.decodeIfPresent([LanguageTag].self, forKey: .sourceLanguages)?.sorted() ?? []
        outputLanguage = try container.decode(LanguageTag.self, forKey: .outputLanguage)
        priorityActorIDs = try container.decodeIfPresent([ActorID].self, forKey: .priorityActorIDs) ?? []
        briefingTemplateID = try container.decodeIfPresent(BriefingTemplateID.self, forKey: .briefingTemplateID)
        cloudProcessingPolicy = try container.decode(MeetingCloudProcessingPolicy.self, forKey: .cloudProcessingPolicy)
        speechToTextRoute =
            try container.decodeIfPresent(
                MeetingSpeechToTextRouteV1.self,
                forKey: .speechToTextRoute
            )
        workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID)
        reviewStatus = try container.decode(ReviewStatus.self, forKey: .reviewStatus)
        userConfirmed = try container.decode(Bool.self, forKey: .userConfirmed)
        try validate()
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct SemanticProjection: Encodable {
        let objectType: SemanticObjectType
        let schemaVersion: SchemaVersion
        let dataClassification: DataClassification
        let inputRevisions: [SemanticRevisionReference]
        let sourceAssetRevisions: [SemanticRevisionReference]
        let evidenceRevisions: [SemanticRevisionReference]
        let title: String
        let meetingNumber: String?
        let meetingDate: CalendarDate?
        let organizationOrUNBody: MeetingOrganization?
        let agendaItems: [AgendaItem]
        let sourceLanguages: [LanguageTag]
        let outputLanguage: LanguageTag
        let priorityActorIDs: [ActorID]
        let briefingTemplateID: BriefingTemplateID?
        let cloudProcessingPolicy: MeetingCloudProcessingPolicy
        let speechToTextRoute:
            MeetingSpeechToTextRouteV1?
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case title
            case meetingNumber = "meeting_number"
            case meetingDate = "meeting_date"
            case organizationOrUNBody = "organization_or_un_body"
            case agendaItems = "agenda_items"
            case sourceLanguages = "source_languages"
            case outputLanguage = "output_language"
            case priorityActorIDs = "priority_actor_ids"
            case briefingTemplateID = "briefing_template_id"
            case cloudProcessingPolicy = "cloud_processing_policy"
            case speechToTextRoute =
                "speech_to_text_route"
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case title
        case meetingNumber = "meeting_number"
        case meetingDate = "meeting_date"
        case organizationOrUNBody = "organization_or_un_body"
        case agendaItems = "agenda_items"
        case sourceLanguages = "source_languages"
        case outputLanguage = "output_language"
        case priorityActorIDs = "priority_actor_ids"
        case briefingTemplateID = "briefing_template_id"
        case cloudProcessingPolicy = "cloud_processing_policy"
        case speechToTextRoute =
            "speech_to_text_route"
        case workspaceID = "workspace_id"
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
