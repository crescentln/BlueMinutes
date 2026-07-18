import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import MeetingBuddyPersistence
import MeetingBuddyTasks

final class MediaTestWorkspace: @unchecked Sendable {
    let container: URL
    let root: URL
    let sourceURL: URL
    let descriptor: LocalWorkspaceDescriptor
    let store: SQLitePersistenceStore
    let storage: LocalStorageService
    let coordinator: ManagedAssetCoordinator
    let fileAccess: LocalManagedMediaFileAccess
    let temporaryStorage: LocalTaskTemporaryStorage
    let logStore: RotatingTaskLogStore
    let repository: SQLiteJobRepository

    let workspaceID = mediaID(1, as: WorkspaceID.self)
    let meetingID = mediaID(2, as: MeetingID.self)

    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meetingbuddy-task005a-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        root = container.appendingPathComponent("workspace", isDirectory: true)
        sourceURL = container.appendingPathComponent("user-source.wav")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        descriptor = try LocalWorkspaceService().createWorkspace(
            at: root,
            workspaceID: workspaceID,
            createdAt: mediaInstant(1_800_100_000_000)
        )
        store = try SQLitePersistenceStore(
            workspace: descriptor,
            migrationTimestamp: mediaInstant(1_800_100_000_001)
        )
        storage = LocalStorageService(workspace: descriptor)
        coordinator = ManagedAssetCoordinator(storage: storage, metadata: store)
        fileAccess = LocalManagedMediaFileAccess(storage: storage, metadata: store)
        temporaryStorage = LocalTaskTemporaryStorage(workspace: descriptor)
        logStore = RotatingTaskLogStore(
            workspace: descriptor,
            configuration: try TaskLogConfiguration()
        )
        repository = SQLiteJobRepository(store: store)
    }

    func installMeeting(classification: DataClassification = .internal) throws {
        let createdAt = mediaInstant(1_800_100_000_010)
        try store.insert(
            MeetingProfileV1(
                revision: RevisionEnvelope(
                    logicalID: meetingID,
                    revisionID: mediaID(3, as: RevisionID.self),
                    schemaVersion: .v1,
                    lifecycleStatus: .draft,
                    validationState: .notValidated,
                    createdAt: createdAt,
                    createdBy: .user,
                    dataClassification: classification
                ),
                title: "Synthetic Task 005A Meeting",
                sourceLanguages: [LanguageTag("en")],
                outputLanguage: LanguageTag("en"),
                cloudProcessingPolicy: .localOnly,
                workspaceID: workspaceID,
                reviewStatus: .unreviewed,
                userConfirmed: false
            )
        )
    }

    func writeUserSource(_ data: Data = Data("synthetic-user-source".utf8)) throws {
        try data.write(to: sourceURL, options: [.atomic])
    }

    func cleanup() {
        try? store.close()
        try? FileManager.default.removeItem(at: container)
    }
}

