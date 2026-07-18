import Foundation
import MeetingBuddyDomain

public enum MediaContractError: Error, Equatable, Sendable {
    case unsupportedFileType(String)
    case unreadableMedia
    case noAudioTrack
    case trackSelectionRequired
    case selectedTrackUnavailable(MediaTrackIdentifier)
    case invalidCanonicalProfile(String)
    case invalidTimeline(String)
    case invalidChunkPlan(String)
    case invalidJobPayload
    case sourceAssetUnavailable(RevisionID)
    case managedSourceUnavailable(StorageObjectID)
    case durationOutsideTolerance(expectedFrames: UInt64, actualFrames: UInt64)
    case processingFailed(String)
}

/// The core local formats approved for Task 005A.
public enum ApprovedMediaFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case mov
    case mp4
    case m4a
    case mp3
    case wav

    public init(fileExtension: String) throws {
        guard let value = Self(rawValue: fileExtension.lowercased()) else {
            throw MediaContractError.unsupportedFileType(fileExtension)
        }
        self = value
    }

    public var fileExtension: String { rawValue }

    public var mimeType: String {
        switch self {
        case .mov: "video/quicktime"
        case .mp4: "video/mp4"
        case .m4a: "audio/mp4"
        case .mp3: "audio/mpeg"
        case .wav: "audio/wav"
        }
    }

    public var assetType: SourceAssetType {
        switch self {
        case .mov, .mp4: .video
        case .m4a, .mp3, .wav: .audio
        }
    }
}

/// The only canonical-audio representation owned by Task 005A.
public struct CanonicalAudioProfile: Codable, Hashable, Sendable {
    public static let v1 = try! CanonicalAudioProfile(
        identifier: "meetingbuddy.canonical-audio.v1",
        sampleRateHertz: 16_000,
        channelCount: 1,
        bitDepth: 16,
        isSignedInteger: true,
        isLittleEndian: true,
        isInterleaved: true,
        container: "caf",
        codec: "lpcm_s16le"
    )

    public let identifier: String
    public let sampleRateHertz: UInt32
    public let channelCount: UInt16
    public let bitDepth: UInt16
    public let isSignedInteger: Bool
    public let isLittleEndian: Bool
    public let isInterleaved: Bool
    public let container: String
    public let codec: String

    public init(
        identifier: String,
        sampleRateHertz: UInt32,
        channelCount: UInt16,
        bitDepth: UInt16,
        isSignedInteger: Bool,
        isLittleEndian: Bool,
        isInterleaved: Bool,
        container: String,
        codec: String
    ) throws {
        guard identifier == "meetingbuddy.canonical-audio.v1",
              sampleRateHertz == 16_000,
              channelCount == 1,
              bitDepth == 16,
              isSignedInteger,
              isLittleEndian,
              isInterleaved,
              container == "caf",
              codec == "lpcm_s16le"
        else {
            throw MediaContractError.invalidCanonicalProfile(
                "Task 005A supports only signed 16-bit little-endian interleaved mono PCM at 16 kHz in CAF."
            )
        }
        self.identifier = identifier
        self.sampleRateHertz = sampleRateHertz
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isSignedInteger = isSignedInteger
        self.isLittleEndian = isLittleEndian
        self.isInterleaved = isInterleaved
        self.container = container
        self.codec = codec
    }
}

