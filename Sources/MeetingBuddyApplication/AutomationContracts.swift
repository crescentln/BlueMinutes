import Foundation
import MeetingBuddyDomain

public enum AutomationCommandIDTag: Sendable {}
public enum AutomationReplayNonceTag: Sendable {}
public enum AutomationAuditEventIDTag: Sendable {}
public enum AutomationSettingsEventIDTag: Sendable {}

public typealias AutomationCommandID = StableID<AutomationCommandIDTag>
public typealias AutomationReplayNonce = StableID<AutomationReplayNonceTag>
public typealias AutomationAuditEventID = StableID<AutomationAuditEventIDTag>
public typealias AutomationSettingsEventID = StableID<AutomationSettingsEventIDTag>

public enum AutomationContractError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case invalidCaller(String)
    case unauthorized(String)
    case policyDenied(String)
    case replayDetected(AutomationCommandID)
    case settingsConflict
    case commandUnavailable(String)
    case persistenceFailure(String)
}

public struct AutomationActorID: Codable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard AutomationContractValidation.isIdentifier(rawValue, maximumBytes: 128) else {
            throw AutomationContractError.invalidCaller("The automation actor identifier is invalid.")
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AutomationPermission: String, Codable, CaseIterable, Hashable, Sendable,
    Comparable
{
    case read
    case safeConfiguration = "safe_configuration"
    case operational
    case sensitive

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: UInt8 {
        switch self {
        case .read: 0
        case .safeConfiguration: 1
        case .operational: 2
        case .sensitive: 3
        }
    }
}

public enum AutomationCallerOrigin: String, Codable, Hashable, Sendable {
    case application
    case cli
    case mcp
}

public enum AutomationCallBoundary: String, Codable, Hashable, Sendable {
    case application
    case cli
    case meetingBuddy = "meetingbuddy"
    case inferenceProvider = "inference_provider"
    case externalAgent = "external_agent"
}

/// Authority supplied by a trusted composition root, never by command input.
public struct AutomationCallerContext: Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let actorID: AutomationActorID
    public let origin: AutomationCallerOrigin
    public let maximumPermission: AutomationPermission
    public let adapterVersion: String
    public let ancestorBoundaries: [AutomationCallBoundary]
    public let rootCommandID: AutomationCommandID?
    public let parentCommandID: AutomationCommandID?
    public let hopCount: UInt8

    public init(
        workspaceID: WorkspaceID,
        actorID: AutomationActorID,
        origin: AutomationCallerOrigin,
        maximumPermission: AutomationPermission,
        adapterVersion: String,
        ancestorBoundaries: [AutomationCallBoundary] = [],
        rootCommandID: AutomationCommandID? = nil,
        parentCommandID: AutomationCommandID? = nil,
        hopCount: UInt8 = 0
    ) throws {
        guard AutomationContractValidation.isIdentifier(adapterVersion, maximumBytes: 64),
              ancestorBoundaries.count <= 8,
              (hopCount == 0 && rootCommandID == nil && parentCommandID == nil)
                || (hopCount > 0 && rootCommandID != nil && parentCommandID != nil)
        else {
            throw AutomationContractError.invalidCaller("The automation caller context is invalid.")
        }
        self.workspaceID = workspaceID
        self.actorID = actorID
        self.origin = origin
        self.maximumPermission = maximumPermission
        self.adapterVersion = adapterVersion
        self.ancestorBoundaries = ancestorBoundaries
        self.rootCommandID = rootCommandID
        self.parentCommandID = parentCommandID
        self.hopCount = hopCount
    }

    public var isRecursiveOrProviderOrigin: Bool {
        hopCount > 0
            || ancestorBoundaries.contains(.meetingBuddy)
            || ancestorBoundaries.contains(.inferenceProvider)
    }
}

public enum AutomationConfirmationRequirement: String, Codable, Hashable, Sendable {
    case none
    case trustedApplicationOneTime = "trusted_application_one_time"
}

public enum AutomationPolicyScope: String, Codable, Hashable, Sendable {
    case workspace
    case meeting
}

public enum AutomationModelRouteDisposition: String, Codable, Hashable, Sendable {
    case notApplicable = "not_applicable"
}

public enum AutomationCommandName: String, Codable, CaseIterable, Hashable, Sendable {
    case getCommandCatalog = "get_command_catalog"
    case getWorkspaceStatus = "get_workspace_status"
    case getMeetingPolicyStatus = "get_meeting_policy_status"
    case getStorageReport = "get_storage_report"
    case getSettings = "get_settings"
    case describeSettings = "describe_settings"
    case updateSettings = "update_settings"
    case rollbackSettings = "rollback_settings"
    case listActivity = "list_activity"
    case runWorkspaceDiagnostics = "run_workspace_diagnostics"
}

public struct AutomationCommandDescriptor: Codable, Hashable, Sendable {
    public let name: AutomationCommandName
    public let permission: AutomationPermission
    public let policyScope: AutomationPolicyScope
    public let confirmation: AutomationConfirmationRequirement
    public let changesBusinessState: Bool
    public let usesRestrictedTaskDirectory: Bool

    public init(
        name: AutomationCommandName,
        permission: AutomationPermission,
        policyScope: AutomationPolicyScope,
        confirmation: AutomationConfirmationRequirement = .none,
        changesBusinessState: Bool,
        usesRestrictedTaskDirectory: Bool = false
    ) {
        self.name = name
        self.permission = permission
        self.policyScope = policyScope
        self.confirmation = confirmation
        self.changesBusinessState = changesBusinessState
        self.usesRestrictedTaskDirectory = usesRestrictedTaskDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case permission
        case policyScope = "policy_scope"
        case confirmation
        case changesBusinessState = "changes_business_state"
        case usesRestrictedTaskDirectory = "uses_restricted_task_directory"
    }
}

public enum AutomationUnavailableCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case export
    case providerOrModel = "provider_or_model"
    case recording
    case jobMutation = "job_mutation"
    case destructiveFilesystem = "destructive_filesystem"
    case credentials
    case accessPolicyMutation = "access_policy_mutation"
    case arbitraryPathOrDatabase = "arbitrary_path_or_database"
    case remoteNetworkControl = "remote_network_control"
    case mcp
    case httpServer = "http_server"
}

