import Foundation
import MeetingBuddyDomain

public enum CodexIntegrationContractError: Error, Equatable, Sendable {
    case authorizationDenied(String)
    case invalidContext(String)
    case invalidPrompt(String)
}

/// Binds Codex text execution to one exact routing result and one complete
/// application-owned external model authorization.
///
/// The initializer is unavailable outside this module. Provider readiness,
/// UI selection, or a Codex login can never construct this value by itself.
public struct CodexTextExecutionAuthorization: Hashable, Sendable {
    public static let providerIdentifier = "codex-subscription"

    public let route: ResolvedTaskRoute
    public let policyAuthorization: ExternalModelExecutionAuthorization

    init(
        route: ResolvedTaskRoute,
        policyAuthorization: ExternalModelExecutionAuthorization
    ) {
        self.route = route
        self.policyAuthorization = policyAuthorization
    }
}

public struct CodexTextExecutionAuthorizationFactory: Sendable {
    private let router: ModelPolicyRouter

    public init(router: ModelPolicyRouter = ModelPolicyRouter()) {
        self.router = router
    }

    public func authorize(
        candidate: ResolvedTaskRoute,
        request: ModelRouteRequest
    ) throws -> CodexTextExecutionAuthorization {
        guard candidate.providerIdentifier
            == CodexTextExecutionAuthorization.providerIdentifier,
              candidate.modelIdentifier == "codex-default",
              candidate.dataRoute == .codexSubscriptionText,
              candidate.costOwner == .codexSubscription,
              !candidate.task.isSpeechToText,
              candidate.task != .externalResearch,
              candidate.task.acceptedCapabilities.contains(candidate.capability),
              candidate.capability != .speechToTextBatch,
              candidate.capability != .speechToTextRealtime,
              request.capability == expectedCapability(for: candidate.task),
              request.dataClassification == candidate.effectiveClassification,
              request.dataCategories.contains(.canonicalAudio) == false,
              let securityPolicy = request.securityPolicy,
              securityPolicy.sensitivityLabelRevision
                  == candidate.sensitivityLabelRevision,
              securityPolicy.accessPolicyRevision
                  == candidate.accessPolicyRevision,
              securityPolicy.effectiveClassification
                  == candidate.effectiveClassification,
              securityPolicy.noOutboundMode == candidate.noOutboundMode,
              securityPolicy.noOutboundMode == false,
              categoriesAreValid(
                  request.dataCategories,
                  for: candidate.task
              )
        else {
            throw CodexIntegrationContractError.authorizationDenied(
                "The Codex route, task, policy revisions, classification, or text categories do not agree."
            )
        }

        let policyAuthorization = try router.authorizeExternal(
            request,
            expectedProviderIdentifier:
                CodexTextExecutionAuthorization.providerIdentifier
        )
        return CodexTextExecutionAuthorization(
            route: candidate,
            policyAuthorization: policyAuthorization
        )
    }

    private func expectedCapability(
        for task: RoutedTask
    ) -> AIProcessingCapability {
        task == .translation ? .translation : .analysis
    }

    private func categoriesAreValid(
        _ categories: [ProviderDataCategory],
        for task: RoutedTask
    ) -> Bool {
        let values = Set(categories)
        switch task {
        case .speechToTextBatch, .speechToTextRealtime:
            return false
        case .translation:
            return values == [.transcriptText]
        case .speakerProcessing, .textAnalysis, .summaryAndMinutes:
            let extraction: Set<ProviderDataCategory> = [
                .transcriptText,
                .speakerContext,
                .evidenceIdentifiers
            ]
            let aggregation: Set<ProviderDataCategory> = [
                .validatedIntelligenceClaims,
                .evidenceIdentifiers
            ]
            return extraction.isSubset(of: values)
                || aggregation.isSubset(of: values)
        case .meetingChat:
            return values.contains(.userPromptText)
        case .documentQuery:
            return values.contains(.userPromptText)
                && values.contains(.documentText)
        case .externalResearch:
            return false
        }
    }
}

public struct CodexTranscriptContextSegment: Hashable, Sendable {
    public let segmentRevision: SemanticRevisionReference
    public let startMilliseconds: Int64
    public let endMilliseconds: Int64
    public let language: LanguageTag
    public let text: String

    init(
        segmentRevision: SemanticRevisionReference,
        startMilliseconds: Int64,
        endMilliseconds: Int64,
        language: LanguageTag,
        text: String
    ) {
        self.segmentRevision = segmentRevision
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.language = language
        self.text = text
    }
}

