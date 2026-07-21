import Foundation
import MeetingBuddyDomain

public struct CaptureManifestSegmentV1: Codable, Hashable, Sendable {
    public let segmentID: RecordingSegmentID
    public let epochID: RecordingEpochID
    public let sequence: UInt64
    public let mediaRange: RecordingTimeRange
    public let hostRange: RecordingTimeRange
    public let frameCount: UInt64
    public let contentHash: ContentDigest

    public init(segment: SealedCaptureSegment) {
        segmentID = segment.segmentID
        epochID = segment.epochID
        sequence = segment.sequence
        mediaRange = segment.mediaRange
        hostRange = segment.hostRange
        frameCount = segment.frameCount
        contentHash = segment.contentHash
    }
}

public struct CaptureManifestTrackV1: Codable, Hashable, Sendable {
    public let trackID: RecordingTrackID
    public let kind: CaptureTrackKind
    public let speechSourceKind: SpeechSourceKind
    public let language: LanguageTag?
    public let format: CaptureAudioFormat
    public let segments: [CaptureManifestSegmentV1]
    public let finalContentHash: ContentDigest
    public let finalByteSize: UInt64
    public let finalFrameCount: UInt64

    public init(
        request: RecordingTrackRequest,
        format: CaptureAudioFormat,
        segments: [SealedCaptureSegment],
        finalContentHash: ContentDigest,
        finalByteSize: UInt64,
        finalFrameCount: UInt64
    ) throws {
        guard !segments.isEmpty,
              segments.allSatisfy({ $0.trackID == request.trackID && $0.format == format }),
              finalContentHash.algorithm == .sha256,
              finalByteSize > 0,
              finalFrameCount == segments.reduce(0, { $0 + $1.frameCount })
        else {
            throw RecordingContractError.integrityFailure("A capture manifest track must bind exact verified segments and final bytes.")
        }
        trackID = request.trackID
        kind = request.kind
        speechSourceKind = request.speechSourceKind
        language = request.language
        self.format = format
        self.segments = segments
            .sorted { ($0.epochID, $0.sequence) < ($1.epochID, $1.sequence) }
            .map(CaptureManifestSegmentV1.init)
        self.finalContentHash = finalContentHash
        self.finalByteSize = finalByteSize
        self.finalFrameCount = finalFrameCount
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, kind, speechSourceKind, language, format, segments
        case finalContentHash, finalByteSize, finalFrameCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let trackID = try values.decode(RecordingTrackID.self, forKey: .trackID)
        let kind = try values.decode(CaptureTrackKind.self, forKey: .kind)
        let speechSourceKind = try values.decode(
            SpeechSourceKind.self,
            forKey: .speechSourceKind
        )
        let language = try values.decodeIfPresent(LanguageTag.self, forKey: .language)
        let format = try values.decode(CaptureAudioFormat.self, forKey: .format)
        let segments = try values.decode([CaptureManifestSegmentV1].self, forKey: .segments)
        let finalContentHash = try values.decode(ContentDigest.self, forKey: .finalContentHash)
        let finalByteSize = try values.decode(UInt64.self, forKey: .finalByteSize)
        let finalFrameCount = try values.decode(UInt64.self, forKey: .finalFrameCount)
        guard !segments.isEmpty,
              Set(segments.map(\.segmentID)).count == segments.count,
              Set(segments.map(\.sequence)).count == segments.count,
              segments.allSatisfy({ $0.contentHash.algorithm == .sha256 }),
              finalContentHash.algorithm == .sha256,
              finalByteSize > 0,
              finalFrameCount == segments.reduce(0, { $0 + $1.frameCount })
        else {
            throw RecordingContractError.integrityFailure(
                "A decoded capture manifest track failed closed."
            )
        }
        self.trackID = trackID
        self.kind = kind
        self.speechSourceKind = speechSourceKind
        self.language = language
        self.format = format
        self.segments = segments.sorted {
            ($0.epochID, $0.sequence) < ($1.epochID, $1.sequence)
        }
        self.finalContentHash = finalContentHash
        self.finalByteSize = finalByteSize
        self.finalFrameCount = finalFrameCount
    }
}

public struct CaptureManifestV1: Codable, Hashable, Sendable {
    public static let formatIdentifier = "meetingbuddy.capture-manifest.v1"
    public static let formatVersion: UInt32 = 1

    public let formatIdentifier: String
    public let formatVersion: UInt32
    public let sessionID: RecordingSessionID
    public let meetingID: MeetingID
    public let captureMode: CaptureMode
    public let terminalState: RecordingState
    public let authorizationEventID: RecordingAuthorizationEventID
    public let authorizationAcknowledgedAt: UTCInstant
    public let epochs: [RecordingEpoch]
    public let tracks: [CaptureManifestTrackV1]
    public let gaps: [RecordingGap]
    public let stateEventChainDigest: ContentDigest
    public let createdAt: UTCInstant