public struct AutomationUnavailableCapabilityRule: Codable, Hashable, Sendable {
    public let capability: AutomationUnavailableCapability
    public let safeReasonCode: String
    public let futureConfirmationRequirement: AutomationConfirmationRequirement

    public init(
        capability: AutomationUnavailableCapability,
        safeReasonCode: String,
        futureConfirmationRequirement: AutomationConfirmationRequirement
    ) throws {
        guard AutomationContractValidation.isIdentifier(safeReasonCode, maximumBytes: 96) else {
            throw AutomationContractError.invalidRequest("The unavailable-capability rule is invalid.")
        }
        self.capability = capability
        self.safeReasonCode = safeReasonCode
        self.futureConfirmationRequirement = futureConfirmationRequirement
    }

    private enum CodingKeys: String, CodingKey {
        case capability
        case safeReasonCode = "safe_reason_code"
        case futureConfirmationRequirement = "future_confirmation_requirement"
    }
}

public struct AutomationCommandCatalog: Codable, Hashable, Sendable {
    public static let currentVersion = "meetingbuddy-automation-catalog-v2"
    public static let currentPolicyVersion = "meetingbuddy-automation-policy-v1"

    public let version: String
    public let policyVersion: String
    public let commands: [AutomationCommandDescriptor]
    public let unavailableCapabilities: [AutomationUnavailableCapabilityRule]
    public let recursiveCallsAllowed: Bool

    public init() {
        version = Self.currentVersion
        policyVersion = Self.currentPolicyVersion
        commands = AutomationCommandName.allCases.map { name in
            switch name {
            case .updateSettings, .rollbackSettings:
                AutomationCommandDescriptor(
                    name: name,
                    permission: .safeConfiguration,
                    policyScope: .workspace,
                    changesBusinessState: true
                )
            case .runWorkspaceDiagnostics:
                AutomationCommandDescriptor(
                    name: name,
                    permission: .operational,
                    policyScope: .workspace,
                    changesBusinessState: false,
                    usesRestrictedTaskDirectory: true
                )
            case .getMeetingPolicyStatus:
                AutomationCommandDescriptor(
                    name: name,
                    permission: .read,
                    policyScope: .meeting,
                    changesBusinessState: false
                )
            default:
                AutomationCommandDescriptor(
                    name: name,
                    permission: .read,
                    policyScope: .workspace,
                    changesBusinessState: false
                )
            }
        }
        unavailableCapabilities = AutomationUnavailableCapability.allCases
            .filter { $0 != .mcp }
            .map { capability in
                let confirmation: AutomationConfirmationRequirement
                switch capability {
                case .export, .recording, .destructiveFilesystem, .credentials,
                     .accessPolicyMutation, .remoteNetworkControl:
                    confirmation = .trustedApplicationOneTime
                default:
                    confirmation = .none
                }
                return try! AutomationUnavailableCapabilityRule(
                    capability: capability,
                    safeReasonCode: "capability_unavailable_task_009b",
                    futureConfirmationRequirement: confirmation
                )
            }
        recursiveCallsAllowed = false
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = Self()
        guard try container.decode(String.self, forKey: .version) == decoded.version,
              try container.decode(String.self, forKey: .policyVersion)
                == decoded.policyVersion,
              try container.decode([AutomationCommandDescriptor].self, forKey: .commands)
                == decoded.commands,
              try container.decode(
                  [AutomationUnavailableCapabilityRule].self,
                  forKey: .unavailableCapabilities
              ) == decoded.unavailableCapabilities,
              try container.decode(Bool.self, forKey: .recursiveCallsAllowed)
                == decoded.recursiveCallsAllowed
        else {
            throw AutomationContractError.invalidRequest(
                "The automation catalog is not the accepted version."
            )
        }
        self = decoded
    }

    public func descriptor(for name: AutomationCommandName) -> AutomationCommandDescriptor {
        commands.first(where: { $0.name == name })!
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case policyVersion = "policy_version"
        case commands
        case unavailableCapabilities = "unavailable_capabilities"
        case recursiveCallsAllowed = "recursive_calls_allowed"
    }
}

public struct AutomationMeetingPolicyRequest: Codable, Hashable, Sendable {
    public let meetingID: MeetingID

    public init(meetingID: MeetingID) { self.meetingID = meetingID }

    private enum CodingKeys: String, CodingKey { case meetingID = "meeting_id" }
}

public struct AutomationStorageReportRequest: Codable, Hashable, Sendable {
    public let maximumEntries: UInt32

    public init(maximumEntries: UInt32 = 10_000) throws {
        guard (1...100_000).contains(maximumEntries) else {
            throw AutomationContractError.invalidRequest("The storage-report bound is invalid.")
        }
        self.maximumEntries = maximumEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(maximumEntries: container.decode(UInt32.self, forKey: .maximumEntries))
    }

    private enum CodingKeys: String, CodingKey { case maximumEntries = "maximum_entries" }
}

public struct AutomationActivityRequest: Codable, Hashable, Sendable {
    public let limit: UInt16?

    public init(limit: UInt16? = nil) throws {
        guard limit.map({ (1...200).contains($0) }) ?? true else {
            throw AutomationContractError.invalidRequest("The activity-list bound is invalid.")
        }
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(limit: container.decodeIfPresent(UInt16.self, forKey: .limit))
    }

    private enum CodingKeys: String, CodingKey { case limit }
}

public struct AutomationSettingsPatch: Codable, Hashable, Sendable {
    public let expectedVersion: UInt64
    public let statusListLimit: UInt16

    public init(expectedVersion: UInt64, statusListLimit: UInt16) throws {
        guard (1...200).contains(statusListLimit) else {
            throw AutomationContractError.invalidRequest("The status-list limit must be between 1 and 200.")
        }
        self.expectedVersion = expectedVersion
        self.statusListLimit = statusListLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            expectedVersion: container.decode(UInt64.self, forKey: .expectedVersion),
            statusListLimit: container.decode(UInt16.self, forKey: .statusListLimit)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case statusListLimit = "status_list_limit"
    }
}

public struct AutomationSettingsRollbackRequest: Codable, Hashable, Sendable {
    public let targetCommandID: AutomationCommandID
    public let expectedVersion: UInt64

