import Foundation
import MeetingBuddyDomain

public enum ProviderRoutingError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
}

/// Capabilities are attached to an exact provider/model pair. A provider name
/// or model name alone never grants task eligibility.
public enum ProviderCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case speechToTextBatch = "speech_to_text_batch"
    case speechToTextRealtime = "speech_to_text_realtime"
    case speakerProcessing = "speaker_processing"
    case translation
    case textAnalysis = "text_analysis"
    case summaryAndMinutes = "summary_and_minutes"
    case meetingChat = "meeting_chat"
    case documentQuery = "document_query"
    case externalResearch = "external_research"
    case structuredOutput = "structured_output"
}

public enum RoutedTask: String, CaseIterable, Codable, Hashable, Sendable {
    case speechToTextBatch = "speech_to_text_batch"
    case speechToTextRealtime = "speech_to_text_realtime"
    case speakerProcessing = "speaker_processing"
    case translation
    case textAnalysis = "text_analysis"
    case summaryAndMinutes = "summary_and_minutes"
    case meetingChat = "meeting_chat"
    case documentQuery = "document_query"
    case externalResearch = "external_research"

    public var acceptedCapabilities: Set<ProviderCapability> {
        switch self {
        case .speechToTextBatch:
            [.speechToTextBatch]
        case .speechToTextRealtime:
            [.speechToTextRealtime]
        case .speakerProcessing:
            [.speakerProcessing]
        case .translation:
            [.translation]
        case .textAnalysis:
            [.textAnalysis]
        case .summaryAndMinutes:
            [.summaryAndMinutes]
        case .meetingChat:
            [.meetingChat]
        case .documentQuery:
            [.documentQuery]
        case .externalResearch:
            [.externalResearch]
        }
    }

    public var isSpeechToText: Bool {
        self == .speechToTextBatch || self == .speechToTextRealtime
    }
}

public enum ProviderKind: String, Codable, Hashable, Sendable {
    case codexSubscription = "codex_subscription"
    case localSpeechToText = "local_speech_to_text"
    case localText = "local_text"
    case remoteAPI = "remote_api"
}

public enum ProviderDataRoute: String, Codable, Hashable, Sendable {
    case localOnly = "local_only"
    case codexSubscriptionText = "codex_subscription_text"
    case userAPIText = "user_api_text"
    case userAPIAudio = "user_api_audio"

    public var sendsAudioOffDevice: Bool {
        self == .userAPIAudio
    }

    public var sendsTextOffDevice: Bool {
        switch self {
        case .localOnly, .userAPIAudio:
            false
        case .codexSubscriptionText, .userAPIText:
            true
        }
    }
}

public enum ProviderCostOwner: String, Codable, Hashable, Sendable {
    case localDevice = "local_device"
    case codexSubscription = "codex_subscription"
    case userAPIAccount = "user_api_account"
}