actor SyntheticMediaProcessor: NativeMediaProcessing {
    let inspection: MediaInspection
    let canonicalIssues: [MediaRangeIssue]
    let slowChunks: Bool
    let failureStartFrame: UInt64?

    private var chunkCalls: [MediaFrameRange] = []
    private var didInjectFailure = false

    init(
        totalFrames: UInt64,
        canonicalIssues: [MediaRangeIssue] = [],
        slowChunks: Bool = false,
        failureStartFrame: UInt64? = nil
    ) throws {
        inspection = try MediaInspection(
            format: .wav,
            durationFrameCount: totalFrames,
            audioTracks: [
                AudioTrackDescriptor(
                    trackIdentifier: MediaTrackIdentifier(1),
                    durationFrameCount: totalFrames,
                    sourceSampleRateHertz: 48_000,
                    sourceChannelCount: 2,
                    codec: "lpcm",
                    language: LanguageTag("en")
                )
            ]
        )
        self.canonicalIssues = canonicalIssues
        self.slowChunks = slowChunks
        self.failureStartFrame = failureStartFrame
    }

    func inspect(_ sourceURL: URL) async throws -> MediaInspection {
        inspection
    }

    func writeCanonicalAudio(
        from sourceURL: URL,
        selectedTrack: MediaTrackIdentifier,
        expectedTimelineFrameCount: UInt64,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws -> CanonicalAudioWriteResult {
        try Task.checkCancellation()
        try Data(repeating: 0x43, count: 512).write(to: destinationURL)
        return try CanonicalAudioWriteResult(
            frameCount: expectedTimelineFrameCount,
            rangeIssues: canonicalIssues
        )
    }

    func writeCanonicalChunk(
        from canonicalAudioURL: URL,
        range: MediaFrameRange,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws {
        chunkCalls.append(range)
        if failureStartFrame == range.startFrame, !didInjectFailure {
            didInjectFailure = true
            throw MediaContractError.processingFailed("Synthetic retry fixture failure.")
        }
        if slowChunks {
            try await Task.sleep(for: .milliseconds(500))
        }
        try Task.checkCancellation()
        let marker = UInt8(truncatingIfNeeded: range.startFrame / 16_000)
        try Data(repeating: marker, count: 128).write(to: destinationURL)
    }

    func recordedChunkCalls() -> [MediaFrameRange] { chunkCalls }
}

func importSyntheticSource(
    workspace: MediaTestWorkspace,
    processor: SyntheticMediaProcessor,
    classification: DataClassification = .internal
) async throws -> ImportedMedia {
    try workspace.installMeeting(classification: classification)
    try workspace.writeUserSource()
    let service = LocalMediaIntakeService(
        processor: processor,
        storage: workspace.coordinator,
        catalog: workspace.store,
        fileAccess: workspace.fileAccess
    )
    let inspection = try await service.inspect(workspace.sourceURL)
    return try await service.importSelectedMedia(
        from: workspace.sourceURL,
        initialInspection: inspection,
        request: MediaIntakeRequest(
            meetingID: workspace.meetingID,
            sourceAssetID: mediaID(10, as: SourceAssetID.self),
            sourceRevisionID: mediaID(11, as: RevisionID.self),
            storageObjectID: mediaID(12, as: StorageObjectID.self),
            selectedTrack: MediaTrackIdentifier(1),
            speechSourceKind: .originalSpeakerAudio,
            language: LanguageTag("en"),
            createdAt: mediaInstant(1_800_100_000_020),
            dataClassification: classification,
            expectedSourceByteSize: UInt64(Data("synthetic-user-source".utf8).count)
        )
    )
}

func mediaPlan(
    workspace: MediaTestWorkspace,
    imported: ImportedMedia,
    classification: DataClassification = .internal
) throws -> CanonicalAudioJobPlan {
    try CanonicalAudioJobPlan(
        sourceRevision: SemanticRevisionReference(
            logicalID: imported.sourceAsset.assetID,
            revisionID: imported.sourceAsset.revision.revisionID
        ),
        selectedTrack: imported.selectedTrack.trackIdentifier,
        speechSourceKind: .originalSpeakerAudio,
        outputAssetID: mediaID(20, as: SourceAssetID.self),
        outputRevisionID: mediaID(21, as: RevisionID.self),
        outputStorageObjectID: mediaID(22, as: StorageObjectID.self),
        meetingID: workspace.meetingID,
        createdAt: mediaInstant(1_800_100_000_030),
        dataClassification: classification,
        language: LanguageTag("en"),
        expectedDurationFrames: imported.inspection.durationFrameCount
    )
}

func mediaManager(
    workspace: MediaTestWorkspace,
    processor: SyntheticMediaProcessor
) throws -> LocalTaskManager {
    let executor = CanonicalAudioJobExecutor(
        processor: processor,
        storage: workspace.coordinator,
        catalog: workspace.store,
        fileAccess: workspace.fileAccess
    )
    return try LocalTaskManager(
        repository: workspace.repository,
        temporaryStorage: workspace.temporaryStorage,
        logStore: workspace.logStore,
        managedAssetRecovery: workspace.coordinator,
        maximumConcurrentJobs: 1,
        executors: [executor]
    )
}

func waitForMediaJob(
    _ manager: LocalTaskManager,
    jobID: JobID,
    state: JobState,
    attempts: Int = 600
) async throws -> JobRecord {
    for _ in 0..<attempts {
        if let record = try await manager.job(id: jobID), record.state == state {
            return record
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    let latest = try await manager.job(id: jobID)
    throw MediaContractError.processingFailed(
        "Timed out waiting for \(state.rawValue); latest=\(latest?.state.rawValue ?? "missing")."
    )
}

func mediaID<Tag>(_ suffix: Int, as type: StableID<Tag>.Type) -> StableID<Tag> {
    StableID<Tag>(
        UUID(uuidString: String(format: "5a000000-0000-0000-0000-%012d", suffix))!
    )
}

func mediaInstant(_ milliseconds: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
}