    public init(targetCommandID: AutomationCommandID, expectedVersion: UInt64) {
        self.targetCommandID = targetCommandID
        self.expectedVersion = expectedVersion
    }

    private enum CodingKeys: String, CodingKey {
        case targetCommandID = "target_command_id"
        case expectedVersion = "expected_version"
    }
}

public struct AutomationDiagnosticsRequest: Codable, Hashable, Sendable {
    public let maximumEntries: UInt32

    public init(maximumEntries: UInt32 = 10_000) throws {
        guard (1...100_000).contains(maximumEntries) else {
            throw AutomationContractError.invalidRequest("The diagnostics bound is invalid.")
        }
        self.maximumEntries = maximumEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(maximumEntries: container.decode(UInt32.self, forKey: .maximumEntries))
    }

    private enum CodingKeys: String, CodingKey { case maximumEntries = "maximum_entries" }
}

public enum AutomationCommand: Codable, Hashable, Sendable {
    case getCommandCatalog
    case getWorkspaceStatus
    case getMeetingPolicyStatus(AutomationMeetingPolicyRequest)
    case getStorageReport(AutomationStorageReportRequest)
    case getSettings
    case describeSettings
    case updateSettings(AutomationSettingsPatch)
    case rollbackSettings(AutomationSettingsRollbackRequest)
    case listActivity(AutomationActivityRequest)
    case runWorkspaceDiagnostics(AutomationDiagnosticsRequest)

    public var name: AutomationCommandName {
        switch self {
        case .getCommandCatalog: .getCommandCatalog
        case .getWorkspaceStatus: .getWorkspaceStatus
        case .getMeetingPolicyStatus: .getMeetingPolicyStatus
        case .getStorageReport: .getStorageReport
        case .getSettings: .getSettings
        case .describeSettings: .describeSettings
        case .updateSettings: .updateSettings
        case .rollbackSettings: .rollbackSettings
        case .listActivity: .listActivity
        case .runWorkspaceDiagnostics: .runWorkspaceDiagnostics
        }
    }

    public var meetingID: MeetingID? {
        if case let .getMeetingPolicyStatus(request) = self { return request.meetingID }
        return nil
    }

    public var requiredPermission: AutomationPermission {
        AutomationCommandCatalog().descriptor(for: name).permission
    }

