import Foundation
import MeetingBuddyDomain

public struct RecordingWritableSegmentLease: Hashable, Sendable {
    public let sessionID: RecordingSessionID
    public let meetingID: MeetingID
    public let storageObjectID: StorageObjectID
    public let partialFileURL: URL
    public let finalRelativePath: WorkspaceRelativePath
    public let diskBudgetBytes: UInt64

    public init(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        partialFileURL: URL,
        finalRelativePath: WorkspaceRelativePath,
        diskBudgetBytes: UInt64
    ) {
        self.sessionID = sessionID
        self.meetingID = meetingID
        self.storageObjectID = storageObjectID
        self.partialFileURL = partialFileURL
        self.finalRelativePath = finalRelativePath
        self.diskBudgetBytes = diskBudgetBytes
    }
}

public struct RecordingSealedFileDescriptor: Codable, Hashable, Sendable {
    public let sessionID: RecordingSessionID
    public let meetingID: MeetingID
    public let storageObjectID: StorageObjectID
    public let relativePath: WorkspaceRelativePath
    public let contentHash: ContentDigest
    public let byteSize: UInt64

    public init(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        relativePath: WorkspaceRelativePath,
        contentHash: ContentDigest,
        byteSize: UInt64
    ) throws {
        guard contentHash.algorithm == .sha256, byteSize > 8 else {
            throw RecordingContractError.invalidSegment("A sealed CAF file must be non-empty and SHA-256 verified.")
        }
        self.sessionID = sessionID
        self.meetingID = meetingID
        self.storageObjectID = storageObjectID
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.byteSize = byteSize
    }
}

public struct RecordingRecoveryFileInventory: Hashable, Sendable {
    public let sealedFiles: [RecordingSealedFileDescriptor]
    public let partialRelativePaths: [WorkspaceRelativePath]
    public let quarantinedRelativePaths: [WorkspaceRelativePath]
    public let truncated: Bool

    public init(
        sealedFiles: [RecordingSealedFileDescriptor],
        partialRelativePaths: [WorkspaceRelativePath],
        quarantinedRelativePaths: [WorkspaceRelativePath],
        truncated: Bool
    ) {
        self.sealedFiles = sealedFiles
        self.partialRelativePaths = partialRelativePaths
        self.quarantinedRelativePaths = quarantinedRelativePaths
        self.truncated = truncated
    }
}

public struct RecordingFinalizationFileLease: Hashable, Sendable {
    public let sessionID: RecordingSessionID
    public let meetingID: MeetingID
    public let trackID: RecordingTrackID?
    public let partialFileURL: URL
    public let sealedFileURL: URL
    public let diskBudgetBytes: UInt64
    public let sealedFileAlreadyExists: Bool

    public init(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        trackID: RecordingTrackID?,
        partialFileURL: URL,
        sealedFileURL: URL,
        diskBudgetBytes: UInt64,
        sealedFileAlreadyExists: Bool = false
    ) {
        self.sessionID = sessionID
        self.meetingID = meetingID
        self.trackID = trackID
        self.partialFileURL = partialFileURL
        self.sealedFileURL = sealedFileURL
        self.diskBudgetBytes = diskBudgetBytes
        self.sealedFileAlreadyExists = sealedFileAlreadyExists
    }
}

public protocol RecordingSegmentFileStore: Sendable {
    func prepareSegment(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        diskBudgetBytes: UInt64
    ) throws -> RecordingWritableSegmentLease

    func sealSegment(_ lease: RecordingWritableSegmentLease) throws -> RecordingSealedFileDescriptor
    func discardPartial(_ lease: RecordingWritableSegmentLease) throws

    func verifySealedFile(_ descriptor: RecordingSealedFileDescriptor) throws
    func verifiedSealedFileURL(_ descriptor: RecordingSealedFileDescriptor) throws -> URL

    func recoveryInventory(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        maximumEntries: UInt32
    ) throws -> RecordingRecoveryFileInventory

    func prepareFinalizationFile(
        sessionID: RecordingSessionID,
        meetingID: MeetingID,
        trackID: RecordingTrackID?,
        fileExtension: ManagedFileExtension,
        diskBudgetBytes: UInt64
    ) throws -> RecordingFinalizationFileLease

    func sealFinalizationFile(_ lease: RecordingFinalizationFileLease) throws -> URL
    func discardFinalizationFile(_ lease: RecordingFinalizationFileLease) throws
}
