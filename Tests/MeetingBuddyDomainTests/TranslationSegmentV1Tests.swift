import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct TranslationSegmentV1Tests {
    @Test
    func machineTranslationRoundTripsWithCompleteProviderProvenance() throws {
        let translation = try Task003BFixtures.translation()
        let data = try CanonicalJSON.encodeValidated(translation)
        let decoded = try CanonicalJSON.decodeValidated(TranslationSegmentV1.self, from: data)

        #expect(decoded == translation)
        #expect(decoded.provider?.providerIdentifier == "synthetic-local-provider")
        #expect(decoded.revision.generationMetadata?.templateVersion == "translation-contract-v1")
        #expect(decoded.translationStatus == .machineTranslated)
        #expect(!decoded.isOriginalVerbatim)
    }

    @Test
    func translationRetainsExactSourceHashAndDoesNotOverwriteTranscript() throws {
        let transcript = try Task003BFixtures.transcript()
        let translation = try Task003BFixtures.translation(sourceTranscript: transcript)
        let sourceBefore = transcript.text

        try InputContractGraphValidation.validate(
            translation: translation,
            sourceTranscript: transcript
        )
        #expect(transcript.text == sourceBefore)
        #expect(translation.translatedText != transcript.text)

        let changedTranscript = try Task003BFixtures.transcript(text: transcript.text + " Changed.")
        #expect(throws: DomainValidationError.self) {
            try InputContractGraphValidation.validate(
                translation: translation,
                sourceTranscript: changedTranscript
            )
        }
    }

    @Test
    func machineTranslationRequiresGenerationMetadata() throws {
        let source = try Task003BFixtures.reference(
            Task003BFixtures.transcriptID,
            Task003BFixtures.transcriptRevisionID
        )
        let envelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: Task003BFixtures.translationID,
            revisionID: Task003BFixtures.translationRevisionID,
            createdBy: .application,
            inputRevisions: [source]
        )

        #expect(throws: DomainValidationError.self) {
            _ = try Task003BFixtures.translation(revision: envelope)
        }
    }

    @Test
    func userEditedTranslationRequiresExactPriorRevisionAndSupersession() throws {
        let sourceTranscript = try Task003BFixtures.transcript()
        let original = try Task003BFixtures.translation(sourceTranscript: sourceTranscript)
        let source = original.sourceSegmentRevision
        let prior = try Task003BFixtures.reference(
            original.translationID,
            original.revision.revisionID
        )
        let editedRevisionID = Task003BFixtures.id(121, RevisionID.self)
        let editedEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: original.translationID,
            revisionID: editedRevisionID,
            createdBy: .user,
            supersedesRevisionID: original.revision.revisionID,
            inputRevisions: [source, prior]
        )
        let edited = try TranslationSegmentV1(
            revision: editedEnvelope,
            meetingID: original.meetingID,
            sourceSegmentRevision: source,
            sourceLanguage: original.sourceLanguage,
            targetLanguage: original.targetLanguage,
            sourceTextHash: original.sourceTextHash,
            translatedText: "用户修订后的合成译文。",
            translationType: .userEditedTranslation,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            reviewStatus: .confirmed,
            userConfirmed: true
        )

        try edited.validate()
        #expect(original.revision.supersedesRevisionID == nil)
        #expect(edited.revision.supersedesRevisionID == original.revision.revisionID)
        #expect(throws: DomainValidationError.self) {
            try InputContractGraphValidation.validate(
                translation: edited,
                sourceTranscript: sourceTranscript
            )
        }
        try InputContractGraphValidation.validate(
            translation: edited,
            sourceTranscript: sourceTranscript,
            additionalDependencies: [
                ResolvedDependencyClassification(resolving: original)
            ]
        )

        let missingPriorEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: original.translationID,
            revisionID: editedRevisionID,
            createdBy: .user,
            supersedesRevisionID: original.revision.revisionID,
            inputRevisions: [source]
        )
        #expect(throws: DomainValidationError.self) {
            _ = try TranslationSegmentV1(
                revision: missingPriorEnvelope,
                meetingID: original.meetingID,
                sourceSegmentRevision: source,
                sourceLanguage: original.sourceLanguage,
                targetLanguage: original.targetLanguage,
                sourceTextHash: original.sourceTextHash,
                translatedText: "用户修订后的合成译文。",
                translationType: .userEditedTranslation,
                alignmentStatus: .aligned,
                confidence: ConfidenceScore(millionths: 1_000_000),
                reviewStatus: .confirmed,
                userConfirmed: true
            )
        }

        let crossLogicalPrior = try Task003BFixtures.reference(
            Task003BFixtures.id(122, TranslationSegmentID.self),
            original.revision.revisionID
        )
        let crossLogicalEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: original.translationID,
            revisionID: editedRevisionID,
            createdBy: .user,
            supersedesRevisionID: original.revision.revisionID,
            inputRevisions: [source, crossLogicalPrior]
        )
        #expect(throws: DomainValidationError.self) {
            _ = try TranslationSegmentV1(
                revision: crossLogicalEnvelope,
                meetingID: original.meetingID,
                sourceSegmentRevision: source,
                sourceLanguage: original.sourceLanguage,
                targetLanguage: original.targetLanguage,
                sourceTextHash: original.sourceTextHash,
                translatedText: "跨逻辑对象的伪修订。",
                translationType: .userEditedTranslation,
                alignmentStatus: .aligned,
                confidence: ConfidenceScore(millionths: 1_000_000),
                reviewStatus: .confirmed,
                userConfirmed: true
            )
        }

        let restrictedOriginalEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: original.translationID,
            revisionID: original.revision.revisionID,
            createdBy: .provider,
            inputRevisions: [source],
            classification: .restricted,
            generationMetadata: Task003BFixtures.generationMetadata()
        )
        let restrictedOriginal = try Task003BFixtures.translation(
            revision: restrictedOriginalEnvelope,
            sourceTranscript: sourceTranscript
        )
        let underclassifiedEditEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: original.translationID,
            revisionID: editedRevisionID,
            createdBy: .user,
            supersedesRevisionID: restrictedOriginal.revision.revisionID,
            inputRevisions: [source, prior],
            classification: .internal
        )
        let underclassifiedEdit = try TranslationSegmentV1(
            revision: underclassifiedEditEnvelope,
            meetingID: original.meetingID,
            sourceSegmentRevision: source,
            sourceLanguage: original.sourceLanguage,
            targetLanguage: original.targetLanguage,
            sourceTextHash: original.sourceTextHash,
            translatedText: "受限前一修订的合成用户修订。",
            translationType: .userEditedTranslation,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 1_000_000),
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        #expect(throws: DomainValidationError.self) {
            try InputContractGraphValidation.validate(
                translation: underclassifiedEdit,
                sourceTranscript: sourceTranscript,
                additionalDependencies: [
                    ResolvedDependencyClassification(resolving: restrictedOriginal)
                ]
            )
        }
    }

    @Test
    func simultaneousInterpretationTranslationTypeNeverClaimsOriginalWording() throws {
        let source = try Task003BFixtures.transcript()
        let envelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: Task003BFixtures.translationID,
            revisionID: Task003BFixtures.translationRevisionID,
            inputRevisions: [try Task003BFixtures.reference(source.segmentID, source.revision.revisionID)]
        )
        let interpretationText = try Task003BFixtures.translation(
            revision: envelope,
            sourceTranscript: source,
            translationType: .simultaneousInterpretationTranscript
        )

        #expect(interpretationText.translationStatus == .simultaneousInterpretation)
        #expect(!interpretationText.isOriginalVerbatim)
    }

    @Test
    func publishedTranslationRejectsMismatchedSemanticHash() throws {
        let draft = try Task003BFixtures.translation()
        let source = draft.sourceSegmentRevision
        let validEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: draft.translationID,
            revisionID: draft.revision.revisionID,
            lifecycleStatus: .published,
            validationState: .valid,
            createdBy: .provider,
            publishedAt: TestFixtures.publishedAt,
            inputRevisions: [source],
            generationMetadata: Task003BFixtures.generationMetadata(),
            semanticContentHash: draft.calculatedSemanticContentHash()
        )
        let published = try Task003BFixtures.translation(revision: validEnvelope)
        try published.validate()

        let badEnvelope: RevisionEnvelope<TranslationSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: draft.translationID,
            revisionID: draft.revision.revisionID,
            lifecycleStatus: .published,
            validationState: .valid,
            createdBy: .provider,
            publishedAt: TestFixtures.publishedAt,
            inputRevisions: [source],
            generationMetadata: Task003BFixtures.generationMetadata(),
            semanticContentHash: TestFixtures.semanticDigest
        )
        #expect(throws: DomainValidationError.self) {
            _ = try Task003BFixtures.translation(revision: badEnvelope)
        }
    }

    @Test
    func directDecoderRejectsUnknownTranslationType() throws {
        let data = try CanonicalJSON.encode(Task003BFixtures.translation())
        let future = Data(
            String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: #""translation_type":"machine_translation""#, with: #""translation_type":"future_translation""#)
                .utf8
        )

        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(TranslationSegmentV1.self, from: future)
        }
    }
}
