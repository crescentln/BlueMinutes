import Foundation
import MeetingBuddyDomain

public enum IntelligenceConfigurationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidConfiguration(String)
    case revisionConflict
    case persistenceUnavailable
    case credentialUnavailable
    case connectionFailed(RemoteProviderConnectionState)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            message
        case .revisionConflict:
            "Intelligence settings changed in another operation. Reload and try again."
        case .persistenceUnavailable:
            "BlueMinutes could not safely read or save Intelligence settings."
        case .credentialUnavailable:
            "The provider API key is unavailable in macOS Keychain."
        case let .connectionFailed(state):
            switch state {
            case .notTested:
                "The provider connection has not been tested."
            case .ready:
                nil
            case .invalidCredential:
                "The provider rejected the API key."
            case .networkUnavailable:
                "The provider could not be reached."
            case .modelUnavailable:
                "The configured model is unavailable for this API account."
            case .serverRejected:
                "The provider rejected the connection test."
            }
        }
    }
}

public enum RemoteProviderFamily:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case openAI = "openai"
}

public enum RemoteProviderPurpose:
    String,
    Codable,
    Hashable,
    Sendable
{
    case speechToText = "speech_to_text"
    case textIntelligence = "text_intelligence"
}

public enum RemoteProviderConnectionState:
    String,
    Codable,
    Hashable,
    Sendable
{
    case notTested = "not_tested"
    case ready
    case invalidCredential = "invalid_credential"
    case networkUnavailable = "network_unavailable"
    case modelUnavailable = "model_unavailable"
    case serverRejected = "server_rejected"
}