public struct ProviderModelProfile: Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let capabilities: Set<ProviderCapability>

    public init(
        identifier: String,
        displayName: String,
        capabilities: Set<ProviderCapability>
    ) throws {
        guard Self.isBoundedIdentifier(identifier),
              Self.isBoundedLabel(displayName),
              !capabilities.isEmpty
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "A provider model needs a bounded identifier, display name, and capabilities."
            )
        }
        self.identifier = identifier
        self.displayName = displayName
        self.capabilities = capabilities
    }

    fileprivate static func isBoundedIdentifier(_ value: String) -> Bool {
        isBoundedLabel(value)
            && !value.contains(" ")
            && !value.contains("/")
            && !value.contains("\\")
    }

    fileprivate static func isBoundedLabel(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 128
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

public struct ProviderProfile: Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let kind: ProviderKind
    public let dataRoute: ProviderDataRoute
    public let costOwner: ProviderCostOwner
    public let models: [ProviderModelProfile]
    public let requiresCredential: Bool

    public init(
        identifier: String,
        displayName: String,
        kind: ProviderKind,
        dataRoute: ProviderDataRoute,
        costOwner: ProviderCostOwner,
        models: [ProviderModelProfile],
        requiresCredential: Bool
    ) throws {
        let sortedModels = models.sorted { $0.identifier < $1.identifier }
        guard ProviderModelProfile.isBoundedIdentifier(identifier),
              ProviderModelProfile.isBoundedLabel(displayName),
              !sortedModels.isEmpty,
              Set(sortedModels.map(\.identifier)).count == sortedModels.count,
              Self.routeMatchesKind(
                  kind: kind,
                  dataRoute: dataRoute,
                  costOwner: costOwner,
                  requiresCredential: requiresCredential
              ),
              Self.capabilitiesMatchRoute(
                  models: sortedModels,
                  kind: kind,
                  dataRoute: dataRoute
              )
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "The provider profile has inconsistent identity, route, cost, credential, or capability metadata."
            )
        }
        self.identifier = identifier
        self.displayName = displayName
        self.kind = kind
        self.dataRoute = dataRoute
        self.costOwner = costOwner
        self.models = sortedModels
        self.requiresCredential = requiresCredential
    }

    public func model(identifier: String) -> ProviderModelProfile? {
        models.first { $0.identifier == identifier }
    }

    public var capabilities: Set<ProviderCapability> {
        models.reduce(into: []) { result, model in
            result.formUnion(model.capabilities)
        }
    }

    private static func routeMatchesKind(
        kind: ProviderKind,
        dataRoute: ProviderDataRoute,
        costOwner: ProviderCostOwner,
        requiresCredential: Bool
    ) -> Bool {
        switch kind {
        case .codexSubscription:
            dataRoute == .codexSubscriptionText
                && costOwner == .codexSubscription
                && !requiresCredential
        case .localSpeechToText, .localText:
            dataRoute == .localOnly
                && costOwner == .localDevice
                && !requiresCredential
        case .remoteAPI:
            (dataRoute == .userAPIText || dataRoute == .userAPIAudio)
                && costOwner == .userAPIAccount
                && requiresCredential
        }
    }

    private static func capabilitiesMatchRoute(
        models: [ProviderModelProfile],
        kind: ProviderKind,
        dataRoute: ProviderDataRoute
    ) -> Bool {
        let capabilities = models.reduce(into: Set<ProviderCapability>()) {
            $0.formUnion($1.capabilities)
        }
        let speechCapabilities: Set<ProviderCapability> = [
            .speechToTextBatch,
            .speechToTextRealtime
        ]

        if dataRoute == .localOnly, capabilities.contains(.externalResearch) {
            return false
        }
        if kind == .codexSubscription {
            return capabilities.isDisjoint(with: speechCapabilities)
        }
        if kind == .localSpeechToText {
            return !capabilities.isDisjoint(with: speechCapabilities)
                && dataRoute == .localOnly
        }
        if dataRoute == .userAPIAudio {
            let audioCapabilities = speechCapabilities.union([.speakerProcessing])
            return !capabilities.isDisjoint(with: speechCapabilities)
                && capabilities.isSubset(of: audioCapabilities)
        }
        return capabilities.isDisjoint(with: speechCapabilities)
    }
}

public struct ProviderRegistry: Hashable, Sendable {
    public let providers: [ProviderProfile]

    public init(providers: [ProviderProfile]) throws {
        let sorted = providers.sorted { $0.identifier < $1.identifier }
        guard Set(sorted.map(\.identifier)).count == sorted.count else {
            throw ProviderRoutingError.invalidConfiguration(
                "Provider identifiers must be unique."
            )
        }
        self.providers = sorted
    }

    public func provider(identifier: String) -> ProviderProfile? {
        providers.first { $0.identifier == identifier }
    }

    public func eligibleModels(for task: RoutedTask) -> [ProviderModelSelection] {
        providers.flatMap { provider in
            provider.models.compactMap { model in
                guard !model.capabilities.isDisjoint(
                    with: task.acceptedCapabilities
                ) else {
                    return nil
                }
                return ProviderModelSelection(
                    validatedProviderIdentifier: provider.identifier,
                    validatedModelIdentifier: model.identifier
                )
            }
        }
    }
}