    public var usesRestrictedTaskDirectory: Bool {
        AutomationCommandCatalog().descriptor(for: name).usesRestrictedTaskDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(AutomationCommandName.self, forKey: .name)
        switch name {
        case .getCommandCatalog: self = .getCommandCatalog
        case .getWorkspaceStatus: self = .getWorkspaceStatus
        case .getMeetingPolicyStatus:
            self = .getMeetingPolicyStatus(try container.decode(AutomationMeetingPolicyRequest.self, forKey: .payload))
        case .getStorageReport:
            self = .getStorageReport(try container.decode(AutomationStorageReportRequest.self, forKey: .payload))
        case .getSettings: self = .getSettings
        case .describeSettings: self = .describeSettings
        case .updateSettings:
            self = .updateSettings(try container.decode(AutomationSettingsPatch.self, forKey: .payload))
        case .rollbackSettings:
            self = .rollbackSettings(try container.decode(AutomationSettingsRollbackRequest.self, forKey: .payload))
        case .listActivity:
            self = .listActivity(try container.decode(AutomationActivityRequest.self, forKey: .payload))
        case .runWorkspaceDiagnostics:
            self = .runWorkspaceDiagnostics(try container.decode(AutomationDiagnosticsRequest.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        switch self {
        case let .getMeetingPolicyStatus(payload): try container.encode(payload, forKey: .payload)
        case let .getStorageReport(payload): try container.encode(payload, forKey: .payload)
        case let .updateSettings(payload): try container.encode(payload, forKey: .payload)
        case let .rollbackSettings(payload): try container.encode(payload, forKey: .payload)
        case let .listActivity(payload): try container.encode(payload, forKey: .payload)
        case let .runWorkspaceDiagnostics(payload): try container.encode(payload, forKey: .payload)
        default: break
        }
    }

    private enum CodingKeys: String, CodingKey { case name; case payload }
}

public struct AutomationCommandRequest: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt16 = 1

    public let schemaVersion: UInt16
    public let commandID: AutomationCommandID
    public let replayNonce: AutomationReplayNonce
    public let command: AutomationCommand
    public let issuedAt: UTCInstant

    public init(
        commandID: AutomationCommandID,
        replayNonce: AutomationReplayNonce,
        command: AutomationCommand,
        issuedAt: UTCInstant
    ) {
        schemaVersion = Self.schemaVersion
        self.commandID = commandID
        self.replayNonce = replayNonce
        self.command = command
        self.issuedAt = issuedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
        guard decodedVersion == Self.schemaVersion else {
            throw AutomationContractError.invalidRequest("The automation command schema is unsupported.")
        }
        schemaVersion = decodedVersion
        commandID = try container.decode(AutomationCommandID.self, forKey: .commandID)
        replayNonce = try container.decode(AutomationReplayNonce.self, forKey: .replayNonce)
        command = try container.decode(AutomationCommand.self, forKey: .command)
        issuedAt = try container.decode(UTCInstant.self, forKey: .issuedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commandID = "command_id"
        case replayNonce = "replay_nonce"
        case command
        case issuedAt = "issued_at"
    }
}

public struct AutomationSettingsValues: Codable, Hashable, Sendable {
    public static let compiledDefault = try! AutomationSettingsValues(statusListLimit: 50)

    public let statusListLimit: UInt16

    public init(statusListLimit: UInt16) throws {
        guard (1...200).contains(statusListLimit) else {
            throw AutomationContractError.invalidRequest("The status-list limit must be between 1 and 200.")
        }
        self.statusListLimit = statusListLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(statusListLimit: container.decode(UInt16.self, forKey: .statusListLimit))
    }

    private enum CodingKeys: String, CodingKey { case statusListLimit = "status_list_limit" }
}

public struct VersionedAutomationSettings: Codable, Hashable, Sendable {
    public let version: UInt64
    public let values: AutomationSettingsValues
    public let updatedAt: UTCInstant?
    public let updatedByCommandID: AutomationCommandID?

    public init(
        version: UInt64,
        values: AutomationSettingsValues,
        updatedAt: UTCInstant?,
        updatedByCommandID: AutomationCommandID?
    ) throws {
        guard (version == 0 && updatedAt == nil && updatedByCommandID == nil)
                || (version > 0 && updatedAt != nil && updatedByCommandID != nil)
        else {
            throw AutomationContractError.invalidRequest("The versioned automation settings are inconsistent.")
        }
        self.version = version
        self.values = values
        self.updatedAt = updatedAt
        self.updatedByCommandID = updatedByCommandID
    }

    public static var compiledDefault: Self {
        try! Self(version: 0, values: .compiledDefault, updatedAt: nil, updatedByCommandID: nil)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decode(UInt64.self, forKey: .version),
            values: container.decode(AutomationSettingsValues.self, forKey: .values),
            updatedAt: container.decodeIfPresent(UTCInstant.self, forKey: .updatedAt),
            updatedByCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .updatedByCommandID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case values
        case updatedAt = "updated_at"
        case updatedByCommandID = "updated_by_command_id"
    }
}

public struct AutomationSettingDescription: Codable, Hashable, Sendable {
    public let key: String
    public let valueType: String
    public let minimum: UInt64
    public let maximum: UInt64
    public let compiledDefault: UInt64
    public let patchable: Bool

    private enum CodingKeys: String, CodingKey {
        case key
        case valueType = "value_type"
        case minimum
        case maximum
        case compiledDefault = "compiled_default"
        case patchable
    }
}

public struct AutomationSettingsDescription: Codable, Hashable, Sendable {
    public let settings: [AutomationSettingDescription]
    public let protectedSettings: [String]

    public init() {
        settings = [
            AutomationSettingDescription(
                key: "status_list_limit",
                valueType: "uint16",
                minimum: 1,
                maximum: 200,
                compiledDefault: 50,
                patchable: true
            )
        ]
        protectedSettings = [
            "access_policy",
            "credentials",
            "model_route",
            "no_outbound_mode",
            "provider_authority",
            "recording_authority",
            "workspace_path"
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case settings
        case protectedSettings = "protected_settings"
    }
}

public struct AutomationWorkspaceStatus: Codable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let databaseSchemaVersion: UInt32
    public let semanticRevisionCount: UInt64
    public let jobCount: UInt64
    public let activeJobCount: UInt64
    public let commandCount: UInt64
    public let incompleteCommandCount: UInt64

    public init(
        workspaceID: WorkspaceID,
        databaseSchemaVersion: UInt32,
        semanticRevisionCount: UInt64,
        jobCount: UInt64,
        activeJobCount: UInt64,
        commandCount: UInt64,
        incompleteCommandCount: UInt64
    ) {
        self.workspaceID = workspaceID
        self.databaseSchemaVersion = databaseSchemaVersion
        self.semanticRevisionCount = semanticRevisionCount
        self.jobCount = jobCount
        self.activeJobCount = activeJobCount
        self.commandCount = commandCount
        self.incompleteCommandCount = incompleteCommandCount
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case databaseSchemaVersion = "database_schema_version"
        case semanticRevisionCount = "semantic_revision_count"
        case jobCount = "job_count"
        case activeJobCount = "active_job_count"
        case commandCount = "command_count"
        case incompleteCommandCount = "incomplete_command_count"
    }
}

public struct AutomationMeetingPolicyStatus: Codable, Hashable, Sendable {
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let sensitivityLabelRevision: SemanticRevisionReference
    public let accessPolicyRevision: SemanticRevisionReference
    public let effectiveClassification: DataClassification
    public let noOutboundMode: Bool
    public let localProcessingAllowed: Bool
    public let manualLocalReviewAllowed: Bool
    public let localExportAllowed: Bool
    public let trashAllowed: Bool
    public let modelRouteDisposition: AutomationModelRouteDisposition

    private enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case meetingRevision = "meeting_revision"
        case sensitivityLabelRevision = "sensitivity_label_revision"
        case accessPolicyRevision = "access_policy_revision"
        case effectiveClassification = "effective_classification"
        case noOutboundMode = "no_outbound_mode"
        case localProcessingAllowed = "local_processing_allowed"
        case manualLocalReviewAllowed = "manual_local_review_allowed"
        case localExportAllowed = "local_export_allowed"
        case trashAllowed = "trash_allowed"
        case modelRouteDisposition = "model_route_disposition"
    }
}

public struct AutomationStorageCategoryUsage: Codable, Hashable, Sendable {
    public let category: WorkspaceStorageCategory
    public let byteCount: UInt64
    public let fileCount: UInt64

    public init(_ usage: WorkspaceStorageCategoryUsage) {
        category = usage.category
        byteCount = usage.byteCount
        fileCount = usage.fileCount
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case byteCount = "byte_count"
        case fileCount = "file_count"
    }
}

public struct AutomationStorageReport: Codable, Hashable, Sendable {
    public let calculatedAt: UTCInstant
    public let totalByteCount: UInt64
    public let categories: [AutomationStorageCategoryUsage]
    public let trashItemCount: UInt64
    public let permissionIssueCount: UInt64
    public let scanTruncated: Bool

    public init(_ report: WorkspaceStorageReport) {
        calculatedAt = report.calculatedAt
        totalByteCount = report.totalByteCount
        categories = report.categories.map(AutomationStorageCategoryUsage.init)
        trashItemCount = UInt64(report.trashItems.count)
        permissionIssueCount = report.permissionIssueCount
        scanTruncated = report.scanTruncated
    }

    private enum CodingKeys: String, CodingKey {
        case calculatedAt = "calculated_at"
        case totalByteCount = "total_byte_count"
        case categories
        case trashItemCount = "trash_item_count"
        case permissionIssueCount = "permission_issue_count"
        case scanTruncated = "scan_truncated"
    }
}

public struct AutomationDiagnosticsReport: Codable, Hashable, Sendable {
    public let calculatedAt: UTCInstant
    public let databaseQuickCheckPassed: Bool
    public let foreignKeyFailureCount: UInt64
    public let incompleteCommandCount: UInt64
    public let storagePermissionIssueCount: UInt64
    public let storageScanTruncated: Bool
    public let usedRestrictedTaskDirectory: Bool

    public init(
        calculatedAt: UTCInstant,
        databaseQuickCheckPassed: Bool,
        foreignKeyFailureCount: UInt64,
        incompleteCommandCount: UInt64,
        storagePermissionIssueCount: UInt64,
        storageScanTruncated: Bool,
        usedRestrictedTaskDirectory: Bool
    ) {
        self.calculatedAt = calculatedAt
        self.databaseQuickCheckPassed = databaseQuickCheckPassed
        self.foreignKeyFailureCount = foreignKeyFailureCount
        self.incompleteCommandCount = incompleteCommandCount
        self.storagePermissionIssueCount = storagePermissionIssueCount
        self.storageScanTruncated = storageScanTruncated
        self.usedRestrictedTaskDirectory = usedRestrictedTaskDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case calculatedAt = "calculated_at"
        case databaseQuickCheckPassed = "database_quick_check_passed"
        case foreignKeyFailureCount = "foreign_key_failure_count"
        case incompleteCommandCount = "incomplete_command_count"
        case storagePermissionIssueCount = "storage_permission_issue_count"
        case storageScanTruncated = "storage_scan_truncated"
        case usedRestrictedTaskDirectory = "used_restricted_task_directory"
    }
}

public enum AutomationCommandResult: Codable, Hashable, Sendable {
    case commandCatalog(AutomationCommandCatalog)
    case workspaceStatus(AutomationWorkspaceStatus)
    case meetingPolicyStatus(AutomationMeetingPolicyStatus)
    case storageReport(AutomationStorageReport)
    case settings(VersionedAutomationSettings)
    case settingsDescription(AutomationSettingsDescription)
    case activity([AutomationAuditTrail])
    case diagnostics(AutomationDiagnosticsReport)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .commandCatalog: self = .commandCatalog(try container.decode(AutomationCommandCatalog.self, forKey: .value))
        case .workspaceStatus: self = .workspaceStatus(try container.decode(AutomationWorkspaceStatus.self, forKey: .value))
        case .meetingPolicyStatus: self = .meetingPolicyStatus(try container.decode(AutomationMeetingPolicyStatus.self, forKey: .value))
        case .storageReport: self = .storageReport(try container.decode(AutomationStorageReport.self, forKey: .value))
        case .settings: self = .settings(try container.decode(VersionedAutomationSettings.self, forKey: .value))
        case .settingsDescription: self = .settingsDescription(try container.decode(AutomationSettingsDescription.self, forKey: .value))
        case .activity: self = .activity(try container.decode([AutomationAuditTrail].self, forKey: .value))
        case .diagnostics: self = .diagnostics(try container.decode(AutomationDiagnosticsReport.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .commandCatalog(value): try container.encode(Kind.commandCatalog, forKey: .kind); try container.encode(value, forKey: .value)
        case let .workspaceStatus(value): try container.encode(Kind.workspaceStatus, forKey: .kind); try container.encode(value, forKey: .value)
        case let .meetingPolicyStatus(value): try container.encode(Kind.meetingPolicyStatus, forKey: .kind); try container.encode(value, forKey: .value)
        case let .storageReport(value): try container.encode(Kind.storageReport, forKey: .kind); try container.encode(value, forKey: .value)
        case let .settings(value): try container.encode(Kind.settings, forKey: .kind); try container.encode(value, forKey: .value)
        case let .settingsDescription(value): try container.encode(Kind.settingsDescription, forKey: .kind); try container.encode(value, forKey: .value)
        case let .activity(value): try container.encode(Kind.activity, forKey: .kind); try container.encode(value, forKey: .value)
        case let .diagnostics(value): try container.encode(Kind.diagnostics, forKey: .kind); try container.encode(value, forKey: .value)
        }
    }

    private enum CodingKeys: String, CodingKey { case kind; case value }
    private enum Kind: String, Codable {
        case commandCatalog = "command_catalog"
        case workspaceStatus = "workspace_status"
        case meetingPolicyStatus = "meeting_policy_status"
        case storageReport = "storage_report"
        case settings
        case settingsDescription = "settings_description"
        case activity
        case diagnostics
    }
}

public struct AutomationCommandExecution: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt16 = 1

    public let schemaVersion: UInt16
    public let commandID: AutomationCommandID
    public let commandName: AutomationCommandName
    public let result: AutomationCommandResult

    public init(
        commandID: AutomationCommandID,
        commandName: AutomationCommandName,
        result: AutomationCommandResult
    ) {
        schemaVersion = Self.schemaVersion
        self.commandID = commandID
        self.commandName = commandName
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commandID = "command_id"
        case commandName = "command_name"
        case result
    }
}

public struct AutomationPolicyEvidence: Codable, Hashable, Sendable {
    public let policyVersion: String
    public let meetingRevision: SemanticRevisionReference?
    public let sensitivityLabelRevision: SemanticRevisionReference?
    public let accessPolicyRevision: SemanticRevisionReference?
    public let effectiveClassification: DataClassification?
    public let modelRouteDisposition: AutomationModelRouteDisposition