public struct RemoteProviderConfiguration:
    Codable,
    Hashable,
    Sendable
{
    public static let openAIBaseURL = "https://api.openai.com"
    public static let sharedOpenAICredentialAccount =
        "openai-api-shared"

    public let identifier: String
    public let displayName: String
    public let family: RemoteProviderFamily
    public let purpose: RemoteProviderPurpose
    public let baseURL: HTTPSURL
    public let modelIdentifier: String
    public let modelDisplayName: String
    public let capabilities: [ProviderCapability]
    public let credentialAccount: String
    public let connectionState: RemoteProviderConnectionState
    public let lastTestedAt: UTCInstant?

    public init(
        identifier: String,
        displayName: String,
        family: RemoteProviderFamily,
        purpose: RemoteProviderPurpose,
        baseURL: HTTPSURL,
        modelIdentifier: String,
        modelDisplayName: String,
        capabilities: [ProviderCapability],
        credentialAccount: String,
        connectionState: RemoteProviderConnectionState = .notTested,
        lastTestedAt: UTCInstant? = nil
    ) throws {
        let sortedCapabilities = capabilities.sorted {
            $0.rawValue < $1.rawValue
        }
        let descriptor:
            OpenAIModelCapabilityDescriptor
        let expectedIdentifier: String
        let expectedDisplayName: String
        switch purpose {
        case .speechToText:
            descriptor = try OpenAIModelCapabilityCatalog
                .speechDescriptor(
                    modelIdentifier
                )
            expectedIdentifier = "openai-stt"
            expectedDisplayName =
                "OpenAI Speech-to-Text API"
        case .textIntelligence:
            descriptor = try OpenAIModelCapabilityCatalog
                .textDescriptor(
                    modelIdentifier
                )
            expectedIdentifier = "openai-text"
            expectedDisplayName = "OpenAI API"
        }
        let expectedCapabilities =
            descriptor.capabilities.sorted {
                $0.rawValue < $1.rawValue
            }
        guard Self.validOpaqueIdentifier(identifier),
              Self.validLabel(displayName),
              Self.validOpaqueIdentifier(modelIdentifier),
              Self.validLabel(modelDisplayName),
              Self.validOpaqueIdentifier(credentialAccount),
              !sortedCapabilities.isEmpty,
              Set(sortedCapabilities).count
                  == sortedCapabilities.count,
              family == .openAI,
              identifier == expectedIdentifier,
              displayName == expectedDisplayName,
              baseURL.absoluteString == Self.openAIBaseURL,
              modelIdentifier == descriptor.identifier,
              modelDisplayName == descriptor.displayName,
              sortedCapabilities == expectedCapabilities,
              credentialAccount
                  == Self.sharedOpenAICredentialAccount,
              Self.capabilities(
                  sortedCapabilities,
                  match: purpose
              ),
              (
                  connectionState == .notTested
                      && lastTestedAt == nil
              )
                  || (
                      connectionState != .notTested
                          && lastTestedAt != nil
                  )
        else {
            throw IntelligenceConfigurationError
                .invalidConfiguration(
                    "A remote provider requires one bounded, capability-compatible model and the approved HTTPS API destination."
                )
        }
        self.identifier = identifier
        self.displayName = displayName
        self.family = family
        self.purpose = purpose
        self.baseURL = baseURL
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
        self.capabilities = sortedCapabilities
        self.credentialAccount = credentialAccount
        self.connectionState = connectionState
        self.lastTestedAt = lastTestedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            identifier: container.decode(
                String.self,
                forKey: .identifier
            ),
            displayName: container.decode(
                String.self,
                forKey: .displayName
            ),
            family: container.decode(
                RemoteProviderFamily.self,
                forKey: .family
            ),
            purpose: container.decode(
                RemoteProviderPurpose.self,
                forKey: .purpose
            ),
            baseURL: container.decode(
                HTTPSURL.self,
                forKey: .baseURL
            ),
            modelIdentifier: container.decode(
                String.self,
                forKey: .modelIdentifier
            ),
            modelDisplayName: container.decode(
                String.self,
                forKey: .modelDisplayName
            ),
            capabilities: container.decode(
                [ProviderCapability].self,
                forKey: .capabilities
            ),
            credentialAccount: container.decode(
                String.self,
                forKey: .credentialAccount
            ),
            connectionState: container.decode(
                RemoteProviderConnectionState.self,
                forKey: .connectionState
            ),
            lastTestedAt: container.decodeIfPresent(
                UTCInstant.self,
                forKey: .lastTestedAt
            )
        )
    }

    public func recordingConnectionResult(
        _ state: RemoteProviderConnectionState,
        testedAt: UTCInstant
    ) throws -> RemoteProviderConfiguration {
        try RemoteProviderConfiguration(
            identifier: identifier,
            displayName: displayName,
            family: family,
            purpose: purpose,
            baseURL: baseURL,
            modelIdentifier: modelIdentifier,
            modelDisplayName: modelDisplayName,
            capabilities: capabilities,
            credentialAccount: credentialAccount,
            connectionState: state,
            lastTestedAt: testedAt
        )
    }

    public func providerProfile() throws -> ProviderProfile {
        try ProviderProfile(
            identifier: identifier,
            displayName: displayName,
            kind: .remoteAPI,
            dataRoute: purpose == .speechToText
                ? .userAPIAudio
                : .userAPIText,
            costOwner: .userAPIAccount,
            models: [
                ProviderModelProfile(
                    identifier: modelIdentifier,
                    displayName: modelDisplayName,
                    capabilities: Set(capabilities)
                )
            ],
            requiresCredential: true
        )
    }

    public var secretIdentifier: SecretIdentifier {
        get throws {
            try SecretIdentifier(
                service: "com.blueminutes.provider-api-key",
                account: credentialAccount
            )
        }
    }

    public static func openAISpeechToText(
        modelIdentifier: String
    ) throws -> RemoteProviderConfiguration {
        let descriptor = try OpenAIModelCapabilityCatalog
            .speechDescriptor(modelIdentifier)
        return try RemoteProviderConfiguration(
            identifier: "openai-stt",
            displayName: "OpenAI Speech-to-Text API",
            family: .openAI,
            purpose: .speechToText,
            baseURL: HTTPSURL(openAIBaseURL),
            modelIdentifier: descriptor.identifier,
            modelDisplayName: descriptor.displayName,
            capabilities: descriptor.capabilities,
            credentialAccount:
                sharedOpenAICredentialAccount
        )
    }

    public static func openAIText(
        modelIdentifier: String
    ) throws -> RemoteProviderConfiguration {
        let descriptor = try OpenAIModelCapabilityCatalog
            .textDescriptor(modelIdentifier)
        return try RemoteProviderConfiguration(
            identifier: "openai-text",
            displayName: "OpenAI API",
            family: .openAI,
            purpose: .textIntelligence,
            baseURL: HTTPSURL(openAIBaseURL),
            modelIdentifier: descriptor.identifier,
            modelDisplayName: descriptor.displayName,
            capabilities: descriptor.capabilities,
            credentialAccount:
                sharedOpenAICredentialAccount
        )
    }

    private static func capabilities(
        _ capabilities: [ProviderCapability],
        match purpose: RemoteProviderPurpose
    ) -> Bool {
        let values = Set(capabilities)
        let speech: Set<ProviderCapability> = [
            .speechToTextBatch,
            .speechToTextRealtime,
            .speakerProcessing
        ]
        switch purpose {
        case .speechToText:
            return !values.isDisjoint(
                with: [
                    .speechToTextBatch,
                    .speechToTextRealtime
                ]
            )
                && values.isSubset(of: speech)
        case .textIntelligence:
            return values.isDisjoint(with: speech)
        }
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case identifier
        case displayName
        case family
        case purpose
        case baseURL
        case modelIdentifier
        case modelDisplayName
        case capabilities
        case credentialAccount
        case connectionState
        case lastTestedAt
    }

    private static func validOpaqueIdentifier(
        _ value: String
    ) -> Bool {
        validLabel(value)
            && !value.contains(" ")
            && !value.contains("/")
            && !value.contains("\\")
    }

    private static func validLabel(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value == value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            && !value.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            )
    }
}

