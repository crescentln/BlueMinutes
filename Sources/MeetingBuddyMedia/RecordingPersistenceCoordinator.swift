@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum RecordingFinalizationFaultPoint: Hashable, Sendable {
    case afterAudioManagedAsset
    case afterManifestManagedAsset
    case afterSemanticPublication
    case afterTerminalCommit
}

public actor RecordingPersistenceCoordinator: CapturedAudioPacketSink {
    private let repository: any RecordingSessionRepository
    private let fileStore: any RecordingSegmentFileStore
    private let assetStorage: any MediaIntakeStorage
    private let assetCatalog: any MediaAssetCatalog
    private let assetFileAccess: any ManagedMediaFileAccess
    private let clock: @Sendable () -> UTCInstant
    private let finalizationFault: @Sendable (RecordingFinalizationFaultPoint) throws -> Void

    private var snapshotValue: RecordingSessionSnapshot?
    private var currentEpoch: RecordingEpoch?
    private var tracks: [RecordingTrackID: CaptureTrackState] = [:]

    public init(
        repository: any RecordingSessionRepository,
        fileStore: any RecordingSegmentFileStore,
        assetStorage: any MediaIntakeStorage,
        assetCatalog: any MediaAssetCatalog,
        assetFileAccess: any ManagedMediaFileAccess,
        finalizationFault: @escaping @Sendable (RecordingFinalizationFaultPoint) throws -> Void = { _ in },
        clock: @escaping @Sendable () -> UTCInstant = {
            try! UTCInstant(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
            )
        }
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.assetStorage = assetStorage
        self.assetCatalog = assetCatalog
        self.assetFileAccess = assetFileAccess
        self.finalizationFault = finalizationFault
        self.clock = clock
    }

    @discardableResult
    public func prepare(
        intent: RecordingIntent,
        epoch: RecordingEpoch
    ) async throws -> RecordingSessionSnapshot {
        guard epoch.sessionID == intent.sessionID,
              Set(epoch.sources.map(\.trackID)) == Set(intent.requestedTracks.map(\.trackID))
        else {
            throw RecordingContractError.invalidIntent("The capture epoch does not cover the exact requested tracks.")
        }
        let snapshot = try await repository.createIntent(intent)
        guard snapshot.state == .preparing else {
            throw RecordingContractError.integrityFailure("A new capture can start only from its durable preparing intent.")
        }
        try await repository.registerEpoch(epoch)
        snapshotValue = snapshot
        currentEpoch = epoch
        tracks = Dictionary(uniqueKeysWithValues: intent.requestedTracks.map { request in
            let source = epoch.sources.first { $0.trackID == request.trackID }!
            return (request.trackID, CaptureTrackState(request: request, epochSource: source))
        })
        return snapshot
    }

    @discardableResult
    public func prepareResume(epoch: RecordingEpoch) async throws -> RecordingSessionSnapshot {
        var snapshot = try requireSnapshot()
        guard snapshot.state == .interrupted || snapshot.state == .recovering,
              epoch.sessionID == snapshot.intent.sessionID,
              Set(epoch.sources.map(\.trackID)) == Set(snapshot.intent.requestedTracks.map(\.trackID))
        else {
            throw RecordingContractError.integrityFailure("Resume requires the interrupted session and a complete new selection epoch.")
        }
        if snapshot.state == .interrupted {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .interrupted,
                    to: .recovering,
                    reason: .recoveryLeaseAcquired,
                    actor: .persistenceCoordinator,
                    occurredAt: clock()
                )
            )
        }
        try await repository.registerEpoch(epoch)
        for request in snapshot.intent.requestedTracks {
            guard let source = epoch.sources.first(where: { $0.trackID == request.trackID }) else {
                throw RecordingContractError.integrityFailure("The resumed epoch omitted a requested track.")
            }
            if let track = tracks[request.trackID] {
                track.beginEpoch(source)
            } else {
                tracks[request.trackID] = CaptureTrackState(request: request, epochSource: source)
            }
        }
        currentEpoch = epoch
        snapshotValue = snapshot
        return snapshot
    }

    public func snapshot() -> RecordingSessionSnapshot? { snapshotValue }

    /// Reconstructs bounded in-memory cursors from normalized rows and files.
    /// The caller must first run the recording recovery service, which proves
    /// every segment descriptor against the sealed CAF bytes.
    @discardableResult
    public func restore(
        outcome: RecordingRecoveryOutcome,
        epochs: [RecordingEpoch]
    ) throws -> RecordingSessionSnapshot {
        let snapshot = outcome.snapshot
        guard snapshot.state == .recovering || snapshot.state == .finalizing,
              !epochs.isEmpty,
              epochs.allSatisfy({ $0.sessionID == snapshot.intent.sessionID }),
              Set(epochs.flatMap(\.sources).map(\.trackID))
                == Set(snapshot.intent.requestedTracks.map(\.trackID))
        else {
            throw RecordingContractError.integrityFailure(
                "Recovered recording rows do not reconstruct one exact session."
            )
        }
        let latestEpoch = epochs.max { ($0.sequence, $0.epochID) < ($1.sequence, $1.epochID) }!
        let grouped = Dictionary(grouping: outcome.verifiedSegments, by: \.trackID)
        var restored: [RecordingTrackID: CaptureTrackState] = [:]
        for request in snapshot.intent.requestedTracks {
            guard let source = latestEpoch.sources.first(where: { $0.trackID == request.trackID }) else {
                throw RecordingContractError.integrityFailure(
                    "The latest recovered epoch omits a requested track."
                )
            }
            let state = CaptureTrackState(request: request, epochSource: source)
            let segments = (grouped[request.trackID] ?? []).sorted {
                ($0.sealedAt, $0.sequence, $0.segmentID)
                    < ($1.sealedAt, $1.sequence, $1.segmentID)
            }
            state.sealedSegments = segments
            state.totalSealedFrames = segments.reduce(0) { $0 + $1.frameCount }
            if let last = segments.last {
                state.rollingDescriptorDigest = last.rollingDescriptorDigest
                state.nextSegmentSequence = last.sequence + 1
            }
            restored[request.trackID] = state
        }
        snapshotValue = snapshot
        currentEpoch = latestEpoch
        tracks = restored
        return snapshot
    }

    public func accept(_ packet: CapturedAudioPacket) async -> CapturePacketDisposition {
        do {
            var snapshot = try requireSnapshot()
            guard let epoch = currentEpoch,
                  packet.sessionID == snapshot.intent.sessionID,
                  packet.epochID == epoch.epochID,
                  let track = tracks[packet.trackID],
                  packet.format == track.epochSource.audioFormat,
                  packet.mediaRange.durationNanoseconds <= 2_000_000_000
            else {
                try await interrupt(
                    trackID: packet.trackID,
                    reason: .formatChanged,
                    gapReason: .formatChanged
                )
                return .stop
            }

            if snapshot.state == .preparing || snapshot.state == .recovering {
                try openWriterIfNeeded(track)
                let reason: RecordingTransitionReason = snapshot.state == .preparing
                    ? .firstPacketAccepted : .userReselectedSource
                snapshot = try await repository.transition(
                    RecordingTransition(
                        sessionID: snapshot.intent.sessionID,
                        expectedStateVersion: snapshot.stateVersion,
                        from: snapshot.state,
                        to: .recording,
                        reason: reason,
                        actor: .persistenceCoordinator,
                        occurredAt: clock()
                    )
                )
                snapshotValue = snapshot
            }
            guard snapshot.state == .recording else { return .stop }
            guard packet.sequence == track.expectedPacketSequence else {
                try await interrupt(
                    trackID: packet.trackID,
                    reason: .backpressureExceeded,
                    gapReason: .packetBackpressure
                )
                return .backpressure
            }

            try openWriterIfNeeded(track)
            if let writer = track.writer,
               writer.frameCount > 0,
               packet.mediaRange.endNanoseconds - writer.firstMediaStartNanoseconds > 5_000_000_000
            {
                try await sealCurrentSegment(track)
                try openWriterIfNeeded(track)
            }
            guard let writer = track.writer else {
                throw RecordingContractError.integrityFailure("The bounded CAF writer was not available.")
            }
            try writer.write(packet)
            track.expectedPacketSequence += 1
            if writer.mediaSpanNanoseconds >= 5_000_000_000 {
                try await sealCurrentSegment(track)
            }
            return .accepted
        } catch {
            try? await interrupt(
                trackID: packet.trackID,
                reason: .diskWriteFailure,
                gapReason: .damagedSegment
            )
            return .stop
        }
    }

    public func providerDidStop(
        track kind: CaptureTrackKind,
        error: CaptureProviderError?
    ) async {
        guard error != nil,
              let track = tracks.values.first(where: { $0.request.kind == kind })
        else { return }
        let mapping: (RecordingTransitionReason, RecordingGapReason)
        switch error {
        case .permissionDenied:
            mapping = (.permissionRevoked, .permissionLoss)
        case .sourceStopped:
            mapping = (.sourceEnded, .sourceEnded)
        case .formatChanged:
            mapping = (.formatChanged, .formatChanged)
        case .boundedQueueExceeded:
            mapping = (.backpressureExceeded, .packetBackpressure)
        default:
            mapping = (.sourceUnavailable, .sourceEnded)
        }
        try? await interrupt(trackID: track.request.trackID, reason: mapping.0, gapReason: mapping.1)
    }

    @discardableResult
    public func stop(
        reason: RecordingTransitionReason = .userStop
    ) async throws -> RecordingSessionSnapshot {
        var snapshot = try requireSnapshot()
        if snapshot.state.isTerminal { return snapshot }
        if snapshot.state == .interrupted {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .interrupted,
                    to: .recovering,
                    reason: .recoveryLeaseAcquired,
                    actor: .persistenceCoordinator,
                    occurredAt: clock()
                )
            )
        }
        if snapshot.state == .preparing || snapshot.state == .recording || snapshot.state == .recovering {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: snapshot.state,
                    to: .stopping,
                    reason: reason,
                    actor: .user,
                    occurredAt: clock()
                )
            )
        }
        snapshotValue = snapshot

        var sealingFailed = false
        for track in tracks.values where track.writer?.frameCount ?? 0 > 0 {
            do { try await sealCurrentSegment(track) } catch { sealingFailed = true }
        }
        snapshot = try requireSnapshot()
        if snapshot.state == .stopping {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .stopping,
                    to: .finalizing,
                    reason: .writersDrained,
                    actor: .persistenceCoordinator,
                    occurredAt: clock()
                )
            )
            snapshotValue = snapshot
        }
        return try await finalize(sealingFailed: sealingFailed)
    }

    private func finalize(sealingFailed: Bool) async throws -> RecordingSessionSnapshot {
        var snapshot = try requireSnapshot()
        guard snapshot.state == .finalizing else { return snapshot }
        let gaps = try await repository.gaps(sessionID: snapshot.intent.sessionID)
        let allRequiredHaveAudio = snapshot.intent.requestedTracks
            .filter(\.required)
            .allSatisfy { !(tracks[$0.trackID]?.sealedSegments.isEmpty ?? true) }
        let usableSegments = tracks.values.flatMap(\.sealedSegments)
        guard !usableSegments.isEmpty else {
            snapshot = try await terminalTransition(
                snapshot: snapshot,
                state: .failed,
                reason: .noUsableAudio,
                manifest: nil
            )
            return snapshot
        }
        guard !sealingFailed, gaps.isEmpty, allRequiredHaveAudio else {
            snapshot = try await terminalTransition(
                snapshot: snapshot,
                state: .incomplete,
                reason: .verifiedIncomplete,
                manifest: nil
            )
            return snapshot
        }

        do {
            let manifestReference = try snapshot.intent.publicationPlan.manifest.revisionReference
            var manifestTracks: [CaptureManifestTrackV1] = []
            var publishedAudio: [(SourceAssetV1, RecordingFinalizationFileLease)] = []
            for track in tracks.values.sorted(by: { $0.request.trackID < $1.request.trackID }) {
                guard let trackPlan = snapshot.intent.publicationPlan.tracks.first(where: {
                    $0.trackID == track.request.trackID
                }) else {
                    throw RecordingContractError.integrityFailure("The durable publication plan omitted a capture track.")
                }
                let lease = try fileStore.prepareFinalizationFile(
                    sessionID: snapshot.intent.sessionID,
                    meetingID: snapshot.intent.meetingID,
                    trackID: track.request.trackID,
                    fileExtension: try ManagedFileExtension("caf"),
                    diskBudgetBytes: snapshot.intent.diskBudgetBytes
                )
                let expectedFrameCount = track.sealedSegments.reduce(UInt64(0)) {
                    $0 + $1.frameCount
                }
                let frameCount: UInt64
                if lease.sealedFileAlreadyExists {
                    frameCount = try validateFinalizedAudio(
                        at: lease.sealedFileURL,
                        format: track.epochSource.audioFormat,
                        expectedFrameCount: expectedFrameCount
                    )
                } else {
                    frameCount = try concatenate(track: track, to: lease.partialFileURL)
                }
                let sealedURL = try fileStore.sealFinalizationFile(lease)
                let record = try importOrVerifyManagedAsset(
                    stagedURL: sealedURL,
                    meetingID: snapshot.intent.meetingID,
                    storageObjectID: trackPlan.asset.storageObjectID,
                    fileExtension: try ManagedFileExtension("caf"),
                    createdAt: clock(),
                    dataClassification: snapshot.intent.policy.dataClassification
                )
                try finalizationFault(.afterAudioManagedAsset)
                let manifestTrack = try CaptureManifestTrackV1(
                    request: track.request,
                    format: track.epochSource.audioFormat,
                    segments: track.sealedSegments,
                    finalContentHash: record.contentHash,
                    finalByteSize: record.byteSize,
                    finalFrameCount: frameCount
                )
                manifestTracks.append(manifestTrack)
                let source = try CaptureSourceAssetFactory.capturedAudio(
                    record: record,
                    plan: trackPlan.asset,
                    request: track.request,
                    format: track.epochSource.audioFormat,
                    frameCount: frameCount,
                    manifestRevision: manifestReference
                )
                publishedAudio.append((source, lease))
            }

            let manifest = try CaptureManifestV1(
                session: snapshot,
                terminalState: .completed,
                epochs: try await repository.epochs(sessionID: snapshot.intent.sessionID),
                tracks: manifestTracks,
                gaps: gaps,
                stateEventChainDigest: try await repository.stateEventChainDigest(
                    sessionID: snapshot.intent.sessionID
                ),
                createdAt: snapshot.updatedAt
            )
            let manifestLease = try fileStore.prepareFinalizationFile(
                sessionID: snapshot.intent.sessionID,
                meetingID: snapshot.intent.meetingID,
                trackID: nil,
                fileExtension: try ManagedFileExtension("json"),
                diskBudgetBytes: snapshot.intent.diskBudgetBytes
            )
            let manifestPayload = try manifest.canonicalPayload()
            if manifestLease.sealedFileAlreadyExists {
                let retainedPayload = try fileDigestAndSize(manifestLease.sealedFileURL)
                guard retainedPayload == (try digestAndSize(manifestPayload)) else {
                    throw RecordingContractError.integrityFailure(
                        "A retained finalization manifest does not match the exact retry payload."
                    )
                }
            } else {
                try manifestPayload.write(to: manifestLease.partialFileURL)
            }
            let sealedManifestURL = try fileStore.sealFinalizationFile(manifestLease)
            let manifestRecord = try importOrVerifyManagedAsset(
                stagedURL: sealedManifestURL,
                meetingID: snapshot.intent.meetingID,
                storageObjectID: snapshot.intent.publicationPlan.manifest.storageObjectID,
                fileExtension: try ManagedFileExtension("json"),
                createdAt: manifest.createdAt,
                dataClassification: snapshot.intent.policy.dataClassification
            )
            try finalizationFault(.afterManifestManagedAsset)
            let manifestSource = try CaptureSourceAssetFactory.manifest(
                record: manifestRecord,
                plan: snapshot.intent.publicationPlan.manifest,
                manifest: manifest
            )
            try insertIdempotently(manifestSource)
            for (source, _) in publishedAudio { try insertIdempotently(source) }
            try finalizationFault(.afterSemanticPublication)

            for (_, lease) in publishedAudio { try? fileStore.discardFinalizationFile(lease) }
            try? fileStore.discardFinalizationFile(manifestLease)
            snapshot = try await terminalTransition(
                snapshot: snapshot,
                state: .completed,
                reason: .verifiedComplete,
                manifest: manifestReference
            )
            try finalizationFault(.afterTerminalCommit)
            for segment in usableSegments {
                _ = try? assetStorage.moveToTrash(
                    storageObjectID: segment.storageObjectID,
                    at: clock()
                )
            }
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot = try await terminalTransition(
                snapshot: snapshot,
                state: .incomplete,
                reason: .verifiedIncomplete,
                manifest: nil
            )
            return snapshot
        }
    }

    private func importOrVerifyManagedAsset(
        stagedURL: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension,
        createdAt: UTCInstant,
        dataClassification: DataClassification
    ) throws -> ManagedAssetRecord {
        let expected = try fileDigestAndSize(stagedURL)
        let existing = try assetCatalog.managedAsset(storageObjectID: storageObjectID)
        let record = try existing ?? assetStorage.importFile(
            from: stagedURL,
            meetingID: meetingID,
            storageObjectID: storageObjectID,
            fileExtension: fileExtension,
            createdAt: createdAt,
            dataClassification: dataClassification,
            retentionClass: .workspaceManaged
        )
        guard record.storageObjectID == storageObjectID,
              record.meetingID == meetingID,
              record.contentHash == expected.digest,
              record.byteSize == expected.byteSize,
              record.dataClassification == dataClassification,
              record.retentionClass == .workspaceManaged,
              record.state == .active
        else {
            throw RecordingContractError.integrityFailure(
                "A managed recording publication does not match its exact staged bytes and policy."
            )
        }
        let managedURL = try assetFileAccess.verifiedFileURL(
            for: ManagedAssetReference(storageObjectID: storageObjectID)
        )
        guard try fileDigestAndSize(managedURL) == expected else {
            throw RecordingContractError.integrityFailure(
                "A managed recording publication failed independent byte verification."
            )
        }
        return record
    }

    private func validateFinalizedAudio(
        at url: URL,
        format: CaptureAudioFormat,
        expectedFrameCount: UInt64
    ) throws -> UInt64 {
        let expectedFormat = try pcmFormat(format)
        let file = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        guard file.processingFormat == expectedFormat,
              UInt64(file.length) == expectedFrameCount
        else {
            throw RecordingContractError.integrityFailure(
                "A retained final CAF does not match the exact retry format and frame count."
            )
        }
        return expectedFrameCount
    }

    private func digestAndSize(_ data: Data) throws -> (digest: ContentDigest, byteSize: UInt64) {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()
        return (
            try ContentDigest(algorithm: .sha256, lowercaseHex: digest),
            UInt64(data.count)
        )
    }

    private func fileDigestAndSize(
        _ url: URL
    ) throws -> (digest: ContentDigest, byteSize: UInt64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteSize: UInt64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            let (nextSize, overflow) = byteSize.addingReportingOverflow(UInt64(data.count))
            guard !overflow else {
                throw RecordingContractError.integrityFailure(
                    "A recording publication exceeded supported file size."
                )
            }
            byteSize = nextSize
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (try ContentDigest(algorithm: .sha256, lowercaseHex: digest), byteSize)
    }

    private func concatenate(
        track: CaptureTrackState,
        to destination: URL
    ) throws -> UInt64 {
        let format = try pcmFormat(track.epochSource.audioFormat)
        var output: AVAudioFile? = try AVAudioFile(
            forWriting: destination,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        var totalFrames: UInt64 = 0
        for segment in track.sealedSegments.sorted(by: { $0.sequence < $1.sequence }) {
            let descriptor = try RecordingSealedFileDescriptor(
                sessionID: segment.sessionID,
                meetingID: try requireSnapshot().intent.meetingID,
                storageObjectID: segment.storageObjectID,
                relativePath: segment.relativePath,
                contentHash: segment.contentHash,
                byteSize: segment.byteSize
            )
            let url = try fileStore.verifiedSealedFileURL(descriptor)
            let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
            guard input.processingFormat == format,
                  UInt64(input.length) == segment.frameCount
            else {
                throw RecordingContractError.integrityFailure("A sealed CAF changed before final concatenation.")
            }
            while input.framePosition < input.length {
                let count = AVAudioFrameCount(min(Int64(8_192), input.length - input.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                    throw RecordingContractError.integrityFailure("The final CAF buffer could not be allocated.")
                }
                try input.read(into: buffer, frameCount: count)
                try output?.write(from: buffer)
                totalFrames += UInt64(buffer.frameLength)
            }
        }
        output = nil
        return totalFrames
    }

    private func insertIdempotently(_ source: SourceAssetV1) throws {
        if let existing = try assetCatalog.sourceAsset(revisionID: source.revision.revisionID) {
            guard existing == source else {
                throw RecordingContractError.integrityFailure("A recording publication revision ID was reused.")
            }
            return
        }
        try assetCatalog.insertSourceAsset(source)
    }

    private func openWriterIfNeeded(_ track: CaptureTrackState) throws {
        guard track.writer == nil else { return }
        let snapshot = try requireSnapshot()
        let storageID = StorageObjectID(UUID())
        let lease = try fileStore.prepareSegment(
            sessionID: snapshot.intent.sessionID,
            meetingID: snapshot.intent.meetingID,
            storageObjectID: storageID,
            diskBudgetBytes: snapshot.intent.diskBudgetBytes
        )
        do {
            track.writer = try BoundedCAFSegmentWriter(
                lease: lease,
                format: track.epochSource.audioFormat,
                segmentSequence: track.nextSegmentSequence
            )
        } catch {
            try? fileStore.discardPartial(lease)
            throw error
        }
    }

    private func sealCurrentSegment(_ track: CaptureTrackState) async throws {
        guard let writer = track.writer, writer.frameCount > 0 else { return }
        let summary = try writer.close()
        track.writer = nil
        let descriptor = try fileStore.sealSegment(summary.lease)
        let retainedBytes = tracks.values
            .flatMap(\.sealedSegments)
            .reduce(UInt64(0)) { $0 + $1.byteSize }
        guard retainedBytes <= snapshotValue!.intent.diskBudgetBytes,
              descriptor.byteSize <= snapshotValue!.intent.diskBudgetBytes - retainedBytes
        else {
            throw RecordingContractError.invalidSegment(
                "The recording session exceeded its approved local disk budget."
            )
        }
        let url = try fileStore.verifiedSealedFileURL(descriptor)
        let reopened = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let expectedFormat = try pcmFormat(summary.format)
        guard UInt64(reopened.length) == summary.frameCount,
              reopened.processingFormat == expectedFormat
        else {
            throw RecordingContractError.integrityFailure("The sealed CAF failed header/frame revalidation.")
        }
        let rollingDigest = try nextRollingDigest(
            previous: track.rollingDescriptorDigest,
            descriptor: descriptor,
            sequence: summary.segmentSequence,
            mediaRange: summary.mediaRange,
            frameCount: summary.frameCount
        )
        let sealedAt = clock()
        let segment = try SealedCaptureSegment(
            sessionID: descriptor.sessionID,
            epochID: currentEpoch!.epochID,
            trackID: track.request.trackID,
            sequence: summary.segmentSequence,
            mediaRange: summary.mediaRange,
            hostRange: summary.hostRange,
            frameCount: summary.frameCount,
            format: summary.format,
            storageObjectID: descriptor.storageObjectID,
            relativePath: descriptor.relativePath,
            contentHash: descriptor.contentHash,
            byteSize: descriptor.byteSize,
            rollingDescriptorDigest: rollingDigest,
            sealedAt: sealedAt
        )
        let priorTotalFrames = track.totalSealedFrames
        let priorRollingDigest = track.rollingDescriptorDigest
        let priorNextSequence = track.nextSegmentSequence
        track.sealedSegments.append(segment)
        track.totalSealedFrames += segment.frameCount
        track.rollingDescriptorDigest = rollingDigest
        track.nextSegmentSequence += 1
        let snapshot = try requireSnapshot()
        let checkpoint = try RecordingCheckpoint(
            sessionID: snapshot.intent.sessionID,
            jobID: snapshot.intent.jobID,
            meetingID: snapshot.intent.meetingID,
            stateVersion: snapshot.stateVersion,
            state: snapshot.state,
            lastStateEventID: snapshot.lastEventID,
            currentEpochID: currentEpoch?.epochID,
            requiredTrackIDs: snapshot.intent.requestedTracks.filter(\.required).map(\.trackID),
            tracks: try tracks.values.compactMap { value in
                guard let last = value.sealedSegments.last else { return nil }
                return try RecordingTrackCheckpoint(
                    trackID: value.request.trackID,
                    lastSealedSequence: last.sequence,
                    lastCoveredMediaRange: last.mediaRange,
                    sealedFrameCount: value.totalSealedFrames,
                    lastSegmentDigest: last.contentHash,
                    rollingDescriptorDigest: value.rollingDescriptorDigest
                )
            },
            outstandingGapCount: UInt32(try await repository.gaps(sessionID: snapshot.intent.sessionID).count),
            reconciliationRequired: false,
            createdAt: clock()
        )
        do {
            _ = try await repository.seal(segment, checkpoint: checkpoint)
        } catch {
            track.sealedSegments.removeLast()
            track.totalSealedFrames = priorTotalFrames
            track.rollingDescriptorDigest = priorRollingDigest
            track.nextSegmentSequence = priorNextSequence
            throw error
        }
    }

    private func interrupt(
        trackID: RecordingTrackID,
        reason: RecordingTransitionReason,
        gapReason: RecordingGapReason
    ) async throws {
        guard var snapshot = snapshotValue, !snapshot.state.isTerminal else { return }
        if snapshot.state == .recording {
            var transitionReason = reason
            var recordedGapReason = gapReason
            if let track = tracks[trackID], track.writer?.frameCount ?? 0 > 0 {
                do {
                    try await sealCurrentSegment(track)
                } catch {
                    transitionReason = .diskWriteFailure
                    recordedGapReason = .damagedSegment
                }
            }
            let gap = try RecordingGap(
                sessionID: snapshot.intent.sessionID,
                epochID: currentEpoch?.epochID,
                trackID: trackID,
                mediaRange: nil,
                hostRange: nil,
                reason: recordedGapReason == .unknownBoundary
                    ? .unknownBoundary : recordedGapReason,
                detectedBy: .persistenceCoordinator,
                detectedAt: clock()
            )
            try await repository.recordGap(gap)
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .recording,
                    to: .interrupted,
                    reason: transitionReason,
                    actor: .persistenceCoordinator,
                    occurredAt: clock()
                )
            )
            snapshotValue = snapshot
        } else if snapshot.state == .preparing {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: snapshot.intent.sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .preparing,
                    to: .failed,
                    reason: .noUsableAudio,
                    actor: .persistenceCoordinator,
                    occurredAt: clock()
                )
            )
            snapshotValue = snapshot
        }
    }

    private func terminalTransition(
        snapshot: RecordingSessionSnapshot,
        state: RecordingState,
        reason: RecordingTransitionReason,
        manifest: SemanticRevisionReference?
    ) async throws -> RecordingSessionSnapshot {
        let value = try await repository.transition(
            RecordingTransition(
                sessionID: snapshot.intent.sessionID,
                expectedStateVersion: snapshot.stateVersion,
                from: .finalizing,
                to: state,
                reason: reason,
                actor: .persistenceCoordinator,
                occurredAt: clock(),
                finalManifestRevision: manifest
            )
        )
        snapshotValue = value
        return value
    }

    private func requireSnapshot() throws -> RecordingSessionSnapshot {
        guard let snapshotValue else {
            throw RecordingContractError.integrityFailure("The recording coordinator has no durable session intent.")
        }
        return snapshotValue
    }

    private func nextRollingDigest(
        previous: ContentDigest,
        descriptor: RecordingSealedFileDescriptor,
        sequence: UInt64,
        mediaRange: RecordingTimeRange,
        frameCount: UInt64
    ) throws -> ContentDigest {
        let material = [
            previous.lowercaseHex,
            String(sequence),
            String(mediaRange.startNanoseconds),
            String(mediaRange.endNanoseconds),
            String(frameCount),
            descriptor.contentHash.lowercaseHex,
            String(descriptor.byteSize)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func pcmFormat(_ format: CaptureAudioFormat) throws -> AVAudioFormat {
        guard format.channelLayout == "interleaved-pcm-s16le",
              let value = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(format.sampleRateHertz),
                  channels: AVAudioChannelCount(format.channelCount),
                  interleaved: true
              )
        else {
            throw RecordingContractError.invalidPacket("The CAF coordinator accepts only its normalized signed-16-bit PCM packets.")
        }
        return value
    }
}

