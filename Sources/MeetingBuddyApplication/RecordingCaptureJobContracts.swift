import Foundation
import MeetingBuddyDomain

public struct RecordingCaptureJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.recording-capture"
    public static let inputFormatVersion: UInt32 = 1

    public let intent: RecordingIntent
    public let initialEpoch: RecordingEpoch

    public init(intent: RecordingIntent, initialEpoch: RecordingEpoch) throws {
        guard initialEpoch.sessionID == intent.sessionID,
              Set(initialEpoch.sources.map(\.trackID)) == Set(intent.requestedTracks.map(\.trackID))
        else {
            throw RecordingContractError.invalidIntent("The recording job plan requires an exact initial capture epoch.")
        }
        self.intent = intent
        self.initialEpoch = initialEpoch
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
            throw RecordingContractError.invalidIntent("The recording job payload version is unsupported.")
        }
        do {
            let decoded = try JSONDecoder().decode(Self.self, from: input.payload)
            return try Self(intent: decoded.intent, initialEpoch: decoded.initialEpoch)
        } catch {
            throw RecordingContractError.invalidIntent("The recording job payload failed closed.")
        }
    }

    public var completedOutputRevisions: [SemanticRevisionReference] {
        get throws {
            [try intent.publicationPlan.manifest.revisionReference]
                + (try intent.publicationPlan.tracks.map { try $0.asset.revisionReference })
        }
    }
}

public extension MediaJobTypes {
    static let recordingCapture = try! JobType("media-recording-capture-v1")
}
