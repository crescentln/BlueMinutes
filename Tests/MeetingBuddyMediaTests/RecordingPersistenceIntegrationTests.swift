import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
@testable import MeetingBuddyPersistence
import MeetingBuddyTasks
import Testing

@Suite(.serialized)
struct RecordingPersistenceIntegrationTests {
    @Test
    func normalCaptureSealsIncrementallyPublishesSeparateManifestDependencyAndTrashesSegments() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }

        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        for packet in try packets(fixture: fixture, count: 51) {
            #expect(await fixture.coordinator.accept(packet) == .accepted)
        }
        let checkpoint = try #require(
            try await fixture.workspace.store.latestCheckpoint(
                sessionID: fixture.intent.sessionID
            )
        )
        #expect(checkpoint.tracks.count == 1)
        #expect(checkpoint.tracks[0].lastCoveredMediaRange.endNanoseconds == 5_000_000_000)
        #expect(try checkpoint.canonicalPayload().count <= JobCheckpoint.maximumPayloadBytes)

        let terminal = try await fixture.coordinator.stop()
        #expect(terminal.state == .completed)
        let manifestPlan = fixture.intent.publicationPlan.manifest
        let trackPlan = try #require(fixture.intent.publicationPlan.tracks.first)
        let loadedManifestSource = try fixture.workspace.store.sourceAsset(
            revisionID: manifestPlan.revisionID
        )
        let loadedAudioSource = try fixture.workspace.store.sourceAsset(
            revisionID: trackPlan.asset.revisionID
        )
        let manifestSource = try #require(loadedManifestSource)
        let audioSource = try #require(loadedAudioSource)
        let manifestReference = try manifestPlan.revisionReference
        #expect(audioSource.revision.sourceAssetRevisions == [manifestReference])
        #expect(manifestSource.assetType == .document)
        #expect(audioSource.assetType == .audio)
        #expect(audioSource.media?.speechSourceKind == .originalSpeakerAudio)

        let segments = try await fixture.workspace.store.segments(
            sessionID: fixture.intent.sessionID
        )
        #expect(segments.count == 2)
        for segment in segments {
            #expect(
                try fixture.workspace.store.managedAsset(
                    storageObjectID: segment.storageObjectID
                )?.state == .trashed
            )
        }
    }

    @Test
    func providerLossRetainsUsableBytesAsVisibleIncompleteWithoutPublishingSource() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }

        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        #expect(
            await fixture.coordinator.accept(
                try packets(fixture: fixture, count: 1)[0]
            ) == .accepted
        )
        await fixture.coordinator.providerDidStop(
            track: .microphone,
            error: .sourceStopped(.microphone)
        )
        let interrupted = try #require(await fixture.coordinator.snapshot())
        #expect(interrupted.state == .interrupted)

        let terminal = try await fixture.coordinator.stop()
        #expect(terminal.state == .incomplete)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) == nil
        )
        #expect(
            try await fixture.workspace.store.gaps(
                sessionID: fixture.intent.sessionID
            ).count == 1
        )
        #expect(
            !(try await fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            )).isEmpty
        )
    }

    @Test
    func boundedDiskBudgetInterruptsWithoutPublishingOrDiscardingPartialEvidence() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        let boundedIntent = try RecordingIntent(
            sessionID: fixture.intent.sessionID,
            jobID: fixture.intent.jobID,
            meetingID: fixture.intent.meetingID,
            mode: fixture.intent.mode,
            requestedTracks: fixture.intent.requestedTracks,
            policy: fixture.intent.policy,
            authorization: fixture.intent.authorization,
            publicationPlan: fixture.intent.publicationPlan,
            diskBudgetBytes: 1_024,
            createdAt: fixture.intent.createdAt
        )
        let coordinator = RecordingPersistenceCoordinator(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            assetStorage: fixture.workspace.coordinator,
            assetCatalog: fixture.workspace.store,
            assetFileAccess: fixture.workspace.fileAccess,
            clock: { fixture.timestamp }
        )
        _ = try await coordinator.prepare(intent: boundedIntent, epoch: fixture.epoch)
        var stoppedAdmission = false
        for packet in try packets(fixture: fixture, count: 50) {
            if await coordinator.accept(packet) == .stop {
                stoppedAdmission = true
                break
            }
        }
        #expect(stoppedAdmission)
        #expect((await coordinator.snapshot())?.state == .interrupted)
        let inventory = try fixture.fileStore.recoveryInventory(
            sessionID: boundedIntent.sessionID,
            meetingID: boundedIntent.meetingID
        )
        #expect(inventory.partialRelativePaths.count == 1)
        let terminal = try await coordinator.stop()
        #expect(terminal.state == .failed)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: boundedIntent.publicationPlan.manifest.revisionID
            ) == nil
        )
    }

    @Test
    func processRestartReprovesSealedCAFRecordsGapAndRecoveryIsIdempotent() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }

        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        for packet in try packets(fixture: fixture, count: 50) {
            #expect(await fixture.coordinator.accept(packet) == .accepted)
        }
        #expect((await fixture.coordinator.snapshot())?.state == .recording)

        let recovery = LocalRecordingRecoveryService(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            clock: { fixture.timestamp }
        )
        let first = try await recovery.recover(fixture.intent.sessionID)
        #expect(first.snapshot.state == .recovering)
        #expect(first.verifiedSegments.count == 1)
        #expect(first.gaps.map(\.reason) == [.processInterruption])
        #expect(first.rebuiltCheckpoint?.reconciliationRequired == false)

        let second = try await recovery.recover(fixture.intent.sessionID)
        #expect(second.snapshot == first.snapshot)
        #expect(second.verifiedSegments == first.verifiedSegments)
        #expect(second.gaps == first.gaps)

        let restored = RecordingPersistenceCoordinator(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            assetStorage: fixture.workspace.coordinator,
            assetCatalog: fixture.workspace.store,
            assetFileAccess: fixture.workspace.fileAccess,
            clock: { fixture.timestamp }
        )
        _ = try await restored.restore(
            outcome: second,
            epochs: try await fixture.workspace.store.epochs(
                sessionID: fixture.intent.sessionID
            )
        )
        let terminal = try await restored.stop(reason: .recoveredWithoutResume)
        #expect(terminal.state == .incomplete)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) == nil
        )
    }

    @Test
    func corruptLatestCheckpointRebuildsFromImmutableRowsAndVerifiedCAF() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        for packet in try packets(fixture: fixture, count: 50) {
            #expect(await fixture.coordinator.accept(packet) == .accepted)
        }
        let validCheckpoint = try #require(
            try await fixture.workspace.store.latestCheckpoint(
                sessionID: fixture.intent.sessionID
            )
        )
        try await fixture.workspace.store.databasePool.write { db in
            try db.execute(
                sql: """
                INSERT INTO recording_checkpoints(
                    checkpoint_id, session_id, state_version, format_identifier,
                    format_version, created_at_ms, checkpoint_payload, checkpoint_sha256
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString.lowercased(),
                    fixture.intent.sessionID.canonicalString,
                    validCheckpoint.stateVersion,
                    RecordingCheckpoint.formatIdentifier,
                    RecordingCheckpoint.formatVersion,
                    validCheckpoint.createdAt.millisecondsSinceUnixEpoch + 1,
                    Data("{".utf8),
                    String(repeating: "0", count: 64)
                ]
            )
        }

        let recovery = LocalRecordingRecoveryService(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            clock: { fixture.timestamp }
        )
        let first = try await recovery.recover(fixture.intent.sessionID)
        #expect(first.snapshot.state == .recovering)
        #expect(first.verifiedSegments.count == 1)
        #expect(first.rebuiltCheckpoint != nil)
        #expect(first.rebuiltCheckpoint?.tracks == validCheckpoint.tracks)
        let second = try await recovery.recover(fixture.intent.sessionID)
        #expect(second.snapshot == first.snapshot)
        #expect(second.verifiedSegments == first.verifiedSegments)
        #expect(second.rebuiltCheckpoint == first.rebuiltCheckpoint)
    }

    @Test
    func tamperedSegmentIsRetainedClassifiedAndNeverPublishedCompleteAcrossRepeatedRecovery() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        for packet in try packets(fixture: fixture, count: 50) {
            #expect(await fixture.coordinator.accept(packet) == .accepted)
        }
        let segment = try #require(
            try await fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            ).first
        )
        let descriptor = try RecordingSealedFileDescriptor(
            sessionID: segment.sessionID,
            meetingID: fixture.intent.meetingID,
            storageObjectID: segment.storageObjectID,
            relativePath: segment.relativePath,
            contentHash: segment.contentHash,
            byteSize: segment.byteSize
        )
        let url = try fixture.fileStore.verifiedSealedFileURL(descriptor)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xff]))
        try handle.synchronize()
        try handle.close()

        let recovery = LocalRecordingRecoveryService(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            clock: { fixture.timestamp }
        )
        let first = try await recovery.recover(fixture.intent.sessionID)
        #expect(first.snapshot.state == .recovering)
        #expect(first.verifiedSegments.isEmpty)
        #expect(first.quarantinedRelativePaths == [segment.relativePath])
        #expect(first.gaps.map(\.reason).contains(.damagedSegment))
        let second = try await recovery.recover(fixture.intent.sessionID)
        #expect(second.gaps == first.gaps)
        #expect(second.quarantinedRelativePaths == first.quarantinedRelativePaths)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let restored = RecordingPersistenceCoordinator(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            assetStorage: fixture.workspace.coordinator,
            assetCatalog: fixture.workspace.store,
            assetFileAccess: fixture.workspace.fileAccess,
            clock: { fixture.timestamp }
        )
        _ = try await restored.restore(
            outcome: second,
            epochs: try await fixture.workspace.store.epochs(
                sessionID: fixture.intent.sessionID
            )
        )
        let terminal = try await restored.stop(reason: .recoveredWithoutResume)
        #expect(terminal.state == .failed)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) == nil
        )
    }

    @Test
    func finalizationRestartReusesExactStagingAndPublishedRevisionsBeforeTrashingSegments() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        let interruptedFinalizer = RecordingPersistenceCoordinator(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            assetStorage: fixture.workspace.coordinator,
            assetCatalog: fixture.workspace.store,
            assetFileAccess: fixture.workspace.fileAccess,
            finalizationFault: { point in
                if point == .afterSemanticPublication { throw CancellationError() }
            },
            clock: { fixture.timestamp }
        )
        _ = try await interruptedFinalizer.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        for packet in try packets(fixture: fixture, count: 51) {
            #expect(await interruptedFinalizer.accept(packet) == .accepted)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await interruptedFinalizer.stop()
        }
        let finalizing = try #require(
            try await fixture.workspace.store.session(fixture.intent.sessionID)
        )
        #expect(finalizing.state == .finalizing)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) != nil
        )
        let retainedSegments = try await fixture.workspace.store.segments(
            sessionID: fixture.intent.sessionID
        )
        #expect(!retainedSegments.isEmpty)
        for segment in retainedSegments {
            #expect(
                try fixture.workspace.store.managedAsset(
                    storageObjectID: segment.storageObjectID
                )?.state == .active
            )
        }

        let recovery = LocalRecordingRecoveryService(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            clock: { fixture.timestamp }
        )
        let outcome = try await recovery.recover(fixture.intent.sessionID)
        #expect(outcome.snapshot.state == .finalizing)
        #expect(outcome.verifiedSegments.count == retainedSegments.count)
        let resumedFinalizer = RecordingPersistenceCoordinator(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            assetStorage: fixture.workspace.coordinator,
            assetCatalog: fixture.workspace.store,
            assetFileAccess: fixture.workspace.fileAccess,
            clock: { fixture.timestamp }
        )
        _ = try await resumedFinalizer.restore(
            outcome: outcome,
            epochs: try await fixture.workspace.store.epochs(
                sessionID: fixture.intent.sessionID
            )
        )
        let completed = try await resumedFinalizer.stop(reason: .recoveredWithoutResume)
        #expect(completed.state == .completed)
        #expect(completed.finalManifestRevision == (try fixture.intent.publicationPlan.manifest.revisionReference))
        for segment in retainedSegments {
            #expect(
                try fixture.workspace.store.managedAsset(
                    storageObjectID: segment.storageObjectID
                )?.state == .trashed
            )
        }
    }

    @Test
    func stopBeforeFirstByteFailsWithoutZeroByteAssetAndPartialIsClassified() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }

        _ = try await fixture.coordinator.prepare(
            intent: fixture.intent,
            epoch: fixture.epoch
        )
        let orphan = try fixture.fileStore.prepareSegment(
            sessionID: fixture.intent.sessionID,
            meetingID: fixture.intent.meetingID,
            storageObjectID: mediaID(9_999, as: StorageObjectID.self),
            diskBudgetBytes: fixture.intent.diskBudgetBytes
        )
        let inventory = try fixture.fileStore.recoveryInventory(
            sessionID: fixture.intent.sessionID,
            meetingID: fixture.intent.meetingID
        )
        #expect(inventory.partialRelativePaths.count == 1)
        try fixture.fileStore.discardPartial(orphan)

        let terminal = try await fixture.coordinator.stop()
        #expect(terminal.state == .failed)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) == nil
        )
        #expect(
            (try await fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            )).isEmpty
        )
    }

    @Test
    func taskManagerCancellationUsesVisibleStopAndProviderStartsOnlyAfterDurableIntent() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        let provider = SyntheticAuthorizedCaptureProvider(
            repository: fixture.workspace.store,
            packets: try packets(fixture: fixture, count: 51)
        )
        let registry = TransientRecordingCaptureRegistry()
        try await registry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: PreparedCapture(
                    authorizationID: UUID(),
                    sessionID: fixture.intent.sessionID,
                    epochID: fixture.epoch.epochID,
                    mode: .microphoneOnly
                ),
                epoch: fixture.epoch,
                provider: provider
            ),
            for: fixture.intent.jobID
        )
        let manager = try LocalTaskManager(
            repository: fixture.workspace.repository,
            temporaryStorage: fixture.workspace.temporaryStorage,
            logStore: fixture.workspace.logStore,
            managedAssetRecovery: fixture.workspace.coordinator,
            maximumConcurrentJobs: 1,
            executors: [
                RecordingCaptureJobExecutor(
                    repository: fixture.workspace.store,
                    fileStore: fixture.fileStore,
                    assetStorage: fixture.workspace.coordinator,
                    assetCatalog: fixture.workspace.store,
                    assetFileAccess: fixture.workspace.fileAccess,
                    registry: registry,
                    recovery: LocalRecordingRecoveryService(
                        repository: fixture.workspace.store,
                        fileStore: fixture.fileStore,
                        clock: { fixture.timestamp }
                    ),
                    clock: { fixture.timestamp }
                )
            ]
        )
        let plan = try RecordingCaptureJobPlan(
            intent: fixture.intent,
            initialEpoch: fixture.epoch
        )
        _ = try await manager.enqueue(
            RecordingCaptureJobFactory().request(
                plan: plan,
                requestedBy: JobRequester("synthetic-recording-test")
            )
        )
        for _ in 0..<1_000 {
            let isRecording = try await fixture.workspace.store.session(
                fixture.intent.sessionID
            )?.state == .recording
            let hasSealedSegment = try await !fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            ).isEmpty
            if isRecording && hasSealedSegment { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await provider.sawDurableIntentBeforeStart())
        #expect(
            try await !fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            ).isEmpty
        )
        _ = try await manager.cancel(jobID: fixture.intent.jobID)
        var terminalJob: JobRecord?
        for _ in 0..<1_000 {
            let current = try await manager.job(id: fixture.intent.jobID)
            if current?.state.isTerminal == true {
                terminalJob = current
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        if terminalJob == nil {
            let currentJob = try await manager.job(id: fixture.intent.jobID)
            let currentSession = try await fixture.workspace.store.session(fixture.intent.sessionID)
            let jobState = currentJob?.state.rawValue ?? "missing"
            let sessionState = currentSession?.state.rawValue ?? "missing"
            let providerState = await provider.diagnosticState()
            let diagnostic = "Recording cancellation did not settle: job=\(jobState) "
                + "session=\(sessionState) provider=\(providerState)"
            Issue.record(Comment(rawValue: diagnostic))
        }
        let finishedJob = try #require(terminalJob)
        #expect(finishedJob.state == .succeeded)
        #expect(finishedJob.outputRevisionIDs == (try plan.completedOutputRevisions).sorted())
        #expect(
            try await fixture.workspace.store.session(
                fixture.intent.sessionID
            )?.state == .completed
        )
    }

    @Test
    func interruptedTaskRequiresExplicitNewEpochBeforeResumeAndRetainsIncompleteAudio() async throws {
        let fixture = try makeFixture()
        defer { fixture.workspace.cleanup() }
        let registry = TransientRecordingCaptureRegistry()
        let interruptedProvider = SyntheticAuthorizedCaptureProvider(
            repository: fixture.workspace.store,
            packets: try packets(fixture: fixture, count: 10),
            terminalError: .sourceStopped(.microphone)
        )
        try await registry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: PreparedCapture(
                    authorizationID: UUID(),
                    sessionID: fixture.intent.sessionID,
                    epochID: fixture.epoch.epochID,
                    mode: .microphoneOnly
                ),
                epoch: fixture.epoch,
                provider: interruptedProvider
            ),
            for: fixture.intent.jobID
        )
        let recovery = LocalRecordingRecoveryService(
            repository: fixture.workspace.store,
            fileStore: fixture.fileStore,
            clock: { fixture.timestamp }
        )
        let manager = try LocalTaskManager(
            repository: fixture.workspace.repository,
            temporaryStorage: fixture.workspace.temporaryStorage,
            logStore: fixture.workspace.logStore,
            managedAssetRecovery: fixture.workspace.coordinator,
            maximumConcurrentJobs: 1,
            executors: [
                RecordingCaptureJobExecutor(
                    repository: fixture.workspace.store,
                    fileStore: fixture.fileStore,
                    assetStorage: fixture.workspace.coordinator,
                    assetCatalog: fixture.workspace.store,
                    assetFileAccess: fixture.workspace.fileAccess,
                    registry: registry,
                    recovery: recovery,
                    clock: { fixture.timestamp }
                )
            ]
        )
        let plan = try RecordingCaptureJobPlan(
            intent: fixture.intent,
            initialEpoch: fixture.epoch
        )
        _ = try await manager.enqueue(
            RecordingCaptureJobFactory().request(
                plan: plan,
                requestedBy: JobRequester("synthetic-recording-resume-test")
            )
        )

        var interruptedJob: JobRecord?
        for _ in 0..<400 {
            let current = try await manager.job(id: fixture.intent.jobID)
            if current?.state == .failed {
                interruptedJob = current
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try #require(interruptedJob).errorRecord?.retryable == true)
        #expect(
            try await fixture.workspace.store.session(fixture.intent.sessionID)?.state
                == .interrupted
        )
        #expect(
            try await fixture.workspace.store.segments(
                sessionID: fixture.intent.sessionID
            ).count == 1
        )

        let recovered = try await recovery.recover(fixture.intent.sessionID)
        #expect(recovered.snapshot.state == .recovering)
        let track = try #require(fixture.intent.requestedTracks.first)
        let resumedEpoch = try RecordingEpoch(
            sessionID: fixture.intent.sessionID,
            sequence: 2,
            selectedAt: fixture.timestamp,
            sources: [
                RecordingEpochSource(
                    trackID: track.trackID,
                    kind: .microphone,
                    sessionScopedDeviceToken: digest("c"),
                    audioFormat: fixture.format
                )
            ],
            sourceSetDigest: digest("d"),
            startHostNanoseconds: 20_000_000_000
        )
        let resumedProvider = SyntheticAuthorizedCaptureProvider(
            repository: fixture.workspace.store,
            packets: try packets(
                fixture: fixture,
                count: 10,
                epoch: resumedEpoch,
                startingAtPacketIndex: 10
            )
        )
        try await registry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: PreparedCapture(
                    authorizationID: UUID(),
                    sessionID: fixture.intent.sessionID,
                    epochID: resumedEpoch.epochID,
                    mode: .microphoneOnly
                ),
                epoch: resumedEpoch,
                provider: resumedProvider
            ),
            for: fixture.intent.jobID
        )
        _ = try await manager.retry(jobID: fixture.intent.jobID)
        for _ in 0..<400 {
            if try await fixture.workspace.store.session(
                fixture.intent.sessionID
            )?.state == .recording { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(
            try await fixture.workspace.store.epochs(
                sessionID: fixture.intent.sessionID
            ).map(\.sequence) == [1, 2]
        )

        _ = try await manager.cancel(jobID: fixture.intent.jobID)
        var terminalJob: JobRecord?
        for _ in 0..<400 {
            let current = try await manager.job(id: fixture.intent.jobID)
            if current?.state.isTerminal == true {
                terminalJob = current
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try #require(terminalJob).state == .succeeded)
        let terminalSession = try #require(
            try await fixture.workspace.store.session(fixture.intent.sessionID)
        )
        #expect(terminalSession.state == .incomplete)
        #expect(terminalSession.finalManifestRevision == nil)
        #expect(
            try fixture.workspace.store.sourceAsset(
                revisionID: fixture.intent.publicationPlan.manifest.revisionID
            ) == nil
        )
    }

    private struct Fixture {
        let workspace: MediaTestWorkspace
        let fileStore: LocalRecordingFileStore
        let coordinator: RecordingPersistenceCoordinator
        let intent: RecordingIntent
        let epoch: RecordingEpoch
        let format: CaptureAudioFormat
        let timestamp: UTCInstant
    }

    private func makeFixture() throws -> Fixture {
        let workspace = try MediaTestWorkspace()
        do {
            try workspace.installMeeting()
            let timestamp = mediaInstant(1_800_100_000_100)
            let loadedMeeting = try workspace.store.fetch(
                MeetingProfileV1.self,
                revisionID: mediaID(3, as: RevisionID.self)
            )
            let meeting = try #require(loadedMeeting)
            let meetingUUID = try #require(UUID(uuidString: meeting.meetingID.canonicalString))
            let policy = try LocalSecurityPolicyFactory().makeDefault(
                meeting: meeting,
                sensitivityLabelID: SensitivityLabelID(meetingUUID),
                sensitivityLabelRevisionID: mediaID(9_001, as: RevisionID.self),
                accessPolicyID: AccessPolicyID(meetingUUID),
                accessPolicyRevisionID: mediaID(9_002, as: RevisionID.self),
                createdAt: timestamp
            )
            try workspace.store.insert(policy.sensitivityLabel)
            _ = try workspace.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: policy.sensitivityLabel.labelID,
                    revisionID: policy.sensitivityLabel.revision.revisionID
                ),
                as: SensitivityLabelV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: timestamp
            )
            try workspace.store.insert(policy.accessPolicy)
            _ = try workspace.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: policy.accessPolicy.policyID,
                    revisionID: policy.accessPolicy.revision.revisionID
                ),
                as: AccessPolicyV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: timestamp
            )

            let format = try CaptureAudioFormat(
                sampleRateHertz: 16_000,
                channelCount: 1,
                channelLayout: "interleaved-pcm-s16le",
                formatRevision: 1
            )
            let sessionID = RecordingSessionID(UUID())
            let track = try RecordingTrackRequest(
                kind: .microphone,
                speechSourceKind: .originalSpeakerAudio,
                language: LanguageTag("en")
            )
            let intent = try RecordingIntent(
                sessionID: sessionID,
                jobID: JobID(UUID()),
                meetingID: workspace.meetingID,
                mode: .microphoneOnly,
                requestedTracks: [track],
                policy: RecordingPolicySnapshot(
                    sensitivityLabelRevision: SemanticRevisionReference(
                        logicalID: policy.sensitivityLabel.labelID,
                        revisionID: policy.sensitivityLabel.revision.revisionID
                    ),
                    accessPolicyRevision: SemanticRevisionReference(
                        logicalID: policy.accessPolicy.policyID,
                        revisionID: policy.accessPolicy.revision.revisionID
                    ),
                    dataClassification: .internal,
                    localProcessingAllowed: true,
                    noOutboundMode: true
                ),
                authorization: RecordingAuthorizationEvent(
                    occurredAt: timestamp,
                    directUserAction: true,
                    visibleRecordingAcknowledged: true,
                    participantAndPolicyResponsibilityAcknowledged: true
                ),
                diskBudgetBytes: 1_073_741_824,
                createdAt: timestamp
            )
            let epoch = try RecordingEpoch(
                sessionID: sessionID,
                sequence: 1,
                selectedAt: timestamp,
                sources: [
                    RecordingEpochSource(
                        trackID: track.trackID,
                        kind: .microphone,
                        sessionScopedDeviceToken: digest("a"),
                        audioFormat: format
                    )
                ],
                sourceSetDigest: digest("b"),
                startHostNanoseconds: 1_000_000_000
            )
            let fileStore = LocalRecordingFileStore(workspace: workspace.descriptor)
            return Fixture(
                workspace: workspace,
                fileStore: fileStore,
                coordinator: RecordingPersistenceCoordinator(
                    repository: workspace.store,
                    fileStore: fileStore,
                    assetStorage: workspace.coordinator,
                    assetCatalog: workspace.store,
                    assetFileAccess: workspace.fileAccess,
                    clock: { timestamp }
                ),
                intent: intent,
                epoch: epoch,
                format: format,
                timestamp: timestamp
            )
        } catch {
            workspace.cleanup()
            throw error
        }
    }

    private func packets(
        fixture: Fixture,
        count: Int,
        epoch: RecordingEpoch? = nil,
        startingAtPacketIndex: Int = 0
    ) throws -> [CapturedAudioPacket] {
        let track = fixture.intent.requestedTracks[0]
        let packetEpoch = epoch ?? fixture.epoch
        let frames: UInt32 = 1_600
        let duration: UInt64 = 100_000_000
        return try (0..<count).map { index in
            let start = UInt64(startingAtPacketIndex + index) * duration
            let hostStart = 10_000_000_000 + start
            return try CapturedAudioPacket(
                sessionID: fixture.intent.sessionID,
                epochID: packetEpoch.epochID,
                trackID: track.trackID,
                sequence: UInt64(index + 1),
                mediaRange: RecordingTimeRange(
                    startNanoseconds: start,
                    endNanoseconds: start + duration
                ),
                hostRange: RecordingTimeRange(
                    startNanoseconds: hostStart,
                    endNanoseconds: hostStart + duration
                ),
                format: fixture.format,
                frameCount: frames,
                linearPCM: Data(repeating: 0, count: Int(frames) * 2)
            )
        }
    }

    private func digest(_ character: String) -> ContentDigest {
        try! ContentDigest(
            algorithm: .sha256,
            lowercaseHex: String(repeating: character, count: 64)
        )
    }
}

private actor SyntheticAuthorizedCaptureProvider: AuthorizedAudioCaptureProvider {
    private let repository: any RecordingSessionRepository
    private let packets: [CapturedAudioPacket]
    private let terminalError: CaptureProviderError?
    private var durableBeforeStart = false
    private var deliveryTask: Task<Void, Never>?
    private var startReturned = false
    private var stopEntered = false
    private var stopFinished = false

    init(
        repository: any RecordingSessionRepository,
        packets: [CapturedAudioPacket],
        terminalError: CaptureProviderError? = nil
    ) {
        self.repository = repository
        self.packets = packets
        self.terminalError = terminalError
    }

    func prepare(_ request: PreparedCaptureRequest) async throws -> PreparedCapture {
        PreparedCapture(
            authorizationID: request.authorization.authorizationID,
            sessionID: request.authorization.sessionID,
            epochID: request.authorization.epochID,
            mode: request.authorization.mode
        )
    }

    func start(
        _ prepared: PreparedCapture,
        sink: any CapturedAudioPacketSink
    ) async throws -> CaptureHandle {
        durableBeforeStart = try await repository.session(prepared.sessionID) != nil
        let packets = packets
        let terminalError = terminalError
        deliveryTask = Task {
            var admittedAllPackets = true
            for packet in packets {
                guard !Task.isCancelled,
                      await sink.accept(packet) == .accepted
                else {
                    admittedAllPackets = false
                    break
                }
            }
            if admittedAllPackets, !Task.isCancelled, let terminalError {
                await sink.providerDidStop(track: .microphone, error: terminalError)
            }
        }
        startReturned = true
        return CaptureHandle(
            sessionID: prepared.sessionID,
            epochID: prepared.epochID
        )
    }

    func stop(_ handle: CaptureHandle) async {
        stopEntered = true
        deliveryTask?.cancel()
        await deliveryTask?.value
        deliveryTask = nil
        stopFinished = true
    }

    func sawDurableIntentBeforeStart() -> Bool { durableBeforeStart }

    func diagnosticState() -> String {
        "startReturned=\(startReturned),stopEntered=\(stopEntered),stopFinished=\(stopFinished)"
    }
}