private final class CaptureTrackState {
    let request: RecordingTrackRequest
    var epochSource: RecordingEpochSource
    var expectedPacketSequence: UInt64 = 1
    var nextSegmentSequence: UInt64 = 1
    var writer: BoundedCAFSegmentWriter?
    var sealedSegments: [SealedCaptureSegment] = []
    var totalSealedFrames: UInt64 = 0
    var rollingDescriptorDigest = try! ContentDigest(
        algorithm: .sha256,
        lowercaseHex: String(repeating: "0", count: 64)
    )

    init(request: RecordingTrackRequest, epochSource: RecordingEpochSource) {
        self.request = request
        self.epochSource = epochSource
    }

    func beginEpoch(_ source: RecordingEpochSource) {
        epochSource = source
        expectedPacketSequence = 1
        writer = nil
    }
}

private final class BoundedCAFSegmentWriter {
    struct Summary {
        let lease: RecordingWritableSegmentLease
        let format: CaptureAudioFormat
        let segmentSequence: UInt64
        let mediaRange: RecordingTimeRange
        let hostRange: RecordingTimeRange
        let frameCount: UInt64
    }

    let lease: RecordingWritableSegmentLease
    let format: CaptureAudioFormat
    let segmentSequence: UInt64
    private var file: AVAudioFile?
    private(set) var frameCount: UInt64 = 0
    private(set) var firstMediaStartNanoseconds: UInt64 = 0
    private var mediaEndNanoseconds: UInt64 = 0
    private var firstHostStartNanoseconds: UInt64 = 0
    private var hostEndNanoseconds: UInt64 = 0