    public init(
        meetingRevision: SemanticRevisionReference? = nil,
        sensitivityLabelRevision: SemanticRevisionReference? = nil,
        accessPolicyRevision: SemanticRevisionReference? = nil,
        effectiveClassification: DataClassification? = nil
    ) throws {
        let values = [meetingRevision != nil, sensitivityLabelRevision != nil, accessPolicyRevision != nil, effectiveClassification != nil]
        guard values.allSatisfy({ $0 }) || values.allSatisfy({ !$0 }),
              meetingRevision.map({ $0.objectType == .meetingProfile }) ?? true,
              sensitivityLabelRevision.map({ $0.objectType == .sensitivityLabel }) ?? true,
              accessPolicyRevision.map({ $0.objectType == .accessPolicy }) ?? true
        else {
            throw AutomationContractError.invalidRequest("The automation policy evidence is incomplete.")
        }
        policyVersion = AutomationCommandCatalog.currentPolicyVersion
        self.meetingRevision = meetingRevision
        self.sensitivityLabelRevision = sensitivityLabelRevision
        self.accessPolicyRevision = accessPolicyRevision
        self.effectiveClassification = effectiveClassification
        modelRouteDisposition = .notApplicable
    }

    public static var workspace: Self { try! Self() }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPolicyVersion = try container.decode(String.self, forKey: .policyVersion)
        let decodedModelRoute = try container.decode(
            AutomationModelRouteDisposition.self,
            forKey: .modelRouteDisposition
        )
        guard decodedPolicyVersion == AutomationCommandCatalog.currentPolicyVersion,
              decodedModelRoute == .notApplicable
        else {
            throw AutomationContractError.invalidRequest(
                "The automation policy evidence version is unsupported."
            )
        }
        try self.init(
            meetingRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .meetingRevision
            ),
            sensitivityLabelRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .sensitivityLabelRevision
            ),
            accessPolicyRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .accessPolicyRevision
            ),
            effectiveClassification: container.decodeIfPresent(
                DataClassification.self,
                forKey: .effectiveClassification
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case meetingRevision = "meeting_revision"
        case sensitivityLabelRevision = "sensitivity_label_revision"
        case accessPolicyRevision = "access_policy_revision"
        case effectiveClassification = "effective_classification"
        case modelRouteDisposition = "model_route_disposition"
    }
}

