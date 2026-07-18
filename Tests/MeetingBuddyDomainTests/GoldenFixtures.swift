import Foundation
@testable import MeetingBuddyDomain

enum GoldenFixtureProvenanceKind: String, Sendable {
    case projectSynthetic = "project_synthetic"
}

enum GoldenFixtureLicensingStatus: String, Sendable {
    case syntheticNoThirdPartyMaterial = "synthetic_original_no_third_party_material"
}

enum GoldenRepositoryReuseTerms: String, Sendable {
    case unspecified
}

enum GoldenHumanReviewStatus: String, Sendable {
    case notPerformed = "not_performed"
}

enum GoldenObservationBasis: String, Sendable {
    case directSourceText = "direct_source_text"
    case directTextualDifference = "direct_textual_difference"
}

enum GoldenForbiddenClaimCode: String, Sendable {
    case fabricatedOpposition = "fabricated_opposition"
    case formalGroupAlignment = "formal_group_alignment"
    case confirmedPolicyChange = "confirmed_policy_change"
    case nationalityEqualsRepresentation = "nationality_equals_representation"
    case unconditionalSupport = "unconditional_support"
    case droppedQualification = "dropped_qualification"
    case confirmedSpeakerIdentity = "confirmed_speaker_identity"
    case inferredNationalPosition = "inferred_national_position"
    case inferredSpeakingCapacity = "inferred_speaking_capacity"
    case silenceAsAlignment = "silence_as_alignment"
    case interpretationAsOriginalVerbatim = "interpretation_as_original_verbatim"
    case translationAsSourceText = "translation_as_source_text"
    case interpreterOmissionAsSpeakerOmission = "interpreter_omission_as_speaker_omission"
    case realOfficialStatement = "real_official_statement"
    case preparedTextDeliveredVerbatim = "prepared_text_delivered_verbatim"
    case realWorldPositionAttribution = "real_world_position_attribution"
}

struct GoldenExpectedObservation: Sendable {
    let code: String
    let basis: GoldenObservationBasis
    let evidenceRevisionIDs: [RevisionID]
}

struct GoldenObjectCount: Sendable {
    let objectType: SemanticObjectType
    let count: Int
}

struct GoldenFixtureManifest: Sendable {
    let testCaseID: String
    let testCaseVersion: String
    let title: String
    let sourceProvenance: GoldenFixtureProvenanceKind
    let licensingStatus: GoldenFixtureLicensingStatus
    let spdxLicenseIdentifier: String?
    let repositoryReuseTerms: GoldenRepositoryReuseTerms
    let externalSources: [String]
    let containsRealMeetingContent: Bool
    let containsPersonalData: Bool
    let containsMediaBytes: Bool
    let acousticGroundTruth: Bool
    let humanDiplomaticReviewStatus: GoldenHumanReviewStatus
    let materialScope: String
    let expectedSemanticObjectCounts: [GoldenObjectCount]
    let expectedObservations: [GoldenExpectedObservation]
    let expectedReservations: [GoldenExpectedObservation]
    let forbiddenClaims: [GoldenForbiddenClaimCode]
    let idealBriefingSectionsStatus: String
    let knownFailurePatterns: [String]
    let scoringRubricVersion: String
}

struct GoldenFixtureGraph: Sendable {
    let meeting: MeetingProfileV1
    let sourceAssets: [SourceAssetV1]
    let transcripts: [TranscriptSegmentV1]
    let translations: [TranslationSegmentV1]
    let actors: [ActorV1]
    let capacities: [SpeakingCapacityV1]
    let assignments: [SpeakerAssignmentV1]
    let evidence: [EvidenceRefV1]
}

struct GoldenFixture: Sendable {
    let manifest: GoldenFixtureManifest
    let graph: GoldenFixtureGraph
}

enum GoldenFixtureCatalog {
    static func all() throws -> [GoldenFixture] {
        try [
            ordinaryDelegation(),
            reservationOrQualification(),
            uncertainSpeaker(),
            interpretationVersusOriginal(),
            preparedChinaStatementVersusDelivered()
        ]
    }

