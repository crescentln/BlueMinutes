import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct AnalysisReviewPresentationTests {
    @Test
    func exactEvidenceResolutionUsesTheFullSemanticReference()
        throws
    {
        let sourceReference = try analysisReference(
            analysisID(1, TranscriptSegmentID.self),
            analysisID(2, RevisionID.self)
        )
        let evidenceRevisionID = analysisID(
            3,
            RevisionID.self
        )
        let evidence = try makeAnalysisEvidence(
            logicalID: analysisID(4, EvidenceID.self),
            revisionID: evidenceRevisionID,
            sourceReference: sourceReference
        )
        let exactReference = try analysisReference(
            evidence.evidenceID,
            evidence.revision.revisionID
        )
        let mismatchedReference = try analysisReference(
            analysisID(5, EvidenceID.self),
            evidenceRevisionID
        )
        let exactPosition = try makeAnalysisPosition(
            logicalID: analysisID(6, PositionID.self),
            revisionID: analysisID(7, RevisionID.self),
            evidenceReference: exactReference
        )
        let mismatchedPosition = try makeAnalysisPosition(
            logicalID: analysisID(8, PositionID.self),
            revisionID: analysisID(9, RevisionID.self),
            evidenceReference: mismatchedReference
        )

        let exact = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [exactPosition],
                evidence: [evidence]
            )
        )
        #expect(
            exact.evidence(for: exactPosition.statement)
                .map(\.evidenceID) == [evidence.evidenceID]
        )
        #expect(
            exact.unresolvedEvidenceCount(
                for: exactPosition.statement
            ) == 0
        )

        let mismatched = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [mismatchedPosition],
                evidence: [evidence]
            )
        )
        #expect(
            mismatched.evidence(
                for: mismatchedPosition.statement
            ).isEmpty
        )
        #expect(
            mismatched.unresolvedEvidenceCount(
                for: mismatchedPosition.statement
            ) == 1
        )
    }

    @Test
    func duplicateEvidenceRevisionFailsClosed() throws {
        let sourceReference = try analysisReference(
            analysisID(10, TranscriptSegmentID.self),
            analysisID(11, RevisionID.self)
        )
        let evidence = try makeAnalysisEvidence(
            logicalID: analysisID(12, EvidenceID.self),
            revisionID: analysisID(13, RevisionID.self),
            sourceReference: sourceReference
        )
        let evidenceReference = try analysisReference(
            evidence.evidenceID,
            evidence.revision.revisionID
        )
        let position = try makeAnalysisPosition(
            logicalID: analysisID(14, PositionID.self),
            revisionID: analysisID(15, RevisionID.self),
            evidenceReference: evidenceReference
        )
        let presentation = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [position],
                evidence: [evidence, evidence]
            )
        )

        #expect(
            presentation.evidence(for: position.statement)
                .isEmpty
        )
        #expect(
            presentation.unresolvedEvidenceCount(
                for: position.statement
            ) == 1
        )
        #expect(
            presentation.evidence(
                for: evidenceReference
            ) == nil
        )
    }

    @Test
    func multipleRevisionsForOneEvidenceIDFailClosed()
        throws
    {
        let sourceReference = try analysisReference(
            analysisID(50, TranscriptSegmentID.self),
            analysisID(51, RevisionID.self)
        )
        let evidenceID = analysisID(52, EvidenceID.self)
        let prior = try makeAnalysisEvidence(
            logicalID: evidenceID,
            revisionID: analysisID(53, RevisionID.self),
            sourceReference: sourceReference
        )
        let replacement = try makeAnalysisEvidence(
            logicalID: evidenceID,
            revisionID: analysisID(54, RevisionID.self),
            sourceReference: sourceReference
        )
        let priorReference = try analysisReference(
            evidenceID,
            prior.revision.revisionID
        )
        let position = try makeAnalysisPosition(
            logicalID: analysisID(55, PositionID.self),
            revisionID: analysisID(56, RevisionID.self),
            evidenceReference: priorReference
        )
        let presentation = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [position],
                evidence: [prior, replacement]
            )
        )

        #expect(
            presentation.evidence(for: priorReference) == nil
        )
        #expect(
            presentation.unresolvedEvidenceCount(
                for: position.statement
            ) == 1
        )
    }

    @Test
    func representedEntityNameRequiresTheExactRevision()
        throws
    {
        let organization = try makeAnalysisOrganization(
            logicalID: analysisID(
                16,
                OrganizationID.self
            ),
            revisionID: analysisID(
                17,
                RevisionID.self
            )
        )
        let exactReference = try analysisReference(
            organization.organizationID,
            organization.revision.revisionID
        )
        let mismatchedReference = try analysisReference(
            organization.organizationID,
            analysisID(18, RevisionID.self)
        )
        let presentation = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [],
                organizations: [organization]
            )
        )

        #expect(
            presentation.representedName(
                for: exactReference
            ) == organization.displayName
        )
        #expect(
            presentation.representedName(
                for: mismatchedReference
            ) == nil
        )
    }

    @Test
    func logicalPositionSelectionResolvesAReplacementRevision()
        throws
    {
        let evidenceReference = try analysisReference(
            analysisID(20, EvidenceID.self),
            analysisID(21, RevisionID.self)
        )
        let positionID = analysisID(22, PositionID.self)
        let original = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(23, RevisionID.self),
            evidenceReference: evidenceReference,
            statement: "Original published meaning"
        )
        let replacement = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(24, RevisionID.self),
            evidenceReference: evidenceReference,
            statement: "Replacement published meaning"
        )
        let originalReview = try makeAnalysisReview(
            positions: [original]
        )
        let replacementReview = try makeAnalysisReview(
            positions: [replacement]
        )

        #expect(
            AnalysisReviewPresentation(review: originalReview)
                .position(id: positionID)?
                .revision.revisionID
                == original.revision.revisionID
        )
        #expect(
            AnalysisReviewPresentation(
                review: replacementReview
            )
            .position(id: positionID)?
            .revision.revisionID
                == replacement.revision.revisionID
        )
        #expect(
            AnalysisReviewPresentationCacheKey(
                review: originalReview
            )
                != AnalysisReviewPresentationCacheKey(
                    review: replacementReview
                )
        )
    }

    @Test @MainActor
    func cleanAndStaleAnalysisDraftsCannotCreateSaveOperations()
        throws
    {
        let evidenceReference = try analysisReference(
            analysisID(60, EvidenceID.self),
            analysisID(61, RevisionID.self)
        )
        let positionID = analysisID(62, PositionID.self)
        let original = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(63, RevisionID.self),
            evidenceReference: evidenceReference,
            statement: "Original published meaning"
        )
        let replacement = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(64, RevisionID.self),
            evidenceReference: evidenceReference,
            statement: "Replacement published meaning"
        )
        let state = MediaReviewSceneState()

        state.analysis.reconcile(
            with: try makeAnalysisReview(
                positions: [original]
            )
        )

        #expect(!state.analysis.isDirty)
        #expect(state.analysis.isSourceRevisionCurrent)
        #expect(state.beginDirectAnalysisSave() == nil)
        #expect(state.pendingSaveRequest == nil)

        state.analysis.statement = "Unpublished local correction"
        #expect(state.analysis.isDirty)
        #expect(state.analysis.isSourceRevisionCurrent)

        state.analysis.reconcile(
            with: try makeAnalysisReview(
                positions: [replacement]
            )
        )

        #expect(state.analysis.isDirty)
        #expect(!state.analysis.isSourceRevisionCurrent)
        #expect(state.beginDirectAnalysisSave() == nil)
        #expect(state.pendingSaveRequest == nil)
    }

    @Test
    func duplicateLogicalPositionSelectionFailsClosed()
        throws
    {
        let evidenceReference = try analysisReference(
            analysisID(30, EvidenceID.self),
            analysisID(31, RevisionID.self)
        )
        let positionID = analysisID(32, PositionID.self)
        let first = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(33, RevisionID.self),
            evidenceReference: evidenceReference
        )
        let second = try makeAnalysisPosition(
            logicalID: positionID,
            revisionID: analysisID(34, RevisionID.self),
            evidenceReference: evidenceReference
        )
        let presentation = AnalysisReviewPresentation(
            review: try makeAnalysisReview(
                positions: [first, second]
            )
        )

        #expect(presentation.positions.count == 2)
        #expect(presentation.position(id: positionID) == nil)
    }

    @Test
    func confidenceSupportAndLedgerConfirmationStayIndependent()
        throws
    {
        let evidenceReference = try analysisReference(
            analysisID(40, EvidenceID.self),
            analysisID(41, RevisionID.self)
        )
        let position = try makeAnalysisPosition(
            logicalID: analysisID(42, PositionID.self),
            revisionID: analysisID(43, RevisionID.self),
            evidenceReference: evidenceReference,
            confidence: 120_000
        )
        let review = try makeAnalysisReview(
            positions: [position]
        )

        #expect(
            position.statement.supportStatus == .supported
        )
        #expect(
            position.statement.confidence.millionths
                == 120_000
        )
        #expect(!position.userConfirmed)
        #expect(!review.isHumanConfirmed)
    }

    @Test
    func analysisSectionEmptyStatesTrackBothCardCollectionsIndependently() {
        let empty =
            AnalysisReviewSectionState(
                delegationPositionCount: 0,
                interventionCount: 0
            )
        #expect(
            empty
                .showsDelegationPositionEmptyState
        )
        #expect(
            empty
                .showsInterventionEmptyState
        )

        let populated =
            AnalysisReviewSectionState(
                delegationPositionCount: 1,
                interventionCount: 1
            )
        #expect(
            !populated
                .showsDelegationPositionEmptyState
        )
        #expect(
            !populated
                .showsInterventionEmptyState
        )

        let interventionOnly =
            AnalysisReviewSectionState(
                delegationPositionCount: 0,
                interventionCount: 1
            )
        #expect(
            interventionOnly
                .showsDelegationPositionEmptyState
        )
        #expect(
            !interventionOnly
                .showsInterventionEmptyState
        )

        let delegationOnly =
            AnalysisReviewSectionState(
                delegationPositionCount: 1,
                interventionCount: 0
            )
        #expect(
            !delegationOnly
                .showsDelegationPositionEmptyState
        )
        #expect(
            delegationOnly
                .showsInterventionEmptyState
        )
    }

    @Test
    func analysisInspectorUsesApplicationOwnedProjectionOnly()
        throws
    {
        let viewSource = try analysisSource(
            "Sources/MeetingBuddyFeatures/Views/AnalysisReviewView.swift"
        )
        let inspectorSource = try analysisSource(
            "Sources/MeetingBuddyFeatures/Views/AnalysisEvidenceInspectorPanel.swift"
        )
        let presentationSource = try analysisSource(
            "Sources/MeetingBuddyFeatures/Models/AnalysisReviewPresentation.swift"
        )
        let sharedEvidenceSource = try analysisSource(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/EvidenceInspectorPanel.swift"
        )

        #expect(viewSource.contains(".inspector("))
        #expect(
            viewSource.contains(
                "No delegation-position cards"
            )
        )
        #expect(
            viewSource.contains(
                "No intervention cards"
            )
        )
        #expect(
            viewSource.contains(
                "review.delegationPositionCards"
            )
        )
        #expect(
            viewSource.contains(
                "review.interventionCards"
            )
        )
        #expect(
            viewSource.contains(
                "@State private var inspectorIsPresented = false"
            )
        )
        #expect(
            viewSource.contains(
                "AnalysisReviewPresentationCacheKey"
            )
        )
        #expect(
            viewSource.contains(
                "evidenceSelection = nil"
            )
        )
        #expect(
            viewSource.contains(
                "inspectorIsPresented = false"
            )
        )
        #expect(
            inspectorSource.contains(
                "Whole-ledger human confirmation"
            )
        )
        #expect(
            inspectorSource.contains(
                "does not grant per-claim confirmation authority"
            )
        )
        #expect(
            sharedEvidenceSource.contains(
                "struct EvidenceRefDetailsView"
            )
        )
        #expect(
            presentationSource.contains(
                "[SemanticRevisionReference: EvidenceRefV1]"
            )
        )
        #expect(!viewSource.contains("SQLite"))
        #expect(!inspectorSource.contains("SQLite"))
        #expect(!viewSource.contains("@AppStorage"))
        #expect(!viewSource.contains("@SceneStorage"))
        #expect(!inspectorSource.contains("prefix("))
    }
}

