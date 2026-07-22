import Foundation
import MeetingBuddyDomain

/// Durable policy and identifiers for one user-authorized local-media copy.
///
/// The source URL and its security-scoped authority are deliberately absent.
/// They remain process-local capabilities supplied to the executor at runtime.
public struct LocalMediaIntakeJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.local-media-intake"
    public static let inputFormatVersion: UInt32 = 1

    public let meetingID: MeetingID
    public let sourceAssetID: SourceAssetID
    public let sourceRevisionID: RevisionID
    public let storageObjectID: StorageObjectID
    public let initialInspection: MediaInspection
    public let selectedTrack: MediaTrackIdentifier
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
        initialInspection: MediaInspection,
        selectedTrack: MediaTrackIdentifier,
        speechSourceKind: SpeechSourceKind,
        language: LanguageTag?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass = .workspaceManaged,
        expectedSourceByteSize: UInt64
    ) throws {
        _ = try initialInspection.requireTrack(selectedTrack)
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
        self.initialInspection = initialInspection
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
        self.language = language
        self.createdAt = createdAt
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
        self.expectedSourceByteSize = expectedSourceByteSize
    }

    public var outputRevision: SemanticRevisionReference {
        get throws {
            try SemanticRevisionReference(
                logicalID: sourceAssetID,
                revisionID: sourceRevisionID
            )
        }
    }

    public func jobInputPayload() throws -> JobInputPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JobInputPayload(
            formatIdentifier: Self.inputFormatIdentifier,
            formatVersion: Self.inputFormatVersion,
            payload: encoder.encode(self)
        )
    }

    public static func decode(from input: JobInputPayload?) throws -> Self {
        guard let input,
              input.formatIdentifier == inputFormatIdentifier,
              input.formatVersion == inputFormatVersion
        else {
            throw MediaContractError.invalidJobPayload
        }
        do {
            let decoded = try JSONDecoder().decode(Self.self, from: input.payload)
            let tracks = try decoded.initialInspection.audioTracks.map { track in
                try AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(track.trackIdentifier.rawValue),
                    durationFrameCount: track.durationFrameCount,
                    sourceSampleRateHertz: track.sourceSampleRateHertz,
                    sourceChannelCount: track.sourceChannelCount,
                    codec: track.codec,
                    language: track.language
                )
            }
            let inspection = try MediaInspection(
                format: ApprovedMediaFormat(
                    fileExtension: decoded.initialInspection.format.rawValue
                ),
                durationFrameCount: decoded.initialInspection.durationFrameCount,
                audioTracks: tracks
            )
            return try Self(
                meetingID: decoded.meetingID,
                sourceAssetID: decoded.sourceAssetID,
                sourceRevisionID: decoded.sourceRevisionID,
                storageObjectID: decoded.storageObjectID,
                initialInspection: inspection,
                selectedTrack: MediaTrackIdentifier(decoded.selectedTrack.rawValue),
                speechSourceKind: decoded.speechSourceKind,
                language: decoded.language,
                createdAt: decoded.createdAt,
                dataClassification: decoded.dataClassification,
                retentionClass: decoded.retentionClass,
                expectedSourceByteSize: decoded.expectedSourceByteSize
            )
        } catch {
            throw MediaContractError.invalidJobPayload
        }
    }
}

/// Managed storage that can cooperatively stop a streamed intake copy.
public protocol MediaIntakeStorage: StorageService {
    func importFile(
        from authorizedSource: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass,
        maximumByteSize: UInt64?,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> ManagedAssetRecord
}

public extension MediaIntakeStorage {
    func importFile(
        from authorizedSource: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> ManagedAssetRecord {
        try importFile(
            from: authorizedSource,
            meetingID: meetingID,
            storageObjectID: storageObjectID,
            fileExtension: fileExtension,
            createdAt: createdAt,
            dataClassification: dataClassification,
            retentionClass: retentionClass,
            maximumByteSize: nil,
            cancellationCheck: cancellationCheck
        )
    }
}

public extension MediaJobTypes {
    static let localIntake = try! JobType("media-local-intake-v1")
}