public struct MediaTrackIdentifier: Codable, Hashable, Sendable, Comparable,
    CustomStringConvertible
{
    public let rawValue: Int32

    public init(_ rawValue: Int32) throws {
        guard rawValue > 0 else {
            throw MediaContractError.invalidTimeline("A media track identifier must be positive.")
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { String(rawValue) }
}

public struct AudioTrackDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var id: MediaTrackIdentifier { trackIdentifier }

    public let trackIdentifier: MediaTrackIdentifier
    public let durationFrameCount: UInt64
    public let sourceSampleRateHertz: UInt32?
    public let sourceChannelCount: UInt16?
    public let codec: String?
    public let language: LanguageTag?

    public init(
        trackIdentifier: MediaTrackIdentifier,
        durationFrameCount: UInt64,
        sourceSampleRateHertz: UInt32? = nil,
        sourceChannelCount: UInt16? = nil,
        codec: String? = nil,
        language: LanguageTag? = nil
    ) throws {
        guard durationFrameCount > 0,
              sourceSampleRateHertz != 0,
              sourceChannelCount != 0,
              codec.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true
        else {
            throw MediaContractError.invalidTimeline(
                "An audio track needs a non-empty duration and bounded technical metadata."
            )
        }
        self.trackIdentifier = trackIdentifier
        self.durationFrameCount = durationFrameCount
        self.sourceSampleRateHertz = sourceSampleRateHertz
        self.sourceChannelCount = sourceChannelCount
        self.codec = codec
        self.language = language
    }
}

public struct MediaInspection: Codable, Hashable, Sendable {
    public let format: ApprovedMediaFormat
    public let durationFrameCount: UInt64
    public let audioTracks: [AudioTrackDescriptor]

    public init(
        format: ApprovedMediaFormat,
        durationFrameCount: UInt64,
        audioTracks: [AudioTrackDescriptor]
    ) throws {
        let tracks = audioTracks.sorted { $0.trackIdentifier < $1.trackIdentifier }
        guard durationFrameCount > 0, !tracks.isEmpty,
              Set(tracks.map(\.trackIdentifier)).count == tracks.count
        else {
            throw tracks.isEmpty
                ? MediaContractError.noAudioTrack
                : MediaContractError.invalidTimeline(
                    "Media inspection requires a positive duration and unique audio tracks."
                )
        }
        self.format = format
        self.durationFrameCount = durationFrameCount
        self.audioTracks = tracks
    }

    public func requireTrack(_ selection: MediaTrackIdentifier?) throws -> AudioTrackDescriptor {
        if let selection {
            guard let track = audioTracks.first(where: { $0.trackIdentifier == selection }) else {
                throw MediaContractError.selectedTrackUnavailable(selection)
            }
            return track
        }
        guard audioTracks.count == 1, let track = audioTracks.first else {
            throw MediaContractError.trackSelectionRequired
        }
        return track
    }

    public var durationMilliseconds: UInt64 {
        let product = durationFrameCount.multipliedFullWidth(by: 1_000)
        return UInt64(CanonicalAudioProfile.v1.sampleRateHertz)
            .dividingFullWidth(product).quotient
    }
}

/// A half-open frame range on the 16 kHz canonical timeline.
public struct MediaFrameRange: Codable, Hashable, Sendable, Comparable {
    public let startFrame: UInt64
    public let endFrame: UInt64

    public init(startFrame: UInt64, endFrame: UInt64) throws {
        guard startFrame < endFrame else {
            throw MediaContractError.invalidTimeline(
                "A media range must be non-empty and half-open."
            )
        }
        self.startFrame = startFrame
        self.endFrame = endFrame
    }

    public var frameCount: UInt64 { endFrame - startFrame }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.startFrame, lhs.endFrame) < (rhs.startFrame, rhs.endFrame)
    }
}

public enum MediaRangeIssueKind: String, Codable, Hashable, Sendable {
    case missing
    case corrupt
    case decodeFailed = "decode_failed"
}

public struct MediaRangeIssue: Codable, Hashable, Sendable {
    public let kind: MediaRangeIssueKind
    public let range: MediaFrameRange
    public let safeSummary: String

    public init(
        kind: MediaRangeIssueKind,
        range: MediaFrameRange,
        safeSummary: String
    ) throws {
        let trimmed = safeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == safeSummary,
              !trimmed.isEmpty,
              trimmed.utf8.count <= 256,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw MediaContractError.invalidTimeline("A range issue needs a bounded safe summary.")
        }
        self.kind = kind
        self.range = range
        self.safeSummary = safeSummary
    }
}

public struct MediaChunkPlanEntry: Codable, Hashable, Sendable, Comparable, Identifiable {
    public var id: UInt32 { index }

    public let index: UInt32
    public let coreRange: MediaFrameRange
    public let physicalRange: MediaFrameRange
    public let relativePath: WorkspaceRelativePath

