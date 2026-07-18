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
    case analysis
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
    case translationText = "translation_text"
    case speakerContext = "speaker_context"
    case evidenceIdentifiers = "evidence_identifiers"
    case validatedIntelligenceClaims = "validated_intelligence_claims"

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
              Set(categories).count == categories.count,
              Self.categoriesAreValid(categories, for: capability)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            capability: container.decode(AIProcessingCapability.self, forKey: .capability),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            offlineMode: container.decode(Bool.self, forKey: .offlineMode),
            organizationAllowsExternalProcessing: container.decode(
                Bool.self,
                forKey: .organizationAllowsExternalProcessing
            ),
            deploymentEnvironment: container.decode(
                ModelDeploymentEnvironment.self,
                forKey: .deploymentEnvironment
            ),
            destination: container.decode(ModelDestinationPolicy.self, forKey: .destination),
            retentionPolicy: container.decode(
                ProviderRetentionPolicy.self,
                forKey: .retentionPolicy
            ),
            dataCategories: container.decode(
                [ProviderDataCategory].self,
                forKey: .dataCategories
            ),
            visibleUserAuthorization: container.decode(
                Bool.self,
                forKey: .visibleUserAuthorization
            ),
            localModelAvailable: container.decode(Bool.self, forKey: .localModelAvailable)
        )
    }

    private static func categoriesAreValid(
        _ categories: [ProviderDataCategory],
        for capability: AIProcessingCapability
    ) -> Bool {
        let set = Set(categories)
        switch capability {
        case .transcription:
            return set == [.canonicalAudio]
        case .translation:
            return set == [.transcriptText]
        case .analysis:
            let allowed: Set<ProviderDataCategory> = [
                .transcriptText,
                .translationText,
                .speakerContext,
                .evidenceIdentifiers,
                .validatedIntelligenceClaims
            ]
            let extractionRequired: Set<ProviderDataCategory> = [
                .transcriptText,
                .speakerContext,
                .evidenceIdentifiers
            ]
            let aggregationRequired: Set<ProviderDataCategory> = [
                .validatedIntelligenceClaims,
                .evidenceIdentifiers
            ]
            return set.isSubset(of: allowed)
                && (extractionRequired.isSubset(of: set) || aggregationRequired.isSubset(of: set))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case capability
        case dataClassification
        case offlineMode
        case organizationAllowsExternalProcessing
        case deploymentEnvironment
        case destination
        case retentionPolicy
        case dataCategories
        case visibleUserAuthorization
        case localModelAvailable
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            route: container.decode(ModelExecutionRoute.self, forKey: .route),
            providerIdentifier: container.decodeIfPresent(
                String.self,
                forKey: .providerIdentifier
            ),
            reasonCode: container.decode(String.self, forKey: .reasonCode),
            request: container.decode(ModelRouteRequest.self, forKey: .request)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case providerIdentifier
        case reasonCode
        case request
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
                case .analysis: "meetingbuddy-deterministic-analysis"
                }
            } else {
                providerIdentifier = switch request.capability {
                case .transcription: "apple-speech"
                case .translation: "apple-translation"
                case .analysis: "apple-foundation-models"
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
            let testProviderIdentifier: String
            switch request.capability {
            case .transcription:
                testProviderIdentifier = "meetingbuddy-deterministic-transcription"
            case .translation:
                testProviderIdentifier = "meetingbuddy-deterministic-translation"
            case .analysis:
                testProviderIdentifier = "meetingbuddy-deterministic-analysis"
            }
            return try ModelRouteDecision(
                route: .deterministicTest,
                providerIdentifier: testProviderIdentifier,
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

public struct AnalysisSpeakerContext: Codable, Hashable, Sendable {
    public let actorLabel: String
    public let capacityLabel: String
    public let representedEntityLabel: String
    public let assignmentIsConfirmed: Bool

    public init(
        actorLabel: String,
        capacityLabel: String,
        representedEntityLabel: String,
        assignmentIsConfirmed: Bool
    ) throws {
        let values = [actorLabel, capacityLabel, representedEntityLabel]
        guard values.allSatisfy({ value in
            !value.isEmpty
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && value.utf8.count <= 512
                && !value.contains("\0")
        }) else {
            throw AIProviderContractError.invalidRequest("Analysis speaker context is missing or unbounded.")
        }
        self.actorLabel = actorLabel
        self.capacityLabel = capacityLabel
        self.representedEntityLabel = representedEntityLabel
        self.assignmentIsConfirmed = assignmentIsConfirmed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            actorLabel: container.decode(String.self, forKey: .actorLabel),
            capacityLabel: container.decode(String.self, forKey: .capacityLabel),
            representedEntityLabel: container.decode(String.self, forKey: .representedEntityLabel),
            assignmentIsConfirmed: container.decode(Bool.self, forKey: .assignmentIsConfirmed)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case actorLabel
        case capacityLabel
        case representedEntityLabel
        case assignmentIsConfirmed
    }
}

/// One bounded, exact source package. Text is untrusted data and never routing authority.
public struct AnalysisRequest: Codable, Hashable, Sendable {
    public let packageIdentifier: String
    public let transcriptRevision: SemanticRevisionReference
    public let translationRevision: SemanticRevisionReference?
    public let speakerAssignmentRevision: SemanticRevisionReference
    public let transcriptText: String
    public let translatedText: String?
    public let speakerContext: AnalysisSpeakerContext
    public let evidenceKeys: [String]
    public let dataClassification: DataClassification
    public let localeIdentifier: String

    public init(
        packageIdentifier: String,
        transcriptRevision: SemanticRevisionReference,
        translationRevision: SemanticRevisionReference? = nil,
        speakerAssignmentRevision: SemanticRevisionReference,
        transcriptText: String,
        translatedText: String? = nil,
        speakerContext: AnalysisSpeakerContext,
        evidenceKeys: [String],
        dataClassification: DataClassification,
        localeIdentifier: String
    ) throws {
        let identifier = packageIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let locale = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = evidenceKeys.sorted()
        guard !identifier.isEmpty,
              identifier == packageIdentifier,
              identifier.utf8.count <= 128,
              transcriptRevision.objectType == .transcriptSegment,
              translationRevision.map({ $0.objectType == .translationSegment }) ?? true,
              speakerAssignmentRevision.objectType == .speakerAssignment,
              Self.validText(transcriptText),
              translatedText.map(Self.validText) ?? true,
              (translationRevision == nil) == (translatedText == nil),
              !evidence.isEmpty,
              Set(evidence).count == evidence.count,
              evidence.allSatisfy(Self.validKey),
              dataClassification.isKnown,
              !locale.isEmpty,
              locale == localeIdentifier,
              locale.utf8.count <= 128
        else {
            throw AIProviderContractError.invalidRequest("The bounded analysis package is malformed.")
        }
        self.packageIdentifier = identifier
        self.transcriptRevision = transcriptRevision
        self.translationRevision = translationRevision
        self.speakerAssignmentRevision = speakerAssignmentRevision
        self.transcriptText = transcriptText
        self.translatedText = translatedText
        self.speakerContext = speakerContext
        self.evidenceKeys = evidence
        self.dataClassification = dataClassification
        self.localeIdentifier = locale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            packageIdentifier: container.decode(String.self, forKey: .packageIdentifier),
            transcriptRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .transcriptRevision
            ),
            translationRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .translationRevision
            ),
            speakerAssignmentRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .speakerAssignmentRevision
            ),
            transcriptText: container.decode(String.self, forKey: .transcriptText),
            translatedText: container.decodeIfPresent(String.self, forKey: .translatedText),
            speakerContext: container.decode(AnalysisSpeakerContext.self, forKey: .speakerContext),
            evidenceKeys: container.decode([String].self, forKey: .evidenceKeys),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            localeIdentifier: container.decode(String.self, forKey: .localeIdentifier)
        )
    }

    private static func validText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed == value
            && value.utf8.count <= 65_536
            && !value.contains("\0")
    }

    private static func validKey(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 128
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private enum CodingKeys: String, CodingKey {
        case packageIdentifier
        case transcriptRevision
        case translationRevision
        case speakerAssignmentRevision
        case transcriptText
        case translatedText
        case speakerContext
        case evidenceKeys
        case dataClassification
        case localeIdentifier
    }
}