    private static func ordinaryDelegation() throws -> GoldenFixture {
        let builder = GoldenBuilder(base: 1_000)
        let source = try builder.audioSource(offset: 10, language: "en", kind: .originalSpeakerAudio)
        let chairText = "I give the floor to the representative of the State of Example."
        let interventionText = "We support the proposed review calendar and request publication of the implementation dates."
        let chair = try builder.transcript(offset: 20, source: source, text: chairText, language: "en", start: 0, end: 2_000)
        let intervention = try builder.transcript(offset: 30, source: source, text: interventionText, language: "en", start: 2_000, end: 6_000)
        let speaker = try builder.actor(offset: 40, identity: .person(displayName: "Synthetic Delegate", personName: "Alex Example"))
        let state = try builder.actor(offset: 50, identity: .country(displayName: "State of Example", countryCode: CountryCode("XE")))
        let capacity = try builder.capacity(offset: 60, meetingID: builder.meetingID, speaker: speaker, represented: state, role: .delegate)
        let chairEvidence = try builder.transcriptEvidence(offset: 70, transcript: chair)
        let interventionEvidence = try builder.transcriptEvidence(offset: 80, transcript: intervention)
        let assignment = try builder.assignment(
            offset: 90,
            meetingID: builder.meetingID,
            transcripts: [intervention],
            actor: speaker,
            capacity: capacity,
            evidence: [chairEvidence, interventionEvidence],
            certainty: .probable,
            reviewStatus: .unreviewed
        )
        let meeting = try builder.meeting(sourceAssets: [source])
        let graph = GoldenFixtureGraph(
            meeting: meeting,
            sourceAssets: [source],
            transcripts: [chair, intervention],
            translations: [],
            actors: [speaker, state],
            capacities: [capacity],
            assignments: [assignment],
            evidence: [chairEvidence, interventionEvidence]
        )
        return GoldenFixture(
            manifest: manifest(
                id: "ordinary_delegation_intervention",
                title: "Ordinary fictional delegation intervention",
                graph: graph,
                observations: [
                    observation("direct_support", evidence: interventionEvidence),
                    observation("direct_request", evidence: interventionEvidence)
                ],
                reservations: [],
                forbidden: [.fabricatedOpposition, .formalGroupAlignment, .confirmedPolicyChange, .nationalityEqualsRepresentation],
                failures: ["invented opposition", "country inferred from a person's identity"]
            ),
            graph: graph
        )
    }

    private static func reservationOrQualification() throws -> GoldenFixture {
        let builder = GoldenBuilder(base: 2_000)
        let source = try builder.audioSource(offset: 10, language: "en", kind: .originalSpeakerAudio)
        let chair = try builder.transcript(
            offset: 20,
            source: source,
            text: "I give the floor to the representative of the State of Example.",
            language: "en",
            start: 0,
            end: 2_000
        )
        let text = "We can support the draft only if participation remains voluntary and all costs are met from existing resources."
        let intervention = try builder.transcript(offset: 30, source: source, text: text, language: "en", start: 2_000, end: 7_000)
        let speaker = try builder.actor(offset: 40, identity: .person(displayName: "Synthetic Delegate", personName: "Taylor Example"))
        let state = try builder.actor(offset: 50, identity: .country(displayName: "State of Example", countryCode: CountryCode("XE")))
        let capacity = try builder.capacity(offset: 60, meetingID: builder.meetingID, speaker: speaker, represented: state, role: .delegate)
        let chairEvidence = try builder.transcriptEvidence(offset: 70, transcript: chair)
        let interventionEvidence = try builder.transcriptEvidence(offset: 80, transcript: intervention)
        let assignment = try builder.assignment(
            offset: 90,
            meetingID: builder.meetingID,
            transcripts: [intervention],
            actor: speaker,
            capacity: capacity,
            evidence: [chairEvidence, interventionEvidence],
            certainty: .probable,
            reviewStatus: .unreviewed
        )
        let meeting = try builder.meeting(sourceAssets: [source])
        let graph = GoldenFixtureGraph(
            meeting: meeting,
            sourceAssets: [source],
            transcripts: [chair, intervention],
            translations: [],
            actors: [speaker, state],
            capacities: [capacity],
            assignments: [assignment],
            evidence: [chairEvidence, interventionEvidence]
        )
        return GoldenFixture(
            manifest: manifest(
                id: "reservation_or_qualification",
                title: "Explicit fictional reservation and qualification",
                graph: graph,
                observations: [],
                reservations: [
                    observation("voluntary_participation_condition", evidence: interventionEvidence),
                    observation("existing_resources_condition", evidence: interventionEvidence)
                ],
                forbidden: [.unconditionalSupport, .fabricatedOpposition, .droppedQualification, .confirmedPolicyChange],
                failures: ["conditional support flattened into unconditional support", "resource qualification omitted"]
            ),
            graph: graph
        )
    }