public struct AutomationSecurityContext: Sendable {
    public let meeting: MeetingProfileV1
    public let sensitivityLabel: SensitivityLabelV1
    public let accessPolicy: AccessPolicyV1

    public init(
        meeting: MeetingProfileV1,
        sensitivityLabel: SensitivityLabelV1,
        accessPolicy: AccessPolicyV1
    ) throws {
        guard meeting.revision.lifecycleStatus == .published,
              sensitivityLabel.revision.lifecycleStatus == .published,
              accessPolicy.revision.lifecycleStatus == .published
        else {
            throw AutomationContractError.policyDenied("automation_policy_not_published")
        }
        try SecurityPolicyGraphValidator.validate(
            meeting: meeting,
            sensitivityLabel: sensitivityLabel,
            accessPolicy: accessPolicy
        )
        self.meeting = meeting
        self.sensitivityLabel = sensitivityLabel
        self.accessPolicy = accessPolicy
    }

    public var evidence: AutomationPolicyEvidence {
        get throws {
            try AutomationPolicyEvidence(
                meetingRevision: SemanticRevisionReference(
                    logicalID: meeting.meetingID,
                    revisionID: meeting.revision.revisionID
                ),
                sensitivityLabelRevision: SemanticRevisionReference(
                    logicalID: sensitivityLabel.labelID,
                    revisionID: sensitivityLabel.revision.revisionID
                ),
                accessPolicyRevision: SemanticRevisionReference(
                    logicalID: accessPolicy.policyID,
                    revisionID: accessPolicy.revision.revisionID
                ),
                effectiveClassification: accessPolicy.effectiveClassification
            )
        }
    }

    public var status: AutomationMeetingPolicyStatus {
        get throws {
            let evidence = try evidence
            return AutomationMeetingPolicyStatus(
                meetingID: meeting.meetingID,
                meetingRevision: evidence.meetingRevision!,
                sensitivityLabelRevision: evidence.sensitivityLabelRevision!,
                accessPolicyRevision: evidence.accessPolicyRevision!,
                effectiveClassification: accessPolicy.effectiveClassification,
                noOutboundMode: accessPolicy.noOutboundMode,
                localProcessingAllowed: accessPolicy.localProcessingAllowed,
                manualLocalReviewAllowed: accessPolicy.manualLocalReviewAllowed,
                localExportAllowed: accessPolicy.localExportAllowed,
                trashAllowed: accessPolicy.trashAllowed,
                modelRouteDisposition: .notApplicable
            )
        }
    }
}

public enum AutomationAuthorizationDecision: String, Codable, Hashable, Sendable {
    case authorized
    case denied
    case replayed
}

public struct AutomationCommandRecord: Codable, Hashable, Sendable {
    public let commandID: AutomationCommandID
    public let replayNonce: AutomationReplayNonce
    public let claimsReplayNonce: Bool
    public let replayOfCommandID: AutomationCommandID?
    public let commandName: AutomationCommandName
    public let requestDigest: ContentDigest
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID?
    public let actorID: AutomationActorID
    public let origin: AutomationCallerOrigin
    public let adapterVersion: String
    public let grantedPermission: AutomationPermission
    public let requiredPermission: AutomationPermission
    public let decision: AutomationAuthorizationDecision
    public let safeReasonCode: String
    public let policyEvidence: AutomationPolicyEvidence
    public let confirmationRequirement: AutomationConfirmationRequirement
    public let rootCommandID: AutomationCommandID?
    public let parentCommandID: AutomationCommandID?
    public let hopCount: UInt8
    public let recordedAt: UTCInstant