public struct ProviderModelSelection: Hashable, Sendable {
    public let providerIdentifier: String
    public let modelIdentifier: String

    public init(
        providerIdentifier: String,
        modelIdentifier: String
    ) throws {
        guard ProviderModelProfile.isBoundedIdentifier(providerIdentifier),
              ProviderModelProfile.isBoundedIdentifier(modelIdentifier)
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "A provider selection needs bounded opaque provider and model identifiers."
            )
        }
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
    }

    fileprivate init(
        validatedProviderIdentifier: String,
        validatedModelIdentifier: String
    ) {
        providerIdentifier = validatedProviderIdentifier
        modelIdentifier = validatedModelIdentifier
    }
}

public enum TaskRouteOverride: Hashable, Sendable {
    /// Continue to the next less-specific scope.
    case inherit
    /// Explicitly disable this task at this scope. For STT this means Record Only.
    case disabled
    /// Select one exact provider/model. The fallback is repair UI only and is
    /// never executed automatically.
    case selection(
        primary: ProviderModelSelection,
        fallback: ProviderModelSelection?
    )
}

public struct TaskRoutePreference: Hashable, Sendable {
    public let task: RoutedTask
    public let routeOverride: TaskRouteOverride

    public init(
        task: RoutedTask,
        routeOverride: TaskRouteOverride
    ) throws {
        if case let .selection(primary, fallback) = routeOverride,
           primary == fallback {
            throw ProviderRoutingError.invalidConfiguration(
                "A fallback requires a distinct primary provider selection."
            )
        }
        self.task = task
        self.routeOverride = routeOverride
    }
}

/// Binds a persisted routing profile to the exact scope that owns it.
///
/// Meeting profiles use the immutable meeting revision, rather than only a
/// logical identifier, so a cached profile cannot cross either a meeting or
/// revision boundary. Workspace profiles are bound to one workspace identity.
public enum TaskRoutingProfileScope: Hashable, Sendable {
    case global
    case workspace(workspaceID: WorkspaceID)
    case meeting(meetingRevision: SemanticRevisionReference)
}

public struct TaskRoutingProfile: Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let scope: TaskRoutingProfileScope
    public let routes: [TaskRoutePreference]

    public init(
        identifier: String,
        displayName: String,
        scope: TaskRoutingProfileScope,
        routes: [TaskRoutePreference]
    ) throws {
        let sorted = routes.sorted { $0.task.rawValue < $1.task.rawValue }
        guard ProviderModelProfile.isBoundedIdentifier(identifier),
              ProviderModelProfile.isBoundedLabel(displayName),
              Set(sorted.map(\.task)).count == sorted.count
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "A routing profile needs bounded identity and one entry per task."
            )
        }
        self.identifier = identifier
        self.displayName = displayName
        self.scope = scope
        self.routes = sorted
    }

    public func preference(for task: RoutedTask) -> TaskRoutePreference? {
        routes.first { $0.task == task }
    }
}

/// A deterministic three-level route stack. Missing entries and `.inherit`
/// continue downward. If no scope makes an explicit choice, the task is
/// disabled; a meeting-level `.disabled` can therefore never inherit global
/// speech-to-text by accident.
public enum TaskRouteOrigin: Hashable, Sendable {
    case meeting(meetingID: MeetingID, profileIdentifier: String)
    case workspace(workspaceID: WorkspaceID, profileIdentifier: String)
    case global(profileIdentifier: String)
    case defaultDisabled
}

public struct EffectiveTaskRouteOverride: Hashable, Sendable {
    public let routeOverride: TaskRouteOverride
    public let origin: TaskRouteOrigin
}

