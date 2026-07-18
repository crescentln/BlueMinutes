import Foundation
import MeetingBuddyDomain

public enum AIProviderContractError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case invalidResponse(String)
    case routeDenied(String)
    case modelUnavailable(String)
    case secretUnavailable
}

public enum AIProcessingCapability: String, Codable, Hashable, Sendable {
    case transcription
    case translation
}

public enum ModelExecutionRoute: String, Codable, Hashable, Sendable {
    case appleOnDevice = "apple_on_device"
    case deterministicTest = "deterministic_test"
    case manualFallback = "manual_fallback"
    case approvedExternal = "approved_external"

    public var privacyRoute: PrivacyRoute {
        switch self {
        case .appleOnDevice, .deterministicTest, .manualFallback: .localOnly
        case .approvedExternal: .approvedCloud
        }
    }
}

public enum ModelDeploymentEnvironment: String, Codable, Hashable, Sendable {
    case production
    case development
    case test
}

public enum ModelDestinationPolicy: Codable, Hashable, Sendable {
    case localDevice
    case approvedProvider(identifier: String)
}

public enum ProviderRetentionPolicy: String, Codable, Hashable, Sendable {
    case localWorkspaceOnly = "local_workspace_only"
    case noProviderRetention = "no_provider_retention"
    case approvedProviderRetention = "approved_provider_retention"
}

public enum ProviderDataCategory: String, Codable, Hashable, Sendable, Comparable {
    case canonicalAudio = "canonical_audio"
    case transcriptText = "transcript_text"

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Every policy input is explicit. A UI provider choice is never sufficient authorization.
public struct ModelRouteRequest: Codable, Hashable, Sendable {
    public let capability: AIProcessingCapability
    public let dataClassification: DataClassification
    public let offlineMode: Bool
    public let organizationAllowsExternalProcessing: Bool
    public let deploymentEnvironment: ModelDeploymentEnvironment
    public let destination: ModelDestinationPolicy
    public let retentionPolicy: ProviderRetentionPolicy
    public let dataCategories: [ProviderDataCategory]
    public let visibleUserAuthorization: Bool
    public let localModelAvailable: Bool

    public init(
        capability: AIProcessingCapability,
        dataClassification: DataClassification,
        offlineMode: Bool,
        organizationAllowsExternalProcessing: Bool,
        deploymentEnvironment: ModelDeploymentEnvironment,
        destination: ModelDestinationPolicy,
        retentionPolicy: ProviderRetentionPolicy,
        dataCategories: [ProviderDataCategory],
        visibleUserAuthorization: Bool,
        localModelAvailable: Bool
    ) throws {
        let categories = dataCategories.sorted()
        guard dataClassification.isKnown,
              !categories.isEmpty,
              Set(categories).count == categories.count
        else {
            throw AIProviderContractError.invalidRequest("The model route has unknown or duplicate policy inputs.")
        }
        self.capability = capability
        self.dataClassification = dataClassification
        self.offlineMode = offlineMode
        self.organizationAllowsExternalProcessing = organizationAllowsExternalProcessing
        self.deploymentEnvironment = deploymentEnvironment
        self.destination = destination
        self.retentionPolicy = retentionPolicy
        self.dataCategories = categories
        self.visibleUserAuthorization = visibleUserAuthorization
        self.localModelAvailable = localModelAvailable
    }
}

public struct ModelRouteDecision: Codable, Hashable, Sendable {
    public let route: ModelExecutionRoute
    public let providerIdentifier: String?
    public let reasonCode: String
    public let request: ModelRouteRequest

    public init(
        route: ModelExecutionRoute,
        providerIdentifier: String?,
        reasonCode: String,
        request: ModelRouteRequest
    ) throws {
        let reason = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty,
              reason.utf8.count <= 128,
              !reason.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              providerIdentifier.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true,
              route.privacyRoute == .localOnly || providerIdentifier != nil
        else {
            throw AIProviderContractError.invalidRequest("The model route decision is malformed.")
        }
        self.route = route
        self.providerIdentifier = providerIdentifier
        self.reasonCode = reason
        self.request = request
    }
}

/// Application-owned, fail-closed policy router.
public struct ModelPolicyRouter: Sendable {
    public init() {}

    public func decide(_ request: ModelRouteRequest) throws -> ModelRouteDecision {
        if request.localModelAvailable {
            let providerIdentifier: String
            if request.deploymentEnvironment == .test {
                providerIdentifier = switch request.capability {
                case .transcription: "meetingbuddy-deterministic-transcription"
                case .translation: "meetingbuddy-deterministic-translation"
                }
            } else {
                providerIdentifier = switch request.capability {
                case .transcription: "apple-speech"
                case .translation: "apple-translation"
                }
            }
            return try ModelRouteDecision(
                route: request.deploymentEnvironment == .test ? .deterministicTest : .appleOnDevice,
                providerIdentifier: providerIdentifier,
                reasonCode: "local_model_selected",
                request: request
            )
        }
        if request.deploymentEnvironment == .test {
            return try ModelRouteDecision(
                route: .deterministicTest,
                providerIdentifier: request.capability == .transcription
                    ? "meetingbuddy-deterministic-transcription"
                    : "meetingbuddy-deterministic-translation",
                reasonCode: "test_route_selected",
                request: request
            )
        }
        if request.offlineMode {
            return try manualDecision(request, reason: "offline_model_unavailable")
        }
        guard request.organizationAllowsExternalProcessing,
              request.visibleUserAuthorization,
              request.dataClassification != .restricted,
              request.retentionPolicy != .localWorkspaceOnly,
              case let .approvedProvider(identifier) = request.destination,
              !identifier.isEmpty
        else {
            return try manualDecision(request, reason: "external_route_denied")
        }
        // Task 005B defines the policy gate but authorizes no outbound adapter.
        throw AIProviderContractError.routeDenied(
            "An external route passed policy, but Task 005B has no approved outbound provider adapter."
        )
    }

