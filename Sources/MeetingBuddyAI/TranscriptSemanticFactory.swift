import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

struct ManualTranscriptPublicationIdentifiers: Sendable {
    let transcriptID: TranscriptSegmentID
    let transcriptRevisionID: RevisionID
    let translationID: TranslationSegmentID
    let translationRevisionID: RevisionID
    let transcriptSetID: TranscriptSetID
    let manifestID: TranscriptCoverageManifestID

    init(
        transcriptID: TranscriptSegmentID = TranscriptSegmentID(UUID()),
        transcriptRevisionID: RevisionID = RevisionID(UUID()),
        translationID: TranslationSegmentID = TranslationSegmentID(UUID()),
        translationRevisionID: RevisionID = RevisionID(UUID()),
        transcriptSetID: TranscriptSetID = TranscriptSetID(UUID()),
        manifestID: TranscriptCoverageManifestID = TranscriptCoverageManifestID(UUID())
    ) {
        self.transcriptID = transcriptID
        self.transcriptRevisionID = transcriptRevisionID
        self.translationID = translationID
        self.translationRevisionID = translationRevisionID
        self.transcriptSetID = transcriptSetID
        self.manifestID = manifestID
    }
}

struct SpeakerConfirmationIdentifiers: Sendable {
    let actorID: ActorID
    let actorRevisionID: RevisionID
    let capacityID: SpeakingCapacityID
    let capacityRevisionID: RevisionID
    let evidenceID: EvidenceID
    let evidenceRevisionID: RevisionID
    let assignmentID: SpeakerAssignmentID
    let assignmentRevisionID: RevisionID

    init(
        actorID: ActorID = ActorID(UUID()),
        actorRevisionID: RevisionID = RevisionID(UUID()),
        capacityID: SpeakingCapacityID = SpeakingCapacityID(UUID()),
        capacityRevisionID: RevisionID = RevisionID(UUID()),
        evidenceID: EvidenceID = EvidenceID(UUID()),
        evidenceRevisionID: RevisionID = RevisionID(UUID()),
        assignmentID: SpeakerAssignmentID = SpeakerAssignmentID(UUID()),
        assignmentRevisionID: RevisionID = RevisionID(UUID())
    ) {
        self.actorID = actorID
        self.actorRevisionID = actorRevisionID
        self.capacityID = capacityID
        self.capacityRevisionID = capacityRevisionID
        self.evidenceID = evidenceID
        self.evidenceRevisionID = evidenceRevisionID
        self.assignmentID = assignmentID
        self.assignmentRevisionID = assignmentRevisionID
    }
}

public enum TranscriptSemanticFactory {
    public static func manualPublication(
        meetingID: MeetingID,
        canonicalSource: SemanticRevisionReference,
        canonicalFrameCount: UInt64,
        speechSourceKind: SpeechSourceKind,
        sourceLanguage: LanguageTag,
        transcriptText: String,
        targetLanguage: LanguageTag?,
        translatedText: String?,
        confirmsCompleteCoverage: Bool,
        classification: DataClassification,
        transcriptionRoute: ModelRouteDecision,
        translationRoute: ModelRouteDecision?,
        createdAt: UTCInstant
    ) throws -> TranscriptPublication {
        try manualPublication(
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            canonicalFrameCount: canonicalFrameCount,
            speechSourceKind: speechSourceKind,
            sourceLanguage: sourceLanguage,
            transcriptText: transcriptText,
            targetLanguage: targetLanguage,
            translatedText: translatedText,
            confirmsCompleteCoverage: confirmsCompleteCoverage,
            classification: classification,
            transcriptionRoute: transcriptionRoute,
            translationRoute: translationRoute,
            createdAt: createdAt,
            identifiers: ManualTranscriptPublicationIdentifiers()
        )
    }