    public init(
        commandID: AutomationCommandID,
        replayNonce: AutomationReplayNonce,
        claimsReplayNonce: Bool,
        replayOfCommandID: AutomationCommandID?,
        commandName: AutomationCommandName,
        requestDigest: ContentDigest,
        caller: AutomationCallerContext,
        meetingID: MeetingID?,
        requiredPermission: AutomationPermission,
        decision: AutomationAuthorizationDecision,
        safeReasonCode: String,
        policyEvidence: AutomationPolicyEvidence,
        confirmationRequirement: AutomationConfirmationRequirement = .none,
        recordedAt: UTCInstant
    ) throws {
        guard AutomationContractValidation.isIdentifier(safeReasonCode, maximumBytes: 96),
              requestDigest.algorithm == .sha256,
              (claimsReplayNonce && replayOfCommandID == nil && decision != .replayed)
                || (!claimsReplayNonce && replayOfCommandID != nil && decision == .replayed),
              (policyEvidence.meetingRevision == nil || meetingID != nil),
              (decision != .authorized || meetingID == nil
                || policyEvidence.meetingRevision != nil),
              decision != .authorized || caller.maximumPermission >= requiredPermission
        else {
            throw AutomationContractError.invalidRequest("The automation command record is inconsistent.")
        }
        self.commandID = commandID
        self.replayNonce = replayNonce
        self.claimsReplayNonce = claimsReplayNonce
        self.replayOfCommandID = replayOfCommandID
        self.commandName = commandName
        self.requestDigest = requestDigest
        workspaceID = caller.workspaceID
        self.meetingID = meetingID
        actorID = caller.actorID
        origin = caller.origin
        adapterVersion = caller.adapterVersion
        grantedPermission = caller.maximumPermission
        self.requiredPermission = requiredPermission
        self.decision = decision
        self.safeReasonCode = safeReasonCode
        self.policyEvidence = policyEvidence
        self.confirmationRequirement = confirmationRequirement
        rootCommandID = caller.rootCommandID
        parentCommandID = caller.parentCommandID
        hopCount = caller.hopCount
        self.recordedAt = recordedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let caller = try AutomationCallerContext(
            workspaceID: container.decode(WorkspaceID.self, forKey: .workspaceID),
            actorID: container.decode(AutomationActorID.self, forKey: .actorID),
            origin: container.decode(AutomationCallerOrigin.self, forKey: .origin),
            maximumPermission: container.decode(AutomationPermission.self, forKey: .grantedPermission),
            adapterVersion: container.decode(String.self, forKey: .adapterVersion),
            rootCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .rootCommandID),
            parentCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .parentCommandID),
            hopCount: container.decode(UInt8.self, forKey: .hopCount)
        )
        try self.init(
            commandID: container.decode(AutomationCommandID.self, forKey: .commandID),
            replayNonce: container.decode(AutomationReplayNonce.self, forKey: .replayNonce),
            claimsReplayNonce: container.decode(Bool.self, forKey: .claimsReplayNonce),
            replayOfCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .replayOfCommandID),
            commandName: container.decode(AutomationCommandName.self, forKey: .commandName),
            requestDigest: container.decode(ContentDigest.self, forKey: .requestDigest),
            caller: caller,
            meetingID: container.decodeIfPresent(MeetingID.self, forKey: .meetingID),
            requiredPermission: container.decode(AutomationPermission.self, forKey: .requiredPermission),
            decision: container.decode(AutomationAuthorizationDecision.self, forKey: .decision),
            safeReasonCode: container.decode(String.self, forKey: .safeReasonCode),
            policyEvidence: container.decode(AutomationPolicyEvidence.self, forKey: .policyEvidence),
            confirmationRequirement: container.decode(AutomationConfirmationRequirement.self, forKey: .confirmationRequirement),
            recordedAt: container.decode(UTCInstant.self, forKey: .recordedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case replayNonce = "replay_nonce"
        case claimsReplayNonce = "claims_replay_nonce"
        case replayOfCommandID = "replay_of_command_id"
        case commandName = "command_name"
        case requestDigest = "request_digest"
        case workspaceID = "workspace_id"
        case meetingID = "meeting_id"
        case actorID = "actor_id"
        case origin
        case adapterVersion = "adapter_version"
        case grantedPermission = "granted_permission"
        case requiredPermission = "required_permission"
        case decision
        case safeReasonCode = "safe_reason_code"
        case policyEvidence = "policy_evidence"
        case confirmationRequirement = "confirmation_requirement"
        case rootCommandID = "root_command_id"
        case parentCommandID = "parent_command_id"
        case hopCount = "hop_count"
        case recordedAt = "recorded_at"
    }
}

public enum AutomationCommandOutcome: String, Codable, Hashable, Sendable {
    case completed
    case failed
    case rejected
    case rolledBack = "rolled_back"
}

public struct AutomationCommandResultEvent: Codable, Hashable, Sendable {
    public let eventID: AutomationAuditEventID
    public let commandID: AutomationCommandID
    public let sequence: UInt16
    public let outcome: AutomationCommandOutcome
    public let safeCode: String
    public let resultDigest: ContentDigest?
    public let priorSettingsVersion: UInt64?
    public let replacementSettingsVersion: UInt64?
    public let rollbackOfCommandID: AutomationCommandID?
    public let usedRestrictedTaskDirectory: Bool
    public let occurredAt: UTCInstant

    public init(
        eventID: AutomationAuditEventID,
        commandID: AutomationCommandID,
        outcome: AutomationCommandOutcome,
        safeCode: String,
        resultDigest: ContentDigest?,
        priorSettingsVersion: UInt64? = nil,
        replacementSettingsVersion: UInt64? = nil,
        rollbackOfCommandID: AutomationCommandID? = nil,
        usedRestrictedTaskDirectory: Bool = false,
        occurredAt: UTCInstant
    ) throws {
        guard AutomationContractValidation.isIdentifier(safeCode, maximumBytes: 96),
              resultDigest.map({ $0.algorithm == .sha256 }) ?? true,
              (priorSettingsVersion == nil) == (replacementSettingsVersion == nil),
              priorSettingsVersion.map({ replacementSettingsVersion == $0 + 1 }) ?? true,
              outcome == .completed || outcome == .rolledBack || resultDigest == nil,
              outcome != .rolledBack || rollbackOfCommandID != nil
        else {
            throw AutomationContractError.invalidRequest("The automation result event is inconsistent.")
        }
        self.eventID = eventID
        self.commandID = commandID
        sequence = 1
        self.outcome = outcome
        self.safeCode = safeCode
        self.resultDigest = resultDigest
        self.priorSettingsVersion = priorSettingsVersion
        self.replacementSettingsVersion = replacementSettingsVersion
        self.rollbackOfCommandID = rollbackOfCommandID
        self.usedRestrictedTaskDirectory = usedRestrictedTaskDirectory
        self.occurredAt = occurredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSequence = try container.decode(UInt16.self, forKey: .sequence)
        guard decodedSequence == 1 else {
            throw AutomationContractError.invalidRequest("The automation result sequence is unsupported.")
        }
        try self.init(
            eventID: container.decode(AutomationAuditEventID.self, forKey: .eventID),
            commandID: container.decode(AutomationCommandID.self, forKey: .commandID),
            outcome: container.decode(AutomationCommandOutcome.self, forKey: .outcome),
            safeCode: container.decode(String.self, forKey: .safeCode),
            resultDigest: container.decodeIfPresent(ContentDigest.self, forKey: .resultDigest),
            priorSettingsVersion: container.decodeIfPresent(UInt64.self, forKey: .priorSettingsVersion),
            replacementSettingsVersion: container.decodeIfPresent(UInt64.self, forKey: .replacementSettingsVersion),
            rollbackOfCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .rollbackOfCommandID),
            usedRestrictedTaskDirectory: container.decode(Bool.self, forKey: .usedRestrictedTaskDirectory),
            occurredAt: container.decode(UTCInstant.self, forKey: .occurredAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case commandID = "command_id"
        case sequence
        case outcome
        case safeCode = "safe_code"
        case resultDigest = "result_digest"
        case priorSettingsVersion = "prior_settings_version"
        case replacementSettingsVersion = "replacement_settings_version"
        case rollbackOfCommandID = "rollback_of_command_id"
        case usedRestrictedTaskDirectory = "used_restricted_task_directory"
        case occurredAt = "occurred_at"
    }
}

public struct AutomationSettingsEvent: Codable, Hashable, Sendable {
    public let eventID: AutomationSettingsEventID
    public let commandID: AutomationCommandID
    public let prior: VersionedAutomationSettings
    public let replacement: VersionedAutomationSettings
    public let rollbackOfCommandID: AutomationCommandID?
    public let occurredAt: UTCInstant