private func makeAnalysisReview(
    positions: [PositionV1],
    evidence: [EvidenceRefV1] = [],
    organizations: [OrganizationV1] = []
) throws -> AnalysisReviewBundle {
    AnalysisReviewBundle(
        ledger: try makeAnalysisLedger(),
        evidence: evidence,
        participants: [],
        organizations: organizations,
        issues: [],
        positions: positions,
        commitments: [],
        decisions: [],
        interventionCards: [],
        delegationPositionCards: []
    )
}

private func makeAnalysisOrganization(
    logicalID: OrganizationID,
    revisionID: RevisionID
) throws -> OrganizationV1 {
    let actorReference = try analysisReference(
        analysisID(190, ActorID.self),
        analysisID(191, RevisionID.self)
    )
    return try OrganizationV1(
        revision: RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: analysisInstant(192),
            createdBy: .application,
            inputRevisions: [actorReference],
            dataClassification: .internal
        ),
        actorRevision: actorReference,
        kind: .internationalOrganization,
        displayName: "Synthetic Exact Organization",
        confidence: ConfidenceScore(
            millionths: 880_000
        ),
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}

private func makeAnalysisLedger() throws
    -> AnalysisCoverageLedger
{
    let meetingID = analysisID(100, MeetingID.self)
    let transcriptReference = try analysisReference(
        analysisID(101, TranscriptSegmentID.self),
        analysisID(102, RevisionID.self)
    )
    let request = try ModelRouteRequest(
        capability: .analysis,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .test,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [
            .transcriptText,
            .speakerContext,
            .evidenceIdentifiers
        ],
        visibleUserAuthorization: true,
        localModelAvailable: false
    )
    return try AnalysisCoverageLedger(
        ledgerID: analysisID(
            103,
            AnalysisCoverageLedgerID.self
        ),
        meetingID: meetingID,
        transcriptManifestID: analysisID(
            104,
            TranscriptCoverageManifestID.self
        ),
        transcriptManifestHash: try ContentDigest.sha256(
            ofUTF8Text: "analysis-presentation-manifest"
        ),
        eligibleSegmentRevisions: [transcriptReference],
        analysisRoute: ModelPolicyRouter().decide(request),
        runtimeEvidence: AnalysisRuntimeEvidence(
            operatingSystemVersion: "synthetic-test-host",
            frameworkIdentifier:
                "meetingbuddy.synthetic.analysis.presentation",
            adapterVersion: "analysis-presentation-v1",
            localeIdentifier: "en",
            modelAvailable: false,
            noOutboundMode: true
        ),
        promptModules: [
            VersionedComponent(
                identifier:
                    "analysis-presentation-fixture",
                version: "1.0.0"
            )
        ],
        protectedRulesDigest: try ContentDigest.sha256(
            ofUTF8Text:
                "analysis-presentation-protected-rules"
        ),
        inputPackageDigest: try ContentDigest.sha256(
            ofUTF8Text: "analysis-presentation-input"
        ),
        status: .incomplete,
        segments: [
            AnalysisSegmentCoverage(
                segmentRevision: transcriptReference,
                disposition: .missing,
                attemptCount: 0
            )
        ],
        createdAt: analysisInstant(105)
    )
}