    static func manualPublication(
        meetingID: MeetingID,
        canonicalSource: SemanticRevisionReference,
        canonicalFrameCount: UInt64,
        speechSourceKind: SpeechSourceKind,
        sourceLanguage: LanguageTag,
        transcriptText: String,
        targetLanguage: LanguageTag?,
        translatedText: String?,
        confirmsCompleteCoverage: Bool,
        classification: DataClassification,
        transcriptionRoute: ModelRouteDecision,
        translationRoute: ModelRouteDecision?,
        createdAt: UTCInstant,
        identifiers: ManualTranscriptPublicationIdentifiers
    ) throws -> TranscriptPublication {
        guard confirmsCompleteCoverage,
              transcriptionRoute.route == .manualFallback,
              transcriptionRoute.request.capability == .transcription,
              (targetLanguage == nil) == (translationRoute == nil),
              targetLanguage == nil || translatedText != nil,
              translationRoute.map({
                  $0.route == .manualFallback && $0.request.capability == .translation
              }) ?? true,
              targetLanguage != sourceLanguage
        else { throw TranscriptCoverageError.publicationConflict }
        let fullRange = try MediaFrameRange(startFrame: 0, endFrame: canonicalFrameCount)
        let transcript = try manualTranscript(
            logicalID: identifiers.transcriptID,
            revisionID: identifiers.transcriptRevisionID,
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            speechSourceKind: speechSourceKind,
            coreRange: fullRange,
            language: sourceLanguage,
            text: transcriptText,
            createdAt: createdAt,
            classification: classification
        )
        let transcriptReference = try SemanticRevisionReference(
            logicalID: transcript.segmentID,
            revisionID: transcript.revision.revisionID
        )
        let translation: TranslationSegmentV1? = try {
            guard let targetLanguage, let translatedText else { return nil }
            return try manualTranslation(
                logicalID: identifiers.translationID,
                revisionID: identifiers.translationRevisionID,
                transcript: transcript,
                canonicalSource: canonicalSource,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                translatedText: translatedText,
                createdAt: createdAt,
                classification: classification
            )
        }()
        let translationReference = try translation.map {
            try SemanticRevisionReference(
                logicalID: $0.translationID,
                revisionID: $0.revision.revisionID
            )
        }
        let chunks = try CanonicalChunkPlanner.plan(totalFrameCount: canonicalFrameCount).map {
            try TranscriptChunkCoverage(
                index: $0.index,
                coreRange: $0.coreRange,
                physicalRange: $0.physicalRange,
                disposition: .transcribed,
                attemptCount: 1,
                reviewedSegmentRevision: transcriptReference,
                translationRevision: translationReference
            )
        }
        let manifest = try TranscriptCoverageManifest(
            manifestID: identifiers.manifestID,
            transcriptSetID: identifiers.transcriptSetID,
            meetingID: meetingID,
            canonicalSourceRevision: canonicalSource,
            canonicalFrameCount: canonicalFrameCount,
            transcriptionRoute: transcriptionRoute,
            translationRoute: translationRoute,
            status: .published,
            chunks: chunks,
            createdAt: createdAt
        )
        return try TranscriptPublication(
            manifest: manifest,
            transcriptSegments: [transcript],
            translations: translation.map { [$0] } ?? []
        )
    }

