import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct TranscriptReviewPresentationTests {
    @Test
    func fullSemanticReferencesFailClosedAcrossEveryPresentationIndex()
        throws
    {
        let review = try makeReferenceMismatchReview()
        let presentation = TranscriptReviewPresentation(
            review: review
        )
        let first = try #require(
            review.transcriptSegments.first
        )
        let second = try #require(
            review.transcriptSegments.last
        )

        #expect(first.revision.revisionID == second.revision.revisionID)
        #expect(first.segmentID != second.segmentID)
        #expect(presentation.translation(for: first) == nil)
        #expect(presentation.translation(for: second) != nil)
        #expect(presentation.assignments(for: first).isEmpty)
        #expect(presentation.assignments(for: second).count == 1)
        #expect(presentation.coverage(for: first).isEmpty)
        #expect(presentation.coverage(for: second).count == 1)
        #expect(presentation.evidence(for: second).isEmpty)
        #expect(
            presentation.unresolvedEvidenceCount(for: second)
                == 1
        )
    }

    @Test
    func noSpeechProofProjectsExactMethodRangeAndVerifierVersion()
        throws
    {
        let review = try makeNoSpeechReview()
        let presentation = TranscriptReviewPresentation(
            review: review
        )
        let chunk = try #require(
            presentation.noSpeechChunks.first
        )
        let confirmation = try #require(
            chunk.noSpeechConfirmation
        )

        #expect(presentation.noSpeechChunks.count == 1)
        #expect(presentation.verifiedNoSpeechChunkCount == 1)
        #expect(presentation.unresolvedNoSpeechChunkCount == 0)
        #expect(
            confirmation.method == .exactDigitalSilence
        )
        #expect(confirmation.verifiedCoreRange == chunk.coreRange)
        #expect(
            confirmation.verifierVersion
                == TranscriptNoSpeechConfirmation.verifierVersion
        )

        let unresolved = TranscriptReviewPresentation(
            review: try makeNoSpeechReview(
                includesConfirmation: false
            )
        )
        #expect(unresolved.verifiedNoSpeechChunkCount == 0)
        #expect(unresolved.unresolvedNoSpeechChunkCount == 1)
    }

    @Test
    func completeThreeHundredSixtySegmentPresentationIndexesEveryLookup()
        throws
    {
        let review = try makeScaleReview(segmentCount: 360)
        let cache = TranscriptReviewPresentationCache(
            review: review
        )
        let presentation = cache.presentation

        #expect(presentation.segments.count == 360)
        #expect(
            cache.key
                == TranscriptReviewPresentationCacheKey(
                    review: review
                )
        )
        for (index, segment) in presentation.segments.enumerated() {
            #expect(
                presentation.translation(for: segment)?
                    .sourceSegmentRevision
                    == semanticReference(for: segment)
            )
            #expect(
                presentation.coverage(for: segment).map(\.index)
                    == [UInt32(index)]
            )
        }
    }

    @Test
    func logicalSelectionResolvesTheReplacementRevision() throws {
        let original = try makeScaleReview(segmentCount: 1)
        let prior = try #require(
            original.transcriptSegments.first
        )
        let replacement = try makeSegment(
            logicalID: prior.segmentID,
            revisionID: transcriptID(90_001, RevisionID.self),
            meetingID: prior.meetingID,
            sourceRevision: prior.sourceAssetRevision,
            timeRange: prior.timeRange,
            text: "Replacement revision"
        )
        let updated = TranscriptReviewBundle(
            manifest: original.manifest,
            transcriptSegments: [replacement],
            translations: []
        )

        #expect(
            TranscriptReviewPresentation(review: original)
                .segment(id: prior.segmentID)?
                .revision.revisionID
                == prior.revision.revisionID
        )
        #expect(
            TranscriptReviewPresentation(review: updated)
                .segment(id: prior.segmentID)?
                .revision.revisionID
                == replacement.revision.revisionID
        )
    }

    @Test
    func visibleAndFocusedCommandsShareEveryInteractionGate() {
        #expect(
            TranscriptCommandAvailability.canNavigate(
                hasDestination: true,
                isWorking: false,
                isInteractionLocked: false,
                isConfirmationPresented: false
            )
        )
        for state in [
            (true, false, false),
            (false, true, false),
            (false, false, true)
        ] {
            #expect(
                !TranscriptCommandAvailability.canNavigate(
                    hasDestination: true,
                    isWorking: state.0,
                    isInteractionLocked: state.1,
                    isConfirmationPresented: state.2
                )
            )
            #expect(
                !TranscriptCommandAvailability.canSave(
                    hasSavableDraft: true,
                    isWorking: state.0,
                    isInteractionLocked: state.1,
                    isConfirmationPresented: state.2
                )
            )
        }
        #expect(
            !TranscriptCommandAvailability.canNavigate(
                hasDestination: false,
                isWorking: false,
                isInteractionLocked: false,
                isConfirmationPresented: false
            )
        )
        #expect(
            !TranscriptCommandAvailability.canSave(
                hasSavableDraft: false,
                isWorking: false,
                isInteractionLocked: false,
                isConfirmationPresented: false
            )
        )
    }

    @Test
    func navigationIndexKeepsThreeHundredSixtySegmentsDeterministic()
    {
        let segmentIDs = (0 ..< 360).map {
            transcriptID($0, TranscriptSegmentID.self)
        }
        let index = TranscriptNavigationIndex(
            orderedSegmentIDs: segmentIDs
        )

        #expect(index.orderedSegmentIDs == segmentIDs)
        #expect(index.previous(to: segmentIDs.first) == nil)
        #expect(index.next(to: segmentIDs.first) == segmentIDs[1])
        #expect(
            index.previous(to: segmentIDs[180])
                == segmentIDs[179]
        )
        #expect(
            index.next(to: segmentIDs[180])
                == segmentIDs[181]
        )
        #expect(index.previous(to: segmentIDs.last) == segmentIDs[358])
        #expect(index.next(to: segmentIDs.last) == nil)
        #expect(index.previous(to: nil) == nil)
        #expect(index.next(to: nil) == nil)

        let duplicate = TranscriptNavigationIndex(
            orderedSegmentIDs: [
                segmentIDs[0],
                segmentIDs[1],
                segmentIDs[0]
            ]
        )
        #expect(duplicate.previous(to: segmentIDs[0]) == nil)
        #expect(duplicate.next(to: segmentIDs[0]) == nil)
    }

    @Test
    func focusedSaveNeverChoosesAnAmbiguousOrDifferentDraft() {
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .transcript,
                transcriptIsDirty: true,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == .transcript
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .translation,
                transcriptIsDirty: true,
                translationIsDirty: false,
                speakerIsDirty: false
            ) == nil
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: nil,
                transcriptIsDirty: false,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == .translation
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: nil,
                transcriptIsDirty: true,
                translationIsDirty: true,
                speakerIsDirty: false
            ) == nil
        )
        #expect(
            TranscriptDraftSaveResolution.resolve(
                focusedEditor: .speaker,
                transcriptIsDirty: false,
                translationIsDirty: false,
                speakerIsDirty: true
            ) == .speaker
        )
    }

    @Test @MainActor
    func commandNavigationReusesDirtyDraftNegotiation() {
        let segmentIDs = (0 ..< 3).map {
            transcriptID($0, TranscriptSegmentID.self)
        }
        let index = TranscriptNavigationIndex(
            orderedSegmentIDs: segmentIDs
        )
        let state = MediaReviewSceneState()
        state.transcript.select(segmentIDs[1])
        state.transcript.transcriptText = "Unsaved correction"

        state.requestTranscriptSelection(
            index.previous(to: segmentIDs[1])
        )

        #expect(
            state.transcript.selectedSegmentID
                == segmentIDs[1]
        )
        #expect(state.isNavigationConfirmationPresented)
        state.cancelPendingNavigation()

        state.requestTranscriptSelection(
            index.next(to: segmentIDs[1])
        )
        #expect(
            state.transcript.selectedSegmentID
                == segmentIDs[1]
        )
        #expect(state.isNavigationConfirmationPresented)
    }

    @Test
    func transcriptCommandsAndInspectorUseOnlyRealReviewContracts()
        throws
    {
        let app = try source(
            "Sources/MeetingBuddyApp/MeetingBuddyApp.swift"
        )
        let commands = try source(
            "Sources/MeetingBuddyFeatures/Views/BlueMinutesTranscriptCommands.swift"
        )
        let review = try source(
            "Sources/MeetingBuddyFeatures/Views/TranscriptReviewView.swift"
        )
        let inspector = try source(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/EvidenceInspectorPanel.swift"
        )
        let anchor = try source(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/EvidenceAnchor.swift"
        )
        let persistence = try source(
            "Sources/MeetingBuddyPersistence/SQLitePersistenceStore.swift"
        )

        #expect(app.contains("BlueMinutesTranscriptCommands()"))
        #expect(
            commands.contains(
                "@FocusedValue(\\.blueMinutesTranscriptCommandActions)"
            )
        )
        #expect(commands.contains("Previous Segment"))
        #expect(commands.contains("Next Segment"))
        #expect(commands.contains("Save Focused Transcript Draft"))
        #expect(commands.contains("Toggle Evidence Inspector"))
        #expect(
            review.contains(
                "sceneState.requestTranscriptSelection("
            )
        )
        #expect(!review.contains("transcript.select("))
        #expect(review.contains(".inspector(isPresented:"))
        #expect(review.contains("EvidenceInspectorPanel("))
        #expect(review.contains("Unsaved local draft"))
        #expect(review.contains("Saved"))
        #expect(review.contains("Coverage and route proof"))
        #expect(review.contains("Machine transcription"))
        #expect(review.contains("Human correction"))
        #expect(review.contains("presentationCache"))
        #expect(review.contains("TranscriptCommandAvailability"))
        #expect(!review.contains("Play Segment"))
        #expect(!review.contains("Open Source"))
        #expect(!review.contains("SQLitePersistenceStore"))
        #expect(inspector.contains("EvidenceRef.v1"))
        #expect(inspector.contains("Evidence excerpt"))
        #expect(inspector.contains("Evidence logical ID"))
        #expect(inspector.contains("Exact source logical ID"))
        #expect(inspector.contains("Created by"))
        #expect(inspector.contains("Classification"))
        #expect(inspector.contains("Verifier method"))
        #expect(inspector.contains("Verified frame range"))
        #expect(inspector.contains("Verifier version"))
        #expect(!inspector.contains("prefix(12)"))
        #expect(!anchor.contains("prefix(12)"))
        #expect(!inspector.contains("sourceURL"))
        #expect(
            persistence.contains(
                "let evidenceRefs = try evidenceReferences.map"
            )
        )
        #expect(
            persistence.contains(
                "throw TranscriptCoverageError.publicationConflict"
            )
        )
    }

    private func transcriptID<Tag>(
        _ index: Int,
        _ type: StableID<Tag>.Type
    ) -> StableID<Tag> {
        StableID<Tag>(
            UUID(
                uuidString: String(
                    format:
                        "5f000000-0000-0000-0000-%012d",
                    index + 1
                )
            )!
        )
    }

    private func makeReferenceMismatchReview() throws
        -> TranscriptReviewBundle
    {
        let sourceRevision = try SemanticRevisionReference(
            logicalID: transcriptID(70_000, SourceAssetID.self),
            revisionID: transcriptID(70_001, RevisionID.self)
        )
        let meetingID = transcriptID(70_002, MeetingID.self)
        let sharedRevisionID = transcriptID(
            70_003,
            RevisionID.self
        )
        let first = try makeSegment(
            logicalID: transcriptID(
                70_004,
                TranscriptSegmentID.self
            ),
            revisionID: sharedRevisionID,
            meetingID: meetingID,
            sourceRevision: sourceRevision,
            timeRange: MediaTimeRange(
                startMilliseconds: 0,
                endMilliseconds: 500
            ),
            text: "First logical segment"
        )
        let second = try makeSegment(
            logicalID: transcriptID(
                70_005,
                TranscriptSegmentID.self
            ),
            revisionID: sharedRevisionID,
            meetingID: meetingID,
            sourceRevision: sourceRevision,
            timeRange: MediaTimeRange(
                startMilliseconds: 500,
                endMilliseconds: 1_000
            ),
            text: "Second logical segment"
        )
        let secondReference = semanticReference(for: second)
        let translation = try makeTranslation(
            index: 70_006,
            meetingID: meetingID,
            sourceSegment: second,
            sourceReference: secondReference
        )
        let translationReference = try SemanticRevisionReference(
            logicalID: translation.translationID,
            revisionID: translation.revision.revisionID
        )
        let chunkPlan = try #require(
            CanonicalChunkPlanner.plan(
                totalFrameCount: 16_000
            ).first
        )
        let coverage = try TranscriptChunkCoverage(
            index: chunkPlan.index,
            coreRange: chunkPlan.coreRange,
            physicalRange: chunkPlan.physicalRange,
            disposition: .transcribed,
            attemptCount: 1,
            reviewedSegmentRevision: secondReference,
            translationRevision: translationReference
        )
        let evidenceRevisionID = transcriptID(
            70_010,
            RevisionID.self
        )
        let actualEvidenceID = transcriptID(
            70_011,
            EvidenceID.self
        )
        let mismatchedEvidenceReference =
            try SemanticRevisionReference(
                logicalID: transcriptID(
                    70_012,
                    EvidenceID.self
                ),
                revisionID: evidenceRevisionID
            )
        let evidence = try EvidenceRefV1(
            revision: RevisionEnvelope(
                logicalID: actualEvidenceID,
                revisionID: evidenceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: testInstant(70_010),
                createdBy: .application,
                inputRevisions: [secondReference],
                dataClassification: .internal
            ),
            location: .transcriptSegment(
                source: secondReference,
                textRange: nil
            ),
            excerpt: EvidenceExcerpt(
                text: second.text,
                language: LanguageTag("en"),
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(
                millionths: 900_000
            )
        )
        let actorReference = try SemanticRevisionReference(
            logicalID: transcriptID(70_013, ActorID.self),
            revisionID: transcriptID(70_014, RevisionID.self)
        )
        let capacityReference = try SemanticRevisionReference(
            logicalID: transcriptID(
                70_015,
                SpeakingCapacityID.self
            ),
            revisionID: transcriptID(70_016, RevisionID.self)
        )
        let assignment = try SpeakerAssignmentV1(
            revision: RevisionEnvelope(
                logicalID: transcriptID(
                    70_017,
                    SpeakerAssignmentID.self
                ),
                revisionID: transcriptID(
                    70_018,
                    RevisionID.self
                ),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: testInstant(70_018),
                createdBy: .application,
                inputRevisions: [
                    secondReference,
                    actorReference,
                    capacityReference
                ],
                evidenceRevisions: [
                    mismatchedEvidenceReference
                ],
                dataClassification: .internal
            ),
            meetingID: meetingID,
            transcriptSegmentRevisions: [secondReference],
            actorRevision: actorReference,
            speakingCapacityRevision: capacityReference,
            confidence: ConfidenceScore(
                millionths: 500_000
            ),
            certainty: .uncertain,
            assignmentSources: [.transcriptContext],
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        let manifest = try makeManifest(
            index: 70_020,
            meetingID: meetingID,
            sourceRevision: sourceRevision,
            canonicalFrameCount: 16_000,
            chunks: [coverage],
            includesTranslation: true
        )
        return TranscriptReviewBundle(
            manifest: manifest,
            transcriptSegments: [first, second],
            translations: [translation],
            speakerAssignments: [assignment],
            evidenceRefs: [evidence]
        )
    }

    private func makeNoSpeechReview(
        includesConfirmation: Bool = true
    ) throws
        -> TranscriptReviewBundle
    {
        let sourceRevision = try SemanticRevisionReference(
            logicalID: transcriptID(71_000, SourceAssetID.self),
            revisionID: transcriptID(71_001, RevisionID.self)
        )
        let plan = try #require(
            CanonicalChunkPlanner.plan(
                totalFrameCount: 16_000
            ).first
        )
        let chunk = try TranscriptChunkCoverage(
            index: plan.index,
            coreRange: plan.coreRange,
            physicalRange: plan.physicalRange,
            disposition: .noSpeech,
            attemptCount: 1,
            noSpeechConfirmation: includesConfirmation
                ? try TranscriptNoSpeechConfirmation(
                    verifiedCoreRange: plan.coreRange
                )
                : nil
        )
        let meetingID = transcriptID(71_002, MeetingID.self)
        return TranscriptReviewBundle(
            manifest: try makeManifest(
                index: 71_003,
                meetingID: meetingID,
                sourceRevision: sourceRevision,
                canonicalFrameCount: 16_000,
                chunks: [chunk],
                includesTranslation: false
            ),
            transcriptSegments: [],
            translations: []
        )
    }

    private func makeScaleReview(
        segmentCount: Int
    ) throws -> TranscriptReviewBundle {
        let sourceRevision = try SemanticRevisionReference(
            logicalID: transcriptID(72_000, SourceAssetID.self),
            revisionID: transcriptID(72_001, RevisionID.self)
        )
        let meetingID = transcriptID(72_002, MeetingID.self)
        let frameCount =
            CanonicalChunkPlanner.coreDurationFrames
            * UInt64(segmentCount)
        let plans = try CanonicalChunkPlanner.plan(
            totalFrameCount: frameCount
        )
        var segments: [TranscriptSegmentV1] = []
        var translations: [TranslationSegmentV1] = []
        var chunks: [TranscriptChunkCoverage] = []
        segments.reserveCapacity(segmentCount)
        translations.reserveCapacity(segmentCount)
        chunks.reserveCapacity(segmentCount)

        for (index, plan) in plans.enumerated() {
            let segment = try makeSegment(
                logicalID: transcriptID(
                    73_000 + index,
                    TranscriptSegmentID.self
                ),
                revisionID: transcriptID(
                    74_000 + index,
                    RevisionID.self
                ),
                meetingID: meetingID,
                sourceRevision: sourceRevision,
                timeRange: MediaTimeRange(
                    startMilliseconds: Int64(
                        plan.coreRange.startFrame / 16
                    ),
                    endMilliseconds: Int64(
                        plan.coreRange.endFrame / 16
                    )
                ),
                text: "Synthetic segment \(index)"
            )
            let segmentReference = semanticReference(
                for: segment
            )
            let translation = try makeTranslation(
                index: 75_000 + index,
                meetingID: meetingID,
                sourceSegment: segment,
                sourceReference: segmentReference
            )
            let translationReference =
                try SemanticRevisionReference(
                    logicalID: translation.translationID,
                    revisionID:
                        translation.revision.revisionID
                )
            segments.append(segment)
            translations.append(translation)
            chunks.append(
                try TranscriptChunkCoverage(
                    index: plan.index,
                    coreRange: plan.coreRange,
                    physicalRange: plan.physicalRange,
                    disposition: .transcribed,
                    attemptCount: 1,
                    reviewedSegmentRevision:
                        segmentReference,
                    translationRevision:
                        translationReference
                )
            )
        }
        return TranscriptReviewBundle(
            manifest: try makeManifest(
                index: 76_000,
                meetingID: meetingID,
                sourceRevision: sourceRevision,
                canonicalFrameCount: frameCount,
                chunks: chunks,
                includesTranslation: true
            ),
            transcriptSegments: segments,
            translations: translations
        )
    }

    private func makeSegment(
        logicalID: TranscriptSegmentID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        sourceRevision: SemanticRevisionReference,
        timeRange: MediaTimeRange,
        text: String
    ) throws -> TranscriptSegmentV1 {
        try TranscriptSegmentV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: testInstant(
                    Int64(timeRange.startMilliseconds)
                ),
                createdBy: .application,
                inputRevisions: [sourceRevision],
                sourceAssetRevisions: [sourceRevision],
                dataClassification: .internal
            ),
            meetingID: meetingID,
            sourceProvenance: .originalSpeakerAudio(
                sourceAssetRevision: sourceRevision
            ),
            timeRange: timeRange,
            detectedLanguage: LanguageTag("en"),
            text: text,
            confidence: ConfidenceScore(
                millionths: 900_000
            ),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    private func makeTranslation(
        index: Int,
        meetingID: MeetingID,
        sourceSegment: TranscriptSegmentV1,
        sourceReference: SemanticRevisionReference
    ) throws -> TranslationSegmentV1 {
        try TranslationSegmentV1(
            revision: RevisionEnvelope(
                logicalID: transcriptID(
                    index,
                    TranslationSegmentID.self
                ),
                revisionID: transcriptID(
                    index + 1_000,
                    RevisionID.self
                ),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: testInstant(Int64(index)),
                createdBy: .application,
                inputRevisions: [sourceReference],
                dataClassification: .internal
            ),
            meetingID: meetingID,
            sourceSegmentRevision: sourceReference,
            sourceLanguage: LanguageTag("en"),
            targetLanguage: LanguageTag("fr"),
            sourceTextHash:
                TranslationSegmentV1.calculateSourceTextHash(
                    sourceSegment.text
                ),
            translatedText: "Traduction \(index)",
            translationType: .humanTranslation,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(
                millionths: 900_000
            ),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    private func makeManifest(
        index: Int,
        meetingID: MeetingID,
        sourceRevision: SemanticRevisionReference,
        canonicalFrameCount: UInt64,
        chunks: [TranscriptChunkCoverage],
        includesTranslation: Bool
    ) throws -> TranscriptCoverageManifest {
        try TranscriptCoverageManifest(
            manifestID: transcriptID(
                index,
                TranscriptCoverageManifestID.self
            ),
            transcriptSetID: transcriptID(
                index + 1,
                TranscriptSetID.self
            ),
            meetingID: meetingID,
            canonicalSourceRevision: sourceRevision,
            canonicalFrameCount: canonicalFrameCount,
            transcriptionRoute: routeDecision(
                capability: .transcription
            ),
            translationRoute: includesTranslation
                ? routeDecision(capability: .translation)
                : nil,
            status: .published,
            chunks: chunks,
            createdAt: testInstant(Int64(index))
        )
    }

    private func routeDecision(
        capability: AIProcessingCapability
    ) throws -> ModelRouteDecision {
        try ModelPolicyRouter().decide(
            ModelRouteRequest(
                capability: capability,
                dataClassification: .internal,
                offlineMode: true,
                organizationAllowsExternalProcessing: false,
                deploymentEnvironment: .test,
                destination: .localDevice,
                retentionPolicy: .localWorkspaceOnly,
                dataCategories: capability == .transcription
                    ? [.canonicalAudio]
                    : [.transcriptText],
                visibleUserAuthorization: true,
                localModelAvailable: true
            )
        )
    }

    private func semanticReference(
        for segment: TranscriptSegmentV1
    ) -> SemanticRevisionReference {
        try! SemanticRevisionReference(
            logicalID: segment.segmentID,
            revisionID: segment.revision.revisionID
        )
    }

    private func testInstant(_ offset: Int64) -> UTCInstant {
        try! UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_000_000 + offset
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf:
                repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