/// A domain-bound security context for one exact meeting and workspace.
///
/// The routing stack cannot be assembled from independent identifiers and a
/// policy snapshot. Construction first proves the MeetingProfile ->
/// SensitivityLabel -> AccessPolicy graph, derives the workspace identity from
/// that exact meeting, and requires the immutable model snapshot to match the
/// graph without widening any processing authority.
public struct TaskRoutingSecurityContext: Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let securityPolicy: ModelSecurityPolicySnapshot

    public init(
        meeting: MeetingProfileV1,
        sensitivityLabel: SensitivityLabelV1,
        accessPolicy: AccessPolicyV1,
        securityPolicy: ModelSecurityPolicySnapshot
    ) throws {
        try SecurityPolicyGraphValidator.validate(
            meeting: meeting,
            sensitivityLabel: sensitivityLabel,
            accessPolicy: accessPolicy
        )
        let meetingRevision = try SemanticRevisionReference(
            logicalID: meeting.meetingID,
            revisionID: meeting.revision.revisionID
        )
        let sensitivityLabelRevision = try SemanticRevisionReference(
            logicalID: sensitivityLabel.labelID,
            revisionID: sensitivityLabel.revision.revisionID
        )
        let accessPolicyRevision = try SemanticRevisionReference(
            logicalID: accessPolicy.policyID,
            revisionID: accessPolicy.revision.revisionID
        )
        guard let workspaceID = meeting.workspaceID,
              securityPolicy.sensitivityLabelRevision
                  == sensitivityLabelRevision,
              securityPolicy.accessPolicyRevision == accessPolicyRevision,
              securityPolicy.effectiveClassification
                  == accessPolicy.effectiveClassification,
              securityPolicy.noOutboundMode == accessPolicy.noOutboundMode,
              securityPolicy.localProcessingAllowed
                  == accessPolicy.localProcessingAllowed,
              securityPolicy.manualLocalReviewAllowed
                  == accessPolicy.manualLocalReviewAllowed,
              securityPolicy.externalProcessingAllowed
                  == accessPolicy.externalProcessingAllowed,
              securityPolicy.approvedExternalProviderIdentifiers
                  == accessPolicy.approvedExternalProviderIdentifiers,
              securityPolicy.externalProcessingAllowed
                  || (
                      securityPolicy.approvedDeploymentEnvironments.isEmpty
                          && securityPolicy.approvedRetentionPolicies.isEmpty
                  )
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "Task routing requires one exact workspace, meeting, sensitivity-label, access-policy, and model-policy graph."
            )
        }
        self.workspaceID = workspaceID
        self.meetingID = meeting.meetingID
        self.meetingRevision = meetingRevision
        self.securityPolicy = securityPolicy
    }
}

public struct TaskRoutingScopeStack: Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let securityPolicy: ModelSecurityPolicySnapshot
    public let global: TaskRoutingProfile
    public let workspace: TaskRoutingProfile?
    public let meeting: TaskRoutingProfile?

    public init(
        securityContext: TaskRoutingSecurityContext,
        global: TaskRoutingProfile,
        workspace: TaskRoutingProfile? = nil,
        meeting: TaskRoutingProfile? = nil
    ) throws {
        let identifiers = [global, workspace, meeting]
            .compactMap { $0?.identifier }
        guard Set(identifiers).count == identifiers.count,
              global.scope == .global,
              workspace?.scope
                  == .workspace(workspaceID: securityContext.workspaceID)
                  || workspace == nil,
              meeting?.scope
                  == .meeting(
                      meetingRevision: securityContext.meetingRevision
                  )
                  || meeting == nil
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "Routing profiles need distinct identities and must match their exact global, workspace, or meeting-revision owner."
            )
        }
        self.workspaceID = securityContext.workspaceID
        self.meetingID = securityContext.meetingID
        self.meetingRevision = securityContext.meetingRevision
        self.securityPolicy = securityContext.securityPolicy
        self.global = global
        self.workspace = workspace
        self.meeting = meeting
    }

    public func effectiveRoute(
        for task: RoutedTask
    ) -> EffectiveTaskRouteOverride {
        if let meeting,
           let preference = meeting.preference(for: task),
           case .inherit = preference.routeOverride {
            // Continue to the workspace scope.
        } else if let meeting,
                  let preference = meeting.preference(for: task) {
            return EffectiveTaskRouteOverride(
                routeOverride: preference.routeOverride,
                origin: .meeting(
                    meetingID: meetingID,
                    profileIdentifier: meeting.identifier
                )
            )
        }
        if let workspace,
           let preference = workspace.preference(for: task),
           case .inherit = preference.routeOverride {
            // Continue to the global scope.
        } else if let workspace,
                  let preference = workspace.preference(for: task) {
            return EffectiveTaskRouteOverride(
                routeOverride: preference.routeOverride,
                origin: .workspace(
                    workspaceID: workspaceID,
                    profileIdentifier: workspace.identifier
                )
            )
        }
        if let preference = global.preference(for: task),
           case .inherit = preference.routeOverride {
            return EffectiveTaskRouteOverride(
                routeOverride: .disabled,
                origin: .defaultDisabled
            )
        } else if let preference = global.preference(for: task) {
            return EffectiveTaskRouteOverride(
                routeOverride: preference.routeOverride,
                origin: .global(profileIdentifier: global.identifier)
            )
        }
        return EffectiveTaskRouteOverride(
            routeOverride: .disabled,
            origin: .defaultDisabled
        )
    }
}

