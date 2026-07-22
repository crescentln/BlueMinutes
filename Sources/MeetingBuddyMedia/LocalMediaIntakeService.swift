import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct MediaIntakeRequest: Sendable {
    public let meetingID: MeetingID
    public let sourceAssetID: SourceAssetID
    public let sourceRevisionID: RevisionID
    public let storageObjectID: StorageObjectID
    public let selectedTrack: MediaTrackIdentifier?
    public let speechSourceKind: SpeechSourceKind
    public let language: LanguageTag?
    public let createdAt: UTCInstant
    public let dataClassification: DataClassification
    public let retentionClass: RetentionClass
    public let expectedSourceByteSize: UInt64

    public init(
        meetingID: MeetingID,
        sourceAssetID: SourceAssetID = SourceAssetID(UUID()),
        sourceRevisionID: RevisionID = RevisionID(UUID()),
        storageObjectID: StorageObjectID = StorageObjectID(UUID()),
        selectedTrack: MediaTrackIdentifier?,
        speechSourceKind: SpeechSourceKind,
        language: LanguageTag? = nil,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass = .workspaceManaged,
        expectedSourceByteSize: UInt64
    ) throws {
        guard speechSourceKind.isKnown,
              dataClassification.isKnown,
              retentionClass.isKnown,
              expectedSourceByteSize > 0,
              expectedSourceByteSize <= JobRequest.maximumDiskBudgetBytes
        else {
            throw MediaContractError.invalidJobPayload
        }
        self.meetingID = meetingID
        self.sourceAssetID = sourceAssetID
        self.sourceRevisionID = sourceRevisionID
        self.storageObjectID = storageObjectID
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
        self.language = language
        self.createdAt = createdAt
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
        self.expectedSourceByteSize = expectedSourceByteSize
    }
}

public struct ImportedMedia: Sendable {
    public let sourceAsset: SourceAssetV1
    public let inspection: MediaInspection
    public let selectedTrack: AudioTrackDescriptor

    public init(
        sourceAsset: SourceAssetV1,
        inspection: MediaInspection,
        selectedTrack: AudioTrackDescriptor
    ) {
        self.sourceAsset = sourceAsset
        self.inspection = inspection
        self.selectedTrack = selectedTrack
    }
}

public final class LocalMediaIntakeService: @unchecked Sendable {
    private let processor: any NativeMediaProcessing
    private let storage: any MediaIntakeStorage
    private let catalog: any MediaAssetCatalog
    private let fileAccess: any ManagedMediaFileAccess

    public init(
        processor: any NativeMediaProcessing,
        storage: any MediaIntakeStorage,
        catalog: any MediaAssetCatalog,
        fileAccess: any ManagedMediaFileAccess
    ) {
        self.processor = processor
        self.storage = storage
        self.catalog = catalog
        self.fileAccess = fileAccess
    }

    public func inspect(_ authorizedSource: URL) async throws -> MediaInspection {
        try await processor.inspect(authorizedSource)
    }

    /// Copies and hashes the user-selected source before the caller releases
    /// its transient security scope. The original URL is never written.
    public func importSelectedMedia(
        from authorizedSource: URL,
        initialInspection: MediaInspection,
        request: MediaIntakeRequest,
        cancellationCheck: @Sendable () throws -> Void = {}
    ) async throws -> ImportedMedia {
        try cancellationCheck()
        let initialTrack = try initialInspection.requireTrack(request.selectedTrack)
        let fileExtension = try ManagedFileExtension(initialInspection.format.fileExtension)
        let record = try storage.importFile(
            from: authorizedSource,
            meetingID: request.meetingID,
            storageObjectID: request.storageObjectID,
            fileExtension: fileExtension,
            createdAt: request.createdAt,
            dataClassification: request.dataClassification,
            retentionClass: request.retentionClass,
            maximumByteSize: request.expectedSourceByteSize,
            cancellationCheck: cancellationCheck
        )
        do {
            guard record.byteSize == request.expectedSourceByteSize else {
                throw MediaContractError.processingFailed(
                    "The selected source changed after inspection."
                )
            }
            try cancellationCheck()
            let managedURL = try fileAccess.verifiedFileURL(
                for: ManagedAssetReference(storageObjectID: record.storageObjectID)
            )
            let managedInspection = try await processor.inspect(managedURL)
            try cancellationCheck()
            guard managedInspection == initialInspection else {
                throw MediaContractError.unreadableMedia
            }
            let managedTrack = try managedInspection.requireTrack(initialTrack.trackIdentifier)
            let sourceAsset = try MediaSourceAssetFactory.originalSource(
                record: record,
                assetID: request.sourceAssetID,
                revisionID: request.sourceRevisionID,
                inspection: managedInspection,
                selectedTrack: managedTrack,
                speechSourceKind: request.speechSourceKind,
                language: request.language
            )
            try cancellationCheck()
            try catalog.insertSourceAsset(sourceAsset)
            return ImportedMedia(
                sourceAsset: sourceAsset,
                inspection: managedInspection,
                selectedTrack: managedTrack
            )
        } catch {
            _ = try? storage.moveToTrash(
                storageObjectID: record.storageObjectID,
                at: request.createdAt
            )
            throw error
        }
    }
}
