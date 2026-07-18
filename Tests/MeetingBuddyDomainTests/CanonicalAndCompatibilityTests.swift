import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct CanonicalAndCompatibilityTests {
    @Test
    func sourceAssetCanonicalBytesAreFrozen() throws {
        let data = try CanonicalJSON.encodeValidated(TestFixtures.sourceAsset())
        let expected = #"{"acquired_at":1699999999000,"acquisition_method":"user_selected_file","asset_type":"audio","byte_size":123456,"language":"en","managed_storage_reference":{"storage_object_id":"00000000-0000-0000-0000-000000000004"},"media":{"channel_layout":"stereo","codec":"mp3","container_format":"mp3","duration_milliseconds":120000,"language_track":"en","sample_rate_hertz":48000,"speech_source_kind":"original_speaker_audio"},"meeting_id":"00000000-0000-0000-0000-000000000003","mime_type":"audio/mpeg","origin_type":"local_import","retention_class":"permanent","revision":{"created_at":1700000000000,"created_by":"import_process","data_classification":"internal","evidence_revisions":[],"input_revisions":[],"lifecycle_status":"draft","logical_id":"00000000-0000-0000-0000-000000000001","object_type":"source_asset","revision_id":"00000000-0000-0000-0000-000000000002","schema_version":{"major":1,"minor":0},"source_asset_revisions":[],"validation_state":"not_validated"},"source_content_hash":{"algorithm":"sha256","lowercase_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}"#
        let repeated = try CanonicalJSON.encodeValidated(TestFixtures.sourceAsset())

        #expect(String(decoding: data, as: UTF8.self) == expected)
        #expect(data == repeated)
    }

    @Test
    func inputWhitespaceAndKeyOrderDoNotChangeCanonicalOutput() throws {
        let canonical = try CanonicalJSON.encodeValidated(TestFixtures.sourceAsset())
        let object = try #require(
            try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        let decoded = try CanonicalJSON.decodeValidated(SourceAssetV1.self, from: pretty)

        #expect(try CanonicalJSON.encodeValidated(decoded) == canonical)
    }

    @Test
    func unknownAdditiveObjectFieldIsIgnoredSafely() throws {
        let canonical = try CanonicalJSON.encodeValidated(TestFixtures.sourceAsset())
        var object = try #require(
            try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["future_additive_field"] = ["value": true]
        let futureData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try CanonicalJSON.decodeValidated(SourceAssetV1.self, from: futureData)
        let expected = try TestFixtures.sourceAsset()
        #expect(decoded == expected)
        #expect(try CanonicalJSON.encodeValidated(decoded) == canonical)
    }

    @Test
    func decodedReferenceCollectionsAreCanonicalized() throws {
        let first = try SemanticRevisionReference(
            logicalID: SourceAssetID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!),
            revisionID: RevisionID(UUID(uuidString: "10000000-0000-0000-0000-000000000002")!)
        )
        let second = try SemanticRevisionReference(
            logicalID: SourceAssetID(UUID(uuidString: "20000000-0000-0000-0000-000000000001")!),
            revisionID: RevisionID(UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        )
        let envelope = try TestFixtures.sourceEnvelope(inputRevisions: [first, second])
        let canonical = try CanonicalJSON.encodeValidated(envelope)
        var object = try #require(
            try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["input_revisions"] = Array(
            try #require(object["input_revisions"] as? [Any]).reversed()
        )
        let reordered = try JSONSerialization.data(withJSONObject: object)

        let decoded = try CanonicalJSON.decodeValidated(
            RevisionEnvelope<SourceAssetIDTag>.self,
            from: reordered
        )
        #expect(decoded.inputRevisions == [first, second])
        #expect(try CanonicalJSON.encodeValidated(decoded) == canonical)
    }

    @Test
    func missingRequiredV1FieldIsRejected() throws {
        let canonical = try CanonicalJSON.encodeValidated(TestFixtures.sourceAsset())
        var object = try #require(
            try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object.removeValue(forKey: "meeting_id")
        let incomplete = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try CanonicalJSON.decode(SourceAssetV1.self, from: incomplete)
        }
    }

    @Test
    func unsupportedFutureSchemaMajorFailsClosedAtCompositeDecode() throws {
        let canonical = try CanonicalJSON.encode(TestFixtures.sourceAsset())
        let future = Data(
            String(decoding: canonical, as: UTF8.self)
                .replacingOccurrences(of: #""schema_version":{"major":1"#, with: #""schema_version":{"major":2"#)
                .utf8
        )

        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(SourceAssetV1.self, from: future)
        }
    }
}
