import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class BriefingPipelineJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = BriefingJobTypes.pipeline

    private let provider: any BriefingSectionProvider
    private let repository: any BriefingRepository

    public init(
        provider: any BriefingSectionProvider,
        repository: any BriefingRepository
    ) {
        self.provider = provider
        self.repository = repository
    }

    public func execute(_ context: JobExecutionContext) async throws -> JobExecutionResult {
        do {
            return try await executePipeline(context)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as JobExecutionFailure {
            throw failure
        } catch let error as AIProviderContractError {
            throw try JobExecutionFailure(
                code: failureCode(error),
                safeSummary: safeSummary(error),
                retryable: isRetryable(error),
                privateDiagnostic: String(describing: error)
            )
        } catch let error as BriefingCoverageError {
            throw try JobExecutionFailure(
                code: "briefing_validation_failed",
                safeSummary: "Structured briefing coverage or validation failed. Nothing was published.",
                retryable: error != .lockedSection,
                privateDiagnostic: String(describing: error)
            )
        } catch let error as JobContractError {
            throw try JobExecutionFailure(
                code: "stale_input",
                safeSummary: "An exact briefing input changed before publication. Nothing was published.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        } catch {
            throw try JobExecutionFailure(
                code: "briefing_pipeline_failed",
                safeSummary: "Local briefing generation failed without publishing partial content.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
    }

    private func executePipeline(
        _ context: JobExecutionContext
    ) async throws -> JobExecutionResult {
        let plan = try BriefingPipelineJobPlan.decode(from: context.job.inputPayload)
        guard context.job.jobType == jobType,
              context.job.meetingID == plan.meetingID,
              context.job.privacyRoute == .localOnly,
              context.job.dataClassification == plan.sectionRoute.request.dataClassification,
              context.job.inputRevisionIDs == plan.inputRevisionIDs,
              provider.route == plan.sectionRoute.route,
              provider.metadata.providerIdentifier == plan.sectionRoute.providerIdentifier
        else {
            throw AIProviderContractError.routeDenied(
                "The briefing executor, approved local route, and durable job metadata do not match."
            )
        }
        let source = try repository.briefingSourceBundle(
            meetingRevision: plan.meetingRevision,
            template: plan.template,
            analysisLedgerID: plan.analysisLedgerID
        )
        let currentReferences = try BriefingPipelineJobPlan.inputReferences(
            source: source,
            operation: plan.operation
        )
        guard currentReferences == plan.inputRevisionIDs,
              source.analysis.ledger.contentHash == plan.analysisLedgerHash,
              source.analysis.ledger.transcriptManifestID == plan.transcriptManifestID,
              source.analysis.ledger.transcriptManifestHash == plan.transcriptManifestHash,
              source.analysis.ledger.eligibleSegmentRevisions == plan.eligibleSegmentRevisions
        else {
            throw JobContractError.invalidRequest(
                "The exact structured briefing package changed after planning."
            )
        }

        let graph: IssuePositionGraphV1
        var sections: [BriefingSectionV1] = []
        var priorState: BriefingAssemblyPriorState?
        var replacedRevisionID: RevisionID?
        var requests: [BriefingSectionType: BriefingSectionRequest] = [:]

        switch plan.operation {
        case .initial:
            let inputs = try BriefingSemanticFactory.generationInputs(
                source: source,
                createdAt: plan.createdAt
            )
            graph = inputs.graph
            requests = inputs.requests
        case let .regenerate(
            sectionType,
            expectedSectionRevisionID,
            graphReference,
            sectionReferences,
            reportReference,
            finalReference,
            ledgerID
        ):
            guard let active = try repository.activeBriefingReview(meetingID: plan.meetingID),
                  active.isCurrent,
                  active.publication.graph.revision.revisionID == graphReference.revisionID,
                  try active.publication.sections.map(BriefingSemanticFactory.reference)
                    == sectionReferences,
                  active.publication.validationReport.revision.revisionID
                    == reportReference.revisionID,
                  active.publication.finalBriefing.revision.revisionID
                    == finalReference.revisionID,
                  active.publication.ledger.ledgerID == ledgerID,
                  let priorSection = active.publication.sections.first(where: {
                      $0.sectionType == sectionType
                          && $0.revision.revisionID == expectedSectionRevisionID
                  })
            else { throw BriefingCoverageError.staleSection }
            guard !priorSection.locked,
                  priorSection.manualEditStatus == .generated
            else { throw BriefingCoverageError.lockedSection }
            graph = active.publication.graph
            sections = active.publication.sections.filter { $0.sectionType != sectionType }
            priorState = BriefingAssemblyPriorState(
                ledgerID: ledgerID,
                validationReport: active.publication.validationReport,
                finalBriefing: active.publication.finalBriefing
            )
            replacedRevisionID = expectedSectionRevisionID
            guard let definition = source.template.section(sectionType) else {
                throw AIProviderContractError.invalidRequest("The selected section is not in the template.")
            }
            requests[sectionType] = try BriefingSectionRequest(
                packageIdentifier: "section_\(sectionType.encodedValue)",
                templateRevision: BriefingSemanticFactory.reference(source.template),
                graphRevision: BriefingSemanticFactory.reference(graph),
                sectionDefinition: definition,
                outputLanguage: source.meeting.outputLanguage,
                sourceClaims: BriefingSemanticFactory.sourceClaims(
                    for: sectionType,
                    source: source,
                    graph: graph
                ),
                dataClassification: plan.sectionRoute.request.dataClassification,
                localeIdentifier: source.meeting.outputLanguage.value
            )
        }

        let available = await provider.isModelAvailable(
            localeIdentifier: source.meeting.outputLanguage.value
        )
        guard available else {
            try? recordIncomplete(
                plan: plan,
                source: source,
                graph: graph,
                reasonCode: "model_unavailable"
            )
            throw AIProviderContractError.modelUnavailable(
                "The approved on-device briefing model is unavailable for this locale."
            )
        }

        let orderedTypes = requests.keys.sorted {
            requests[$0]!.sectionDefinition.order < requests[$1]!.sectionDefinition.order
        }
        for (index, type) in orderedTypes.enumerated() {
            try Task.checkCancellation()
            let request = requests[type]!
            let candidate: BriefingSectionCandidate
            do {
                candidate = try await provider.generateSection(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? recordIncomplete(
                    plan: plan,
                    source: source,
                    graph: graph,
                    reasonCode: failureCode(error)
                )
                throw error
            }
            let priorSection: BriefingSectionV1?
            if case .regenerate = plan.operation {
                let active = try repository.activeBriefingReview(meetingID: plan.meetingID)
                priorSection = active?.publication.sections.first { $0.sectionType == type }
            } else {
                priorSection = nil
            }
            sections.append(try BriefingSemanticFactory.makeGeneratedSection(
                request: request,
                candidate: candidate,
                source: source,
                graph: graph,
                provider: provider.metadata,
                createdAt: plan.createdAt,
                superseding: priorSection
            ))
            try await context.checkpoint(
                progress: JobProgress(
                    completedUnitCount: UInt64(index + 1),
                    totalUnitCount: UInt64(orderedTypes.count),
                    currentNode: "briefing-section-\(type.encodedValue)"
                )
            )
        }
        let publication = try BriefingSemanticFactory.makePublication(
            source: source,
            graph: graph,
            sections: sections,
            prior: priorState,
            createdAt: plan.createdAt
        )
        if let replacedRevisionID {
            try repository.replaceBriefingSection(
                publication,
                replacing: replacedRevisionID,
                changedAt: plan.createdAt
            )
        } else {
            try repository.publishBriefing(
                publication,
                validatingInputRevisions: plan.inputRevisionIDs
            )
        }
        let outputs = try [
            BriefingSemanticFactory.reference(publication.template),
            BriefingSemanticFactory.reference(publication.graph),
            BriefingSemanticFactory.reference(publication.validationReport),
            BriefingSemanticFactory.reference(publication.finalBriefing)
        ] + publication.sections.map(BriefingSemanticFactory.reference)
        return try JobExecutionResult(
            outputRevisionIDs: outputs,
            providerUsage: [
                ProviderUsageMetadata(
                    provider: provider.metadata,
                    inputUnitCount: UInt64(orderedTypes.count),
                    outputUnitCount: UInt64(publication.sections.flatMap(\.items).count)
                )
            ]
        )
    }

    private func recordIncomplete(
        plan: BriefingPipelineJobPlan,
        source: BriefingSourceBundle,
        graph: IssuePositionGraphV1,
        reasonCode: String
    ) throws {
        let graphReference = try BriefingSemanticFactory.reference(graph)
        let sectionReferences = try source.template.sections.map { definition in
            try SemanticRevisionReference(
                logicalID: BriefingSectionID(BriefingSemanticFactory.deterministicUUID(
                    "task006b-section-v1:\(source.meeting.meetingID.canonicalString):\(definition.sectionType.encodedValue):logical"
                )),
                revisionID: RevisionID(BriefingSemanticFactory.deterministicUUID(
                    "task006b-incomplete:\(plan.createdAt.millisecondsSinceUnixEpoch):\(definition.sectionType.encodedValue)"
                ))
            )
        }
        let safeReason = sanitizedReason(reasonCode)
        let segments = try source.analysis.ledger.segments.map { segment in
            if segment.disposition == .nonSubstantive {
                return try BriefingSegmentCoverage(
                    segmentRevision: segment.segmentRevision,
                    analysisOutputRevisions: [],
                    evidenceRevisions: segment.evidenceRevisions,
                    conclusionReferences: [],
                    disposition: .nonSubstantive,
                    safeReasonCode: segment.safeReasonCode ?? "analysis_non_substantive"
                )
            }
            return try BriefingSegmentCoverage(
                segmentRevision: segment.segmentRevision,
                analysisOutputRevisions: segment.outputRevisions,
                evidenceRevisions: segment.evidenceRevisions,
                conclusionReferences: [],
                disposition: .failed,
                safeReasonCode: safeReason
            )
        }
        let supersedes: BriefingCoverageLedgerID? = switch plan.operation {
        case .initial: nil
        case let .regenerate(_, _, _, _, _, _, ledgerID): ledgerID
        }
        let ledger = try BriefingCoverageLedger(
            ledgerID: BriefingCoverageLedgerID(BriefingSemanticFactory.deterministicUUID(
                "task006b-incomplete:\(plan.meetingID.canonicalString):\(plan.createdAt.millisecondsSinceUnixEpoch):\(safeReason)"
            )),
            supersedesLedgerID: supersedes,
            meetingID: plan.meetingID,
            transcriptManifestID: plan.transcriptManifestID,
            transcriptManifestHash: plan.transcriptManifestHash,
            analysisLedgerID: plan.analysisLedgerID,
            analysisLedgerHash: plan.analysisLedgerHash,
            eligibleSegmentRevisions: plan.eligibleSegmentRevisions,
            templateRevision: BriefingSemanticFactory.reference(plan.template),
            graphRevision: graphReference,
            sectionRevisions: sectionReferences,
            status: .incomplete,
            segments: segments,
            createdAt: plan.createdAt
        )
        try repository.recordIncompleteBriefing(ledger)
    }

    private func sanitizedReason(_ value: String) -> String {
        let safe = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
                ? Character(String(scalar)) : "_"
        }
        return String(safe.prefix(96)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .isEmpty ? "briefing_provider_failed" : String(safe.prefix(96))
    }

    private func failureCode(_ error: Error) -> String {
        guard let error = error as? AIProviderContractError else {
            return "briefing_provider_failed"
        }
        return switch error {
        case .modelUnavailable: "model_unavailable"
        case .routeDenied: "route_denied"
        case .invalidRequest: "invalid_request"
        case .invalidResponse: "invalid_response"
        case .secretUnavailable: "secret_unavailable"
        }
    }

    private func safeSummary(_ error: AIProviderContractError) -> String {
        return switch error {
        case .modelUnavailable:
            "The local briefing model is unavailable. Existing validated content remains unchanged."
        case .routeDenied:
            "The application policy router denied this briefing route."
        case .invalidRequest:
            "The exact structured briefing package failed validation."
        case .invalidResponse:
            "The local model returned a section that failed protected validation."
        case .secretUnavailable:
            "A required provider secret is unavailable."
        }
    }

    private func isRetryable(_ error: AIProviderContractError) -> Bool {
        return switch error {
        case .modelUnavailable, .invalidResponse: true
        case .routeDenied, .invalidRequest, .secretUnavailable: false
        }
    }
}