public enum ProviderRuntimeState: String, Codable, Hashable, Sendable {
    case ready
    case notInstalled = "not_installed"
    case notAuthenticated = "not_authenticated"
    case invalidCredential = "invalid_credential"
    case incompatibleRuntime = "incompatible_runtime"
    case quotaUnavailable = "quota_unavailable"
    case unavailable

    public var isReady: Bool {
        self == .ready
    }
}

public struct ProviderRuntimeSnapshot: Hashable, Sendable {
    public let providerIdentifier: String
    public let modelIdentifier: String
    public let state: ProviderRuntimeState

    public init(
        providerIdentifier: String,
        modelIdentifier: String,
        state: ProviderRuntimeState
    ) throws {
        guard ProviderModelProfile.isBoundedIdentifier(providerIdentifier),
              ProviderModelProfile.isBoundedIdentifier(modelIdentifier)
        else {
            throw ProviderRoutingError.invalidConfiguration(
                "A runtime snapshot needs bounded provider and model identifiers."
            )
        }
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
        self.state = state
    }
}

public struct ProviderRuntimeRegistry: Hashable, Sendable {
    public let snapshots: [ProviderRuntimeSnapshot]

    public init(snapshots: [ProviderRuntimeSnapshot]) throws {
        let sorted = snapshots.sorted {
            ($0.providerIdentifier, $0.modelIdentifier)
                < ($1.providerIdentifier, $1.modelIdentifier)
        }
        let identities = sorted.map {
            ProviderModelSelection(
                validatedProviderIdentifier: $0.providerIdentifier,
                validatedModelIdentifier: $0.modelIdentifier
            )
        }
        guard Set(identities).count == identities.count else {
            throw ProviderRoutingError.invalidConfiguration(
                "Runtime readiness must contain one state per exact provider/model pair."
            )
        }
        self.snapshots = sorted
    }

    public func state(
        for selection: ProviderModelSelection
    ) -> ProviderRuntimeState? {
        snapshots.first {
            $0.providerIdentifier == selection.providerIdentifier
                && $0.modelIdentifier == selection.modelIdentifier
        }?.state
    }
}

public struct ResolvedTaskRoute: Hashable, Sendable {
    public let task: RoutedTask
    public let providerIdentifier: String
    public let modelIdentifier: String
    public let capability: ProviderCapability
    public let dataRoute: ProviderDataRoute
    public let costOwner: ProviderCostOwner
    public let meetingRevision: SemanticRevisionReference
    public let sensitivityLabelRevision: SemanticRevisionReference
    public let accessPolicyRevision: SemanticRevisionReference
    public let effectiveClassification: DataClassification
    public let noOutboundMode: Bool
    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID
    public let routeOrigin: TaskRouteOrigin

    public var sendsAudioOffDevice: Bool {
        dataRoute.sendsAudioOffDevice
    }
}