    private static func uncertainSpeaker() throws -> GoldenFixture {
        let builder = GoldenBuilder(base: 3_000)
        let source = try builder.audioSource(offset: 10, language: "en", kind: .originalSpeakerAudio)
        let transcript = try builder.transcript(
            offset: 20,
            source: source,
            text: "We favor further consultations before any decision.",
            language: "en",
            start: 0,
            end: 3_000
        )
        let actor = try builder.actor(
            offset: 30,
            identity: .unidentifiedParticipant(label: "Unidentified participant"),
            reviewStatus: .needsReview
        )
        let capacity = try builder.capacity(
            offset: 40,
            meetingID: builder.meetingID,
            speaker: actor,
            represented: nil,
            role: .unidentified,
            reviewStatus: .needsReview
        )
        let evidence = try builder.transcriptEvidence(offset: 50, transcript: transcript)
        let assignment = try builder.assignment(
            offset: 60,
            meetingID: builder.meetingID,
            transcripts: [transcript],
            actor: actor,
            capacity: capacity,
            evidence: [evidence],
            certainty: .uncertain,
            reviewStatus: .needsReview
        )
        let meeting = try builder.meeting(sourceAssets: [source])
        let graph = GoldenFixtureGraph(
            meeting: meeting,
            sourceAssets: [source],
            transcripts: [transcript],
            translations: [],
            actors: [actor],
            capacities: [capacity],
            assignments: [assignment],
            evidence: [evidence]
        )
        return GoldenFixture(
            manifest: manifest(
                id: "uncertain_speaker",
                title: "Unidentified fictional speaker",
                graph: graph,
                observations: [observation("direct_consultation_preference", evidence: evidence)],
                reservations: [],
                forbidden: [.confirmedSpeakerIdentity, .inferredNationalPosition, .inferredSpeakingCapacity, .silenceAsAlignment],
                failures: ["low confidence promoted to confirmed", "country invented for unidentified speaker"]
            ),
            graph: graph
        )
    }

    private static func interpretationVersusOriginal() throws -> GoldenFixture {
        let builder = GoldenBuilder(base: 4_000)
        let originalSource = try builder.audioSource(offset: 10, language: "fr", kind: .originalSpeakerAudio)
        let interpretationSource = try builder.audioSource(offset: 20, language: "en", kind: .simultaneousInterpretation)
        let originalText = "Nous appuyons le projet, à condition que la participation reste volontaire."
        let original = try builder.transcript(offset: 30, source: originalSource, text: originalText, language: "fr", start: 0, end: 5_000)
        let interpretation = try builder.transcript(
            offset: 40,
            source: interpretationSource,
            text: "We support the proposal.",
            language: "en",
            start: 0,
            end: 5_000
        )
        let humanTranslation = try builder.translation(
            offset: 50,
            source: original,
            targetLanguage: "en",
            translatedText: "We support the proposal, provided that participation remains voluntary.",
            type: .humanTranslation
        )
        let originalEvidence = try builder.transcriptEvidence(offset: 60, transcript: original)
        let interpretationEvidence = try builder.transcriptEvidence(
            offset: 70,
            transcript: interpretation,
            status: .simultaneousInterpretation
        )
        let translationEvidence = try builder.translationEvidence(offset: 80, translation: humanTranslation)
        let meeting = try builder.meeting(sourceAssets: [originalSource, interpretationSource], languages: ["fr", "en"])
        let graph = GoldenFixtureGraph(
            meeting: meeting,
            sourceAssets: [originalSource, interpretationSource],
            transcripts: [original, interpretation],
            translations: [humanTranslation],
            actors: [],
            capacities: [],
            assignments: [],
            evidence: [originalEvidence, interpretationEvidence, translationEvidence]
        )
        return GoldenFixture(
            manifest: manifest(
                id: "interpretation_versus_original_audio",
                title: "Original, interpretation, and translation remain distinct",
                graph: graph,
                observations: [
                    observation("original_contains_voluntary_condition", evidence: originalEvidence),
                    observation("interpretation_omits_condition", basis: .directTextualDifference, evidence: originalEvidence, interpretationEvidence),
                    observation("human_translation_preserves_condition", evidence: translationEvidence)
                ],
                reservations: [observation("voluntary_participation_condition", evidence: originalEvidence)],
                forbidden: [.interpretationAsOriginalVerbatim, .translationAsSourceText, .interpreterOmissionAsSpeakerOmission],
                failures: ["interpretation labeled original", "interpreter omission attributed to speaker"]
            ),
            graph: graph
        )
    }