private func makeAnalysisEvidence(
    logicalID: EvidenceID,
    revisionID: RevisionID,
    sourceReference: SemanticRevisionReference
) throws -> EvidenceRefV1 {
    try EvidenceRefV1(
        revision: RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: analysisInstant(200),
            createdBy: .application,
            inputRevisions: [sourceReference],
            dataClassification: .internal
        ),
        location: .transcriptSegment(
            source: sourceReference,
            textRange: nil
        ),
        excerpt: EvidenceExcerpt(
            text: "Synthetic bounded analysis evidence.",
            language: LanguageTag("en"),
            translationStatus: .sourceOnly
        ),
        confidence: ConfidenceScore(
            millionths: 900_000
        )
    )
}

private func makeAnalysisPosition(
    logicalID: PositionID,
    revisionID: RevisionID,
    evidenceReference: SemanticRevisionReference,
    statement: String = "Synthetic delegation position",
    confidence: UInt32 = 900_000
) throws -> PositionV1 {
    let meetingID = analysisID(300, MeetingID.self)
    let meetingReference = try analysisReference(
        meetingID,
        analysisID(301, RevisionID.self)
    )
    let actorReference = try analysisReference(
        analysisID(302, ActorID.self),
        analysisID(303, RevisionID.self)
    )
    let organizationReference = try analysisReference(
        analysisID(304, OrganizationID.self),
        analysisID(305, RevisionID.self)
    )
    let capacityReference = try analysisReference(
        analysisID(306, SpeakingCapacityID.self),
        analysisID(307, RevisionID.self)
    )
    let issueReference = try analysisReference(
        analysisID(308, IssueID.self),
        analysisID(309, RevisionID.self)
    )
    return try PositionV1(
        revision: RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: analysisInstant(310),
            createdBy: .application,
            inputRevisions: [
                meetingReference,
                actorReference,
                organizationReference,
                capacityReference,
                issueReference
            ],
            evidenceRevisions: [evidenceReference],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        actorRevision: actorReference,
        representedEntityRevision: organizationReference,
        speakingCapacityRevision: capacityReference,
        issueRevision: issueReference,
        positionType: .supports,
        statement: EvidenceLinkedClaim(
            text: statement,
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidenceReference],
            confidence: ConfidenceScore(
                millionths: confidence
            )
        ),
        comparisonState: .unknown,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}

private func analysisReference<
    Tag: LogicalObjectIDScope
>(
    _ logicalID: StableID<Tag>,
    _ revisionID: RevisionID
) throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: logicalID,
        revisionID: revisionID
    )
}

private func analysisID<Tag>(
    _ value: Int,
    _: StableID<Tag>.Type
) -> StableID<Tag> {
    let suffix = String(format: "%012x", value)
    return StableID<Tag>(
        UUID(
            uuidString:
                "00000000-0000-0000-0000-\(suffix)"
        )!
    )
}

private func analysisInstant(_ value: Int) -> UTCInstant {
    try! UTCInstant(
        millisecondsSinceUnixEpoch:
            1_950_000_000_000 + Int64(value)
    )
}

private func analysisSource(
    _ relativePath: String
) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf:
            repositoryRoot.appendingPathComponent(
                relativePath
            ),
        encoding: .utf8
    )
}