    init(
        lease: RecordingWritableSegmentLease,
        format: CaptureAudioFormat,
        segmentSequence: UInt64
    ) throws {
        guard format.channelLayout == "interleaved-pcm-s16le",
              let pcm = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(format.sampleRateHertz),
                  channels: AVAudioChannelCount(format.channelCount),
                  interleaved: true
              )
        else { throw RecordingContractError.invalidPacket("The CAF writer requires normalized interleaved PCM.") }
        self.lease = lease
        self.format = format
        self.segmentSequence = segmentSequence
        file = try AVAudioFile(
            forWriting: lease.partialFileURL,
            settings: pcm.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    var mediaSpanNanoseconds: UInt64 {
        frameCount == 0 ? 0 : mediaEndNanoseconds - firstMediaStartNanoseconds
    }

    func write(_ packet: CapturedAudioPacket) throws {
        guard packet.format == format,
              let pcm = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(format.sampleRateHertz),
                  channels: AVAudioChannelCount(format.channelCount),
                  interleaved: true
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: pcm,
                  frameCapacity: AVAudioFrameCount(packet.frameCount)
              ),
              let channelData = buffer.int16ChannelData
        else { throw RecordingContractError.invalidPacket("The capture packet cannot be represented in the CAF writer.") }
        let expectedBytes = Int(packet.frameCount) * Int(format.channelCount) * MemoryLayout<Int16>.size
        guard packet.linearPCM.count == expectedBytes,
              mediaSpanNanoseconds == 0 || packet.mediaRange.startNanoseconds <= mediaEndNanoseconds + 1_000_000,
              mediaSpanNanoseconds == 0 || packet.hostRange.startNanoseconds <= hostEndNanoseconds + 1_000_000
        else { throw RecordingContractError.invalidPacket("The packet bytes or continuity do not match the active segment.") }
        buffer.frameLength = AVAudioFrameCount(packet.frameCount)
        _ = packet.linearPCM.withUnsafeBytes { bytes in
            memcpy(channelData[0], bytes.baseAddress!, expectedBytes)
        }
        try file?.write(from: buffer)
        if frameCount == 0 {
            firstMediaStartNanoseconds = packet.mediaRange.startNanoseconds
            firstHostStartNanoseconds = packet.hostRange.startNanoseconds
        }
        mediaEndNanoseconds = packet.mediaRange.endNanoseconds
        hostEndNanoseconds = packet.hostRange.endNanoseconds
        frameCount += UInt64(packet.frameCount)
        guard mediaSpanNanoseconds <= 6_000_000_000 else {
            throw RecordingContractError.invalidSegment("The open CAF segment exceeded six seconds.")
        }
    }

    func close() throws -> Summary {
        guard frameCount > 0 else {
            throw RecordingContractError.invalidSegment("A zero-byte capture segment cannot be sealed.")
        }
        file = nil
        return Summary(
            lease: lease,
            format: format,
            segmentSequence: segmentSequence,
            mediaRange: try RecordingTimeRange(
                startNanoseconds: firstMediaStartNanoseconds,
                endNanoseconds: mediaEndNanoseconds
            ),
            hostRange: try RecordingTimeRange(
                startNanoseconds: firstHostStartNanoseconds,
                endNanoseconds: hostEndNanoseconds
            ),
            frameCount: frameCount
        )
    }
}