    private static func preparedChinaStatementVersusDelivered() throws -> GoldenFixture {
        let builder = GoldenBuilder(base: 5_000)
        let preparedText = "关于完全虚构的合成议题甲，中方支持年度审议并于一月启动。"
        let deliveredText = "关于完全虚构的合成议题甲，中方愿继续讨论审议频次和启动时间。"
        let preparedSource = try builder.documentSource(offset: 10, language: "zh-hans", text: preparedText)
        let deliveredSource = try builder.audioSource(offset: 20, language: "zh-hans", kind: .originalSpeakerAudio)
        let introduction = try builder.transcript(
            offset: 30,
            source: deliveredSource,
            text: "下面请完全虚构的中方代表发言。",
            language: "zh-hans",
            start: 0,
            end: 2_000
        )
        let delivered = try builder.transcript(offset: 40, source: deliveredSource, text: deliveredText, language: "zh-hans", start: 2_000, end: 7_000)
        let person = try builder.actor(offset: 50, identity: .person(displayName: "完全虚构的中方代表", personName: "合成人物甲"))
        let china = try builder.actor(offset: 60, identity: .country(displayName: "China", countryCode: CountryCode("CN")))
        let capacity = try builder.capacity(offset: 70, meetingID: builder.meetingID, speaker: person, represented: china, role: .delegate)
        let preparedEvidence = try builder.documentEvidence(offset: 80, source: preparedSource, text: preparedText)
        let introductionEvidence = try builder.transcriptEvidence(offset: 90, transcript: introduction)
        let deliveredEvidence = try builder.transcriptEvidence(offset: 100, transcript: delivered)
        let assignment = try builder.assignment(
            offset: 110,
            meetingID: builder.meetingID,
            transcripts: [delivered],
            actor: person,
            capacity: capacity,
            evidence: [introductionEvidence, deliveredEvidence],
            certainty: .probable,
            reviewStatus: .unreviewed
        )
        let meeting = try builder.meeting(
            sourceAssets: [preparedSource, deliveredSource],
            languages: ["zh-hans"],
            title: "完全虚构的合成议题甲会议"
        )
        let graph = GoldenFixtureGraph(
            meeting: meeting,
            sourceAssets: [preparedSource, deliveredSource],
            transcripts: [introduction, delivered],
            translations: [],
            actors: [person, china],
            capacities: [capacity],
            assignments: [assignment],
            evidence: [preparedEvidence, introductionEvidence, deliveredEvidence]
        )
        return GoldenFixture(
            manifest: manifest(
                id: "prepared_china_statement_versus_delivered",
                title: "Entirely synthetic China prepared-versus-delivered wording",
                graph: graph,
                observations: [
                    observation("prepared_annual_review_wording", evidence: preparedEvidence),
                    observation("delivered_discussion_wording", evidence: deliveredEvidence),
                    observation("prepared_delivered_textual_difference", basis: .directTextualDifference, evidence: preparedEvidence, deliveredEvidence)
                ],
                reservations: [],
                forbidden: [.realOfficialStatement, .preparedTextDeliveredVerbatim, .confirmedPolicyChange, .realWorldPositionAttribution],
                failures: ["synthetic wording treated as a real statement", "wording difference asserted as policy change"]
            ),
            graph: graph
        )
    }

    private static func observation(
        _ code: String,
        basis: GoldenObservationBasis = .directSourceText,
        evidence: EvidenceRefV1...
    ) -> GoldenExpectedObservation {
        GoldenExpectedObservation(
            code: code,
            basis: basis,
            evidenceRevisionIDs: evidence.map { $0.revision.revisionID }
        )
    }

