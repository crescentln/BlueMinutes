import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public final class LocalRecordingRecoveryService: RecordingRecoveryService, @unchecked Sendable {
    private let repository: any RecordingSessionRepository
    private let fileStore: any RecordingSegmentFileStore
    private let clock: @Sendable () -> UTCInstant

    public init(
        repository: any RecordingSessionRepository,
        fileStore: any RecordingSegmentFileStore,
        clock: @escaping @Sendable () -> UTCInstant = {
            try! UTCInstant(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
            )
        }
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.clock = clock
    }

    public func recover(
        _ sessionID: RecordingSessionID
    ) async throws -> RecordingRecoveryOutcome {
        guard var snapshot = try await repository.session(sessionID) else {
            throw RecordingContractError.sessionNotFound(sessionID)
        }
        if snapshot.state == .recording {
            let activeEpochID = try await repository.epochs(sessionID: sessionID).last?.epochID
            for track in snapshot.intent.requestedTracks where track.required {
                try await repository.recordGap(
                    RecordingGap(
                        gapID: deterministicGapID(
                            "process-interruption",
                            sessionID.canonicalString,
                            activeEpochID?.canonicalString ?? "unknown-epoch",
                            track.trackID.canonicalString
                        ),
                        sessionID: sessionID,
                        epochID: activeEpochID,
                        trackID: track.trackID,
                        mediaRange: nil,
                        hostRange: nil,
                        reason: .processInterruption,
                        detectedBy: .startupRecovery,
                        detectedAt: snapshot.updatedAt
                    )
                )
            }
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .recording,
                    to: .interrupted,
                    reason: .processRestart,
                    actor: .startupRecovery,
                    occurredAt: clock()
                )
            )
        }
        if snapshot.state == .interrupted {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .interrupted,
                    to: .recovering,
                    reason: .recoveryLeaseAcquired,
                    actor: .startupRecovery,
                    occurredAt: clock()
                )
            )
        } else if snapshot.state == .preparing {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .preparing,
                    to: .failed,
                    reason: .noUsableAudio,
                    actor: .startupRecovery,
                    occurredAt: clock()
                )
            )
        } else if snapshot.state == .stopping {
            snapshot = try await repository.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: snapshot.stateVersion,
                    from: .stopping,
                    to: .finalizing,
                    reason: .writersDrained,
                    actor: .startupRecovery,
                    occurredAt: clock()
                )
            )
        }

        let inventory = try fileStore.recoveryInventory(
            sessionID: sessionID,
            meetingID: snapshot.intent.meetingID,
            maximumEntries: 10_000
        )
        let storedSegments = try await repository.segments(sessionID: sessionID)
        var verified: [SealedCaptureSegment] = []
        var quarantined = inventory.partialRelativePaths + inventory.quarantinedRelativePaths
        let storedIDs = Set(storedSegments.map(\.storageObjectID))

        for orphan in inventory.sealedFiles where !storedIDs.contains(orphan.storageObjectID) {
            quarantined.append(orphan.relativePath)
        }
        for segment in storedSegments {
            let descriptor = try RecordingSealedFileDescriptor(
                sessionID: sessionID,
                meetingID: snapshot.intent.meetingID,
                storageObjectID: segment.storageObjectID,
                relativePath: segment.relativePath,
                contentHash: segment.contentHash,
                byteSize: segment.byteSize
            )
            do {
                try fileStore.verifySealedFile(descriptor)
                verified.append(segment)
            } catch {
                quarantined.append(segment.relativePath)
                if !snapshot.state.isTerminal {
                    let gap = try RecordingGap(
                        gapID: deterministicGapID(
                            "damaged-segment",
                            segment.segmentID.canonicalString
                        ),
                        sessionID: sessionID,
                        epochID: segment.epochID,
                        trackID: segment.trackID,
                        mediaRange: segment.mediaRange,
                        hostRange: segment.hostRange,
                        reason: .damagedSegment,
                        detectedBy: .startupRecovery,
                        detectedAt: snapshot.updatedAt
                    )
                    try? await repository.recordGap(gap)
                }
            }
        }
        let gaps = try await repository.gaps(sessionID: sessionID)
        let rebuilt = try rebuildCheckpoint(
            snapshot: snapshot,
            segments: verified,
            gaps: gaps,
            reconciliationRequired: !quarantined.isEmpty || inventory.truncated
        )

        do {
            if let stored = try await repository.latestCheckpoint(sessionID: sessionID),
               stored.stateVersion == rebuilt?.stateVersion,
               stored.tracks == rebuilt?.tracks,
               !inventory.truncated,
               quarantined.isEmpty
            {
                return RecordingRecoveryOutcome(
                    snapshot: snapshot,
                    verifiedSegments: verified,
                    gaps: gaps,
                    quarantinedRelativePaths: [],
                    rebuiltCheckpoint: stored
                )
            }
        } catch {
            // The normalized rows and verified files remain authoritative. A
            // corrupt bounded cursor is intentionally ignored and rebuilt.
        }
        return RecordingRecoveryOutcome(
            snapshot: snapshot,
            verifiedSegments: verified,
            gaps: gaps,
            quarantinedRelativePaths: Array(Set(quarantined)).sorted { $0.rawValue < $1.rawValue },
            rebuiltCheckpoint: rebuilt
        )
    }

    public func recoverNonterminalSessions() async throws -> [RecordingRecoveryOutcome] {
        var outcomes: [RecordingRecoveryOutcome] = []
        for snapshot in try await repository.nonterminalSessions() {
            outcomes.append(try await recover(snapshot.intent.sessionID))
        }
        return outcomes
    }

    private func deterministicGapID(_ components: String...) -> RecordingGapID {
        let digest = Array(SHA256.hash(data: Data(components.joined(separator: "|").utf8)))
        let bytes = Array(digest.prefix(16))
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], (bytes[6] & 0x0f) | 0x50, bytes[7],
            (bytes[8] & 0x3f) | 0x80, bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return RecordingGapID(uuid)
    }

    private func rebuildCheckpoint(
        snapshot: RecordingSessionSnapshot,
        segments: [SealedCaptureSegment],
        gaps: [RecordingGap],
        reconciliationRequired: Bool
    ) throws -> RecordingCheckpoint? {
        guard !segments.isEmpty else { return nil }
        let grouped = Dictionary(grouping: segments, by: \.trackID)
        let cursors = try grouped.map { trackID, values in
            let sorted = values.sorted { ($0.epochID, $0.sequence) < ($1.epochID, $1.sequence) }
            let last = sorted.last!
            return try RecordingTrackCheckpoint(
                trackID: trackID,
                lastSealedSequence: last.sequence,
                lastCoveredMediaRange: last.mediaRange,
                sealedFrameCount: sorted.reduce(0) { $0 + $1.frameCount },
                lastSegmentDigest: last.contentHash,
                rollingDescriptorDigest: last.rollingDescriptorDigest
            )
        }
        let latestEpoch = segments.max {
            ($0.sealedAt, $0.epochID) < ($1.sealedAt, $1.epochID)
        }?.epochID
        return try RecordingCheckpoint(
            sessionID: snapshot.intent.sessionID,
            jobID: snapshot.intent.jobID,
            meetingID: snapshot.intent.meetingID,
            stateVersion: snapshot.stateVersion,
            state: snapshot.state,
            lastStateEventID: snapshot.lastEventID,
            currentEpochID: latestEpoch,
            requiredTrackIDs: snapshot.intent.requestedTracks.filter(\.required).map(\.trackID),
            tracks: cursors,
            outstandingGapCount: UInt32(gaps.count),
            reconciliationRequired: reconciliationRequired,
            createdAt: clock()
        )
    }
}
