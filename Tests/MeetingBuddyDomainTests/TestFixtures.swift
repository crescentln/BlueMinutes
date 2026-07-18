import Foundation
@testable import MeetingBuddyDomain

enum TestFixtures {
    static let sourceAssetID = SourceAssetID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    static let sourceRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    static let meetingID = MeetingID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
    static let storageObjectID = StorageObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
    static let evidenceID = EvidenceID(UUID(uuidString: "00000000-0000-0000-0000-000000000005")!)
    static let evidenceRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000006")!)
    static let replacementSourceRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000007")!)
    static let transcriptSegmentID = TranscriptSegmentID(UUID(uuidString: "00000000-0000-0000-0000-000000000008")!)
    static let transcriptRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000009")!)
    static let noteID = UserConfirmedNoteID(UUID(uuidString: "00000000-0000-0000-0000-000000000010")!)
    static let noteRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
    static let meetingRevisionID = RevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000012")!)

    static let createdAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_700_000_000_000)
    static let acquiredAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_699_999_999_000)
    static let publishedAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_700_000_001_000)
    static let sourceDigest = try! ContentDigest(
        algorithm: .sha256,
        lowercaseHex: String(repeating: "a", count: 64)
    )
    static let semanticDigest = try! ContentDigest(
        algorithm: .sha256,
        lowercaseHex: String(repeating: "b", count: 64)
    )

    static func sourceReference() throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: sourceAssetID,
            revisionID: sourceRevisionID
        )
    }

    static func transcriptReference() throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: transcriptSegmentID,
            revisionID: transcriptRevisionID
        )
    }

    static func noteReference() throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: noteID,
            revisionID: noteRevisionID
        )
    }

    static func meetingReference() throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: meetingID,
            revisionID: meetingRevisionID
        )
    }

    static func sourceEnvelope(
        revisionID: RevisionID = sourceRevisionID,
        lifecycleStatus: LifecycleStatus = .draft,
        validationState: ValidationState = .notValidated,
        publishedAt: UTCInstant? = nil,
        supersedesRevisionID: RevisionID? = nil,
        inputRevisions: [SemanticRevisionReference] = [],
        classification: DataClassification = .internal,
        semanticContentHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<SourceAssetIDTag> {
        try RevisionEnvelope(
            logicalID: sourceAssetID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: lifecycleStatus,
            validationState: validationState,
            createdAt: createdAt,
            createdBy: .importProcess,
            publishedAt: publishedAt,
            supersedesRevisionID: supersedesRevisionID,
            inputRevisions: inputRevisions,
            dataClassification: classification,
            semanticContentHash: semanticContentHash
        )
    }

    static func sourceAsset(
        revision suppliedRevision: RevisionEnvelope<SourceAssetIDTag>? = nil,
        media: MediaProvenance? = nil
    ) throws -> SourceAssetV1 {
        let revision = try suppliedRevision ?? sourceEnvelope()
        let media = try media ?? MediaProvenance(
            durationMilliseconds: 120_000,
            containerFormat: "mp3",
            codec: "mp3",
            sampleRateHertz: 48_000,
            channelLayout: "stereo",
            languageTrack: LanguageTag("en"),
            speechSourceKind: .originalSpeakerAudio
        )
        return try SourceAssetV1(
            revision: revision,
            meetingID: meetingID,
            assetType: .audio,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(storageObjectID: storageObjectID),
            sourceContentHash: sourceDigest,
            mimeType: MIMEType("audio/mpeg"),
            byteSize: 123_456,
            language: LanguageTag("en"),
            acquisitionMethod: .userSelectedFile,
            acquiredAt: acquiredAt,
            retentionClass: .permanent,
            media: media
        )
    }

    static func evidenceEnvelope(
        source: SemanticRevisionReference? = nil,
        classification: DataClassification = .internal,
        lifecycleStatus: LifecycleStatus = .draft,
        validationState: ValidationState = .notValidated,
        publishedAt: UTCInstant? = nil,
        semanticContentHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<EvidenceIDTag> {
        let source = try source ?? sourceReference()
        return try RevisionEnvelope(
            logicalID: evidenceID,
            revisionID: evidenceRevisionID,
            schemaVersion: .v1,
            lifecycleStatus: lifecycleStatus,
            validationState: validationState,
            createdAt: createdAt,
            createdBy: .application,
            publishedAt: publishedAt,
            inputRevisions: [source],
            sourceAssetRevisions: source.objectType == .sourceAsset ? [source] : [],
            dataClassification: classification,
            semanticContentHash: semanticContentHash
        )
    }

    static func evidenceRef(
        location suppliedLocation: EvidenceLocation? = nil,
        excerptText: String = "Synthetic source excerpt.",
        revision suppliedRevision: RevisionEnvelope<EvidenceIDTag>? = nil
    ) throws -> EvidenceRefV1 {
        let location = try suppliedLocation ?? .mediaTimeRange(
            source: sourceReference(),
            range: MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 2_500)
        )
        let revision = try suppliedRevision ?? evidenceEnvelope(source: location.source)
        return try EvidenceRefV1(
            revision: revision,
            location: location,
            excerpt: EvidenceExcerpt(
                text: excerptText,
                language: LanguageTag("en"),
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(millionths: 900_000)
        )
    }
}

func capturedValidationError(_ operation: () throws -> Void) -> DomainValidationError? {
    do {
        try operation()
        return nil
    } catch let error as DomainValidationError {
        return error
    } catch {
        return nil
    }
}
