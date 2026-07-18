import Foundation
@testable import MeetingBuddyDomain

enum Task003BFixtures {
    static let meetingID = TestFixtures.meetingID
    static let meetingRevisionID = TestFixtures.meetingRevisionID
    static let replacementMeetingRevisionID = id(101, RevisionID.self)
    static let transcriptID = TestFixtures.transcriptSegmentID
    static let transcriptRevisionID = TestFixtures.transcriptRevisionID
    static let translationID = id(102, TranslationSegmentID.self)
    static let translationRevisionID = id(103, RevisionID.self)
    static let actorID = id(104, ActorID.self)
    static let actorRevisionID = id(105, RevisionID.self)
    static let stateActorID = id(106, ActorID.self)
    static let stateActorRevisionID = id(107, RevisionID.self)
    static let unidentifiedActorID = id(108, ActorID.self)
    static let unidentifiedActorRevisionID = id(109, RevisionID.self)
    static let capacityID = id(110, SpeakingCapacityID.self)
    static let capacityRevisionID = id(111, RevisionID.self)
    static let uncertainCapacityID = id(112, SpeakingCapacityID.self)
    static let uncertainCapacityRevisionID = id(113, RevisionID.self)
    static let assignmentID = id(114, SpeakerAssignmentID.self)
    static let assignmentRevisionID = id(115, RevisionID.self)
    static let agendaItemID = id(116, AgendaItemID.self)
    static let workspaceID = id(117, WorkspaceID.self)
    static let templateID = id(118, BriefingTemplateID.self)