    public init(
        index: UInt32,
        coreRange: MediaFrameRange,
        physicalRange: MediaFrameRange,
        relativePath: WorkspaceRelativePath
    ) throws {
        guard physicalRange.startFrame <= coreRange.startFrame,
              physicalRange.endFrame >= coreRange.endFrame
        else {
            throw MediaContractError.invalidChunkPlan(
                "A physical chunk range must contain its exact core range."
            )
        }
        self.index = index
        self.coreRange = coreRange
        self.physicalRange = physicalRange
        self.relativePath = relativePath
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }
}

public enum CanonicalChunkPlanner {
    public static let coreDurationFrames: UInt64 = 480_000
    public static let contextFrames: UInt64 = 16_000

    public static func plan(totalFrameCount: UInt64) throws -> [MediaChunkPlanEntry] {
        guard totalFrameCount > 0 else {
            throw MediaContractError.invalidChunkPlan("Canonical audio cannot be empty.")
        }
        var entries: [MediaChunkPlanEntry] = []
        var start: UInt64 = 0
        var index: UInt32 = 0
        while start < totalFrameCount {
            let coreEnd = min(totalFrameCount, start + coreDurationFrames)
            let physicalStart = start >= contextFrames ? start - contextFrames : 0
            let physicalEnd = min(totalFrameCount, coreEnd + contextFrames)
            let path = try WorkspaceRelativePath(
                String(format: "chunks/chunk-%06u.caf", index)
            )
            entries.append(
                try MediaChunkPlanEntry(
                    index: index,
                    coreRange: MediaFrameRange(startFrame: start, endFrame: coreEnd),
                    physicalRange: MediaFrameRange(
                        startFrame: physicalStart,
                        endFrame: physicalEnd
                    ),
                    relativePath: path
                )
            )
            start = coreEnd
            let (nextIndex, overflow) = index.addingReportingOverflow(1)
            guard !overflow else {
                throw MediaContractError.invalidChunkPlan("The chunk index overflowed.")
            }
            index = nextIndex
        }
        return entries
    }
}

public struct CanonicalAudioWriteResult: Codable, Hashable, Sendable {
    public let frameCount: UInt64
    public let rangeIssues: [MediaRangeIssue]

    public init(frameCount: UInt64, rangeIssues: [MediaRangeIssue] = []) throws {
        guard frameCount > 0 else {
            throw MediaContractError.invalidTimeline("Canonical audio cannot be empty.")
        }
        self.frameCount = frameCount
        self.rangeIssues = rangeIssues.sorted { $0.range < $1.range }
    }
}

public struct CanonicalChunkArtifact: Codable, Hashable, Sendable, Comparable {
    public let plan: MediaChunkPlanEntry
    public let file: TaskTemporaryFileDescriptor

    public init(plan: MediaChunkPlanEntry, file: TaskTemporaryFileDescriptor) throws {
        guard plan.relativePath == file.relativePathWithinTask else {
            throw MediaContractError.invalidChunkPlan(
                "A chunk artifact must match its deterministic task path."
            )
        }
        self.plan = plan
        self.file = file
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.plan < rhs.plan }
}