public struct AnalysisCommitmentCandidate: Codable, Hashable, Sendable {
    public let content: String
    public let recipientLabel: String?
    public let conditions: [String]
    public let deadlineDescription: String?
    public let status: CommitmentStatus

    public init(
        content: String,
        recipientLabel: String? = nil,
        conditions: [String] = [],
        deadlineDescription: String? = nil,
        status: CommitmentStatus
    ) throws {
        guard AnalysisOutputCandidate.validMaterial(content),
              recipientLabel.map(AnalysisOutputCandidate.validLabel) ?? true,
              conditions.count <= 16,
              conditions.allSatisfy(AnalysisOutputCandidate.validMaterial),
              deadlineDescription.map(AnalysisOutputCandidate.validLabel) ?? true,
              status.isKnown,
              status != .completed
        else { throw AIProviderContractError.invalidResponse("The commitment candidate is malformed or overclaims completion.") }
        self.content = content
        self.recipientLabel = recipientLabel
        self.conditions = conditions
        self.deadlineDescription = deadlineDescription
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            content: container.decode(String.self, forKey: .content),
            recipientLabel: container.decodeIfPresent(String.self, forKey: .recipientLabel),
            conditions: container.decode([String].self, forKey: .conditions),
            deadlineDescription: container.decodeIfPresent(
                String.self,
                forKey: .deadlineDescription
            ),
            status: container.decode(CommitmentStatus.self, forKey: .status)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case recipientLabel
        case conditions
        case deadlineDescription
        case status
    }
}

public struct AnalysisDecisionCandidate: Codable, Hashable, Sendable {
    public let content: String
    public let decisionType: DecisionType

