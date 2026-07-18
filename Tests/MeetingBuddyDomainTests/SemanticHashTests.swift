import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct SemanticHashTests {
    @Test
    func semanticHashesAreFrozenAndRepeatable() throws {
        let source = try TestFixtures.sourceAsset()
        let evidence = try TestFixtures.evidenceRef()

        #expect(
            try source.calculatedSemanticContentHash().lowercaseHex
                == "4799c54b9ce934384a00f57331315f4216e69f50ff8f0e1697ae12904e96fcad"
        )
        #expect(
            try evidence.calculatedSemanticContentHash().lowercaseHex
                == "3999e9c9c54ef2f4505a33793d190f9f969273a3a36d8b822833e4043256aa18"
        )
        #expect(
            try source.calculatedSemanticContentHash()
                == source.calculatedSemanticContentHash()
        )
    }

    @Test
    func publishedSourceRequiresItsCalculatedSemanticHash() throws {
        let draft = try TestFixtures.sourceAsset()
        let calculated = try draft.calculatedSemanticContentHash()
        let publishedEnvelope = try TestFixtures.sourceEnvelope(
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            semanticContentHash: calculated
        )
        let published = try TestFixtures.sourceAsset(revision: publishedEnvelope)

        try published.validate()
        #expect(published.revision.semanticContentHash == calculated)

        let mismatchedEnvelope = try TestFixtures.sourceEnvelope(
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            semanticContentHash: TestFixtures.semanticDigest
        )
        #expect(throws: DomainValidationError.self) {
            try TestFixtures.sourceAsset(revision: mismatchedEnvelope)
        }
    }

    @Test
    func publishedEvidenceRequiresItsCalculatedSemanticHash() throws {
        let draft = try TestFixtures.evidenceRef()
        let calculated = try draft.calculatedSemanticContentHash()
        let publishedEnvelope = try TestFixtures.evidenceEnvelope(
            source: draft.source,
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            semanticContentHash: calculated
        )
        let published = try TestFixtures.evidenceRef(
            location: draft.location,
            excerptText: draft.excerpt.text,
            revision: publishedEnvelope
        )

        try published.validate()
        #expect(published.revision.semanticContentHash == calculated)

        let mismatchedEnvelope = try TestFixtures.evidenceEnvelope(
            source: draft.source,
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            semanticContentHash: TestFixtures.semanticDigest
        )
        #expect(throws: DomainValidationError.self) {
            try TestFixtures.evidenceRef(
                location: draft.location,
                excerptText: draft.excerpt.text,
                revision: mismatchedEnvelope
            )
        }
    }

    @Test
    func evidenceCanonicalBytesAreFrozen() throws {
        let data = try CanonicalJSON.encodeValidated(TestFixtures.evidenceRef())
        let expected = #"{"confidence":900000,"excerpt":"Synthetic source excerpt.","excerpt_language":"en","location":{"kind":"media_time_range","media_time_range":{"end_milliseconds":2500,"start_milliseconds":1000},"source":{"logical_id":"00000000-0000-0000-0000-000000000001","object_type":"source_asset","revision_id":"00000000-0000-0000-0000-000000000002"}},"revision":{"created_at":1700000000000,"created_by":"application","data_classification":"internal","evidence_revisions":[],"input_revisions":[{"logical_id":"00000000-0000-0000-0000-000000000001","object_type":"source_asset","revision_id":"00000000-0000-0000-0000-000000000002"}],"lifecycle_status":"draft","logical_id":"00000000-0000-0000-0000-000000000005","object_type":"evidence_ref","revision_id":"00000000-0000-0000-0000-000000000006","schema_version":{"major":1,"minor":0},"source_asset_revisions":[{"logical_id":"00000000-0000-0000-0000-000000000001","object_type":"source_asset","revision_id":"00000000-0000-0000-0000-000000000002"}],"validation_state":"not_validated"},"translation_status":"source_only"}"#

        #expect(String(decoding: data, as: UTF8.self) == expected)
    }
}