    public init(
        session: RecordingSessionSnapshot,
        terminalState: RecordingState,
        epochs: [RecordingEpoch],
        tracks: [CaptureManifestTrackV1],
        gaps: [RecordingGap],
        stateEventChainDigest: ContentDigest,
        createdAt: UTCInstant
    ) throws {
        guard terminalState == .completed || terminalState == .incomplete,
              !tracks.isEmpty,
              !epochs.isEmpty,
              epochs.allSatisfy({ $0.sessionID == session.intent.sessionID }),
              epochs.allSatisfy({ epoch in
                  Set(epoch.sources.map(\.trackID))
                    == Set(session.intent.requestedTracks.map(\.trackID))
              }),
              Set(tracks.map(\.trackID)).count == tracks.count,
              Set(tracks.map(\.trackID))
                == Set(session.intent.requestedTracks.map(\.trackID)),
              Set(tracks.map(\.kind)) == session.intent.mode.requestedTrackKinds,
              tracks.allSatisfy({ track in session.intent.requestedTracks.contains { $0.trackID == track.trackID } }),
              gaps.allSatisfy({ $0.sessionID == session.intent.sessionID }),
              stateEventChainDigest.algorithm == .sha256,
              createdAt >= session.intent.createdAt
        else {
            throw RecordingContractError.integrityFailure("The immutable capture manifest is inconsistent with its recording session.")
        }
        formatIdentifier = Self.formatIdentifier
        formatVersion = Self.formatVersion
        sessionID = session.intent.sessionID
        meetingID = session.intent.meetingID
        captureMode = session.intent.mode
        self.terminalState = terminalState
        authorizationEventID = session.intent.authorization.eventID
        authorizationAcknowledgedAt = session.intent.authorization.occurredAt
        self.epochs = epochs.sorted { ($0.sequence, $0.epochID) < ($1.sequence, $1.epochID) }
        self.tracks = tracks.sorted { $0.trackID < $1.trackID }
        self.gaps = gaps.sorted { ($0.trackID, $0.detectedAt, $0.gapID) < ($1.trackID, $1.detectedAt, $1.gapID) }
        self.stateEventChainDigest = stateEventChainDigest
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case formatIdentifier, formatVersion, sessionID, meetingID, captureMode
        case terminalState, authorizationEventID, authorizationAcknowledgedAt
        case epochs, tracks, gaps, stateEventChainDigest, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let formatIdentifier = try values.decode(String.self, forKey: .formatIdentifier)
        let formatVersion = try values.decode(UInt32.self, forKey: .formatVersion)
        let sessionID = try values.decode(RecordingSessionID.self, forKey: .sessionID)
        let meetingID = try values.decode(MeetingID.self, forKey: .meetingID)
        let captureMode = try values.decode(CaptureMode.self, forKey: .captureMode)
        let terminalState = try values.decode(RecordingState.self, forKey: .terminalState)
        let authorizationEventID = try values.decode(
            RecordingAuthorizationEventID.self,
            forKey: .authorizationEventID
        )
        let authorizationAcknowledgedAt = try values.decode(
            UTCInstant.self,
            forKey: .authorizationAcknowledgedAt
        )
        let epochs = try values.decode([RecordingEpoch].self, forKey: .epochs)
        let tracks = try values.decode([CaptureManifestTrackV1].self, forKey: .tracks)
        let gaps = try values.decode([RecordingGap].self, forKey: .gaps)
        let stateEventChainDigest = try values.decode(
            ContentDigest.self,
            forKey: .stateEventChainDigest
        )
        let createdAt = try values.decode(UTCInstant.self, forKey: .createdAt)

        let trackIDs = Set(tracks.map(\.trackID))
        let trackKinds = Set(tracks.map(\.kind))
        let epochIDs = Set(epochs.map(\.epochID))
        let segmentIDs = tracks.flatMap(\.segments).map(\.segmentID)
        guard formatIdentifier == Self.formatIdentifier,
              formatVersion == Self.formatVersion,
              terminalState == .completed || terminalState == .incomplete,
              !tracks.isEmpty,
              !epochs.isEmpty,
              Set(tracks.map(\.trackID)).count == tracks.count,
              trackKinds == captureMode.requestedTrackKinds,
              epochs.allSatisfy({ $0.sessionID == sessionID }),
              Set(epochs.map(\.epochID)).count == epochs.count,
              Set(epochs.map(\.sequence)).count == epochs.count,
              epochs.allSatisfy({ epoch in
                  Set(epoch.sources.map(\.trackID)) == trackIDs
                      && epoch.sources.allSatisfy({ source in
                          tracks.contains(where: {
                              $0.trackID == source.trackID && $0.kind == source.kind
                          })
                      })
              }),
              tracks.flatMap(\.segments).allSatisfy({ epochIDs.contains($0.epochID) }),
              Set(segmentIDs).count == segmentIDs.count,
              gaps.allSatisfy({
                  $0.sessionID == sessionID
                      && trackIDs.contains($0.trackID)
                      && $0.epochID.map(epochIDs.contains) ?? true
              }),
              terminalState != .completed || gaps.isEmpty,
              stateEventChainDigest.algorithm == .sha256,
              authorizationAcknowledgedAt <= createdAt,
              epochs.allSatisfy({ $0.selectedAt <= createdAt })
        else {
            throw RecordingContractError.integrityFailure(
                "A decoded capture manifest version or provenance graph failed closed."
            )
        }
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.sessionID = sessionID
        self.meetingID = meetingID
        self.captureMode = captureMode
        self.terminalState = terminalState
        self.authorizationEventID = authorizationEventID
        self.authorizationAcknowledgedAt = authorizationAcknowledgedAt
        self.epochs = epochs.sorted { ($0.sequence, $0.epochID) < ($1.sequence, $1.epochID) }
        self.tracks = tracks.sorted { $0.trackID < $1.trackID }
        self.gaps = gaps.sorted {
            ($0.trackID, $0.detectedAt, $0.gapID) < ($1.trackID, $1.detectedAt, $1.gapID)
        }
        self.stateEventChainDigest = stateEventChainDigest
        self.createdAt = createdAt
    }

    public func canonicalPayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= 16 * 1_024 * 1_024 else {
            throw RecordingContractError.integrityFailure("The capture manifest is unexpectedly unbounded.")
        }
        return data
    }
}
