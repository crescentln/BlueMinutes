import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum MediaSourceAssetFactory {
    static func originalSource(
        record: ManagedAssetRecord,
        assetID: SourceAssetID,
        revisionID: RevisionID,
        inspection: MediaInspection,
        selectedTrack: AudioTrackDescriptor,
        speechSourceKind: SpeechSourceKind,
        language: LanguageTag?
    ) throws -> SourceAssetV1 {
        let media = try MediaProvenance(
            durationMilliseconds: milliseconds(for: inspection.durationFrameCount),
            containerFormat: inspection.format.rawValue,
            codec: selectedTrack.codec,
            sampleRateHertz: selectedTrack.sourceSampleRateHertz,
            channelLayout: selectedTrack.sourceChannelCount.map(channelLayout),
            languageTrack: language ?? selectedTrack.language,
            speechSourceKind: speechSourceKind
        )
        let draft = try sourceAsset(
            assetID: assetID,
            revisionID: revisionID,
            meetingID: record.meetingID,
            assetType: inspection.format.assetType,
            originType: .localImport,
            record: record,
            mimeType: MIMEType(inspection.format.mimeType),
            language: language ?? selectedTrack.language,
            acquisitionMethod: .userSelectedFile,
            media: media,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            publishedAt: nil,
            createdBy: .importProcess,
            sourceRevisions: [],
            generationMetadata: nil,
            semanticHash: nil
        )
        return try sourceAsset(
            assetID: assetID,
            revisionID: revisionID,
            meetingID: record.meetingID,
            assetType: inspection.format.assetType,
            originType: .localImport,
            record: record,
            mimeType: MIMEType(inspection.format.mimeType),
            language: language ?? selectedTrack.language,
            acquisitionMethod: .userSelectedFile,
            media: media,
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: record.createdAt,
            createdBy: .importProcess,
            sourceRevisions: [],
            generationMetadata: nil,
            semanticHash: draft.calculatedSemanticContentHash()
        )
    }

    static func canonicalSource(
        record: ManagedAssetRecord,
        plan: CanonicalAudioJobPlan,
        frameCount: UInt64
    ) throws -> SourceAssetV1 {
        let generation = try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "apple-avfoundation",
                modelIdentifier: "native-audio-pipeline",
                modelVersion: nil,
                clientVersion: "task005a"
            ),
            promptModuleVersions: [
                VersionedComponent(
                    identifier: "canonical-audio-profile",
                    version: plan.profile.identifier
                )
            ],
            outputSchemaVersion: .v1,
            templateVersion: "task005a-v1",
            generatedAt: plan.createdAt,
            privacyRoute: .localOnly
        )
        let media = try MediaProvenance(
            durationMilliseconds: milliseconds(for: frameCount),
            containerFormat: plan.profile.container,
            codec: plan.profile.codec,
            sampleRateHertz: plan.profile.sampleRateHertz,
            channelLayout: "mono",
            languageTrack: plan.language,
            speechSourceKind: plan.speechSourceKind
        )
        let draft = try sourceAsset(
            assetID: plan.outputAssetID,
            revisionID: plan.outputRevisionID,
            meetingID: plan.meetingID,
            assetType: .audio,
            originType: .generated,
            record: record,
            mimeType: MIMEType("audio/x-caf"),
            language: plan.language,
            acquisitionMethod: .generated,
            media: media,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            publishedAt: nil,
            createdBy: .application,
            sourceRevisions: [plan.sourceRevision],
            generationMetadata: generation,
            semanticHash: nil
        )
        return try sourceAsset(
            assetID: plan.outputAssetID,
            revisionID: plan.outputRevisionID,
            meetingID: plan.meetingID,
            assetType: .audio,
            originType: .generated,
            record: record,
            mimeType: MIMEType("audio/x-caf"),
            language: plan.language,
            acquisitionMethod: .generated,
            media: media,
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: plan.createdAt,
            createdBy: .application,
            sourceRevisions: [plan.sourceRevision],
            generationMetadata: generation,
            semanticHash: draft.calculatedSemanticContentHash()
        )
    }

    private static func sourceAsset(
        assetID: SourceAssetID,
        revisionID: RevisionID,
        meetingID: MeetingID,
        assetType: SourceAssetType,
        originType: SourceOriginType,
        record: ManagedAssetRecord,
        mimeType: MIMEType,
        language: LanguageTag?,
        acquisitionMethod: AcquisitionMethod,
        media: MediaProvenance,
        lifecycleStatus: LifecycleStatus,
        validationState: ValidationState,
        publishedAt: UTCInstant?,
        createdBy: CreationActor,
        sourceRevisions: [SemanticRevisionReference],
        generationMetadata: GenerationMetadata?,
        semanticHash: ContentDigest?
    ) throws -> SourceAssetV1 {
        try SourceAssetV1(
            revision: RevisionEnvelope(
                logicalID: assetID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: lifecycleStatus,
                validationState: validationState,
                createdAt: record.createdAt,
                createdBy: createdBy,
                publishedAt: publishedAt,
                sourceAssetRevisions: sourceRevisions,
                dataClassification: record.dataClassification,
                generationMetadata: generationMetadata,
                semanticContentHash: semanticHash
            ),
            meetingID: meetingID,
            assetType: assetType,
            originType: originType,
            managedStorageReference: ManagedAssetReference(
                storageObjectID: record.storageObjectID
            ),
            sourceContentHash: record.contentHash,
            mimeType: mimeType,
            byteSize: record.byteSize,
            language: language,
            acquisitionMethod: acquisitionMethod,
            acquiredAt: record.createdAt,
            retentionClass: record.retentionClass,
            media: media
        )
    }

    private static func milliseconds(for frameCount: UInt64) -> UInt64 {
        let product = frameCount.multipliedFullWidth(by: 1_000)
        return UInt64(CanonicalAudioProfile.v1.sampleRateHertz)
            .dividingFullWidth(product).quotient
    }

    private static func channelLayout(_ count: UInt16) -> String {
        switch count {
        case 1: "mono"
        case 2: "stereo"
        default: "\(count)-channel"
        }
    }
}