    private static func manifest(
        id: String,
        title: String,
        graph: GoldenFixtureGraph,
        observations: [GoldenExpectedObservation],
        reservations: [GoldenExpectedObservation],
        forbidden: [GoldenForbiddenClaimCode],
        failures: [String]
    ) -> GoldenFixtureManifest {
        let counts = [
            GoldenObjectCount(objectType: .meetingProfile, count: 1),
            GoldenObjectCount(objectType: .sourceAsset, count: graph.sourceAssets.count),
            GoldenObjectCount(objectType: .transcriptSegment, count: graph.transcripts.count),
            GoldenObjectCount(objectType: .translationSegment, count: graph.translations.count),
            GoldenObjectCount(objectType: .actor, count: graph.actors.count),
            GoldenObjectCount(objectType: .speakingCapacity, count: graph.capacities.count),
            GoldenObjectCount(objectType: .speakerAssignment, count: graph.assignments.count),
            GoldenObjectCount(objectType: .evidenceRef, count: graph.evidence.count)
        ]
        return GoldenFixtureManifest(
            testCaseID: id,
            testCaseVersion: "1.0",
            title: title,
            sourceProvenance: .projectSynthetic,
            licensingStatus: .syntheticNoThirdPartyMaterial,
            spdxLicenseIdentifier: nil,
            repositoryReuseTerms: .unspecified,
            externalSources: [],
            containsRealMeetingContent: false,
            containsPersonalData: false,
            containsMediaBytes: false,
            acousticGroundTruth: false,
            humanDiplomaticReviewStatus: .notPerformed,
            materialScope: "semantic_contract_only",
            expectedSemanticObjectCounts: counts,
            expectedObservations: observations,
            expectedReservations: reservations,
            forbiddenClaims: forbidden,
            idealBriefingSectionsStatus: "deferred_to_task_006b",
            knownFailurePatterns: failures,
            scoringRubricVersion: "contract_input_v1"
        )
    }
}

private struct GoldenBuilder {
    let base: Int

    var meetingID: MeetingID { id(1, MeetingID.self) }

    func id<Tag>(_ offset: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
        let string = String(format: "20000000-0000-0000-0000-%012d", base + offset)
        return StableID<Tag>(UUID(uuidString: string)!)
    }

    func reference<Tag: LogicalObjectIDScope>(
        _ logicalID: StableID<Tag>,
        _ revisionID: RevisionID
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(logicalID: logicalID, revisionID: revisionID)
    }

