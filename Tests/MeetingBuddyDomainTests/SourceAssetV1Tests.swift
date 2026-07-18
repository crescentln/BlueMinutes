import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct SourceAssetV1Tests {
    @Test
    func localAudioFixtureValidatesAndRoundTrips() throws {
        let asset = try TestFixtures.sourceAsset()
        let data = try CanonicalJSON.encodeValidated(asset)
        let decoded = try CanonicalJSON.decodeValidated(SourceAssetV1.self, from: data)

        #expect(decoded == asset)
        #expect(decoded.assetID == TestFixtures.sourceAssetID)
        #expect(decoded.sourceContentHash != decoded.revision.semanticContentHash)
    }

    @Test
    func localImportRequiresManagedReferenceAndMatchingMethod() throws {
        let error = capturedValidationError {
            _ = try SourceAssetV1(
                revision: TestFixtures.sourceEnvelope(),
                meetingID: TestFixtures.meetingID,
                assetType: .document,
                originType: .localImport,
                sourceContentHash: TestFixtures.sourceDigest,
                mimeType: MIMEType("application/pdf"),
                byteSize: 1,
                acquisitionMethod: .generated,
                acquiredAt: TestFixtures.acquiredAt,
                retentionClass: .permanent
            )
        }

        #expect(error?.issues.map(\.path) == ["managed_storage_reference", "acquisition_method"])
    }

    @Test
    func approvedWebSourceRequiresHTTPSURLAndMatchingMethod() throws {
        let valid = try SourceAssetV1(
            revision: TestFixtures.sourceEnvelope(),
            meetingID: TestFixtures.meetingID,
            assetType: .document,
            originType: .approvedWebSource,
            sourceURL: HTTPSURL("https://example.invalid/statement.pdf"),
            managedStorageReference: ManagedAssetReference(
                storageObjectID: TestFixtures.storageObjectID
            ),
            sourceContentHash: TestFixtures.sourceDigest,
            mimeType: MIMEType("application/pdf"),
            byteSize: 42,
            language: LanguageTag("en"),
            acquisitionMethod: .approvedHTTPSDownload,
            acquiredAt: TestFixtures.acquiredAt,
            retentionClass: .permanent
        )

        try valid.validate()

        let missingStorage = capturedValidationError {
            _ = try SourceAssetV1(
                revision: TestFixtures.sourceEnvelope(),
                meetingID: TestFixtures.meetingID,
                assetType: .document,
                originType: .approvedWebSource,
                sourceURL: HTTPSURL("https://example.invalid/statement.pdf"),
                sourceContentHash: TestFixtures.sourceDigest,
                mimeType: MIMEType("application/pdf"),
                byteSize: 42,
                acquisitionMethod: .approvedHTTPSDownload,
                acquiredAt: TestFixtures.acquiredAt,
                retentionClass: .permanent
            )
        }
        #expect(missingStorage?.issues.map(\.path) == ["managed_storage_reference"])
    }

    @Test
    func mediaInspectionIsOptionalButAssetMustBeNonEmpty() throws {
        let noMedia = try SourceAssetV1(
            revision: TestFixtures.sourceEnvelope(),
            meetingID: TestFixtures.meetingID,
            assetType: .audio,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(storageObjectID: TestFixtures.storageObjectID),
            sourceContentHash: TestFixtures.sourceDigest,
            mimeType: MIMEType("audio/mpeg"),
            byteSize: 1,
            acquisitionMethod: .userSelectedFile,
            acquiredAt: TestFixtures.acquiredAt,
            retentionClass: .permanent
        )
        try noMedia.validate()

        let error = capturedValidationError {
            _ = try SourceAssetV1(
                revision: TestFixtures.sourceEnvelope(),
                meetingID: TestFixtures.meetingID,
                assetType: .audio,
                originType: .localImport,
                managedStorageReference: ManagedAssetReference(storageObjectID: TestFixtures.storageObjectID),
                sourceContentHash: TestFixtures.sourceDigest,
                mimeType: MIMEType("audio/mpeg"),
                byteSize: 0,
                acquisitionMethod: .userSelectedFile,
                acquiredAt: TestFixtures.acquiredAt,
                retentionClass: .permanent
            )
        }

        #expect(error?.issues.map(\.path) == ["byte_size"])

        #expect(throws: DomainValidationError.self) {
            try MediaProvenance(
                durationMilliseconds: 1,
                containerFormat: " mp3",
                speechSourceKind: .originalSpeakerAudio
            )
        }
    }

    @Test
    func unknownClassificationIsPreservedStandaloneButCompositeDecodeFailsClosed() throws {
        let asset = try TestFixtures.sourceAsset()
        let original = try CanonicalJSON.encode(asset)
        let unknown = Data(
            String(decoding: original, as: UTF8.self)
                .replacingOccurrences(of: #""data_classification":"internal""#, with: #""data_classification":"future_secret""#)
                .utf8
        )

        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(SourceAssetV1.self, from: unknown)
        }
    }
}