    public static func providerTranscript(
        logicalID: TranscriptSegmentID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        canonicalSource: SemanticRevisionReference,
        speechSourceKind: SpeechSourceKind,
        coreRange: MediaFrameRange,
        language: LanguageTag,
        text: String,
        confidence: ConfidenceScore,
        provider: ProviderMetadata,
        createdAt: UTCInstant,
        classification: DataClassification
    ) throws -> TranscriptSegmentV1 {
        let generation = try generationMetadata(
            provider: provider,
            component: "transcription-provider-output",
            createdAt: createdAt
        )
        let draft = try transcript(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            speechSourceKind: speechSourceKind,
            coreRange: coreRange,
            language: language,
            text: text,
            confidence: confidence,
            createdAt: createdAt,
            createdBy: .provider,
            classification: classification,
            generation: generation,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .needsReview,
            userConfirmed: false,
            semanticHash: nil
        )
        return try transcript(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            speechSourceKind: speechSourceKind,
            coreRange: coreRange,
            language: language,
            text: text,
            confidence: confidence,
            createdAt: createdAt,
            createdBy: .provider,
            classification: classification,
            generation: generation,
            lifecycle: .published,
            validation: .valid,
            publishedAt: createdAt,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .needsReview,
            userConfirmed: false,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
    }

    public static func manualTranscript(
        logicalID: TranscriptSegmentID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        canonicalSource: SemanticRevisionReference,
        speechSourceKind: SpeechSourceKind,
        coreRange: MediaFrameRange,
        language: LanguageTag,
        text: String,
        createdAt: UTCInstant,
        classification: DataClassification
    ) throws -> TranscriptSegmentV1 {
        let draft = try transcript(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            speechSourceKind: speechSourceKind,
            coreRange: coreRange,
            language: language,
            text: text,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: createdAt,
            createdBy: .user,
            classification: classification,
            generation: nil,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: nil
        )
        return try transcript(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: meetingID,
            canonicalSource: canonicalSource,
            speechSourceKind: speechSourceKind,
            coreRange: coreRange,
            language: language,
            text: text,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: createdAt,
            createdBy: .user,
            classification: classification,
            generation: nil,
            lifecycle: .published,
            validation: .valid,
            publishedAt: createdAt,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
    }

    public static func providerTranslation(
        logicalID: TranslationSegmentID,
        revisionID: RevisionID,
        transcript: TranscriptSegmentV1,
        canonicalSource: SemanticRevisionReference,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag,
        translatedText: String,
        confidence: ConfidenceScore,
        provider: ProviderMetadata,
        createdAt: UTCInstant,
        classification: DataClassification
    ) throws -> TranslationSegmentV1 {
        let sourceReference = try SemanticRevisionReference(
            logicalID: transcript.segmentID,
            revisionID: transcript.revision.revisionID
        )
        let generation = try generationMetadata(
            provider: provider,
            component: "translation-provider-output",
            createdAt: createdAt
        )
        let draft = try translation(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: transcript.meetingID,
            sourceReference: sourceReference,
            canonicalSource: canonicalSource,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceText: transcript.text,
            translatedText: translatedText,
            type: .machineTranslation,
            alignment: .unreviewed,
            confidence: confidence,
            createdAt: createdAt,
            createdBy: .provider,
            classification: classification,
            generation: generation,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .needsReview,
            userConfirmed: false,
            semanticHash: nil
        )
        return try translation(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: transcript.meetingID,
            sourceReference: sourceReference,
            canonicalSource: canonicalSource,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceText: transcript.text,
            translatedText: translatedText,
            type: .machineTranslation,
            alignment: .unreviewed,
            confidence: confidence,
            createdAt: createdAt,
            createdBy: .provider,
            classification: classification,
            generation: generation,
            lifecycle: .published,
            validation: .valid,
            publishedAt: createdAt,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .needsReview,
            userConfirmed: false,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
    }

    public static func manualTranslation(
        logicalID: TranslationSegmentID,
        revisionID: RevisionID,
        transcript: TranscriptSegmentV1,
        canonicalSource: SemanticRevisionReference,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag,
        translatedText: String,
        createdAt: UTCInstant,
        classification: DataClassification
    ) throws -> TranslationSegmentV1 {
        let sourceReference = try SemanticRevisionReference(
            logicalID: transcript.segmentID,
            revisionID: transcript.revision.revisionID
        )
        let draft = try translation(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: transcript.meetingID,
            sourceReference: sourceReference,
            canonicalSource: canonicalSource,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceText: transcript.text,
            translatedText: translatedText,
            type: .humanTranslation,
            alignment: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: createdAt,
            createdBy: .user,
            classification: classification,
            generation: nil,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: nil
        )
        return try translation(
            logicalID: logicalID,
            revisionID: revisionID,
            meetingID: transcript.meetingID,
            sourceReference: sourceReference,
            canonicalSource: canonicalSource,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceText: transcript.text,
            translatedText: translatedText,
            type: .humanTranslation,
            alignment: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: createdAt,
            createdBy: .user,
            classification: classification,
            generation: nil,
            lifecycle: .published,
            validation: .valid,
            publishedAt: createdAt,
            supersedes: nil,
            extraInputs: [],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
    }

    public static func correctedTranscript(
        prior: TranscriptSegmentV1,
        newRevisionID: RevisionID = RevisionID(UUID()),
        text: String,
        changedAt: UTCInstant
    ) throws -> TranscriptSegmentV1 {
        let priorReference = try SemanticRevisionReference(
            logicalID: prior.segmentID,
            revisionID: prior.revision.revisionID
        )
        let draft = try transcript(
            logicalID: prior.segmentID,
            revisionID: newRevisionID,
            meetingID: prior.meetingID,
            canonicalSource: prior.sourceAssetRevision,
            speechSourceKind: prior.speechSourceKind,
            coreRange: try frames(for: prior.timeRange),
            language: prior.detectedLanguage,
            text: text,
            confidence: prior.confidence,
            createdAt: changedAt,
            createdBy: .user,
            classification: prior.revision.dataClassification,
            generation: nil,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: prior.revision.revisionID,
            extraInputs: [priorReference],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: nil,
            exactTimeRange: prior.timeRange
        )
        return try transcript(
            logicalID: prior.segmentID,
            revisionID: newRevisionID,
            meetingID: prior.meetingID,
            canonicalSource: prior.sourceAssetRevision,
            speechSourceKind: prior.speechSourceKind,
            coreRange: try frames(for: prior.timeRange),
            language: prior.detectedLanguage,
            text: text,
            confidence: prior.confidence,
            createdAt: changedAt,
            createdBy: .user,
            classification: prior.revision.dataClassification,
            generation: nil,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            supersedes: prior.revision.revisionID,
            extraInputs: [priorReference],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: try draft.calculatedSemanticContentHash(),
            exactTimeRange: prior.timeRange
        )
    }

    public static func correctedTranslation(
        prior: TranslationSegmentV1,
        sourceTranscript: TranscriptSegmentV1,
        newRevisionID: RevisionID = RevisionID(UUID()),
        text: String,
        changedAt: UTCInstant
    ) throws -> TranslationSegmentV1 {
        let priorReference = try SemanticRevisionReference(
            logicalID: prior.translationID,
            revisionID: prior.revision.revisionID
        )
        let sourceReference = try SemanticRevisionReference(
            logicalID: sourceTranscript.segmentID,
            revisionID: sourceTranscript.revision.revisionID
        )
        let draft = try translation(
            logicalID: prior.translationID,
            revisionID: newRevisionID,
            meetingID: prior.meetingID,
            sourceReference: sourceReference,
            canonicalSource: sourceTranscript.sourceAssetRevision,
            sourceLanguage: prior.sourceLanguage,
            targetLanguage: prior.targetLanguage,
            sourceText: sourceTranscript.text,
            translatedText: text,
            type: .userEditedTranslation,
            alignment: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: changedAt,
            createdBy: .user,
            classification: prior.revision.dataClassification,
            generation: nil,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            supersedes: prior.revision.revisionID,
            extraInputs: [priorReference],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: nil
        )
        return try translation(
            logicalID: prior.translationID,
            revisionID: newRevisionID,
            meetingID: prior.meetingID,
            sourceReference: sourceReference,
            canonicalSource: sourceTranscript.sourceAssetRevision,
            sourceLanguage: prior.sourceLanguage,
            targetLanguage: prior.targetLanguage,
            sourceText: sourceTranscript.text,
            translatedText: text,
            type: .userEditedTranslation,
            alignment: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            createdAt: changedAt,
            createdBy: .user,
            classification: prior.revision.dataClassification,
            generation: nil,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            supersedes: prior.revision.revisionID,
            extraInputs: [priorReference],
            reviewStatus: .confirmed,
            userConfirmed: true,
            semanticHash: try draft.calculatedSemanticContentHash()
        )
    }

    public static func replacingTranscript(
        in manifest: TranscriptCoverageManifest,
        oldRevisionID: RevisionID,
        with corrected: TranscriptSegmentV1,
        at changedAt: UTCInstant
    ) throws -> TranscriptCoverageManifest {
        let reference = try SemanticRevisionReference(
            logicalID: corrected.segmentID,
            revisionID: corrected.revision.revisionID
        )
        var didReplace = false
        let chunks = try manifest.chunks.map { chunk in
            guard chunk.reviewedSegmentRevision?.revisionID == oldRevisionID else { return chunk }
            didReplace = true
            return try TranscriptChunkCoverage(
                index: chunk.index,
                coreRange: chunk.coreRange,
                physicalRange: chunk.physicalRange,
                disposition: .transcribed,
                attemptCount: chunk.attemptCount,
                provider: chunk.provider,
                machineSegmentRevision: chunk.machineSegmentRevision,
                reviewedSegmentRevision: reference,
                translationRevision: nil
            )
        }
        guard didReplace else { throw TranscriptCoverageError.publicationConflict }
        return try TranscriptCoverageManifest(
            transcriptSetID: manifest.transcriptSetID,
            supersedesManifestID: manifest.manifestID,
            meetingID: manifest.meetingID,
            canonicalSourceRevision: manifest.canonicalSourceRevision,
            canonicalFrameCount: manifest.canonicalFrameCount,
            transcriptionRoute: manifest.transcriptionRoute,
            translationRoute: manifest.translationRoute,
            status: .published,
            chunks: chunks,
            createdAt: changedAt
        )
    }

    public static func replacingTranslation(
        in manifest: TranscriptCoverageManifest,
        oldRevisionID: RevisionID,
        with corrected: TranslationSegmentV1,
        at changedAt: UTCInstant
    ) throws -> TranscriptCoverageManifest {
        let reference = try SemanticRevisionReference(
            logicalID: corrected.translationID,
            revisionID: corrected.revision.revisionID
        )
        var didReplace = false
        let chunks = try manifest.chunks.map { chunk in
            guard chunk.translationRevision?.revisionID == oldRevisionID else { return chunk }
            didReplace = true
            return try TranscriptChunkCoverage(
                index: chunk.index,
                coreRange: chunk.coreRange,
                physicalRange: chunk.physicalRange,
                disposition: chunk.disposition,
                attemptCount: chunk.attemptCount,
                provider: chunk.provider,
                machineSegmentRevision: chunk.machineSegmentRevision,
                reviewedSegmentRevision: chunk.reviewedSegmentRevision,
                translationRevision: reference
            )
        }
        guard didReplace else { throw TranscriptCoverageError.publicationConflict }
        return try TranscriptCoverageManifest(
            transcriptSetID: manifest.transcriptSetID,
            supersedesManifestID: manifest.manifestID,
            meetingID: manifest.meetingID,
            canonicalSourceRevision: manifest.canonicalSourceRevision,
            canonicalFrameCount: manifest.canonicalFrameCount,
            transcriptionRoute: manifest.transcriptionRoute,
            translationRoute: manifest.translationRoute,
            status: .published,
            chunks: chunks,
            createdAt: changedAt
        )
    }

    public static func speakerConfirmation(
        transcript: TranscriptSegmentV1,
        displayName: String,
        changedAt: UTCInstant
    ) throws -> (ActorV1, SpeakingCapacityV1, EvidenceRefV1, SpeakerAssignmentV1) {
        try speakerConfirmation(
            transcript: transcript,
            displayName: displayName,
            changedAt: changedAt,
            identifiers: SpeakerConfirmationIdentifiers()
        )
    }

    static func speakerConfirmation(
        transcript: TranscriptSegmentV1,
        displayName: String,
        changedAt: UTCInstant,
        identifiers: SpeakerConfirmationIdentifiers
    ) throws -> (ActorV1, SpeakingCapacityV1, EvidenceRefV1, SpeakerAssignmentV1) {
        let transcriptReference = try SemanticRevisionReference(
            logicalID: transcript.segmentID,
            revisionID: transcript.revision.revisionID
        )
        let actorID = identifiers.actorID
        let actorRevisionID = identifiers.actorRevisionID
        let actorDraft = try actor(
            logicalID: actorID,
            revisionID: actorRevisionID,
            displayName: displayName,
            createdAt: changedAt,
            classification: transcript.revision.dataClassification,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil
        )
        let actor = try actor(
            logicalID: actorID,
            revisionID: actorRevisionID,
            displayName: displayName,
            createdAt: changedAt,
            classification: transcript.revision.dataClassification,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            semanticHash: try actorDraft.calculatedSemanticContentHash()
        )
        let actorReference = try SemanticRevisionReference(
            logicalID: actor.actorID,
            revisionID: actor.revision.revisionID
        )

        let capacityID = identifiers.capacityID
        let capacityRevisionID = identifiers.capacityRevisionID
        let capacityDraft = try capacity(
            logicalID: capacityID,
            revisionID: capacityRevisionID,
            meetingID: transcript.meetingID,
            actorReference: actorReference,
            displayName: displayName,
            createdAt: changedAt,
            classification: transcript.revision.dataClassification,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil
        )
        let capacity = try capacity(
            logicalID: capacityID,
            revisionID: capacityRevisionID,
            meetingID: transcript.meetingID,
            actorReference: actorReference,
            displayName: displayName,
            createdAt: changedAt,
            classification: transcript.revision.dataClassification,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            semanticHash: try capacityDraft.calculatedSemanticContentHash()
        )
        let capacityReference = try SemanticRevisionReference(
            logicalID: capacity.capacityID,
            revisionID: capacity.revision.revisionID
        )

        let evidenceID = identifiers.evidenceID
        let evidenceRevisionID = identifiers.evidenceRevisionID
        let evidenceDraft = try evidence(
            logicalID: evidenceID,
            revisionID: evidenceRevisionID,
            transcript: transcript,
            transcriptReference: transcriptReference,
            createdAt: changedAt,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil
        )
        let evidence = try evidence(
            logicalID: evidenceID,
            revisionID: evidenceRevisionID,
            transcript: transcript,
            transcriptReference: transcriptReference,
            createdAt: changedAt,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            semanticHash: try evidenceDraft.calculatedSemanticContentHash()
        )
        let evidenceReference = try SemanticRevisionReference(
            logicalID: evidence.evidenceID,
            revisionID: evidence.revision.revisionID
        )

        let assignmentID = identifiers.assignmentID
        let assignmentRevisionID = identifiers.assignmentRevisionID
        let assignmentDraft = try assignment(
            logicalID: assignmentID,
            revisionID: assignmentRevisionID,
            transcript: transcript,
            transcriptReference: transcriptReference,
            actorReference: actorReference,
            capacityReference: capacityReference,
            evidenceReference: evidenceReference,
            createdAt: changedAt,
            lifecycle: .draft,
            validation: .notValidated,
            publishedAt: nil,
            semanticHash: nil
        )
        let assignment = try assignment(
            logicalID: assignmentID,
            revisionID: assignmentRevisionID,
            transcript: transcript,
            transcriptReference: transcriptReference,
            actorReference: actorReference,
            capacityReference: capacityReference,
            evidenceReference: evidenceReference,
            createdAt: changedAt,
            lifecycle: .published,
            validation: .valid,
            publishedAt: changedAt,
            semanticHash: try assignmentDraft.calculatedSemanticContentHash()
        )
        return (actor, capacity, evidence, assignment)
    }

    private static func transcript(
        logicalID: TranscriptSegmentID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        canonicalSource: SemanticRevisionReference,
        speechSourceKind: SpeechSourceKind,
        coreRange: MediaFrameRange,
        language: LanguageTag,
        text: String,
        confidence: ConfidenceScore,
        createdAt: UTCInstant,
        createdBy: CreationActor,
        classification: DataClassification,
        generation: GenerationMetadata?,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        supersedes: RevisionID?,
        extraInputs: [SemanticRevisionReference],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool,
        semanticHash: ContentDigest?,
        exactTimeRange: MediaTimeRange? = nil
    ) throws -> TranscriptSegmentV1 {
        let provenance: TranscriptSourceProvenance = switch speechSourceKind {
        case .originalSpeakerAudio: .originalSpeakerAudio(sourceAssetRevision: canonicalSource)
        case .simultaneousInterpretation: .simultaneousInterpretation(sourceAssetRevision: canonicalSource)
        case .translatedAudioTrack: .translatedAudioTrack(sourceAssetRevision: canonicalSource)
        case .unknown, .unrecognized: .unknown(sourceAssetRevision: canonicalSource)
        }
        return try TranscriptSegmentV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: createdBy,
                publishedAt: publishedAt,
                supersedesRevisionID: supersedes,
                inputRevisions: [canonicalSource] + extraInputs,
                sourceAssetRevisions: [canonicalSource],
                dataClassification: classification,
                generationMetadata: generation,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            sourceProvenance: provenance,
            timeRange: exactTimeRange ?? timeRange(for: coreRange),
            detectedLanguage: language,
            text: text,
            confidence: confidence,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    private static func translation(
        logicalID: TranslationSegmentID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        sourceReference: SemanticRevisionReference,
        canonicalSource: SemanticRevisionReference,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag,
        sourceText: String,
        translatedText: String,
        type: TranslationType,
        alignment: AlignmentStatus,
        confidence: ConfidenceScore,
        createdAt: UTCInstant,
        createdBy: CreationActor,
        classification: DataClassification,
        generation: GenerationMetadata?,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        supersedes: RevisionID?,
        extraInputs: [SemanticRevisionReference],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool,
        semanticHash: ContentDigest?
    ) throws -> TranslationSegmentV1 {
        try TranslationSegmentV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: createdBy,
                publishedAt: publishedAt,
                supersedesRevisionID: supersedes,
                inputRevisions: [sourceReference] + extraInputs,
                sourceAssetRevisions: [canonicalSource],
                dataClassification: classification,
                generationMetadata: generation,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            sourceSegmentRevision: sourceReference,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceTextHash: TranslationSegmentV1.calculateSourceTextHash(sourceText),
            translatedText: translatedText,
            translationType: type,
            alignmentStatus: alignment,
            confidence: confidence,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    private static func actor(
        logicalID: ActorID,
        revisionID: RevisionID,
        displayName: String,
        createdAt: UTCInstant,
        classification: DataClassification,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        semanticHash: ContentDigest?
    ) throws -> ActorV1 {
        try ActorV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: .user,
                publishedAt: publishedAt,
                dataClassification: classification,
                semanticContentHash: semanticHash
            ),
            identity: .person(displayName: displayName, personName: displayName),
            canonicalAliases: [displayName],
            reviewStatus: .confirmed,
            userConfirmed: true
        )
    }

    private static func capacity(
        logicalID: SpeakingCapacityID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        actorReference: SemanticRevisionReference,
        displayName: String,
        createdAt: UTCInstant,
        classification: DataClassification,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        semanticHash: ContentDigest?
    ) throws -> SpeakingCapacityV1 {
        try SpeakingCapacityV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: .user,
                publishedAt: publishedAt,
                inputRevisions: [actorReference],
                dataClassification: classification,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            speakerActorRevision: actorReference,
            meetingRole: .other,
            capacityLabel: displayName,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
    }

    private static func evidence(
        logicalID: EvidenceID,
        revisionID: RevisionID,
        transcript: TranscriptSegmentV1,
        transcriptReference: SemanticRevisionReference,
        createdAt: UTCInstant,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        semanticHash: ContentDigest?
    ) throws -> EvidenceRefV1 {
        try EvidenceRefV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: .user,
                publishedAt: publishedAt,
                inputRevisions: [transcriptReference],
                sourceAssetRevisions: [transcript.sourceAssetRevision],
                dataClassification: transcript.revision.dataClassification,
                semanticContentHash: semanticHash
            ),
            location: .transcriptSegment(
                source: transcriptReference,
                textRange: try UTF8TextRange(
                    startOffset: 0,
                    length: UInt64(transcript.text.utf8.count)
                )
            ),
            excerpt: EvidenceExcerpt(
                text: transcript.text,
                language: transcript.detectedLanguage,
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(millionths: 1_000_000)
        )
    }

    private static func assignment(
        logicalID: SpeakerAssignmentID,
        revisionID: RevisionID,
        transcript: TranscriptSegmentV1,
        transcriptReference: SemanticRevisionReference,
        actorReference: SemanticRevisionReference,
        capacityReference: SemanticRevisionReference,
        evidenceReference: SemanticRevisionReference,
        createdAt: UTCInstant,
        lifecycle: LifecycleStatus,
        validation: ValidationState,
        publishedAt: UTCInstant?,
        semanticHash: ContentDigest?
    ) throws -> SpeakerAssignmentV1 {
        try SpeakerAssignmentV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycle,
                validationState: validation,
                createdAt: createdAt,
                createdBy: .user,
                publishedAt: publishedAt,
                inputRevisions: [transcriptReference, actorReference, capacityReference],
                sourceAssetRevisions: [transcript.sourceAssetRevision],
                evidenceRevisions: [evidenceReference],
                dataClassification: transcript.revision.dataClassification,
                semanticContentHash: semanticHash
            ),
            meetingID: transcript.meetingID,
            transcriptSegmentRevisions: [transcriptReference],
            actorRevision: actorReference,
            speakingCapacityRevision: capacityReference,
            confidence: ConfidenceScore(millionths: 1_000_000),
            certainty: .confirmed,
            assignmentSources: [.userCorrection],
            reviewStatus: .confirmed,
            userConfirmed: true
        )
    }

    private static func generationMetadata(
        provider: ProviderMetadata,
        component: String,
        createdAt: UTCInstant
    ) throws -> GenerationMetadata {
        try GenerationMetadata(
            provider: provider,
            promptModuleVersions: [VersionedComponent(identifier: component, version: "1")],
            outputSchemaVersion: .v1,
            templateVersion: "task005b-v1",
            generatedAt: createdAt,
            privacyRoute: .localOnly
        )
    }

    private static func timeRange(for frames: MediaFrameRange) throws -> MediaTimeRange {
        try MediaTimeRange(
            startMilliseconds: milliseconds(frames.startFrame),
            endMilliseconds: milliseconds(frames.endFrame)
        )
    }

    private static func frames(for range: MediaTimeRange) throws -> MediaFrameRange {
        try MediaFrameRange(
            startFrame: UInt64(range.startMilliseconds) * 16,
            endFrame: UInt64(range.endMilliseconds) * 16
        )
    }

    private static func milliseconds(_ frame: UInt64) -> Int64 {
        Int64(frame / 16)
    }
}
