import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum CaptureSourceAssetFactory {
    static func manifest(
        record: ManagedAssetRecord,
        plan: RecordingAssetPublicationPlan,
        manifest: CaptureManifestV1
    ) throws -> SourceAssetV1 {
        let generation = try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "meetingbuddy-local",
                modelIdentifier: "capture-manifest",
                clientVersion: "task008b"
            ),
            promptModuleVersions: [
                try VersionedComponent(identifier: "capture-manifest", version: "1")
            ],
            outputSchemaVersion: .v1,
            templateVersion: "task008b-v1",
            generatedAt: manifest.createdAt,
            privacyRoute: .localOnly
        )
        let draft = try sourceAsset(
            plan: plan,
            meetingID: record.meetingID,
            record: record,
            assetType: .document,
            originType: .generated,
            mimeType: try MIMEType("application/vnd.meetingbuddy.capture-manifest+json"),
            acquisitionMethod: .generated,
            media: nil,
            sourceRevisions: [],
            generationMetadata: generation,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            semanticHash: nil
        )
        return try sourceAsset(
            plan: plan,
            meetingID: record.meetingID,
            record: record,
            assetType: .document,
            originType: .generated,
            mimeType: try MIMEType("application/vnd.meetingbuddy.capture-manifest+json"),
            acquisitionMethod: .generated,
            media: nil,
            sourceRevisions: [],
            generationMetadata: generation,
            lifecycleStatus: .published,
            validationState: .valid,
            semanticHash: draft.calculatedSemanticContentHash()
        )
    }

    static func capturedAudio(
        record: ManagedAssetRecord,
        plan: RecordingAssetPublicationPlan,
        request: RecordingTrackRequest,
        format: CaptureAudioFormat,
        frameCount: UInt64,
        manifestRevision: SemanticRevisionReference
    ) throws -> SourceAssetV1 {
        let durationProduct = frameCount.multipliedFullWidth(by: 1_000)
        let durationMilliseconds = UInt64(format.sampleRateHertz)
            .dividingFullWidth(durationProduct).quotient
        let media = try MediaProvenance(
            durationMilliseconds: durationMilliseconds,
            containerFormat: "caf",
            codec: "linear-pcm-s16le",
            sampleRateHertz: format.sampleRateHertz,
            channelLayout: format.channelCount == 1 ? "mono" : "\(format.channelCount)-channel",
            languageTrack: request.language,
            speechSourceKind: request.speechSourceKind
        )
        let draft = try sourceAsset(
            plan: plan,
            meetingID: record.meetingID,
            record: record,
            assetType: .audio,
            originType: .authorizedCapture,
            mimeType: try MIMEType("audio/x-caf"),
            acquisitionMethod: .authorizedCapture,
            media: media,
            sourceRevisions: [manifestRevision],
            generationMetadata: nil,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            semanticHash: nil
        )
        return try sourceAsset(
            plan: plan,
            meetingID: record.meetingID,
            record: record,
            assetType: .audio,
            originType: .authorizedCapture,
            mimeType: try MIMEType("audio/x-caf"),
            acquisitionMethod: .authorizedCapture,
            media: media,
            sourceRevisions: [manifestRevision],
            generationMetadata: nil,
            lifecycleStatus: .published,
            validationState: .valid,
            semanticHash: draft.calculatedSemanticContentHash()
        )
    }

    private static func sourceAsset(
        plan: RecordingAssetPublicationPlan,
        meetingID: MeetingID,
        record: ManagedAssetRecord,
        assetType: SourceAssetType,
        originType: SourceOriginType,
        mimeType: MIMEType,
        acquisitionMethod: AcquisitionMethod,
        media: MediaProvenance?,
        sourceRevisions: [SemanticRevisionReference],
        generationMetadata: GenerationMetadata?,
        lifecycleStatus: LifecycleStatus,
        validationState: ValidationState,
        semanticHash: ContentDigest?
    ) throws -> SourceAssetV1 {
        try SourceAssetV1(
            revision: RevisionEnvelope(
                logicalID: plan.assetID,
                revisionID: plan.revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycleStatus,
                validationState: validationState,
                createdAt: record.createdAt,
                createdBy: .application,
                publishedAt: lifecycleStatus == .published ? record.createdAt : nil,
                sourceAssetRevisions: sourceRevisions,
                dataClassification: record.dataClassification,
                generationMetadata: generationMetadata,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            assetType: assetType,
            originType: originType,
            managedStorageReference: ManagedAssetReference(storageObjectID: record.storageObjectID),
            sourceContentHash: record.contentHash,
            mimeType: mimeType,
            byteSize: record.byteSize,
            language: media?.languageTrack,
            acquisitionMethod: acquisitionMethod,
            acquiredAt: record.createdAt,
            retentionClass: record.retentionClass,
            media: media
        )
    }
}
