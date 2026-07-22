import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class AnalysisPipelineJobExecutor: TaskJobExecutor, @unchecked Sendable {
    public let jobType = AnalysisJobTypes.pipeline

    private let provider: any AnalysisProvider
    private let repository: any AnalysisRepository

    public init(
        provider: any AnalysisProvider,
        repository: any AnalysisRepository
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
        } catch let error as AnalysisCoverageError {
            throw try JobExecutionFailure(
                code: "analysis_coverage_invalid",
                safeSummary: "Local analysis coverage or publication validation failed. Nothing was published.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        } catch let error as JobContractError {
            throw try JobExecutionFailure(
                code: "stale_input",
                safeSummary: "An exact analysis input changed before publication. Nothing was published.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        } catch {
            throw try JobExecutionFailure(
                code: "analysis_pipeline_failed",
                safeSummary: "Local analysis failed without publishing partial intelligence.",
                retryable: true,
                privateDiagnostic: String(describing: error)
            )
        }
    }

    private func executePipeline(
        _ context: JobExecutionContext
    ) async throws -> JobExecutionResult {
        let plan = try AnalysisPipelineJobPlan.decode(from: context.job.inputPayload)
        guard context.job.jobType == jobType,
              context.job.meetingID == plan.meetingID,
              context.job.privacyRoute == .localOnly,
              context.job.dataClassification == plan.analysisRoute.request.dataClassification,
              context.job.inputRevisionIDs == plan.inputRevisionIDs,
              context.job.progress.totalUnitCount
                == UInt64(plan.eligibleSegmentRevisions.count),
              provider.route == plan.analysisRoute.route,
              provider.metadata.providerIdentifier == plan.analysisRoute.providerIdentifier
        else {
            throw AIProviderContractError.routeDenied(
                "The analysis executor, route decision, provider, and durable job metadata do not match."
            )
        }

        let source = try repository.analysisSourceBundle(
            meetingRevision: plan.meetingRevision,
            transcriptManifestID: plan.transcriptManifestID
        )
        let packages = try AnalysisPipelineJobPlan.requestPackages(from: source)
        let currentReferences = try AnalysisPipelineJobPlan.inputReferences(from: source)
        let packageDigest = try DiplomaticAnalysisPrompt.inputPackageDigest(
            requests: packages.map(\.request)
        )
        guard currentReferences == plan.inputRevisionIDs,
              packageDigest == plan.inputPackageDigest,
              source.transcriptReview.manifest.contentHash == plan.transcriptManifestHash,
              packages.map(\.request.transcriptRevision).sorted()
                == plan.eligibleSegmentRevisions
        else {
            throw JobContractError.invalidRequest(
                "The exact analysis source package changed after the job was planned."
            )
        }

        let isAvailable = await provider.isModelAvailable(
            localeIdentifier: plan.runtimeEvidence.localeIdentifier
        )
        guard isAvailable else {
            try? recordIncomplete(
                plan: plan,
                packages: packages,
                failedIndex: 0,
                reasonCode: "model_unavailable",
                modelAvailable: false
            )
            throw AIProviderContractError.modelUnavailable(
                "The approved local analysis model is currently unavailable."
            )
        }

        var units: [AnalysisUnitObjects] = []
        var entries: [AnalysisSegmentCoverage] = []
        var participantCache: [String: ParticipantV1] = [:]
        var organizationCache: [String: OrganizationV1] = [:]
        var issueCache: [String: IssueV1] = [:]

        for (index, package) in packages.enumerated() {
            try Task.checkCancellation()
            let candidate: AnalysisOutputCandidate
            do {
                candidate = try await provider.analyze(package.request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? recordIncomplete(
                    plan: plan,
                    packages: packages,
                    failedIndex: index,
                    reasonCode: failureCode(error),
                    modelAvailable: true
                )
                throw error
            }
            if candidate.substantive {
                let participantKey = [
                    package.resolved.speakerActor.revision.revisionID.canonicalString,
                    package.resolved.speakingCapacity.revision.revisionID.canonicalString
                ].joined(separator: ":")
                let organizationKey = package.resolved.representedActor.revision
                    .revisionID.canonicalString
                let issueKey = candidate.issueTitle ?? ""
                let unit = try AnalysisSemanticFactory.makeUnit(
                    candidate: candidate,
                    resolved: package.resolved,
                    provider: provider.metadata,
                    sharedParticipant: participantCache[participantKey],
                    sharedOrganization: organizationCache[organizationKey],
                    sharedIssue: issueCache[issueKey],
                    createdAt: plan.createdAt
                )
                participantCache[participantKey] = unit.participant
                if let organization = unit.organization {
                    organizationCache[organizationKey] = organization
                }
                issueCache[issueKey] = unit.issue
                units.append(unit)
                entries.append(
                    try AnalysisSegmentCoverage(
                        segmentRevision: package.request.transcriptRevision,
                        translationRevision: package.request.translationRevision,
                        speakerAssignmentRevision: package.request.speakerAssignmentRevision,
                        disposition: .substantive,
                        attemptCount: 1,
                        provider: provider.metadata,
                        evidenceRevisions: try unit.evidence.map(
                            AnalysisSemanticFactory.reference
                        ),
                        outputRevisions: try unit.outputReferences
                    )
                )
            } else {
                guard let confirmation = try AnalysisNonSubstantiveVerifier.confirmation(
                    for: package.request
                ) else {
                    try? recordIncomplete(
                        plan: plan,
                        packages: packages,
                        failedIndex: index,
                        reasonCode: "provider_output_invalid",
                        modelAvailable: true
                    )
                    throw AIProviderContractError.invalidResponse(
                        "Provider-only non-substantive output cannot omit meaningful source text."
                    )
                }
                entries.append(
                    try AnalysisSegmentCoverage(
                        segmentRevision: package.request.transcriptRevision,
                        translationRevision: package.request.translationRevision,
                        speakerAssignmentRevision: package.request.speakerAssignmentRevision,
                        disposition: .nonSubstantive,
                        attemptCount: 1,
                        provider: provider.metadata,
                        evidenceRevisions: package.resolved.speakerAssignment.revision
                            .evidenceRevisions,
                        safeReasonCode: "application_verified_non_semantic_marker",
                        omissionConfirmation: confirmation
                    )
                )
            }
            try await context.checkpoint(
                progress: JobProgress(
                    completedUnitCount: UInt64(index + 1),
                    totalUnitCount: UInt64(packages.count),
                    currentNode: "analysis-segment-\(index)"
                )
            )
        }

        let delegationCards = try AnalysisSemanticFactory.aggregateDelegationCards(
            units: units,
            meeting: source.meeting,
            provider: provider.metadata,
            createdAt: plan.createdAt
        )
        let cardAssignments = try Dictionary(
            uniqueKeysWithValues: delegationCards.flatMap { card in
                guard !card.positionRevisions.isEmpty else {
                    throw AnalysisCoverageError.invalidLedger(
                        "A delegation card has no source position."
                    )
                }
                let cardReference = try AnalysisSemanticFactory.reference(card)
                return card.positionRevisions.map { ($0, cardReference) }
            }
        )
        entries = try entries.map { entry in
            guard entry.disposition == .substantive,
                  let positionReference = entry.outputRevisions.first(where: {
                      $0.objectType == .position
                  }),
                  let cardReference = cardAssignments[positionReference]
            else { return entry }
            return try AnalysisSegmentCoverage(
                segmentRevision: entry.segmentRevision,
                translationRevision: entry.translationRevision,
                speakerAssignmentRevision: entry.speakerAssignmentRevision,
                disposition: entry.disposition,
                attemptCount: entry.attemptCount,
                provider: entry.provider,
                evidenceRevisions: entry.evidenceRevisions,
                outputRevisions: entry.outputRevisions + [cardReference],
                omissionConfirmation: entry.omissionConfirmation
            )
        }

        let evidence = unique(units.flatMap(\.evidence), by: \.revision.revisionID)
        let participants = unique(units.map(\.participant), by: \.revision.revisionID)
        let organizations = unique(units.compactMap(\.organization), by: \.revision.revisionID)
        let issues = unique(units.map(\.issue), by: \.revision.revisionID)
        let positions = unique(units.map(\.position), by: \.revision.revisionID)
        let commitments = unique(units.compactMap(\.commitment), by: \.revision.revisionID)
        let decisions = unique(units.compactMap(\.decision), by: \.revision.revisionID)
        let interventionCards = unique(
            units.map(\.interventionCard),
            by: \.revision.revisionID
        )
        let ledger = try AnalysisCoverageLedger(
            ledgerID: plan.ledgerID,
            meetingID: plan.meetingID,
            transcriptManifestID: plan.transcriptManifestID,
            transcriptManifestHash: plan.transcriptManifestHash,
            eligibleSegmentRevisions: plan.eligibleSegmentRevisions,
            analysisRoute: plan.analysisRoute,
            runtimeEvidence: plan.runtimeEvidence,
            promptModules: plan.promptModules,
            protectedRulesDigest: plan.protectedRulesDigest,
            outputSchemaVersion: plan.outputSchemaVersion,
            inputPackageDigest: plan.inputPackageDigest,
            fixtureProvenance: plan.fixtureProvenance,
            status: .published,
            segments: entries,
            createdAt: plan.createdAt
        )
        let publication = try AnalysisPublication(
            ledger: ledger,
            evidence: evidence,
            participants: participants,
            organizations: organizations,
            issues: issues,
            positions: positions,
            commitments: commitments,
            decisions: decisions,
            interventionCards: interventionCards,
            delegationPositionCards: delegationCards
        )
        try validateGraph(publication: publication, source: source)
        try repository.publishAnalysis(
            publication,
            validatingInputRevisions: plan.inputRevisionIDs
        )
        return try JobExecutionResult(
            outputRevisionIDs: (
                ledger.evidenceRevisionReferences + ledger.outputRevisionReferences
            ).sorted(),
            providerUsage: [
                try ProviderUsageMetadata(
                    provider: provider.metadata,
                    inputUnitCount: UInt64(packages.count),
                    outputUnitCount: UInt64(ledger.outputRevisionReferences.count)
                )
            ]
        )
    }

    private func recordIncomplete(
        plan: AnalysisPipelineJobPlan,
        packages: [(request: AnalysisRequest, resolved: AnalysisResolvedUnit)],
        failedIndex: Int,
        reasonCode: String,
        modelAvailable: Bool
    ) throws {
        let entries = try packages.enumerated().map { index, package in
            if index == failedIndex {
                return try AnalysisSegmentCoverage(
                    segmentRevision: package.request.transcriptRevision,
                    translationRevision: package.request.translationRevision,
                    speakerAssignmentRevision: package.request.speakerAssignmentRevision,
                    disposition: .failed,
                    attemptCount: 1,
                    provider: provider.metadata,
                    safeReasonCode: sanitizedReason(reasonCode)
                )
            }
            return try AnalysisSegmentCoverage(
                segmentRevision: package.request.transcriptRevision,
                translationRevision: package.request.translationRevision,
                speakerAssignmentRevision: package.request.speakerAssignmentRevision,
                disposition: .missing,
                attemptCount: 0
            )
        }
        let runtime = try AnalysisRuntimeEvidence(
            operatingSystemVersion: plan.runtimeEvidence.operatingSystemVersion,
            frameworkIdentifier: plan.runtimeEvidence.frameworkIdentifier,
            adapterVersion: plan.runtimeEvidence.adapterVersion,
            localeIdentifier: plan.runtimeEvidence.localeIdentifier,
            modelAvailable: modelAvailable,
            noOutboundMode: true
        )
        let ledger = try AnalysisCoverageLedger(
            meetingID: plan.meetingID,
            transcriptManifestID: plan.transcriptManifestID,
            transcriptManifestHash: plan.transcriptManifestHash,
            eligibleSegmentRevisions: plan.eligibleSegmentRevisions,
            analysisRoute: plan.analysisRoute,
            runtimeEvidence: runtime,
            promptModules: plan.promptModules,
            protectedRulesDigest: plan.protectedRulesDigest,
            outputSchemaVersion: plan.outputSchemaVersion,
            inputPackageDigest: plan.inputPackageDigest,
            fixtureProvenance: plan.fixtureProvenance,
            status: .incomplete,
            segments: entries,
            createdAt: plan.createdAt
        )
        try repository.recordIncompleteAnalysis(ledger)
    }

    private func validateGraph(
        publication: AnalysisPublication,
        source: AnalysisSourceBundle
    ) throws {
        var dependencies: [ResolvedDependencyClassification] = []
        dependencies.append(try ResolvedDependencyClassification(resolving: source.meeting))
        dependencies += try source.transcriptReview.transcriptSegments.map {
            try ResolvedDependencyClassification(resolving: $0)
        }
        dependencies += try source.transcriptReview.translations.map {
            try ResolvedDependencyClassification(resolving: $0)
        }
        dependencies += try source.sourceAssets.map {
            try ResolvedDependencyClassification(resolving: $0)
        }
        dependencies += try publication.evidence.map {
            try ResolvedDependencyClassification(resolving: $0)
        }
        try IntelligenceGraphValidation.validate(
            participants: publication.participants,
            organizations: publication.organizations,
            issues: publication.issues,
            positions: publication.positions,
            commitments: publication.commitments,
            decisions: publication.decisions,
            interventionCards: publication.interventionCards,
            delegationPositionCards: publication.delegationPositionCards,
            actors: source.actors,
            capacities: source.capacities,
            assignments: source.transcriptReview.speakerAssignments,
            additionalDependencies: dependencies
        )
    }

    private func unique<Value>(
        _ values: [Value],
        by keyPath: KeyPath<Value, RevisionID>
    ) -> [Value] {
        var seen: Set<RevisionID> = []
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }

    private func sanitizedReason(_ value: String) -> String {
        let allowed = value.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
                ? character : "_"
        }
        let result = String(allowed.prefix(96))
        return result.isEmpty ? "analysis_failed" : result
    }

    private func failureCode(_ error: Error) -> String {
        if let error = error as? AIProviderContractError { return failureCode(error) }
        if error is AnalysisCoverageError { return "coverage_invalid" }
        return "provider_output_invalid"
    }

    private func failureCode(_ error: AIProviderContractError) -> String {
        switch error {
        case .modelUnavailable: "model_unavailable"
        case .routeDenied: "route_denied"
        case .invalidRequest: "analysis_input_invalid"
        case .invalidResponse: "provider_output_invalid"
        case .secretUnavailable: "secret_unavailable"
        }
    }

    private func safeSummary(_ error: AIProviderContractError) -> String {
        switch error {
        case .modelUnavailable:
            "The local analysis model is unavailable. Existing local analysis remains reviewable."
        case .routeDenied:
            "The application policy router denied this analysis route."
        case .invalidRequest:
            "The exact analysis input package failed validation."
        case .invalidResponse:
            "The local model returned invalid structured analysis. Nothing was published."
        case .secretUnavailable:
            "A required secure local capability is unavailable."
        }
    }

    private func isRetryable(_ error: AIProviderContractError) -> Bool {
        switch error {
        case .modelUnavailable, .invalidResponse: true
        case .invalidRequest, .routeDenied, .secretUnavailable: false
        }
    }
}