public struct OpenAIModelCapabilityDescriptor:
    Hashable,
    Sendable
{
    public let identifier: String
    public let displayName: String
    public let capabilities: [ProviderCapability]

    public init(
        identifier: String,
        displayName: String,
        capabilities: [ProviderCapability]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

public enum OpenAIModelCapabilityCatalog {
    public static let speechModels = [
        OpenAIModelCapabilityDescriptor(
            identifier: "whisper-1",
            displayName: "Whisper 1 · batch with timestamps",
            capabilities: [.speechToTextBatch]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-4o-transcribe-diarize",
            displayName: "GPT-4o Transcribe Diarize",
            capabilities: [
                .speechToTextBatch,
                .speakerProcessing
            ]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            capabilities: [.speechToTextBatch]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe",
            capabilities: [.speechToTextBatch]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier:
                "gpt-4o-mini-transcribe-2025-12-15",
            displayName:
                "GPT-4o Mini Transcribe 2025-12-15",
            capabilities: [.speechToTextBatch]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-realtime-whisper",
            displayName: "GPT Realtime Whisper",
            capabilities: [.speechToTextRealtime]
        )
    ]

    public static let textModels = [
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-5.6-terra",
            displayName: "GPT-5.6 Terra",
            capabilities: [
                .translation,
                .textAnalysis,
                .summaryAndMinutes,
                .meetingChat,
                .documentQuery,
                .externalResearch,
                .structuredOutput
            ]
        ),
        OpenAIModelCapabilityDescriptor(
            identifier: "gpt-5.6-sol",
            displayName: "GPT-5.6 Sol",
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
    ]

    public static func speechDescriptor(
        _ identifier: String
    ) throws -> OpenAIModelCapabilityDescriptor {
        guard let value = speechModels.first(where: {
            $0.identifier == identifier
        }) else {
            throw IntelligenceConfigurationError
                .invalidConfiguration(
                    "The selected model is not in the current verified OpenAI speech-to-text capability catalog."
                )
        }
        return value
    }

    public static func textDescriptor(
        _ identifier: String
    ) throws -> OpenAIModelCapabilityDescriptor {
        guard let value = textModels.first(where: {
            $0.identifier == identifier
        }) else {
            throw IntelligenceConfigurationError
                .invalidConfiguration(
                    "The selected model is not in the current verified OpenAI text capability catalog."
                )
        }
        return value
    }
}

public struct IntelligenceTaskRouteSetting:
    Codable,
    Hashable,
    Sendable
{
    public let task: RoutedTask
    public let selection: ProviderModelSelectionRecord?

    public init(
        task: RoutedTask,
        selection: ProviderModelSelectionRecord?
    ) {
        self.task = task
        self.selection = selection
    }

    public func preference() throws -> TaskRoutePreference {
        try TaskRoutePreference(
            task: task,
            routeOverride: try selection.map {
                .selection(
                    primary: try $0.selection(),
                    fallback: nil
                )
            } ?? .disabled
        )
    }
}

public struct ProviderModelSelectionRecord:
    Codable,
    Hashable,
    Sendable
{
    public let providerIdentifier: String
    public let modelIdentifier: String

    public init(
        providerIdentifier: String,
        modelIdentifier: String
    ) {
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
    }

    public func selection() throws -> ProviderModelSelection {
        try ProviderModelSelection(
            providerIdentifier: providerIdentifier,
            modelIdentifier: modelIdentifier
        )
    }
}

public struct IntelligenceConfigurationState:
    Codable,
    Hashable,
    Sendable
{
    public static let schemaVersion: UInt32 = 1

    public let schemaVersion: UInt32
    public let revision: UInt64
    public let defaultSpeechLanguageTag: String
    public let providers: [RemoteProviderConfiguration]
    public let routes: [IntelligenceTaskRouteSetting]

    public init(
        revision: UInt64,
        defaultSpeechLanguageTag: String,
        providers: [RemoteProviderConfiguration],
        routes: [IntelligenceTaskRouteSetting]
    ) throws {
        let sortedProviders = providers.sorted {
            $0.identifier < $1.identifier
        }
        let sortedRoutes = routes.sorted {
            $0.task.rawValue < $1.task.rawValue
        }
        _ = try LanguageTag(defaultSpeechLanguageTag)
        guard Set(sortedProviders.map(\.identifier)).count
                    == sortedProviders.count,
              Set(sortedRoutes.map(\.task)).count
                    == sortedRoutes.count,
              Set(sortedRoutes.map(\.task))
                    == Set(RoutedTask.allCases)
        else {
            throw IntelligenceConfigurationError
                .invalidConfiguration(
                    "Intelligence settings require unique providers and exactly one explicit route per supported task."
                )
        }
        let registry = try Self.registry(
            remoteProviders: sortedProviders
        )
        for route in sortedRoutes {
            guard let selection = route.selection else {
                continue
            }
            guard registry.eligibleModels(
                for: route.task
            ).contains(try selection.selection()) else {
                throw IntelligenceConfigurationError
                    .invalidConfiguration(
                        "A task route selected a provider/model without the required capability."
                    )
            }
        }
        schemaVersion = Self.schemaVersion
        self.revision = revision
        self.defaultSpeechLanguageTag =
            defaultSpeechLanguageTag
        self.providers = sortedProviders
        self.routes = sortedRoutes
    }

    public static func compiledDefault() throws
        -> IntelligenceConfigurationState
    {
        try IntelligenceConfigurationState(
            revision: 0,
            defaultSpeechLanguageTag: "en",
            providers: [],
            routes: RoutedTask.allCases.map {
                IntelligenceTaskRouteSetting(
                    task: $0,
                    selection: nil
                )
            }
        )
    }

    public func replacing(
        providers: [RemoteProviderConfiguration]? = nil,
        routes: [IntelligenceTaskRouteSetting]? = nil,
        defaultSpeechLanguageTag: String? = nil
    ) throws -> IntelligenceConfigurationState {
        try IntelligenceConfigurationState(
            revision: revision + 1,
            defaultSpeechLanguageTag:
                defaultSpeechLanguageTag
                    ?? self.defaultSpeechLanguageTag,
            providers: providers ?? self.providers,
            routes: routes ?? self.routes
        )
    }

    public func registry() throws -> ProviderRegistry {
        try Self.registry(remoteProviders: providers)
    }

    public func routingProfile() throws -> TaskRoutingProfile {
        try TaskRoutingProfile(
            identifier: "global-intelligence",
            displayName: "Global Intelligence",
            scope: .global,
            routes: try routes.map { try $0.preference() }
        )
    }

    public func route(
        for task: RoutedTask
    ) -> IntelligenceTaskRouteSetting {
        routes.first { $0.task == task }
            ?? IntelligenceTaskRouteSetting(
                task: task,
                selection: nil
            )
    }

    private static func registry(
        remoteProviders: [RemoteProviderConfiguration]
    ) throws -> ProviderRegistry {
        let builtIn = try BlueMinutesBuiltInProviders
            .registry().providers
        return try ProviderRegistry(
            providers: builtIn
                + remoteProviders.map {
                    try $0.providerProfile()
                }
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let decodedSchema = try container.decode(
            UInt32.self,
            forKey: .schemaVersion
        )
        guard decodedSchema == Self.schemaVersion else {
            throw IntelligenceConfigurationError
                .invalidConfiguration(
                    "The Intelligence settings schema is unsupported."
                )
        }
        try self.init(
            revision: container.decode(
                UInt64.self,
                forKey: .revision
            ),
            defaultSpeechLanguageTag: container.decode(
                String.self,
                forKey: .defaultSpeechLanguageTag
            ),
            providers: container.decode(
                [RemoteProviderConfiguration].self,
                forKey: .providers
            ),
            routes: container.decode(
                [IntelligenceTaskRouteSetting].self,
                forKey: .routes
            )
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case schemaVersion = "schema_version"
        case revision
        case defaultSpeechLanguageTag =
            "default_speech_language_tag"
        case providers
        case routes
    }
}

public protocol IntelligenceConfigurationRepository:
    Sendable
{
    func load() throws -> IntelligenceConfigurationState

    func save(
        _ state: IntelligenceConfigurationState,
        expectedRevision: UInt64
    ) throws
}

public protocol RemoteProviderConnectionTesting: Sendable {
    func test(
        configuration: RemoteProviderConfiguration,
        apiKey: Data
    ) async -> RemoteProviderConnectionState
}

public enum LocalSpeechModelPhase:
    String,
    Hashable,
    Sendable
{
    case unsupported
    case supported
    case downloading
    case paused
    case installed
    case failed
}

public struct LocalSpeechModelSnapshot:
    Hashable,
    Sendable
{
    public let languageTag: String
    public let resolvedLocaleIdentifier: String?
    public let phase: LocalSpeechModelPhase
    public let completedUnitCount: Int64
    public let totalUnitCount: Int64
    public let isReserved: Bool

    public init(
        languageTag: String,
        resolvedLocaleIdentifier: String?,
        phase: LocalSpeechModelPhase,
        completedUnitCount: Int64 = 0,
        totalUnitCount: Int64 = 0,
        isReserved: Bool = false
    ) {
        self.languageTag = languageTag
        self.resolvedLocaleIdentifier =
            resolvedLocaleIdentifier
        self.phase = phase
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.isReserved = isReserved
    }

    public var fractionCompleted: Double? {
        guard totalUnitCount > 0 else { return nil }
        return min(
            max(
                Double(completedUnitCount)
                    / Double(totalUnitCount),
                0
            ),
            1
        )
    }
}

public protocol LocalSpeechModelManaging: Sendable {
    var events: AsyncStream<LocalSpeechModelSnapshot> { get }

    func snapshot(
        languageTag: String
    ) async -> LocalSpeechModelSnapshot
    func install(languageTag: String) async throws
    func pauseDownload() async
    func resumeDownload() async
    func cancelDownload() async
    func release(languageTag: String) async throws
}
