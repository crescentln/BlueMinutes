import Foundation
import MeetingBuddyDomain

public enum CaptureProviderError: Error, Equatable, Sendable {
    case capabilityUnavailable(String)
    case directUserSelectionRequired
    case invalidSelection
    case authorizationExpired
    case permissionDenied(CaptureTrackKind)
    case sourceStopped(CaptureTrackKind)
    case formatChanged(CaptureTrackKind)
    case boundedQueueExceeded(CaptureTrackKind)
    case providerFailure(String)
}

public enum CapturePermissionState: String, Codable, Hashable, Sendable {
    case notDetermined = "not_determined"
    case denied
    case authorized
    case restricted
}

public struct CaptureCapabilitySnapshot: Codable, Hashable, Sendable {
    public let microphonePermission: CapturePermissionState
    public let applicationAudioAvailable: Bool
    public let systemPickerAvailable: Bool
    public let checkedAt: UTCInstant

    public init(
        microphonePermission: CapturePermissionState,
        applicationAudioAvailable: Bool,
        systemPickerAvailable: Bool,
        checkedAt: UTCInstant
    ) {
        self.microphonePermission = microphonePermission
        self.applicationAudioAvailable = applicationAudioAvailable
        self.systemPickerAvailable = systemPickerAvailable
        self.checkedAt = checkedAt
    }
}

public struct CaptureMicrophoneChoice: Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let audioFormat: CaptureAudioFormat

    public init(
        id: String,
        displayName: String,
        audioFormat: CaptureAudioFormat
    ) throws {
        guard !id.isEmpty, id.utf8.count <= 512,
              !displayName.isEmpty, displayName.utf8.count <= 128,
              !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw CaptureProviderError.invalidSelection
        }
        self.id = id
        self.displayName = displayName
        self.audioFormat = audioFormat
    }
}

public struct CaptureSelectionRequest: Hashable, Sendable {
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID
    public let mode: CaptureMode
    public let microphoneDeviceID: String?

    public init(
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        mode: CaptureMode,
        microphoneDeviceID: String?
    ) throws {
        let requiresMicrophone = mode.requestedTrackKinds.contains(.microphone)
        guard requiresMicrophone == (microphoneDeviceID != nil),
              microphoneDeviceID?.utf8.count ?? 0 <= 512
        else {
            throw CaptureProviderError.invalidSelection
        }
        self.sessionID = sessionID
        self.epochID = epochID
        self.mode = mode
        self.microphoneDeviceID = microphoneDeviceID
    }
}

/// A process-local, epoch-scoped selection capability. It deliberately cannot
/// be serialized and contains no reusable platform filter or workspace path.
public struct CaptureSelectionAuthorization: Hashable, Sendable {
    public let authorizationID: UUID
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID
    public let mode: CaptureMode
    public let microphoneDeviceID: String?
    public let applicationSourceToken: ContentDigest?
    public let selectedAt: UTCInstant

    public init(
        authorizationID: UUID = UUID(),
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        mode: CaptureMode,
        microphoneDeviceID: String?,
        applicationSourceToken: ContentDigest? = nil,
        selectedAt: UTCInstant
    ) throws {
        let requiresApplication = mode.requestedTrackKinds.contains(.applicationAudio)
        guard requiresApplication == (applicationSourceToken != nil),
              applicationSourceToken?.algorithm ?? .sha256 == .sha256
        else {
            throw CaptureProviderError.invalidSelection
        }
        self.authorizationID = authorizationID
        self.sessionID = sessionID
        self.epochID = epochID
        self.mode = mode
        self.microphoneDeviceID = microphoneDeviceID
        self.applicationSourceToken = applicationSourceToken
        self.selectedAt = selectedAt
    }
}

public struct PreparedCaptureRequest: Sendable {
    public let authorization: CaptureSelectionAuthorization
    public let tracks: [RecordingTrackRequest]
    public let maximumQueuedDurationNanoseconds: UInt64

    public init(
        authorization: CaptureSelectionAuthorization,
        tracks: [RecordingTrackRequest],
        maximumQueuedDurationNanoseconds: UInt64 = 2_000_000_000
    ) throws {
        guard Set(tracks.map(\.kind)) == authorization.mode.requestedTrackKinds,
              maximumQueuedDurationNanoseconds > 0,
              maximumQueuedDurationNanoseconds <= 2_000_000_000
        else {
            throw CaptureProviderError.invalidSelection
        }
        self.authorization = authorization
        self.tracks = tracks
        self.maximumQueuedDurationNanoseconds = maximumQueuedDurationNanoseconds
    }
}

public struct PreparedCapture: Hashable, Sendable {
    public let preparationID: UUID
    public let authorizationID: UUID
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID
    public let mode: CaptureMode

    public init(
        preparationID: UUID = UUID(),
        authorizationID: UUID,
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        mode: CaptureMode
    ) {
        self.preparationID = preparationID
        self.authorizationID = authorizationID
        self.sessionID = sessionID
        self.epochID = epochID
        self.mode = mode
    }
}

public struct CaptureHandle: Hashable, Sendable {
    public let id: UUID
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID

    public init(
        id: UUID = UUID(),
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID
    ) {
        self.id = id
        self.sessionID = sessionID
        self.epochID = epochID
    }
}

public protocol CaptureCapabilityProvider: Sendable {
    func snapshot() async -> CaptureCapabilitySnapshot
    func microphones() async throws -> [CaptureMicrophoneChoice]
}

public protocol CaptureSourcePicker: Sendable {
    func requestSelection(_ request: CaptureSelectionRequest) async throws -> CaptureSelectionAuthorization
}

public protocol CapturedAudioPacketSink: Sendable {
    func accept(_ packet: CapturedAudioPacket) async -> CapturePacketDisposition
    func providerDidStop(track: CaptureTrackKind, error: CaptureProviderError?) async
}

public protocol AuthorizedAudioCaptureProvider: Sendable {
    func prepare(_ request: PreparedCaptureRequest) async throws -> PreparedCapture
    func start(
        _ prepared: PreparedCapture,
        sink: any CapturedAudioPacketSink
    ) async throws -> CaptureHandle
    func stop(_ handle: CaptureHandle) async
}