public struct CanonicalAudioJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.canonical-audio-job"
    public static let inputFormatVersion: UInt32 = 1

    public let sourceRevision: SemanticRevisionReference
    public let selectedTrack: MediaTrackIdentifier
    public let speechSourceKind: SpeechSourceKind
    public let outputAssetID: SourceAssetID
    public let outputRevisionID: RevisionID
    public let outputStorageObjectID: StorageObjectID
    public let meetingID: MeetingID
    public let createdAt: UTCInstant
    public let dataClassification: DataClassification
    public let language: LanguageTag?
    public let expectedDurationFrames: UInt64
    public let profile: CanonicalAudioProfile

    public init(
        sourceRevision: SemanticRevisionReference,
        selectedTrack: MediaTrackIdentifier,
        speechSourceKind: SpeechSourceKind,
        outputAssetID: SourceAssetID = SourceAssetID(UUID()),
        outputRevisionID: RevisionID = RevisionID(UUID()),
        outputStorageObjectID: StorageObjectID = StorageObjectID(UUID()),
        meetingID: MeetingID,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        language: LanguageTag?,
        expectedDurationFrames: UInt64,
        profile: CanonicalAudioProfile = .v1
    ) throws {
        guard sourceRevision.objectType == .sourceAsset,
              speechSourceKind.isKnown,
              dataClassification.isKnown,
              expectedDurationFrames > 0
        else {
            throw MediaContractError.invalidJobPayload
        }
        self.sourceRevision = sourceRevision
        self.selectedTrack = selectedTrack
        self.speechSourceKind = speechSourceKind
        self.outputAssetID = outputAssetID
        self.outputRevisionID = outputRevisionID
        self.outputStorageObjectID = outputStorageObjectID
        self.meetingID = meetingID
        self.createdAt = createdAt
        self.dataClassification = dataClassification
        self.language = language
        self.expectedDurationFrames = expectedDurationFrames
        self.profile = profile
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
            return try Self(
                sourceRevision: decoded.sourceRevision,
                selectedTrack: MediaTrackIdentifier(decoded.selectedTrack.rawValue),
                speechSourceKind: decoded.speechSourceKind,
                outputAssetID: decoded.outputAssetID,
                outputRevisionID: decoded.outputRevisionID,
                outputStorageObjectID: decoded.outputStorageObjectID,
                meetingID: decoded.meetingID,
                createdAt: decoded.createdAt,
                dataClassification: decoded.dataClassification,
                language: decoded.language,
                expectedDurationFrames: decoded.expectedDurationFrames,
                profile: CanonicalAudioProfile(
                    identifier: decoded.profile.identifier,
                    sampleRateHertz: decoded.profile.sampleRateHertz,
                    channelCount: decoded.profile.channelCount,
                    bitDepth: decoded.profile.bitDepth,
                    isSignedInteger: decoded.profile.isSignedInteger,
                    isLittleEndian: decoded.profile.isLittleEndian,
                    isInterleaved: decoded.profile.isInterleaved,
                    container: decoded.profile.container,
                    codec: decoded.profile.codec
                )
            )
        } catch {
            throw MediaContractError.invalidJobPayload
        }
    }
}

public struct CanonicalAudioCheckpoint: Codable, Hashable, Sendable {
    public static let formatVersion: UInt32 = 1

    public let canonicalFile: TaskTemporaryFileDescriptor
    public let canonicalFrameCount: UInt64
    public let completedChunks: [CanonicalChunkArtifact]
    public let rangeIssues: [MediaRangeIssue]

    public init(
        canonicalFile: TaskTemporaryFileDescriptor,
        canonicalFrameCount: UInt64,
        completedChunks: [CanonicalChunkArtifact],
        rangeIssues: [MediaRangeIssue]
    ) throws {
        let chunks = completedChunks.sorted()
        let expectedPlan = try CanonicalChunkPlanner.plan(
            totalFrameCount: canonicalFrameCount
        )
        let expectedByIndex = Dictionary(
            uniqueKeysWithValues: expectedPlan.map { ($0.index, $0) }
        )
        guard canonicalFrameCount > 0,
              canonicalFile.relativePathWithinTask.rawValue == "canonical/audio.caf",
              Set(chunks.map { $0.plan.index }).count == chunks.count,
              chunks.allSatisfy({ expectedByIndex[$0.plan.index] == $0.plan }),
              rangeIssues.allSatisfy({ $0.range.endFrame <= canonicalFrameCount })
        else {
            throw MediaContractError.invalidJobPayload
        }
        self.canonicalFile = canonicalFile
        self.canonicalFrameCount = canonicalFrameCount
        self.completedChunks = chunks
        self.rangeIssues = rangeIssues.sorted { $0.range < $1.range }
    }

    public func jobCheckpoint() throws -> JobCheckpoint {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = DurablePayload(
            canonicalHash: canonicalFile.contentHash.lowercaseHex,
            canonicalByteSize: canonicalFile.byteSize,
            canonicalFrameCount: canonicalFrameCount,
            completedChunks: completedChunks.map {
                DurableChunk(
                    index: $0.plan.index,
                    contentHash: $0.file.contentHash.lowercaseHex,
                    byteSize: $0.file.byteSize
                )
            },
            rangeIssues: rangeIssues
        )
        return try JobCheckpoint(
            formatVersion: Self.formatVersion,
            payload: encoder.encode(payload)
        )
    }