    private func manualDecision(
        _ request: ModelRouteRequest,
        reason: String
    ) throws -> ModelRouteDecision {
        try ModelRouteDecision(
            route: .manualFallback,
            providerIdentifier: nil,
            reasonCode: reason,
            request: request
        )
    }
}

/// A capability for one task-owned, bounded audio chunk. It is intentionally not Codable or loggable.
public struct TaskOwnedAudioChunk: @unchecked Sendable {
    public let fileURL: URL
    public let plan: MediaChunkPlanEntry

    public init(fileURL: URL, plan: MediaChunkPlanEntry) throws {
        guard fileURL.isFileURL, fileURL.hasDirectoryPath == false else {
            throw AIProviderContractError.invalidRequest("A provider audio capability must be one local file.")
        }
        self.fileURL = fileURL
        self.plan = plan
    }
}

public struct TranscriptionSpan: Codable, Hashable, Sendable, Comparable {
    public let startMilliseconds: Int64
    public let endMilliseconds: Int64
    public let text: String
    public let confidence: ConfidenceScore

    public init(
        startMilliseconds: Int64,
        endMilliseconds: Int64,
        text: String,
        confidence: ConfidenceScore
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard startMilliseconds >= 0,
              endMilliseconds > startMilliseconds,
              trimmed == text,
              !trimmed.isEmpty,
              trimmed.utf8.count <= 65_536,
              !trimmed.contains("\0")
        else {
            throw AIProviderContractError.invalidResponse("A transcription span is empty, unbounded, or outside its chunk.")
        }
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
        self.confidence = confidence
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.startMilliseconds, lhs.endMilliseconds, lhs.text)
            < (rhs.startMilliseconds, rhs.endMilliseconds, rhs.text)
    }
}

public enum TranscriptionChunkResult: Codable, Hashable, Sendable {
    case speech(spans: [TranscriptionSpan])
    case noSpeech

    public init(validatingSpans spans: [TranscriptionSpan]) throws {
        let sorted = spans.sorted()
        guard !sorted.isEmpty else { throw AIProviderContractError.invalidResponse("Speech requires at least one span.") }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.endMilliseconds > pair.1.startMilliseconds {
            throw AIProviderContractError.invalidResponse("Provider spans must not overlap.")
        }
        self = .speech(spans: sorted)
    }
}

public struct TranscriptionRequest: Sendable {
    public let audio: TaskOwnedAudioChunk
    public let canonicalSourceRevision: SemanticRevisionReference
    public let language: LanguageTag
    public let dataClassification: DataClassification

    public init(
        audio: TaskOwnedAudioChunk,
        canonicalSourceRevision: SemanticRevisionReference,
        language: LanguageTag,
        dataClassification: DataClassification
    ) throws {
        guard canonicalSourceRevision.objectType == .sourceAsset, dataClassification.isKnown else {
            throw AIProviderContractError.invalidRequest("Transcription requires an exact source revision and known classification.")
        }
        self.audio = audio
        self.canonicalSourceRevision = canonicalSourceRevision
        self.language = language
        self.dataClassification = dataClassification
    }
}

public protocol TranscriptionProvider: Sendable {
    var metadata: ProviderMetadata { get }
    var route: ModelExecutionRoute { get }
    func isModelInstalled(for language: LanguageTag) async -> Bool
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionChunkResult
}

public struct TranslationRequest: Sendable {
    public let sourceText: String
    public let sourceLanguage: LanguageTag
    public let targetLanguage: LanguageTag
    public let dataClassification: DataClassification

    public init(
        sourceText: String,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag,
        dataClassification: DataClassification
    ) throws {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == sourceText,
              trimmed.utf8.count <= 65_536,
              sourceLanguage != targetLanguage,
              dataClassification.isKnown
        else {
            throw AIProviderContractError.invalidRequest("Translation requires bounded text and distinct languages.")
        }
        self.sourceText = sourceText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.dataClassification = dataClassification
    }
}

public struct TranslationResponse: Codable, Sendable, Hashable {
    public let translatedText: String
    public let confidence: ConfidenceScore

    public init(translatedText: String, confidence: ConfidenceScore) throws {
        let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == translatedText, trimmed.utf8.count <= 65_536 else {
            throw AIProviderContractError.invalidResponse("A translation response must contain bounded text.")
        }
        self.translatedText = translatedText
        self.confidence = confidence
    }
}

public protocol TranslationProvider: Sendable {
    var metadata: ProviderMetadata { get }
    var route: ModelExecutionRoute { get }
    func isModelInstalled(source: LanguageTag, target: LanguageTag) async -> Bool
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse
}

public struct SecretIdentifier: Hashable, Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) throws {
        guard Self.valid(service), Self.valid(account) else {
            throw AIProviderContractError.invalidRequest("Secret identifiers must be bounded opaque names.")
        }
        self.service = service
        self.account = account
    }

    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

public protocol SecretStore: Sendable {
    func read(_ identifier: SecretIdentifier) throws -> Data?
    func write(_ value: Data, for identifier: SecretIdentifier) throws
    func remove(_ identifier: SecretIdentifier) throws
}