    public init(
        eventID: AutomationSettingsEventID,
        commandID: AutomationCommandID,
        prior: VersionedAutomationSettings,
        replacement: VersionedAutomationSettings,
        rollbackOfCommandID: AutomationCommandID?,
        occurredAt: UTCInstant
    ) throws {
        guard replacement.version == prior.version + 1,
              replacement.updatedByCommandID == commandID,
              replacement.updatedAt == occurredAt,
              prior.values != replacement.values
        else {
            throw AutomationContractError.invalidRequest("The automation settings event is inconsistent.")
        }
        self.eventID = eventID
        self.commandID = commandID
        self.prior = prior
        self.replacement = replacement
        self.rollbackOfCommandID = rollbackOfCommandID
        self.occurredAt = occurredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            eventID: container.decode(AutomationSettingsEventID.self, forKey: .eventID),
            commandID: container.decode(AutomationCommandID.self, forKey: .commandID),
            prior: container.decode(VersionedAutomationSettings.self, forKey: .prior),
            replacement: container.decode(VersionedAutomationSettings.self, forKey: .replacement),
            rollbackOfCommandID: container.decodeIfPresent(AutomationCommandID.self, forKey: .rollbackOfCommandID),
            occurredAt: container.decode(UTCInstant.self, forKey: .occurredAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case commandID = "command_id"
        case prior
        case replacement
        case rollbackOfCommandID = "rollback_of_command_id"
        case occurredAt = "occurred_at"
    }
}

public struct AutomationAuditTrail: Codable, Hashable, Sendable {
    public let record: AutomationCommandRecord
    public let inputRevisions: [SemanticRevisionReference]
    public let resultEvents: [AutomationCommandResultEvent]

    public init(
        record: AutomationCommandRecord,
        inputRevisions: [SemanticRevisionReference],
        resultEvents: [AutomationCommandResultEvent]
    ) throws {
        let inputs = inputRevisions.sorted()
        let events = resultEvents.sorted { ($0.sequence, $0.eventID) < ($1.sequence, $1.eventID) }
        guard Set(inputs).count == inputs.count,
              events.allSatisfy({ $0.commandID == record.commandID }),
              events.count <= 1
        else {
            throw AutomationContractError.invalidRequest("The automation audit trail is inconsistent.")
        }
        self.record = record
        self.inputRevisions = inputs
        self.resultEvents = events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            record: container.decode(AutomationCommandRecord.self, forKey: .record),
            inputRevisions: container.decode(
                [SemanticRevisionReference].self,
                forKey: .inputRevisions
            ),
            resultEvents: container.decode(
                [AutomationCommandResultEvent].self,
                forKey: .resultEvents
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case record
        case inputRevisions = "input_revisions"
        case resultEvents = "result_events"
    }
}

public enum AutomationCommandClaimResult: Hashable, Sendable {
    case claimed
    case replayed(originalCommandID: AutomationCommandID)
    case duplicateCommandID(existingDigest: ContentDigest)
}

public protocol AutomationCommandRepository: Sendable {
    func claimAutomationCommand(
        _ record: AutomationCommandRecord,
        inputRevisions: [SemanticRevisionReference]
    ) throws -> AutomationCommandClaimResult

    func recordAutomationReplay(
        _ record: AutomationCommandRecord,
        result: AutomationCommandResultEvent
    ) throws

    func appendAutomationResult(_ event: AutomationCommandResultEvent) throws

    func currentAutomationSettings() throws -> VersionedAutomationSettings
    func automationSettingsEvent(commandID: AutomationCommandID) throws -> AutomationSettingsEvent?
    func applyAutomationSettings(
        _ replacement: VersionedAutomationSettings,
        event: AutomationSettingsEvent,
        result: AutomationCommandResultEvent,
        expectedVersion: UInt64
    ) throws

    func automationActivity(
        limit: UInt16,
        excludingCommandID: AutomationCommandID?
    ) throws -> [AutomationAuditTrail]
    func automationWorkspaceStatus(
        excludingCommandID: AutomationCommandID?
    ) throws -> AutomationWorkspaceStatus
    func automationStorageReport(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32
    ) throws -> AutomationStorageReport
    func automationDiagnostics(
        calculatedAt: UTCInstant,
        maximumEntries: UInt32,
        usedRestrictedTaskDirectory: Bool,
        excludingCommandID: AutomationCommandID?
    ) throws -> AutomationDiagnosticsReport
    func currentAutomationSecurityContext(meetingID: MeetingID) throws -> AutomationSecurityContext
}

public protocol AutomationCommandExecuting: Sendable {
    func execute(_ request: AutomationCommandRequest) async throws -> AutomationCommandExecution
}

private enum AutomationContractValidation {
    static func isIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        let bytes = Array(value.utf8)
        return !bytes.isEmpty
            && bytes.count <= maximumBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && bytes.allSatisfy { byte in
                (byte >= 48 && byte <= 57)
                    || (byte >= 65 && byte <= 90)
                    || (byte >= 97 && byte <= 122)
                    || byte == 45 || byte == 46 || byte == 95
            }
    }
}