    public static func decode(from checkpoint: JobCheckpoint?) throws -> Self? {
        guard let checkpoint else { return nil }
        guard checkpoint.formatVersion == formatVersion else {
            throw MediaContractError.invalidJobPayload
        }
        do {
            let payload = try PropertyListDecoder().decode(
                DurablePayload.self,
                from: checkpoint.payload
            )
            let canonicalPath = try WorkspaceRelativePath("canonical/audio.caf")
            let canonicalFile = try TaskTemporaryFileDescriptor(
                relativePathWithinTask: canonicalPath,
                contentHash: ContentDigest(
                    algorithm: .sha256,
                    lowercaseHex: payload.canonicalHash
                ),
                byteSize: payload.canonicalByteSize
            )
            let plan = try CanonicalChunkPlanner.plan(
                totalFrameCount: payload.canonicalFrameCount
            )
            let planByIndex = Dictionary(uniqueKeysWithValues: plan.map { ($0.index, $0) })
            let artifacts = try payload.completedChunks.map { stored in
                guard let entry = planByIndex[stored.index] else {
                    throw MediaContractError.invalidJobPayload
                }
                let file = try TaskTemporaryFileDescriptor(
                    relativePathWithinTask: entry.relativePath,
                    contentHash: ContentDigest(
                        algorithm: .sha256,
                        lowercaseHex: stored.contentHash
                    ),
                    byteSize: stored.byteSize
                )
                return try CanonicalChunkArtifact(plan: entry, file: file)
            }
            let issues = try payload.rangeIssues.map {
                try MediaRangeIssue(
                    kind: $0.kind,
                    range: MediaFrameRange(
                        startFrame: $0.range.startFrame,
                        endFrame: $0.range.endFrame
                    ),
                    safeSummary: $0.safeSummary
                )
            }
            guard issues.allSatisfy({ $0.range.endFrame <= payload.canonicalFrameCount }) else {
                throw MediaContractError.invalidJobPayload
            }
            return try Self(
                canonicalFile: canonicalFile,
                canonicalFrameCount: payload.canonicalFrameCount,
                completedChunks: artifacts,
                rangeIssues: issues
            )
        } catch {
            throw MediaContractError.invalidJobPayload
        }
    }

    private struct DurablePayload: Codable {
        let canonicalHash: String
        let canonicalByteSize: UInt64
        let canonicalFrameCount: UInt64
        let completedChunks: [DurableChunk]
        let rangeIssues: [MediaRangeIssue]

        private enum CodingKeys: String, CodingKey {
            case canonicalHash = "h"
            case canonicalByteSize = "b"
            case canonicalFrameCount = "f"
            case completedChunks = "c"
            case rangeIssues = "i"
        }
    }

    private struct DurableChunk: Codable {
        let index: UInt32
        let contentHash: String
        let byteSize: UInt64

        private enum CodingKeys: String, CodingKey {
            case index = "i"
            case contentHash = "h"
            case byteSize = "b"
        }
    }
}

/// Narrow media-facing catalog operations; implementations retain SQLite
/// ownership and never expose database handles.
public protocol MediaAssetCatalog: Sendable {
    func sourceAsset(revisionID: RevisionID) throws -> SourceAssetV1?
    func managedAsset(storageObjectID: StorageObjectID) throws -> ManagedAssetRecord?
    func insertSourceAsset(_ sourceAsset: SourceAssetV1) throws
}

/// Resolves only one already-registered managed asset after re-verifying its
/// hash and workspace confinement.
public protocol ManagedMediaFileAccess: Sendable {
    func verifiedFileURL(for reference: ManagedAssetReference) throws -> URL
}

public protocol NativeMediaProcessing: Sendable {
    func inspect(_ sourceURL: URL) async throws -> MediaInspection

    func writeCanonicalAudio(
        from sourceURL: URL,
        selectedTrack: MediaTrackIdentifier,
        expectedTimelineFrameCount: UInt64,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws -> CanonicalAudioWriteResult

    func writeCanonicalChunk(
        from canonicalAudioURL: URL,
        range: MediaFrameRange,
        profile: CanonicalAudioProfile,
        to destinationURL: URL
    ) async throws
}

public enum MediaJobTypes {
    public static let canonicalAudio = try! JobType("media-canonical-audio-v1")
}