public enum TaskRouteResolution: Hashable, Sendable {
    case ready(ResolvedTaskRoute)
    /// Capability, exact provider/model, runtime readiness, and the immutable
    /// security snapshot agree, but an external execution still needs the
    /// existing full ModelRouteRequest policy inputs and an approved adapter.
    case requiresExecutionAuthorization(candidate: ResolvedTaskRoute)
    case recordOnly(origin: TaskRouteOrigin)
    case unavailable(
        reasonCode: String,
        repairSelection: ProviderModelSelection?,
        origin: TaskRouteOrigin
    )
}

/// Resolves one exact task without silent provider fallback.
public struct TaskRoutingResolver: Sendable {
    public init() {}

    public func resolve(
        task: RoutedTask,
        scopeStack: TaskRoutingScopeStack,
        registry: ProviderRegistry,
        runtime: ProviderRuntimeRegistry
    ) -> TaskRouteResolution {
        let effectiveRoute = scopeStack.effectiveRoute(for: task)
        let securityPolicy = scopeStack.securityPolicy
        guard case let .selection(primary, fallback) =
            effectiveRoute.routeOverride
        else {
            return task.isSpeechToText
                ? .recordOnly(origin: effectiveRoute.origin)
                : .unavailable(
                    reasonCode: "route_disabled",
                    repairSelection: nil,
                    origin: effectiveRoute.origin
                )
        }
        let repairSelection = eligibleRepairSelection(
            fallback,
            task: task,
            registry: registry,
            securityPolicy: securityPolicy
        )
        guard let provider = registry.provider(
            identifier: primary.providerIdentifier
        ), let model = provider.model(identifier: primary.modelIdentifier) else {
            return .unavailable(
                reasonCode: "provider_or_model_missing",
                repairSelection: repairSelection,
                origin: effectiveRoute.origin
            )
        }
        guard let capability = model.capabilities
            .intersection(task.acceptedCapabilities)
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first
        else {
            return .unavailable(
                reasonCode: "provider_capability_mismatch",
                repairSelection: repairSelection,
                origin: effectiveRoute.origin
            )
        }
        if task.isSpeechToText, provider.kind == .codexSubscription {
            return .unavailable(
                reasonCode: "codex_never_provides_speech_to_text",
                repairSelection: repairSelection,
                origin: effectiveRoute.origin
            )
        }
        let sensitiveMeeting = isSensitiveMeeting(securityPolicy)
        if sensitiveMeeting, task == .externalResearch {
            return .unavailable(
                reasonCode: "sensitive_meeting_disables_external_research",
                repairSelection: nil,
                origin: effectiveRoute.origin
            )
        }
        if sensitiveMeeting, provider.dataRoute != .localOnly {
            return .unavailable(
                reasonCode: "sensitive_meeting_requires_local_provider",
                repairSelection: nil,
                origin: effectiveRoute.origin
            )
        }
        if provider.dataRoute == .localOnly {
            guard securityPolicy.localProcessingAllowed else {
                return .unavailable(
                    reasonCode: "security_policy_denies_local_processing",
                    repairSelection: repairSelection,
                    origin: effectiveRoute.origin
                )
            }
        } else if !securityPolicy.allowsExternalProvider(provider.identifier) {
            return .unavailable(
                reasonCode: "security_policy_denies_external_provider",
                repairSelection: repairSelection,
                origin: effectiveRoute.origin
            )
        }
        let state = runtime.state(for: primary) ?? .unavailable
        guard state.isReady else {
            return .unavailable(
                reasonCode: "provider_\(state.rawValue)",
                repairSelection: repairSelection,
                origin: effectiveRoute.origin
            )
        }
        let resolved = ResolvedTaskRoute(
            task: task,
            providerIdentifier: provider.identifier,
            modelIdentifier: model.identifier,
            capability: capability,
            dataRoute: provider.dataRoute,
            costOwner: provider.costOwner,
            meetingRevision: scopeStack.meetingRevision,
            sensitivityLabelRevision: securityPolicy.sensitivityLabelRevision,
            accessPolicyRevision: securityPolicy.accessPolicyRevision,
            effectiveClassification: securityPolicy.effectiveClassification,
            noOutboundMode: securityPolicy.noOutboundMode,
            workspaceID: scopeStack.workspaceID,
            meetingID: scopeStack.meetingID,
            routeOrigin: effectiveRoute.origin
        )
        if provider.dataRoute != .localOnly {
            return .requiresExecutionAuthorization(candidate: resolved)
        }
        return .ready(resolved)
    }

