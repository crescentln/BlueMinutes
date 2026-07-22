import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import MeetingBuddyPersistence
import MeetingBuddyTasks
import Testing

@Suite(.serialized)
struct CanonicalAudioIntegrationTests {
    @Test
    func localAcquisitionRunsThroughTaskManagerWithTransientSourceAuthority() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        try workspace.installMeeting()
        let sourceBytes = Data("task-managed-local-source".utf8)
        try workspace.writeUserSource(sourceBytes)
        let processor = try SyntheticMediaProcessor(totalFrames: 48_000)
        let intake = LocalMediaIntakeService(
            processor: processor,
            storage: workspace.coordinator,
            catalog: workspace.store,
            fileAccess: workspace.fileAccess
        )
        let inspection = try await intake.inspect(workspace.sourceURL)
        let plan = try LocalMediaIntakeJobPlan(
            meetingID: workspace.meetingID,
            sourceAssetID: mediaID(40, as: SourceAssetID.self),
            sourceRevisionID: mediaID(41, as: RevisionID.self),
            storageObjectID: mediaID(42, as: StorageObjectID.self),
            initialInspection: inspection,
            selectedTrack: MediaTrackIdentifier(1),
            speechSourceKind: .originalSpeakerAudio,
            language: LanguageTag("en"),
            createdAt: mediaInstant(1_800_100_000_040),
            dataClassification: .internal,
            expectedSourceByteSize: UInt64(sourceBytes.count)
        )
        let registry = TransientMediaSourceRegistry()
        let executor = LocalMediaIntakeJobExecutor(intake: intake, sources: registry)
        let manager = try LocalTaskManager(
            repository: workspace.repository,
            temporaryStorage: workspace.temporaryStorage,
            logStore: workspace.logStore,
            managedAssetRecovery: workspace.coordinator,
            maximumConcurrentJobs: 1,
            executors: [executor]
        )
        let request = try LocalMediaIntakeJobFactory().request(
            plan: plan,
            jobID: mediaID(43, as: JobID.self),
            requestedBy: JobRequester("task005a-test")
        )
        try registry.register(workspace.sourceURL, for: request.jobID)