    func envelope<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID,
        createdBy: CreationActor = .application,
        inputRevisions: [SemanticRevisionReference] = [],
        sourceAssetRevisions: [SemanticRevisionReference] = [],
        evidenceRevisions: [SemanticRevisionReference] = [],
        generationMetadata: GenerationMetadata? = nil
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: TestFixtures.createdAt,
            createdBy: createdBy,
            inputRevisions: inputRevisions,
            sourceAssetRevisions: sourceAssetRevisions,
            evidenceRevisions: evidenceRevisions,
            dataClassification: .public,
            generationMetadata: generationMetadata
        )
    }

    func meeting(
        sourceAssets: [SourceAssetV1],
        languages: [String] = ["en"],
        title: String = "Synthetic Meeting"
    ) throws -> MeetingProfileV1 {
        let sourceReferences = try sourceAssets.map {
            try reference($0.assetID, $0.revision.revisionID)
        }
        return try MeetingProfileV1(
            revision: envelope(
                logicalID: meetingID,
                revisionID: id(2, RevisionID.self),
                inputRevisions: sourceReferences,
                sourceAssetRevisions: sourceReferences
            ),
            title: title,
            meetingDate: CalendarDate(year: 2026, month: 1, day: 1),
            organizationOrUNBody: .unresolved(label: "Synthetic Committee"),
            agendaItems: [
                AgendaItem(itemID: id(3, AgendaItemID.self), ordinal: 1, title: "Synthetic agenda item")
            ],
            sourceLanguages: try languages.map(LanguageTag.init),
            outputLanguage: LanguageTag("zh-hans"),
            cloudProcessingPolicy: .localOnly,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    func audioSource(
        offset: Int,
        language: String,
        kind: SpeechSourceKind
    ) throws -> SourceAssetV1 {
        let logicalID = id(offset, SourceAssetID.self)
        let revisionID = id(offset + 1, RevisionID.self)
        let syntheticBytes = "synthetic-audio-descriptor-\(base)-\(offset)-\(language)-\(kind.encodedValue)"
        return try SourceAssetV1(
            revision: envelope(logicalID: logicalID, revisionID: revisionID),
            meetingID: meetingID,
            assetType: .audio,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(storageObjectID: id(offset + 2, StorageObjectID.self)),
            sourceContentHash: ContentDigest.sha256(ofUTF8Text: syntheticBytes),
            mimeType: MIMEType("audio/wav"),
            byteSize: UInt64(syntheticBytes.utf8.count),
            language: LanguageTag(language),
            acquisitionMethod: .userSelectedFile,
            acquiredAt: TestFixtures.acquiredAt,
            retentionClass: .permanent,
            media: MediaProvenance(
                durationMilliseconds: 60_000,
                languageTrack: LanguageTag(language),
                speechSourceKind: kind
            )
        )
    }

    func documentSource(offset: Int, language: String, text: String) throws -> SourceAssetV1 {
        let logicalID = id(offset, SourceAssetID.self)
        return try SourceAssetV1(
            revision: envelope(logicalID: logicalID, revisionID: id(offset + 1, RevisionID.self)),
            meetingID: meetingID,
            assetType: .document,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(storageObjectID: id(offset + 2, StorageObjectID.self)),
            sourceContentHash: ContentDigest.sha256(ofUTF8Text: text),
            mimeType: MIMEType("text/plain"),
            byteSize: UInt64(text.utf8.count),
            language: LanguageTag(language),
            acquisitionMethod: .userSelectedFile,
            acquiredAt: TestFixtures.acquiredAt,
            retentionClass: .permanent
        )
    }

    func transcript(
        offset: Int,
        source: SourceAssetV1,
        text: String,
        language: String,
        start: Int64,
        end: Int64
    ) throws -> TranscriptSegmentV1 {
        let sourceReference = try reference(source.assetID, source.revision.revisionID)
        let provenance: TranscriptSourceProvenance
        switch source.media?.speechSourceKind ?? .unknown {
        case .originalSpeakerAudio:
            provenance = .originalSpeakerAudio(sourceAssetRevision: sourceReference)
        case .simultaneousInterpretation:
            provenance = .simultaneousInterpretation(sourceAssetRevision: sourceReference)
        case .translatedAudioTrack:
            provenance = .translatedAudioTrack(sourceAssetRevision: sourceReference)
        case .unknown:
            provenance = .unknown(sourceAssetRevision: sourceReference)
        case .unrecognized:
            throw DomainValidationError(
                issues: [ValidationIssue(code: .unsupportedValue, path: "fixture.source_kind", message: "Unsupported fixture source kind.")]
            )
        }
        return try TranscriptSegmentV1(
            revision: envelope(
                logicalID: id(offset, TranscriptSegmentID.self),
                revisionID: id(offset + 1, RevisionID.self),
                inputRevisions: [sourceReference],
                sourceAssetRevisions: [sourceReference]
            ),
            meetingID: meetingID,
            sourceProvenance: provenance,
            timeRange: MediaTimeRange(startMilliseconds: start, endMilliseconds: end),
            detectedLanguage: LanguageTag(language),
            text: text,
            confidence: ConfidenceScore(millionths: 900_000),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    func translation(
        offset: Int,
        source: TranscriptSegmentV1,
        targetLanguage: String,
        translatedText: String,
        type: TranslationType
    ) throws -> TranslationSegmentV1 {
        let sourceReference = try reference(source.segmentID, source.revision.revisionID)
        return try TranslationSegmentV1(
            revision: envelope(
                logicalID: id(offset, TranslationSegmentID.self),
                revisionID: id(offset + 1, RevisionID.self),
                createdBy: .user,
                inputRevisions: [sourceReference]
            ),
            meetingID: meetingID,
            sourceSegmentRevision: sourceReference,
            sourceLanguage: source.detectedLanguage,
            targetLanguage: LanguageTag(targetLanguage),
            sourceTextHash: TranslationSegmentV1.calculateSourceTextHash(source.text),
            translatedText: translatedText,
            translationType: type,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    func actor(
        offset: Int,
        identity: ActorIdentity,
        reviewStatus: ReviewStatus = .unreviewed
    ) throws -> ActorV1 {
        try ActorV1(
            revision: envelope(
                logicalID: id(offset, ActorID.self),
                revisionID: id(offset + 1, RevisionID.self)
            ),
            identity: identity,
            canonicalAliases: [identity.displayName],
            reviewStatus: reviewStatus,
            userConfirmed: false
        )
    }

    func capacity(
        offset: Int,
        meetingID: MeetingID,
        speaker: ActorV1,
        represented: ActorV1?,
        role: MeetingRole,
        reviewStatus: ReviewStatus = .unreviewed
    ) throws -> SpeakingCapacityV1 {
        let speakerReference = try reference(speaker.actorID, speaker.revision.revisionID)
        let relationships: [RepresentationRelationship]
        if let represented {
            relationships = [
                try RepresentationRelationship(
                    kind: .represents,
                    entityRevision: reference(represented.actorID, represented.revision.revisionID)
                )
            ]
        } else {
            relationships = []
        }
        return try SpeakingCapacityV1(
            revision: envelope(
                logicalID: id(offset, SpeakingCapacityID.self),
                revisionID: id(offset + 1, RevisionID.self),
                inputRevisions: [speakerReference] + relationships.map(\.entityRevision)
            ),
            meetingID: meetingID,
            speakerActorRevision: speakerReference,
            representationRelationships: relationships,
            meetingRole: role,
            reviewStatus: reviewStatus,
            userConfirmed: false
        )
    }

    func transcriptEvidence(
        offset: Int,
        transcript: TranscriptSegmentV1,
        status: TranslationStatus = .sourceOnly
    ) throws -> EvidenceRefV1 {
        let source = try reference(transcript.segmentID, transcript.revision.revisionID)
        return try evidence(
            offset: offset,
            source: source,
            location: .transcriptSegment(
                source: source,
                textRange: UTF8TextRange(startOffset: 0, length: UInt64(transcript.text.utf8.count))
            ),
            text: transcript.text,
            language: transcript.detectedLanguage,
            status: status
        )
    }

    func translationEvidence(offset: Int, translation: TranslationSegmentV1) throws -> EvidenceRefV1 {
        let source = try reference(translation.translationID, translation.revision.revisionID)
        return try evidence(
            offset: offset,
            source: source,
            location: .semanticObjectRevision(source: source, jsonPointer: "/translated_text"),
            text: translation.translatedText,
            language: translation.targetLanguage,
            status: translation.translationStatus
        )
    }

    func documentEvidence(offset: Int, source: SourceAssetV1, text: String) throws -> EvidenceRefV1 {
        let sourceReference = try reference(source.assetID, source.revision.revisionID)
        return try evidence(
            offset: offset,
            source: sourceReference,
            location: .officialStatement(
                source: sourceReference,
                location: DocumentLocation(section: "Synthetic prepared statement")
            ),
            text: text,
            language: source.language ?? LanguageTag("und"),
            status: .sourceOnly
        )
    }

    func assignment(
        offset: Int,
        meetingID: MeetingID,
        transcripts: [TranscriptSegmentV1],
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        evidence: [EvidenceRefV1],
        certainty: AssignmentCertainty,
        reviewStatus: ReviewStatus
    ) throws -> SpeakerAssignmentV1 {
        let transcriptReferences = try transcripts.map { try reference($0.segmentID, $0.revision.revisionID) }
        let actorReference = try reference(actor.actorID, actor.revision.revisionID)
        let capacityReference = try reference(capacity.capacityID, capacity.revision.revisionID)
        let evidenceReferences = try evidence.map { try reference($0.evidenceID, $0.revision.revisionID) }
        return try SpeakerAssignmentV1(
            revision: envelope(
                logicalID: id(offset, SpeakerAssignmentID.self),
                revisionID: id(offset + 1, RevisionID.self),
                inputRevisions: transcriptReferences + [actorReference, capacityReference],
                evidenceRevisions: evidenceReferences
            ),
            meetingID: meetingID,
            transcriptSegmentRevisions: transcriptReferences,
            actorRevision: actorReference,
            speakingCapacityRevision: capacityReference,
            confidence: ConfidenceScore(millionths: certainty == .uncertain ? 250_000 : 800_000),
            certainty: certainty,
            assignmentSources: [.transcriptContext],
            reviewStatus: reviewStatus,
            userConfirmed: false
        )
    }

    private func evidence(
        offset: Int,
        source: SemanticRevisionReference,
        location: EvidenceLocation,
        text: String,
        language: LanguageTag,
        status: TranslationStatus
    ) throws -> EvidenceRefV1 {
        let sourceAssets = source.objectType == .sourceAsset ? [source] : []
        return try EvidenceRefV1(
            revision: envelope(
                logicalID: id(offset, EvidenceID.self),
                revisionID: id(offset + 1, RevisionID.self),
                inputRevisions: [source],
                sourceAssetRevisions: sourceAssets
            ),
            location: location,
            excerpt: EvidenceExcerpt(text: text, language: language, translationStatus: status),
            confidence: ConfidenceScore(millionths: 1_000_000)
        )
    }
}