    private func eligibleRepairSelection(
        _ selection: ProviderModelSelection?,
        task: RoutedTask,
        registry: ProviderRegistry,
        securityPolicy: ModelSecurityPolicySnapshot
    ) -> ProviderModelSelection? {
        guard let selection,
              let provider = registry.provider(
                  identifier: selection.providerIdentifier
              ),
              let model = provider.model(identifier: selection.modelIdentifier),
              !model.capabilities.isDisjoint(with: task.acceptedCapabilities),
              !(task.isSpeechToText && provider.kind == .codexSubscription)
        else {
            return nil
        }

        let sensitiveMeeting = isSensitiveMeeting(securityPolicy)
        if sensitiveMeeting,
           task == .externalResearch || provider.dataRoute != .localOnly {
            return nil
        }
        if provider.dataRoute == .localOnly {
            return securityPolicy.localProcessingAllowed ? selection : nil
        }
        return securityPolicy.allowsExternalProvider(provider.identifier)
            ? selection
            : nil
    }

    private func isSensitiveMeeting(
        _ securityPolicy: ModelSecurityPolicySnapshot
    ) -> Bool {
        securityPolicy.noOutboundMode
            || securityPolicy.effectiveClassification.restrictionRank
                >= DataClassification.sensitive.restrictionRank
    }
}

public enum BlueMinutesBuiltInProviders {
    public static func registry() throws -> ProviderRegistry {
        try ProviderRegistry(
            providers: [
                ProviderProfile(
                    identifier: "apple-speech",
                    displayName: "Apple On-Device Speech",
                    kind: .localSpeechToText,
                    dataRoute: .localOnly,
                    costOwner: .localDevice,
                    models: [
                        ProviderModelProfile(
                            identifier: "speech-analyzer-installed",
                            displayName: "Installed Speech Model",
                            capabilities: [.speechToTextBatch]
                        )
                    ],
                    requiresCredential: false
                ),
                ProviderProfile(
                    identifier: "apple-translation",
                    displayName: "Apple On-Device Translation",
                    kind: .localText,
                    dataRoute: .localOnly,
                    costOwner: .localDevice,
                    models: [
                        ProviderModelProfile(
                            identifier: "translation-installed",
                            displayName: "Installed Translation Model",
                            capabilities: [.translation]
                        )
                    ],
                    requiresCredential: false
                ),
                ProviderProfile(
                    identifier: "apple-foundation-models",
                    displayName: "Apple On-Device Intelligence",
                    kind: .localText,
                    dataRoute: .localOnly,
                    costOwner: .localDevice,
                    models: [
                        ProviderModelProfile(
                            identifier: "system-language-model",
                            displayName: "System Language Model",
                            capabilities: [
                                .textAnalysis,
                                .summaryAndMinutes,
                                .structuredOutput
                            ]
                        )
                    ],
                    requiresCredential: false
                ),
                ProviderProfile(
                    identifier: "codex-subscription",
                    displayName: "Codex with ChatGPT Subscription",
                    kind: .codexSubscription,
                    dataRoute: .codexSubscriptionText,
                    costOwner: .codexSubscription,
                    models: [
                        ProviderModelProfile(
                            identifier: "codex-default",
                            displayName: "Codex Default",
                            capabilities: [
                                .translation,
                                .textAnalysis,
                                .summaryAndMinutes,
                                .meetingChat,
                                .documentQuery,
                                .externalResearch,
                                .structuredOutput
                            ]
                        )
                    ],
                    requiresCredential: false
                )
            ]
        )
    }
}