    public init(content: String, decisionType: DecisionType) throws {
        guard AnalysisOutputCandidate.validMaterial(content),
              decisionType == .uncertain
        else { throw AIProviderContractError.invalidResponse("An unconfirmed provider decision must remain uncertain.") }
        self.content = content
        self.decisionType = decisionType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            content: container.decode(String.self, forKey: .content),
            decisionType: container.decode(DecisionType.self, forKey: .decisionType)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case decisionType
    }
}

/// Provider-neutral candidate fields only. Identity, provenance, lifecycle, routing and IDs are application-owned.
public struct AnalysisOutputCandidate: Codable, Hashable, Sendable {
    public let substantive: Bool
    public let nonSubstantiveReasonCode: String?
    public let interventionType: InterventionType?
    public let issueTitle: String?
    public let positionType: PositionType?
    public let positionStatement: String?
    public let reservations: [String]
    public let conditions: [String]
    public let commitment: AnalysisCommitmentCandidate?
    public let decision: AnalysisDecisionCandidate?
    public let confidence: ConfidenceScore

    public init(
        substantive: Bool,
        nonSubstantiveReasonCode: String? = nil,
        interventionType: InterventionType? = nil,
        issueTitle: String? = nil,
        positionType: PositionType? = nil,
        positionStatement: String? = nil,
        reservations: [String] = [],
        conditions: [String] = [],
        commitment: AnalysisCommitmentCandidate? = nil,
        decision: AnalysisDecisionCandidate? = nil,
        confidence: ConfidenceScore
    ) throws {
        guard reservations.count <= 32,
              conditions.count <= 32,
              reservations.allSatisfy(Self.validMaterial),
              conditions.allSatisfy(Self.validMaterial),
              Set(reservations).count == reservations.count,
              Set(conditions).count == conditions.count
        else { throw AIProviderContractError.invalidResponse("Analysis qualifications are malformed or duplicated.") }
        if substantive {
            guard nonSubstantiveReasonCode == nil,
                  interventionType?.isKnown == true,
                  issueTitle.map(Self.validLabel) == true,
                  positionType?.isKnown == true,
                  positionType != .noStatedPosition,
                  positionStatement.map(Self.validMaterial) == true
            else { throw AIProviderContractError.invalidResponse("A substantive analysis candidate is incomplete or unsafe.") }
            if positionType == .supportsWithConditions, conditions.isEmpty {
                throw AIProviderContractError.invalidResponse("Conditional support must preserve its conditions.")
            }
            if positionType == .opposesWithQualification, reservations.isEmpty {
                throw AIProviderContractError.invalidResponse("Qualified opposition must preserve its reservation.")
            }
        } else {
            guard let reason = nonSubstantiveReasonCode,
                  Self.validKey(reason),
                  interventionType == nil,
                  issueTitle == nil,
                  positionType == nil,
                  positionStatement == nil,
                  reservations.isEmpty,
                  conditions.isEmpty,
                  commitment == nil,
                  decision == nil
            else { throw AIProviderContractError.invalidResponse("A non-substantive result cannot contain semantic claims.") }
        }
        self.substantive = substantive
        self.nonSubstantiveReasonCode = nonSubstantiveReasonCode
        self.interventionType = interventionType
        self.issueTitle = issueTitle
        self.positionType = positionType
        self.positionStatement = positionStatement
        self.reservations = reservations
        self.conditions = conditions
        self.commitment = commitment
        self.decision = decision
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            substantive: container.decode(Bool.self, forKey: .substantive),
            nonSubstantiveReasonCode: container.decodeIfPresent(
                String.self,
                forKey: .nonSubstantiveReasonCode
            ),
            interventionType: container.decodeIfPresent(
                InterventionType.self,
                forKey: .interventionType
            ),
            issueTitle: container.decodeIfPresent(String.self, forKey: .issueTitle),
            positionType: container.decodeIfPresent(PositionType.self, forKey: .positionType),
            positionStatement: container.decodeIfPresent(
                String.self,
                forKey: .positionStatement
            ),
            reservations: container.decode([String].self, forKey: .reservations),
            conditions: container.decode([String].self, forKey: .conditions),
            commitment: container.decodeIfPresent(
                AnalysisCommitmentCandidate.self,
                forKey: .commitment
            ),
            decision: container.decodeIfPresent(
                AnalysisDecisionCandidate.self,
                forKey: .decision
            ),
            confidence: container.decode(ConfidenceScore.self, forKey: .confidence)
        )
    }

    static func validMaterial(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value && value.utf8.count <= 16_384 && !value.contains("\0")
    }

    static func validLabel(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value && value.utf8.count <= 512 && !value.contains("\0")
    }

    private static func validKey(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 96
            && value.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
            }
    }

    private enum CodingKeys: String, CodingKey {
        case substantive
        case nonSubstantiveReasonCode
        case interventionType
        case issueTitle
        case positionType
        case positionStatement
        case reservations
        case conditions
        case commitment
        case decision
        case confidence
    }
}

public protocol AnalysisProvider: Sendable {
    var metadata: ProviderMetadata { get }
    var route: ModelExecutionRoute { get }
    func isModelAvailable(localeIdentifier: String) async -> Bool
    func analyze(_ request: AnalysisRequest) async throws -> AnalysisOutputCandidate
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