/// A bounded, path-free projection of user-selected transcript revisions.
public struct CodexMeetingTextContext: Hashable, Sendable {
    public static let maximumSegmentCount = 64
    public static let maximumSegmentUTF8Bytes = 16 * 1_024
    public static let maximumTotalUTF8Bytes = 96 * 1_024

    public let workspaceID: WorkspaceID
    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let segments: [CodexTranscriptContextSegment]
    public let totalUTF8Bytes: Int

    init(
        workspaceID: WorkspaceID,
        meetingID: MeetingID,
        meetingRevision: SemanticRevisionReference,
        segments: [CodexTranscriptContextSegment],
        totalUTF8Bytes: Int
    ) {
        self.workspaceID = workspaceID
        self.meetingID = meetingID
        self.meetingRevision = meetingRevision
        self.segments = segments
        self.totalUTF8Bytes = totalUTF8Bytes
    }
}

public struct CodexMeetingTextContextFactory: Sendable {
    public init() {}

    public func make(
        authorization: CodexTextExecutionAuthorization,
        selectedSegments: [TranscriptSegmentV1]
    ) throws -> CodexMeetingTextContext {
        guard !selectedSegments.isEmpty,
              selectedSegments.count
                  <= CodexMeetingTextContext.maximumSegmentCount
        else {
            throw CodexIntegrationContractError.invalidContext(
                "Codex context requires 1–64 explicitly selected transcript segments."
            )
        }

        let route = authorization.route
        let sorted = selectedSegments.sorted {
            (
                $0.timeRange.startMilliseconds,
                $0.timeRange.endMilliseconds,
                $0.revision.revisionID.canonicalString
            ) < (
                $1.timeRange.startMilliseconds,
                $1.timeRange.endMilliseconds,
                $1.revision.revisionID.canonicalString
            )
        }
        var seenRevisions = Set<RevisionID>()
        var projected: [CodexTranscriptContextSegment] = []
        projected.reserveCapacity(sorted.count)
        var totalUTF8Bytes = 0

        for segment in sorted {
            let byteCount = segment.text.utf8.count
            guard segment.meetingID == route.meetingID,
                  segment.revision.dataClassification.restrictionRank
                      <= route.effectiveClassification.restrictionRank,
                  seenRevisions.insert(segment.revision.revisionID).inserted,
                  byteCount <= CodexMeetingTextContext.maximumSegmentUTF8Bytes
            else {
                throw CodexIntegrationContractError.invalidContext(
                    "Selected transcript context crossed a meeting, classification, revision, or per-segment bound."
                )
            }
            totalUTF8Bytes += byteCount
            guard totalUTF8Bytes
                <= CodexMeetingTextContext.maximumTotalUTF8Bytes
            else {
                throw CodexIntegrationContractError.invalidContext(
                    "Selected transcript context exceeds the bounded text budget."
                )
            }
            projected.append(
                CodexTranscriptContextSegment(
                    segmentRevision: try SemanticRevisionReference(
                        logicalID: segment.segmentID,
                        revisionID: segment.revision.revisionID
                    ),
                    startMilliseconds:
                        segment.timeRange.startMilliseconds,
                    endMilliseconds:
                        segment.timeRange.endMilliseconds,
                    language: segment.detectedLanguage,
                    text: segment.text
                )
            )
        }

        return CodexMeetingTextContext(
            workspaceID: route.workspaceID,
            meetingID: route.meetingID,
            meetingRevision: route.meetingRevision,
            segments: projected,
            totalUTF8Bytes: totalUTF8Bytes
        )
    }
}

public struct CodexMeetingTurnRequest: Hashable, Sendable {
    public static let maximumPromptUTF8Bytes = 16 * 1_024

    public let authorization: CodexTextExecutionAuthorization
    public let context: CodexMeetingTextContext
    public let prompt: String

    public init(
        authorization: CodexTextExecutionAuthorization,
        context: CodexMeetingTextContext,
        prompt: String
    ) throws {
        let trimmed = prompt.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let containsUnsupportedControl = prompt.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
                && $0 != "\n"
                && $0 != "\r"
                && $0 != "\t"
        }
        guard !trimmed.isEmpty,
              prompt.utf8.count <= Self.maximumPromptUTF8Bytes,
              !containsUnsupportedControl,
              context.workspaceID == authorization.route.workspaceID,
              context.meetingID == authorization.route.meetingID,
              context.meetingRevision == authorization.route.meetingRevision,
              authorization.policyAuthorization.decision.request
                  .dataCategories.contains(.userPromptText)
        else {
            throw CodexIntegrationContractError.invalidPrompt(
                "The prompt or selected context is empty, oversized, unsafe, or outside the authorized meeting scope."
            )
        }
        self.authorization = authorization
        self.context = context
        self.prompt = prompt
    }
}
