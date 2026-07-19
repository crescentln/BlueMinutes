import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum BriefingJobTypes {
    public static let pipeline = try! JobType("briefing-pipeline-v1")
}

public enum BriefingJobOperation: Codable, Hashable, Sendable {
    case initial
    case regenerate(
        sectionType: BriefingSectionType,
        expectedSectionRevisionID: RevisionID,
        graphRevision: SemanticRevisionReference,
        sectionRevisions: [SemanticRevisionReference],
        validationReportRevision: SemanticRevisionReference,
        finalBriefingRevision: SemanticRevisionReference,
        briefingLedgerID: BriefingCoverageLedgerID
    )
}

public struct BriefingPipelineJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.briefing-pipeline"
    public static let inputFormatVersion: UInt32 = 1

    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let template: MeetingTemplateV1
    public let transcriptManifestID: TranscriptCoverageManifestID
    public let transcriptManifestHash: ContentDigest
    public let analysisLedgerID: AnalysisCoverageLedgerID
    public let analysisLedgerHash: ContentDigest
    public let eligibleSegmentRevisions: [SemanticRevisionReference]
    public let sectionRoute: ModelRouteDecision
    public let operation: BriefingJobOperation
    public let createdAt: UTCInstant
    public let inputRevisionIDs: [SemanticRevisionReference]

    public init(
        source: BriefingSourceBundle,
        sectionRoute: ModelRouteDecision,
        operation: BriefingJobOperation = .initial,
        createdAt: UTCInstant
    ) throws {
        let meetingReference = try Self.reference(source.meeting)
        let references = try Self.inputReferences(source: source, operation: operation)
        meetingID = source.meeting.meetingID
        meetingRevision = meetingReference
        template = source.template
        transcriptManifestID = source.analysis.ledger.transcriptManifestID
        transcriptManifestHash = source.analysis.ledger.transcriptManifestHash
        analysisLedgerID = source.analysis.ledger.ledgerID
        analysisLedgerHash = source.analysis.ledger.contentHash
        eligibleSegmentRevisions = source.analysis.ledger.eligibleSegmentRevisions
        self.sectionRoute = sectionRoute
        self.operation = operation
        self.createdAt = createdAt
        inputRevisionIDs = references
        try validate()
    }

    private init(validating decoded: Self) throws {
        self = decoded
        try validate()
    }

    public func validate() throws {
        let categories = Set(sectionRoute.request.dataCategories)
        guard meetingRevision.objectType == .meetingProfile,
              meetingRevision.logicalID.canonicalString == meetingID.canonicalString,
              template.revision.lifecycleStatus == .published,
              template.revision.validationState == .valid,
              !eligibleSegmentRevisions.isEmpty,
              eligibleSegmentRevisions.allSatisfy({ $0.objectType == .transcriptSegment }),
              Set(eligibleSegmentRevisions).count == eligibleSegmentRevisions.count,
              sectionRoute.request.capability == .analysis,
              sectionRoute.route == .appleOnDevice || sectionRoute.route == .deterministicTest,
              sectionRoute.route.privacyRoute == .localOnly,
              sectionRoute.providerIdentifier != nil,
              categories == [.validatedIntelligenceClaims, .evidenceIdentifiers],
              sectionRoute.request.visibleUserAuthorization,
              sectionRoute.request.localModelAvailable,
              sectionRoute.request.retentionPolicy == .noProviderRetention,
              Set(inputRevisionIDs).count == inputRevisionIDs.count,
              inputRevisionIDs.contains(meetingRevision),
              Set(eligibleSegmentRevisions).isSubset(of: Set(inputRevisionIDs))
        else {
            throw AIProviderContractError.invalidRequest(
                "The persisted briefing job failed its exact local route, template, or source contract."
            )
        }
        switch operation {
        case .initial:
            break
        case let .regenerate(
            sectionType,
            expectedSectionRevisionID,
            graphRevision,
            sectionRevisions,
            validationReportRevision,
            finalBriefingRevision,
            _
        ):
            guard sectionType.isKnown,
                  graphRevision.objectType == .issuePositionGraph,
                  sectionRevisions.count == 3,
                  sectionRevisions.allSatisfy({ $0.objectType == .briefingSection }),
                  sectionRevisions.contains(where: {
                      $0.revisionID == expectedSectionRevisionID
                  }),
                  validationReportRevision.objectType == .validationReport,
                  finalBriefingRevision.objectType == .finalBriefing,
                  inputRevisionIDs.contains(graphRevision),
                  Set(sectionRevisions.filter({
                      $0.revisionID != expectedSectionRevisionID
                  })).isSubset(of: Set(inputRevisionIDs)),
                  !inputRevisionIDs.contains(where: {
                      $0.revisionID == expectedSectionRevisionID
                          || $0 == validationReportRevision
                          || $0 == finalBriefingRevision
                  })
            else {
                throw AIProviderContractError.invalidRequest(
                    "A regeneration plan lacks the exact current briefing chain."
                )
            }
        }
    }

    public func jobInputPayload() throws -> JobInputPayload {
        try validate()
        return try JobInputPayload(
            formatIdentifier: Self.inputFormatIdentifier,
            formatVersion: Self.inputFormatVersion,
            payload: CanonicalJSON.encode(self)
        )
    }

    public static func decode(from input: JobInputPayload?) throws -> Self {
        guard let input,
              input.formatIdentifier == inputFormatIdentifier,
              input.formatVersion == inputFormatVersion
        else {
            throw AIProviderContractError.invalidRequest(
                "The briefing job payload is missing or unsupported."
            )
        }
        do {
            return try Self(validating: JSONDecoder().decode(Self.self, from: input.payload))
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError.invalidRequest(
                "The briefing job payload could not be decoded."
            )
        }
    }

    public static func inputReferences(
        source: BriefingSourceBundle,
        operation: BriefingJobOperation
    ) throws -> [SemanticRevisionReference] {
        var references = [try reference(source.meeting)]
        references += try source.transcriptReview.transcriptSegments.map(reference)
        references += try source.transcriptReview.translations.map(reference)
        references += try source.transcriptReview.speakerAssignments.map(reference)
        references += try source.analysis.evidence.map(reference)
        references += try source.analysis.participants.map(reference)
        references += try source.analysis.organizations.map(reference)
        references += try source.analysis.issues.map(reference)
        references += try source.analysis.positions.map(reference)
        references += try source.analysis.commitments.map(reference)
        references += try source.analysis.decisions.map(reference)
        references += try source.analysis.interventionCards.map(reference)
        references += try source.analysis.delegationPositionCards.map(reference)
        if case let .regenerate(
            _, expectedSectionRevisionID, graphRevision, sectionRevisions,
            _, _, _
        ) = operation {
            // The target section, validation report and final briefing are
            // exact compare-and-swap preconditions persisted in `operation`.
            // They are intentionally excluded from the Task Manager's
            // post-success current-input check because this transaction is
            // expected to supersede them atomically.
            references += [graphRevision]
                + sectionRevisions.filter {
                    $0.revisionID != expectedSectionRevisionID
                }
        }
        return Array(Set(references)).sorted()
    }

    private static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }
}

public struct BriefingPipelineJobFactory: Sendable {
    public init() {}

    public func request(
        plan: BriefingPipelineJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester,
        maximumRetryCount: UInt32 = 2
    ) throws -> JobRequest {
        try plan.validate()
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }
            .joined()
        let totalUnits: UInt64 = switch plan.operation {
        case .initial: 3
        case .regenerate: 1
        }
        return try JobRequest(
            jobID: jobID,
            jobType: BriefingJobTypes.pipeline,
            meetingID: plan.meetingID,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            inputRevisionIDs: plan.inputRevisionIDs,
            privacyRoute: .localOnly,
            dataClassification: plan.sectionRoute.request.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .restartOnly,
            maximumRetryCount: maximumRetryCount,
            totalUnitCount: totalUnits,
            diskBudgetBytes: 4 * 1_024 * 1_024
        )
    }
}