        _ = try await manager.enqueue(request)
        let succeeded = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )

        let outputRevision = try plan.outputRevision
        #expect(succeeded.outputRevisionIDs == [outputRevision])
        let fetchedSource = try workspace.store.sourceAsset(
            revisionID: plan.sourceRevisionID
        )
        let source = try #require(fetchedSource)
        #expect(
            source.sourceContentHash
                == (try ContentDigest.sha256(ofUTF8Text: "task-managed-local-source"))
        )
        #expect(source.byteSize == UInt64(sourceBytes.count))
        #expect(try Data(contentsOf: workspace.sourceURL) == sourceBytes)
        let managed = try #require(source.managedStorageReference)
        _ = try workspace.fileAccess.verifiedFileURL(for: managed)
        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))
    }

    @Test
    func localAcquisitionCancellationRemovesPartialManagedCopy() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        try workspace.installMeeting()
        let sourceBytes = Data(repeating: 0x5a, count: 3 * 1_048_576)
        try workspace.writeUserSource(sourceBytes)
        let processor = try SyntheticMediaProcessor(totalFrames: 48_000)
        let intake = LocalMediaIntakeService(
            processor: processor,
            storage: workspace.coordinator,
            catalog: workspace.store,
            fileAccess: workspace.fileAccess
        )
        let inspection = try await intake.inspect(workspace.sourceURL)
        let cancellation = CancellationAfterChecks(limit: 5)
        await #expect(throws: CancellationError.self) {
            _ = try await intake.importSelectedMedia(
                from: workspace.sourceURL,
                initialInspection: inspection,
                request: MediaIntakeRequest(
                    meetingID: workspace.meetingID,
                    sourceAssetID: mediaID(44, as: SourceAssetID.self),
                    sourceRevisionID: mediaID(45, as: RevisionID.self),
                    storageObjectID: mediaID(46, as: StorageObjectID.self),
                    selectedTrack: MediaTrackIdentifier(1),
                    speechSourceKind: .originalSpeakerAudio,
                    language: LanguageTag("en"),
                    createdAt: mediaInstant(1_800_100_000_041),
                    dataClassification: .internal,
                    expectedSourceByteSize: UInt64(sourceBytes.count)
                ),
                cancellationCheck: { try cancellation.check() }
            )
        }
        #expect(
            try workspace.store.managedAsset(
                storageObjectID: mediaID(46, as: StorageObjectID.self)
            ) == nil
        )
        #expect(
            try workspace.store.sourceAsset(
                revisionID: mediaID(45, as: RevisionID.self)
            ) == nil
        )
        #expect(try Data(contentsOf: workspace.sourceURL) == sourceBytes)
        let stagingEntries = try FileManager.default.contentsOfDirectory(
            at: workspace.root.appendingPathComponent(".temp", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        #expect(stagingEntries.isEmpty)
    }

    @Test
    func localAcquisitionRejectsSourceGrowthBeforeWritingPastInspectedSize() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        try workspace.installMeeting()
        let inspectedByteSize = 1_048_576
        let sourceBytes = Data(repeating: 0x47, count: 3 * inspectedByteSize)
        try workspace.writeUserSource(sourceBytes)
        let processor = try SyntheticMediaProcessor(totalFrames: 48_000)
        let intake = LocalMediaIntakeService(
            processor: processor,
            storage: workspace.coordinator,
            catalog: workspace.store,
            fileAccess: workspace.fileAccess
        )
        let inspection = try await intake.inspect(workspace.sourceURL)

        await #expect(throws: WorkspaceContractError.self) {
            _ = try await intake.importSelectedMedia(
                from: workspace.sourceURL,
                initialInspection: inspection,
                request: MediaIntakeRequest(
                    meetingID: workspace.meetingID,
                    sourceAssetID: mediaID(47, as: SourceAssetID.self),
                    sourceRevisionID: mediaID(48, as: RevisionID.self),
                    storageObjectID: mediaID(49, as: StorageObjectID.self),
                    selectedTrack: MediaTrackIdentifier(1),
                    speechSourceKind: .originalSpeakerAudio,
                    language: LanguageTag("en"),
                    createdAt: mediaInstant(1_800_100_000_042),
                    dataClassification: .internal,
                    expectedSourceByteSize: UInt64(inspectedByteSize)
                )
            )
        }
        #expect(
            try workspace.store.managedAsset(
                storageObjectID: mediaID(49, as: StorageObjectID.self)
            ) == nil
        )
        #expect(
            try workspace.store.sourceAsset(
                revisionID: mediaID(48, as: RevisionID.self)
            ) == nil
        )
        let stagingEntries = try FileManager.default.contentsOfDirectory(
            at: workspace.root.appendingPathComponent(".temp", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        #expect(stagingEntries.isEmpty)
        #expect(try Data(contentsOf: workspace.sourceURL) == sourceBytes)
    }

    @Test
    func managedImportCanonicalPublicationAndChunkCleanupCompleteEndToEnd() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        let processor = try SyntheticMediaProcessor(totalFrames: 1_000_000)
        let originalBytes = Data("synthetic-user-source".utf8)
        let imported = try await importSyntheticSource(
            workspace: workspace,
            processor: processor
        )
        let plan = try mediaPlan(workspace: workspace, imported: imported)
        let manager = try mediaManager(workspace: workspace, processor: processor)
        let request = try CanonicalAudioJobFactory().request(
            plan: plan,
            jobID: mediaID(30, as: JobID.self),
            requestedBy: JobRequester("task005a-test")
        )

        _ = try await manager.enqueue(request)
        let succeeded = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )

        #expect(try Data(contentsOf: workspace.sourceURL) == originalBytes)
        #expect(succeeded.outputRevisionIDs.count == 1)
        #expect(succeeded.outputRevisionIDs.first?.revisionID == plan.outputRevisionID)
        let fetchedCanonical = try workspace.store.sourceAsset(
            revisionID: plan.outputRevisionID
        )
        let canonical = try #require(fetchedCanonical)
        #expect(canonical.assetID == plan.outputAssetID)
        #expect(canonical.originType == .generated)
        #expect(canonical.media?.sampleRateHertz == 16_000)
        #expect(canonical.media?.channelLayout == "mono")
        #expect(canonical.media?.speechSourceKind == .originalSpeakerAudio)
        let managedReference = try #require(canonical.managedStorageReference)
        _ = try workspace.fileAccess.verifiedFileURL(for: managedReference)

        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))
        let checkpoint = try #require(
            try CanonicalAudioCheckpoint.decode(from: succeeded.checkpoint)
        )
        #expect(checkpoint.completedChunks.count == 3)
        #expect(checkpoint.rangeIssues.isEmpty)
        let expectedCalls = try CanonicalChunkPlanner.plan(
            totalFrameCount: plan.expectedDurationFrames
        ).map(\.physicalRange)
        #expect(await processor.recordedChunkCalls() == expectedCalls)
    }

    @Test
    func retryReusesVerifiedCanonicalAndCompletedChunks() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        let processor = try SyntheticMediaProcessor(
            totalFrames: 1_000_000,
            failureStartFrame: 464_000
        )
        let imported = try await importSyntheticSource(
            workspace: workspace,
            processor: processor
        )
        let plan = try mediaPlan(workspace: workspace, imported: imported)
        let manager = try mediaManager(workspace: workspace, processor: processor)
        let request = try CanonicalAudioJobFactory().request(
            plan: plan,
            jobID: mediaID(31, as: JobID.self),
            requestedBy: JobRequester("task005a-test"),
            maximumRetryCount: 1
        )

        _ = try await manager.enqueue(request)
        let failed = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .failed
        )
        #expect(failed.checkpoint != nil)
        #expect(failed.progress.completedUnitCount == 2)
        let outputBeforeRetry = try workspace.store.sourceAsset(
            revisionID: plan.outputRevisionID
        )
        #expect(outputBeforeRetry == nil)

        _ = try await manager.retry(jobID: request.jobID)
        let succeeded = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        #expect(succeeded.retryCount == 1)
        let calls = await processor.recordedChunkCalls()
        #expect(calls.filter { $0.startFrame == 0 }.count == 1)
        #expect(calls.filter { $0.startFrame == 464_000 }.count == 2)
        #expect(calls.filter { $0.startFrame == 944_000 }.count == 1)
        let checkpoint = try #require(
            try CanonicalAudioCheckpoint.decode(from: succeeded.checkpoint)
        )
        #expect(checkpoint.rangeIssues.isEmpty)
    }

    @Test
    func cancellationPublishesNothingAndRemovesTaskArtifacts() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        let processor = try SyntheticMediaProcessor(
            totalFrames: 1_000_000,
            slowChunks: true
        )
        let imported = try await importSyntheticSource(
            workspace: workspace,
            processor: processor
        )
        let plan = try mediaPlan(workspace: workspace, imported: imported)
        let manager = try mediaManager(workspace: workspace, processor: processor)
        let request = try CanonicalAudioJobFactory().request(
            plan: plan,
            jobID: mediaID(32, as: JobID.self),
            requestedBy: JobRequester("task005a-test")
        )

        _ = try await manager.enqueue(request)
        _ = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .running
        )
        for _ in 0..<200 {
            if let current = try await manager.job(id: request.jobID),
               current.progress.completedUnitCount >= 1
            {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = try await manager.cancel(jobID: request.jobID)
        _ = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .cancelled
        )

        let cancelledOutput = try workspace.store.sourceAsset(
            revisionID: plan.outputRevisionID
        )
        #expect(cancelledOutput == nil)
        #expect(try workspace.store.managedAsset(
            storageObjectID: plan.outputStorageObjectID
        ) == nil)
        let taskDirectory = workspace.root.appendingPathComponent(
            ".tasks/\(request.jobID.canonicalString)",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path))
        #expect(try Data(contentsOf: workspace.sourceURL) == Data("synthetic-user-source".utf8))
    }

    @Test
    func canonicalGapReportRetainsExactHalfOpenRangeInCheckpoint() async throws {
        let workspace = try MediaTestWorkspace()
        defer { workspace.cleanup() }
        let gap = try MediaRangeIssue(
            kind: .missing,
            range: MediaFrameRange(startFrame: 16_000, endFrame: 24_000),
            safeSummary: "The synthetic source timeline contains a missing range."
        )
        let processor = try SyntheticMediaProcessor(
            totalFrames: 32_000,
            canonicalIssues: [gap]
        )
        let imported = try await importSyntheticSource(
            workspace: workspace,
            processor: processor
        )
        let plan = try mediaPlan(workspace: workspace, imported: imported)
        let manager = try mediaManager(workspace: workspace, processor: processor)
        let request = try CanonicalAudioJobFactory().request(
            plan: plan,
            jobID: mediaID(33, as: JobID.self),
            requestedBy: JobRequester("task005a-test")
        )

        _ = try await manager.enqueue(request)
        let succeeded = try await waitForMediaJob(
            manager,
            jobID: request.jobID,
            state: .succeeded
        )
        let checkpoint = try #require(
            try CanonicalAudioCheckpoint.decode(from: succeeded.checkpoint)
        )
        #expect(checkpoint.rangeIssues == [gap])
    }
}

private final class CancellationAfterChecks: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var count = 0

    init(limit: Int) {
        self.limit = limit
    }

    func check() throws {
        lock.lock()
        count += 1
        let shouldCancel = count >= limit
        lock.unlock()
        if shouldCancel { throw CancellationError() }
    }
}