    static func id<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
        let string = String(format: "10000000-0000-0000-0000-%012d", suffix)
        return StableID<Tag>(UUID(uuidString: string)!)
    }

    static func reference<Tag: LogicalObjectIDScope>(
        _ logicalID: StableID<Tag>,
        _ revisionID: RevisionID
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(logicalID: logicalID, revisionID: revisionID)
    }

    static func envelope<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID,
        lifecycleStatus: LifecycleStatus = .draft,
        validationState: ValidationState = .notValidated,
        createdBy: CreationActor = .application,
        publishedAt: UTCInstant? = nil,
        supersedesRevisionID: RevisionID? = nil,
        inputRevisions: [SemanticRevisionReference] = [],
        sourceAssetRevisions: [SemanticRevisionReference] = [],
        evidenceRevisions: [SemanticRevisionReference] = [],
        classification: DataClassification = .internal,
        generationMetadata: GenerationMetadata? = nil,
        semanticContentHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: lifecycleStatus,
            validationState: validationState,
            createdAt: TestFixtures.createdAt,
            createdBy: createdBy,
            publishedAt: publishedAt,
            supersedesRevisionID: supersedesRevisionID,
            inputRevisions: inputRevisions,
            sourceAssetRevisions: sourceAssetRevisions,
            evidenceRevisions: evidenceRevisions,
            dataClassification: classification,
            generationMetadata: generationMetadata,
            semanticContentHash: semanticContentHash
        )
    }

    static func meetingEnvelope(
        revisionID: RevisionID = meetingRevisionID,
        lifecycleStatus: LifecycleStatus = .draft,
        validationState: ValidationState = .notValidated,
        createdBy: CreationActor = .application,
        publishedAt: UTCInstant? = nil,
        supersedesRevisionID: RevisionID? = nil,
        semanticContentHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<MeetingIDTag> {
        try envelope(
            logicalID: meetingID,
            revisionID: revisionID,
            lifecycleStatus: lifecycleStatus,
            validationState: validationState,
            createdBy: createdBy,
            publishedAt: publishedAt,
            supersedesRevisionID: supersedesRevisionID,
            semanticContentHash: semanticContentHash
        )
    }

    static func meetingProfile(
        revision suppliedRevision: RevisionEnvelope<MeetingIDTag>? = nil,
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false
    ) throws -> MeetingProfileV1 {
        try MeetingProfileV1(
            revision: suppliedRevision ?? meetingEnvelope(),
            title: "Synthetic Committee Meeting",
            meetingNumber: "SYN-1",
            meetingDate: CalendarDate(year: 2026, month: 7, day: 17),
            organizationOrUNBody: .unresolved(label: "Synthetic Committee"),
            agendaItems: [
                AgendaItem(itemID: agendaItemID, ordinal: 1, title: "Synthetic agenda item")
            ],
            sourceLanguages: [LanguageTag("en")],
            outputLanguage: LanguageTag("zh-hans"),
            briefingTemplateID: templateID,
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspaceID,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    static func transcriptEnvelope(
        revisionID: RevisionID = transcriptRevisionID,
        source: SemanticRevisionReference? = nil,
        createdBy: CreationActor = .application,
        generationMetadata: GenerationMetadata? = nil,
        lifecycleStatus: LifecycleStatus = .draft,
        validationState: ValidationState = .notValidated,
        publishedAt: UTCInstant? = nil,
        semanticContentHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<TranscriptSegmentIDTag> {
        let source = try source ?? TestFixtures.sourceReference()
        return try envelope(
            logicalID: transcriptID,
            revisionID: revisionID,
            lifecycleStatus: lifecycleStatus,
            validationState: validationState,
            createdBy: createdBy,
            publishedAt: publishedAt,
            inputRevisions: [source],
            sourceAssetRevisions: [source],
            generationMetadata: generationMetadata,
            semanticContentHash: semanticContentHash
        )
    }

    static func transcript(
        revision suppliedRevision: RevisionEnvelope<TranscriptSegmentIDTag>? = nil,
        sourceProvenance: TranscriptSourceProvenance? = nil,
        text: String = "We support the synthetic proposal, subject to review.",
        language: String = "en",
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false
    ) throws -> TranscriptSegmentV1 {
        let provenance = try sourceProvenance ?? .originalSpeakerAudio(
            sourceAssetRevision: TestFixtures.sourceReference()
        )
        return try TranscriptSegmentV1(
            revision: suppliedRevision ?? transcriptEnvelope(source: provenance.sourceAssetRevision),
            meetingID: meetingID,
            sourceProvenance: provenance,
            timeRange: MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 4_000),
            detectedLanguage: LanguageTag(language),
            text: text,
            confidence: ConfidenceScore(millionths: 900_000),
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    static func generationMetadata() throws -> GenerationMetadata {
        try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "synthetic-local-provider",
                modelIdentifier: "synthetic-translation-model",
                modelVersion: "1"
            ),
            promptModuleVersions: [
                VersionedComponent(identifier: "translation-contract", version: "1")
            ],
            outputSchemaVersion: .v1,
            templateVersion: "translation-contract-v1",
            generatedAt: TestFixtures.acquiredAt,
            privacyRoute: .localOnly
        )
    }

    static func translationEnvelope(
        revisionID: RevisionID = translationRevisionID,
        source: SemanticRevisionReference? = nil,
        createdBy: CreationActor = .provider,
        supersedesRevisionID: RevisionID? = nil,
        extraInputs: [SemanticRevisionReference] = [],
        generationMetadata: GenerationMetadata? = nil
    ) throws -> RevisionEnvelope<TranslationSegmentIDTag> {
        let source = try source ?? reference(transcriptID, transcriptRevisionID)
        return try envelope(
            logicalID: translationID,
            revisionID: revisionID,
            createdBy: createdBy,
            supersedesRevisionID: supersedesRevisionID,
            inputRevisions: [source] + extraInputs,
            generationMetadata: generationMetadata ?? self.generationMetadata()
        )
    }

    static func translation(
        revision suppliedRevision: RevisionEnvelope<TranslationSegmentIDTag>? = nil,
        sourceTranscript: TranscriptSegmentV1? = nil,
        translatedText: String = "我们支持这一合成提案，但须经过审议。",
        translationType: TranslationType = .machineTranslation,
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false
    ) throws -> TranslationSegmentV1 {
        let sourceTranscript = try sourceTranscript ?? transcript()
        let sourceReference = try reference(
            sourceTranscript.segmentID,
            sourceTranscript.revision.revisionID
        )
        return try TranslationSegmentV1(
            revision: suppliedRevision ?? translationEnvelope(source: sourceReference),
            meetingID: sourceTranscript.meetingID,
            sourceSegmentRevision: sourceReference,
            sourceLanguage: sourceTranscript.detectedLanguage,
            targetLanguage: LanguageTag("zh-hans"),
            sourceTextHash: TranslationSegmentV1.calculateSourceTextHash(sourceTranscript.text),
            translatedText: translatedText,
            translationType: translationType,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 850_000),
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    static func actor(
        logicalID: ActorID = actorID,
        revisionID: RevisionID = actorRevisionID,
        identity: ActorIdentity = .person(
            displayName: "Synthetic Delegate",
            personName: "Alex Example"
        ),
        createdBy: CreationActor = .application,
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false
    ) throws -> ActorV1 {
        try ActorV1(
            revision: envelope(
                logicalID: logicalID,
                revisionID: revisionID,
                createdBy: createdBy
            ),
            identity: identity,
            canonicalAliases: [identity.displayName],
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    static func stateActor() throws -> ActorV1 {
        try actor(
            logicalID: stateActorID,
            revisionID: stateActorRevisionID,
            identity: .country(displayName: "State of Example", countryCode: CountryCode("XE"))
        )
    }

    static func unidentifiedActor() throws -> ActorV1 {
        try actor(
            logicalID: unidentifiedActorID,
            revisionID: unidentifiedActorRevisionID,
            identity: .unidentifiedParticipant(label: "Unidentified participant"),
            reviewStatus: .needsReview
        )
    }

    static func capacity(
        logicalID: SpeakingCapacityID = capacityID,
        revisionID: RevisionID = capacityRevisionID,
        speaker: ActorV1? = nil,
        represented: ActorV1? = nil,
        role: MeetingRole = .delegate,
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false
    ) throws -> SpeakingCapacityV1 {
        let speaker = try speaker ?? actor()
        let speakerReference = try reference(speaker.actorID, speaker.revision.revisionID)
        let represented = try represented ?? stateActor()
        let representedReference = try reference(represented.actorID, represented.revision.revisionID)
        let relationships = role == .unidentified ? [] : [
            try RepresentationRelationship(kind: .represents, entityRevision: representedReference)
        ]
        return try SpeakingCapacityV1(
            revision: envelope(
                logicalID: logicalID,
                revisionID: revisionID,
                inputRevisions: [speakerReference] + relationships.map(\.entityRevision)
            ),
            meetingID: meetingID,
            speakerActorRevision: speakerReference,
            representationRelationships: relationships,
            meetingRole: role,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    static func evidenceForTranscript(
        transcript: TranscriptSegmentV1? = nil
    ) throws -> EvidenceRefV1 {
        let transcript = try transcript ?? self.transcript()
        let transcriptReference = try reference(transcript.segmentID, transcript.revision.revisionID)
        let location = EvidenceLocation.transcriptSegment(
            source: transcriptReference,
            textRange: try UTF8TextRange(startOffset: 0, length: UInt64(transcript.text.utf8.count))
        )
        return try TestFixtures.evidenceRef(
            location: location,
            excerptText: transcript.text,
            revision: TestFixtures.evidenceEnvelope(source: transcriptReference)
        )
    }

    static func assignment(
        transcript suppliedTranscript: TranscriptSegmentV1? = nil,
        actor suppliedActor: ActorV1? = nil,
        capacity suppliedCapacity: SpeakingCapacityV1? = nil,
        evidence suppliedEvidence: EvidenceRefV1? = nil,
        certainty: AssignmentCertainty = .probable,
        reviewStatus: ReviewStatus = .unreviewed,
        userConfirmed: Bool = false,
        createdBy: CreationActor = .application
    ) throws -> SpeakerAssignmentV1 {
        let transcript = try suppliedTranscript ?? self.transcript()
        let actor = try suppliedActor ?? self.actor()
        let capacity = try suppliedCapacity ?? self.capacity(speaker: actor)
        let evidence = try suppliedEvidence ?? evidenceForTranscript(transcript: transcript)
        let transcriptReference = try reference(transcript.segmentID, transcript.revision.revisionID)
        let actorReference = try reference(actor.actorID, actor.revision.revisionID)
        let capacityReference = try reference(capacity.capacityID, capacity.revision.revisionID)
        let evidenceReference = try reference(evidence.evidenceID, evidence.revision.revisionID)
        return try SpeakerAssignmentV1(
            revision: envelope(
                logicalID: assignmentID,
                revisionID: assignmentRevisionID,
                createdBy: createdBy,
                inputRevisions: [transcriptReference, actorReference, capacityReference],
                evidenceRevisions: [evidenceReference]
            ),
            meetingID: meetingID,
            transcriptSegmentRevisions: [transcriptReference],
            actorRevision: actorReference,
            speakingCapacityRevision: capacityReference,
            confidence: ConfidenceScore(millionths: certainty == .uncertain ? 300_000 : 800_000),
            certainty: certainty,
            assignmentSources: [.transcriptContext],
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }
}
