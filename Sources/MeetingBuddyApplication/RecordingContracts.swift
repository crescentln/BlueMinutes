import Foundation
import MeetingBuddyDomain

public enum RecordingSessionIDTag: Sendable {}
public enum RecordingEpochIDTag: Sendable {}
public enum RecordingTrackIDTag: Sendable {}
public enum RecordingSegmentIDTag: Sendable {}
public enum RecordingGapIDTag: Sendable {}
public enum RecordingStateEventIDTag: Sendable {}
public enum RecordingAuthorizationEventIDTag: Sendable {}

public typealias RecordingSessionID = StableID<RecordingSessionIDTag>
public typealias RecordingEpochID = StableID<RecordingEpochIDTag>
public typealias RecordingTrackID = StableID<RecordingTrackIDTag>
public typealias RecordingSegmentID = StableID<RecordingSegmentIDTag>
public typealias RecordingGapID = StableID<RecordingGapIDTag>
public typealias RecordingStateEventID = StableID<RecordingStateEventIDTag>
public typealias RecordingAuthorizationEventID = StableID<RecordingAuthorizationEventIDTag>

public enum RecordingContractError: Error, Equatable, Sendable {
    case invalidIntent(String)
    case invalidTransition(from: RecordingState, to: RecordingState)
    case invalidPacket(String)
    case invalidSegment(String)
    case invalidCheckpoint(String)
    case optimisticLockFailed(RecordingSessionID)
    case sessionNotFound(RecordingSessionID)
    case integrityFailure(String)
}

public enum RecordingState: String, Codable, CaseIterable, Hashable, Sendable {
    case preparing
    case recording
    case interrupted
    case recovering
    case stopping
    case finalizing
    case completed
    case incomplete
    case failed

    public var isTerminal: Bool {
        self == .completed || self == .incomplete || self == .failed
    }

    public func allowsTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.preparing, .recording), (.preparing, .stopping), (.preparing, .failed),
             (.recording, .interrupted), (.recording, .stopping),
             (.interrupted, .recovering),
             (.recovering, .recording), (.recovering, .stopping), (.recovering, .finalizing),
             (.stopping, .finalizing),
             (.finalizing, .completed), (.finalizing, .incomplete), (.finalizing, .failed):
            true
        default:
            false
        }
    }
}

public enum CaptureMode: String, Codable, CaseIterable, Hashable, Sendable {
    case microphoneOnly = "microphone_only"
    case applicationAudioOnly = "application_audio_only"
    case microphoneAndApplicationAudio = "microphone_and_application_audio"

    public var requestedTrackKinds: Set<CaptureTrackKind> {
        switch self {
        case .microphoneOnly: [.microphone]
        case .applicationAudioOnly: [.applicationAudio]
        case .microphoneAndApplicationAudio: [.microphone, .applicationAudio]
        }
    }
}

public enum CaptureTrackKind: String, Codable, CaseIterable, Hashable, Sendable {
    case microphone
    case applicationAudio = "application_audio"
}

public enum RecordingTransitionReason: String, Codable, CaseIterable, Hashable, Sendable {
    case firstPacketAccepted = "first_packet_accepted"
    case userStop = "user_stop"
    case taskCancellation = "task_cancellation"
    case permissionDenied = "permission_denied"
    case permissionRevoked = "permission_revoked"
    case sourceUnavailable = "source_unavailable"
    case sourceEnded = "source_ended"
    case deviceDisconnected = "device_disconnected"
    case formatChanged = "format_changed"
    case sleepWakeDiscontinuity = "sleep_wake_discontinuity"
    case backpressureExceeded = "backpressure_exceeded"
    case checkpointDeadlineExceeded = "checkpoint_deadline_exceeded"
    case diskCapacityDenied = "disk_capacity_denied"
    case diskWriteFailure = "disk_write_failure"
    case processRestart = "process_restart"
    case recoveryLeaseAcquired = "recovery_lease_acquired"
    case userReselectedSource = "user_reselected_source"
    case recoveredWithoutResume = "recovered_without_resume"
    case writersDrained = "writers_drained"
    case verifiedComplete = "verified_complete"
    case verifiedIncomplete = "verified_incomplete"
    case noUsableAudio = "no_usable_audio"
    case integrityFailure = "integrity_failure"
}

public enum RecordingEventActor: String, Codable, CaseIterable, Hashable, Sendable {
    case user
    case captureProvider = "capture_provider"
    case persistenceCoordinator = "persistence_coordinator"
    case taskManager = "task_manager"
    case startupRecovery = "startup_recovery"
}

public enum RecordingGapReason: String, Codable, CaseIterable, Hashable, Sendable {
    case packetBackpressure = "packet_backpressure"
    case permissionLoss = "permission_loss"
    case sourceEnded = "source_ended"
    case deviceDisconnected = "device_disconnected"
    case formatChanged = "format_changed"
    case sleepWakeDiscontinuity = "sleep_wake_discontinuity"
    case processInterruption = "process_interruption"
    case damagedSegment = "damaged_segment"
    case missingRequiredTrack = "missing_required_track"
    case unknownBoundary = "unknown_boundary"
}

public struct RecordingTimeRange: Codable, Hashable, Sendable {
    public let startNanoseconds: UInt64
    public let endNanoseconds: UInt64

    public init(startNanoseconds: UInt64, endNanoseconds: UInt64) throws {
        guard endNanoseconds > startNanoseconds else {
            throw RecordingContractError.invalidPacket("Recording ranges must be non-empty and half-open.")
        }
        self.startNanoseconds = startNanoseconds
        self.endNanoseconds = endNanoseconds
    }

    public var durationNanoseconds: UInt64 { endNanoseconds - startNanoseconds }

    private enum CodingKeys: String, CodingKey {
        case startNanoseconds, endNanoseconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            startNanoseconds: values.decode(UInt64.self, forKey: .startNanoseconds),
            endNanoseconds: values.decode(UInt64.self, forKey: .endNanoseconds)
        )
    }
}

public struct CaptureAudioFormat: Codable, Hashable, Sendable {
    public let sampleRateHertz: UInt32
    public let channelCount: UInt16
    public let channelLayout: String
    public let formatRevision: UInt32

    public init(
        sampleRateHertz: UInt32,
        channelCount: UInt16,
        channelLayout: String,
        formatRevision: UInt32
    ) throws {
        guard (8_000...384_000).contains(sampleRateHertz),
              (1...32).contains(channelCount),
              !channelLayout.isEmpty,
              channelLayout.utf8.count <= 128,
              channelLayout == channelLayout.trimmingCharacters(in: .whitespacesAndNewlines),
              !channelLayout.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              formatRevision > 0
        else {
            throw RecordingContractError.invalidPacket("The capture audio format is unsupported or unbounded.")
        }
        self.sampleRateHertz = sampleRateHertz
        self.channelCount = channelCount
        self.channelLayout = channelLayout
        self.formatRevision = formatRevision
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRateHertz, channelCount, channelLayout, formatRevision
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sampleRateHertz: values.decode(UInt32.self, forKey: .sampleRateHertz),
            channelCount: values.decode(UInt16.self, forKey: .channelCount),
            channelLayout: values.decode(String.self, forKey: .channelLayout),
            formatRevision: values.decode(UInt32.self, forKey: .formatRevision)
        )
    }
}

public struct RecordingPolicySnapshot: Codable, Hashable, Sendable {
    public let sensitivityLabelRevision: SemanticRevisionReference
    public let accessPolicyRevision: SemanticRevisionReference
    public let dataClassification: DataClassification
    public let localProcessingAllowed: Bool
    public let noOutboundMode: Bool

    public init(
        sensitivityLabelRevision: SemanticRevisionReference,
        accessPolicyRevision: SemanticRevisionReference,
        dataClassification: DataClassification,
        localProcessingAllowed: Bool,
        noOutboundMode: Bool
    ) throws {
        guard sensitivityLabelRevision.objectType == .sensitivityLabel,
              accessPolicyRevision.objectType == .accessPolicy,
              dataClassification.isKnown,
              localProcessingAllowed
        else {
            throw RecordingContractError.invalidIntent("Capture requires exact recognized local policy revisions.")
        }
        self.sensitivityLabelRevision = sensitivityLabelRevision
        self.accessPolicyRevision = accessPolicyRevision
        self.dataClassification = dataClassification
        self.localProcessingAllowed = localProcessingAllowed
        self.noOutboundMode = noOutboundMode
    }

    private enum CodingKeys: String, CodingKey {
        case sensitivityLabelRevision, accessPolicyRevision, dataClassification
        case localProcessingAllowed, noOutboundMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sensitivityLabelRevision: values.decode(
                SemanticRevisionReference.self,
                forKey: .sensitivityLabelRevision
            ),
            accessPolicyRevision: values.decode(
                SemanticRevisionReference.self,
                forKey: .accessPolicyRevision
            ),
            dataClassification: values.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            localProcessingAllowed: values.decode(
                Bool.self,
                forKey: .localProcessingAllowed
            ),
            noOutboundMode: values.decode(Bool.self, forKey: .noOutboundMode)
        )
    }
}

public struct RecordingAuthorizationEvent: Codable, Hashable, Sendable {
    public let eventID: RecordingAuthorizationEventID
    public let occurredAt: UTCInstant
    public let directUserAction: Bool
    public let visibleRecordingAcknowledged: Bool
    public let participantAndPolicyResponsibilityAcknowledged: Bool

    public init(
        eventID: RecordingAuthorizationEventID = RecordingAuthorizationEventID(UUID()),
        occurredAt: UTCInstant,
        directUserAction: Bool,
        visibleRecordingAcknowledged: Bool,
        participantAndPolicyResponsibilityAcknowledged: Bool
    ) throws {
        guard directUserAction,
              visibleRecordingAcknowledged,
              participantAndPolicyResponsibilityAcknowledged
        else {
            throw RecordingContractError.invalidIntent("Recording requires a direct visible user acknowledgement.")
        }
        self.eventID = eventID
        self.occurredAt = occurredAt
        self.directUserAction = directUserAction
        self.visibleRecordingAcknowledged = visibleRecordingAcknowledged
        self.participantAndPolicyResponsibilityAcknowledged = participantAndPolicyResponsibilityAcknowledged
    }

    private enum CodingKeys: String, CodingKey {
        case eventID, occurredAt, directUserAction, visibleRecordingAcknowledged
        case participantAndPolicyResponsibilityAcknowledged
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            eventID: values.decode(RecordingAuthorizationEventID.self, forKey: .eventID),
            occurredAt: values.decode(UTCInstant.self, forKey: .occurredAt),
            directUserAction: values.decode(Bool.self, forKey: .directUserAction),
            visibleRecordingAcknowledged: values.decode(
                Bool.self,
                forKey: .visibleRecordingAcknowledged
            ),
            participantAndPolicyResponsibilityAcknowledged: values.decode(
                Bool.self,
                forKey: .participantAndPolicyResponsibilityAcknowledged
            )
        )
    }
}

public struct RecordingTrackRequest: Codable, Hashable, Sendable {
    public let trackID: RecordingTrackID
    public let kind: CaptureTrackKind
    public let required: Bool
    public let speechSourceKind: SpeechSourceKind
    public let language: LanguageTag?

    public init(
        trackID: RecordingTrackID = RecordingTrackID(UUID()),
        kind: CaptureTrackKind,
        required: Bool = true,
        speechSourceKind: SpeechSourceKind = .unknown,
        language: LanguageTag? = nil
    ) throws {
        guard speechSourceKind.isKnown else {
            throw RecordingContractError.invalidIntent("A capture track cannot infer an unknown future speech provenance value.")
        }
        self.trackID = trackID
        self.kind = kind
        self.required = required
        self.speechSourceKind = speechSourceKind
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, kind, required, speechSourceKind, language
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            trackID: values.decode(RecordingTrackID.self, forKey: .trackID),
            kind: values.decode(CaptureTrackKind.self, forKey: .kind),
            required: values.decode(Bool.self, forKey: .required),
            speechSourceKind: values.decode(
                SpeechSourceKind.self,
                forKey: .speechSourceKind
            ),
            language: values.decodeIfPresent(LanguageTag.self, forKey: .language)
        )
    }
}

public struct RecordingAssetPublicationPlan: Codable, Hashable, Sendable {
    public let assetID: SourceAssetID
    public let revisionID: RevisionID
    public let storageObjectID: StorageObjectID

    public init(
        assetID: SourceAssetID = SourceAssetID(UUID()),
        revisionID: RevisionID = RevisionID(UUID()),
        storageObjectID: StorageObjectID = StorageObjectID(UUID())
    ) {
        self.assetID = assetID
        self.revisionID = revisionID
        self.storageObjectID = storageObjectID
    }

    public var revisionReference: SemanticRevisionReference {
        get throws {
            try SemanticRevisionReference(logicalID: assetID, revisionID: revisionID)
        }
    }
}

public struct RecordingTrackPublicationPlan: Codable, Hashable, Sendable {
    public let trackID: RecordingTrackID
    public let asset: RecordingAssetPublicationPlan

    public init(
        trackID: RecordingTrackID,
        asset: RecordingAssetPublicationPlan = RecordingAssetPublicationPlan()
    ) {
        self.trackID = trackID
        self.asset = asset
    }
}

public struct RecordingPublicationPlan: Codable, Hashable, Sendable {
    public let manifest: RecordingAssetPublicationPlan
    public let tracks: [RecordingTrackPublicationPlan]

    public init(
        manifest: RecordingAssetPublicationPlan = RecordingAssetPublicationPlan(),
        tracks: [RecordingTrackPublicationPlan]
    ) throws {
        guard !tracks.isEmpty,
              Set(tracks.map(\.trackID)).count == tracks.count,
              Set(tracks.map(\.asset.assetID)).count == tracks.count,
              !tracks.contains(where: { $0.asset.assetID == manifest.assetID })
        else {
            throw RecordingContractError.invalidIntent("Recording publication identifiers must be unique and complete.")
        }
        self.manifest = manifest
        self.tracks = tracks.sorted { $0.trackID < $1.trackID }
    }
}

public struct RecordingIntent: Codable, Hashable, Sendable {
    public static let formatVersion: UInt32 = 1

    public let formatVersion: UInt32
    public let sessionID: RecordingSessionID
    public let jobID: JobID
    public let meetingID: MeetingID
    public let mode: CaptureMode
    public let requestedTracks: [RecordingTrackRequest]
    public let policy: RecordingPolicySnapshot
    public let authorization: RecordingAuthorizationEvent
    public let publicationPlan: RecordingPublicationPlan
    public let diskBudgetBytes: UInt64
    public let createdAt: UTCInstant

    public init(
        formatVersion: UInt32 = Self.formatVersion,
        sessionID: RecordingSessionID = RecordingSessionID(UUID()),
        jobID: JobID = JobID(UUID()),
        meetingID: MeetingID,
        mode: CaptureMode,
        requestedTracks: [RecordingTrackRequest],
        policy: RecordingPolicySnapshot,
        authorization: RecordingAuthorizationEvent,
        publicationPlan: RecordingPublicationPlan? = nil,
        diskBudgetBytes: UInt64,
        createdAt: UTCInstant
    ) throws {
        let kinds = Set(requestedTracks.map(\.kind))
        let resolvedPublicationPlan = try publicationPlan ?? RecordingPublicationPlan(
            tracks: requestedTracks.map { RecordingTrackPublicationPlan(trackID: $0.trackID) }
        )
        guard formatVersion == Self.formatVersion,
              !requestedTracks.isEmpty,
              Set(requestedTracks.map(\.trackID)).count == requestedTracks.count,
              kinds == mode.requestedTrackKinds,
              requestedTracks.allSatisfy(\.required),
              Set(resolvedPublicationPlan.tracks.map(\.trackID)) == Set(requestedTracks.map(\.trackID)),
              diskBudgetBytes > 0,
              diskBudgetBytes <= JobRequest.maximumDiskBudgetBytes,
              authorization.occurredAt <= createdAt
        else {
            throw RecordingContractError.invalidIntent("The recording intent is incomplete, duplicated, or outside the accepted capture modes.")
        }
        self.formatVersion = formatVersion
        self.sessionID = sessionID
        self.jobID = jobID
        self.meetingID = meetingID
        self.mode = mode
        self.requestedTracks = requestedTracks.sorted { $0.trackID < $1.trackID }
        self.policy = policy
        self.authorization = authorization
        self.publicationPlan = resolvedPublicationPlan
        self.diskBudgetBytes = diskBudgetBytes
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, sessionID, jobID, meetingID, mode, requestedTracks
        case policy, authorization, publicationPlan, diskBudgetBytes, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatVersion: values.decode(UInt32.self, forKey: .formatVersion),
            sessionID: values.decode(RecordingSessionID.self, forKey: .sessionID),
            jobID: values.decode(JobID.self, forKey: .jobID),
            meetingID: values.decode(MeetingID.self, forKey: .meetingID),
            mode: values.decode(CaptureMode.self, forKey: .mode),
            requestedTracks: values.decode(
                [RecordingTrackRequest].self,
                forKey: .requestedTracks
            ),
            policy: values.decode(RecordingPolicySnapshot.self, forKey: .policy),
            authorization: values.decode(
                RecordingAuthorizationEvent.self,
                forKey: .authorization
            ),
            publicationPlan: values.decode(
                RecordingPublicationPlan.self,
                forKey: .publicationPlan
            ),
            diskBudgetBytes: values.decode(UInt64.self, forKey: .diskBudgetBytes),
            createdAt: values.decode(UTCInstant.self, forKey: .createdAt)
        )
    }
}

public struct RecordingSessionSnapshot: Codable, Hashable, Sendable {
    public let intent: RecordingIntent
    public let state: RecordingState
    public let stateVersion: UInt64
    public let lastEventID: RecordingStateEventID?
    public let terminalReason: RecordingTransitionReason?
    public let finalManifestRevision: SemanticRevisionReference?
    public let updatedAt: UTCInstant

    public init(
        intent: RecordingIntent,
        state: RecordingState,
        stateVersion: UInt64,
        lastEventID: RecordingStateEventID? = nil,
        terminalReason: RecordingTransitionReason? = nil,
        finalManifestRevision: SemanticRevisionReference? = nil,
        updatedAt: UTCInstant
    ) throws {
        guard stateVersion > 0,
              updatedAt >= intent.createdAt,
              (state.isTerminal == (terminalReason != nil)),
              (finalManifestRevision == nil || finalManifestRevision?.objectType == .sourceAsset),
              (state == .completed || finalManifestRevision == nil)
        else {
            throw RecordingContractError.integrityFailure("The recording session snapshot is internally inconsistent.")
        }
        self.intent = intent
        self.state = state
        self.stateVersion = stateVersion
        self.lastEventID = lastEventID
        self.terminalReason = terminalReason
        self.finalManifestRevision = finalManifestRevision
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case intent, state, stateVersion, lastEventID, terminalReason
        case finalManifestRevision, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            intent: values.decode(RecordingIntent.self, forKey: .intent),
            state: values.decode(RecordingState.self, forKey: .state),
            stateVersion: values.decode(UInt64.self, forKey: .stateVersion),
            lastEventID: values.decodeIfPresent(
                RecordingStateEventID.self,
                forKey: .lastEventID
            ),
            terminalReason: values.decodeIfPresent(
                RecordingTransitionReason.self,
                forKey: .terminalReason
            ),
            finalManifestRevision: values.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .finalManifestRevision
            ),
            updatedAt: values.decode(UTCInstant.self, forKey: .updatedAt)
        )
    }
}

public struct RecordingTransition: Codable, Hashable, Sendable {
    public let eventID: RecordingStateEventID
    public let sessionID: RecordingSessionID
    public let expectedStateVersion: UInt64
    public let from: RecordingState
    public let to: RecordingState
    public let reason: RecordingTransitionReason
    public let actor: RecordingEventActor
    public let occurredAt: UTCInstant
    public let finalManifestRevision: SemanticRevisionReference?

    public init(
        eventID: RecordingStateEventID = RecordingStateEventID(UUID()),
        sessionID: RecordingSessionID,
        expectedStateVersion: UInt64,
        from: RecordingState,
        to: RecordingState,
        reason: RecordingTransitionReason,
        actor: RecordingEventActor,
        occurredAt: UTCInstant,
        finalManifestRevision: SemanticRevisionReference? = nil
    ) throws {
        guard expectedStateVersion > 0, from.allowsTransition(to: to),
              (finalManifestRevision == nil || (to == .completed && finalManifestRevision?.objectType == .sourceAsset))
        else {
            throw RecordingContractError.invalidTransition(from: from, to: to)
        }
        self.eventID = eventID
        self.sessionID = sessionID
        self.expectedStateVersion = expectedStateVersion
        self.from = from
        self.to = to
        self.reason = reason
        self.actor = actor
        self.occurredAt = occurredAt
        self.finalManifestRevision = finalManifestRevision
    }
}

public struct RecordingEpochSource: Codable, Hashable, Sendable {
    public let trackID: RecordingTrackID
    public let kind: CaptureTrackKind
    public let sessionScopedDeviceToken: ContentDigest
    public let audioFormat: CaptureAudioFormat

    public init(
        trackID: RecordingTrackID,
        kind: CaptureTrackKind,
        sessionScopedDeviceToken: ContentDigest,
        audioFormat: CaptureAudioFormat
    ) throws {
        guard sessionScopedDeviceToken.algorithm == .sha256 else {
            throw RecordingContractError.invalidIntent("An epoch source requires a session-scoped SHA-256 device token.")
        }
        self.trackID = trackID
        self.kind = kind
        self.sessionScopedDeviceToken = sessionScopedDeviceToken
        self.audioFormat = audioFormat
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, kind, sessionScopedDeviceToken, audioFormat
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            trackID: values.decode(RecordingTrackID.self, forKey: .trackID),
            kind: values.decode(CaptureTrackKind.self, forKey: .kind),
            sessionScopedDeviceToken: values.decode(
                ContentDigest.self,
                forKey: .sessionScopedDeviceToken
            ),
            audioFormat: values.decode(CaptureAudioFormat.self, forKey: .audioFormat)
        )
    }
}

public struct RecordingEpoch: Codable, Hashable, Sendable {
    public let epochID: RecordingEpochID
    public let sessionID: RecordingSessionID
    public let sequence: UInt32
    public let selectedAt: UTCInstant
    public let sources: [RecordingEpochSource]
    public let sourceSetDigest: ContentDigest
    public let startHostNanoseconds: UInt64

    public init(
        epochID: RecordingEpochID = RecordingEpochID(UUID()),
        sessionID: RecordingSessionID,
        sequence: UInt32,
        selectedAt: UTCInstant,
        sources: [RecordingEpochSource],
        sourceSetDigest: ContentDigest,
        startHostNanoseconds: UInt64
    ) throws {
        guard sequence > 0,
              !sources.isEmpty,
              sources.count <= 2,
              Set(sources.map(\.trackID)).count == sources.count,
              Set(sources.map(\.kind)).count == sources.count,
              sourceSetDigest.algorithm == .sha256
        else {
            throw RecordingContractError.invalidIntent("An epoch requires one or two distinct authorized source descriptors.")
        }
        self.epochID = epochID
        self.sessionID = sessionID
        self.sequence = sequence
        self.selectedAt = selectedAt
        self.sources = sources.sorted { $0.trackID < $1.trackID }
        self.sourceSetDigest = sourceSetDigest
        self.startHostNanoseconds = startHostNanoseconds
    }

    private enum CodingKeys: String, CodingKey {
        case epochID, sessionID, sequence, selectedAt, sources
        case sourceSetDigest, startHostNanoseconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            epochID: values.decode(RecordingEpochID.self, forKey: .epochID),
            sessionID: values.decode(RecordingSessionID.self, forKey: .sessionID),
            sequence: values.decode(UInt32.self, forKey: .sequence),
            selectedAt: values.decode(UTCInstant.self, forKey: .selectedAt),
            sources: values.decode([RecordingEpochSource].self, forKey: .sources),
            sourceSetDigest: values.decode(ContentDigest.self, forKey: .sourceSetDigest),
            startHostNanoseconds: values.decode(
                UInt64.self,
                forKey: .startHostNanoseconds
            )
        )
    }
}

public struct CapturedAudioPacket: Sendable {
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID
    public let trackID: RecordingTrackID
    public let sequence: UInt64
    public let mediaRange: RecordingTimeRange
    public let hostRange: RecordingTimeRange
    public let format: CaptureAudioFormat
    public let frameCount: UInt32
    public let linearPCM: Data

    public init(
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        trackID: RecordingTrackID,
        sequence: UInt64,
        mediaRange: RecordingTimeRange,
        hostRange: RecordingTimeRange,
        format: CaptureAudioFormat,
        frameCount: UInt32,
        linearPCM: Data
    ) throws {
        let expectedDuration = UInt64(frameCount) * 1_000_000_000 / UInt64(format.sampleRateHertz)
        let tolerance = max(UInt64(1), 2_000_000_000 / UInt64(format.sampleRateHertz))
        guard sequence > 0,
              frameCount > 0,
              !linearPCM.isEmpty,
              linearPCM.count <= 16 * 1_024 * 1_024,
              mediaRange.durationNanoseconds.absDifference(from: expectedDuration) <= tolerance
        else {
            throw RecordingContractError.invalidPacket("A capture packet must carry bounded PCM and coherent timing.")
        }
        self.sessionID = sessionID
        self.epochID = epochID
        self.trackID = trackID
        self.sequence = sequence
        self.mediaRange = mediaRange
        self.hostRange = hostRange
        self.format = format
        self.frameCount = frameCount
        self.linearPCM = linearPCM
    }
}

private extension UInt64 {
    func absDifference(from other: UInt64) -> UInt64 {
        self >= other ? self - other : other - self
    }
}

public enum CapturePacketDisposition: String, Codable, Hashable, Sendable {
    case accepted
    case backpressure
    case stop
}

public struct SealedCaptureSegment: Codable, Hashable, Sendable {
    public let segmentID: RecordingSegmentID
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID
    public let trackID: RecordingTrackID
    public let sequence: UInt64
    public let mediaRange: RecordingTimeRange
    public let hostRange: RecordingTimeRange
    public let frameCount: UInt64
    public let format: CaptureAudioFormat
    public let storageObjectID: StorageObjectID
    public let relativePath: WorkspaceRelativePath
    public let contentHash: ContentDigest
    public let byteSize: UInt64
    public let rollingDescriptorDigest: ContentDigest
    public let sealedAt: UTCInstant

    public init(
        segmentID: RecordingSegmentID = RecordingSegmentID(UUID()),
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        trackID: RecordingTrackID,
        sequence: UInt64,
        mediaRange: RecordingTimeRange,
        hostRange: RecordingTimeRange,
        frameCount: UInt64,
        format: CaptureAudioFormat,
        storageObjectID: StorageObjectID,
        relativePath: WorkspaceRelativePath,
        contentHash: ContentDigest,
        byteSize: UInt64,
        rollingDescriptorDigest: ContentDigest,
        sealedAt: UTCInstant
    ) throws {
        guard sequence > 0,
              frameCount > 0,
              byteSize > 0,
              mediaRange.durationNanoseconds <= 6_000_000_000,
              contentHash.algorithm == .sha256,
              rollingDescriptorDigest.algorithm == .sha256
        else {
            throw RecordingContractError.invalidSegment("A segment must be bounded, non-empty, and SHA-256 verified.")
        }
        self.segmentID = segmentID
        self.sessionID = sessionID
        self.epochID = epochID
        self.trackID = trackID
        self.sequence = sequence
        self.mediaRange = mediaRange
        self.hostRange = hostRange
        self.frameCount = frameCount
        self.format = format
        self.storageObjectID = storageObjectID
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.rollingDescriptorDigest = rollingDescriptorDigest
        self.sealedAt = sealedAt
    }

    private enum CodingKeys: String, CodingKey {
        case segmentID, sessionID, epochID, trackID, sequence, mediaRange
        case hostRange, frameCount, format, storageObjectID, relativePath
        case contentHash, byteSize, rollingDescriptorDigest, sealedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            segmentID: values.decode(RecordingSegmentID.self, forKey: .segmentID),
            sessionID: values.decode(RecordingSessionID.self, forKey: .sessionID),
            epochID: values.decode(RecordingEpochID.self, forKey: .epochID),
            trackID: values.decode(RecordingTrackID.self, forKey: .trackID),
            sequence: values.decode(UInt64.self, forKey: .sequence),
            mediaRange: values.decode(RecordingTimeRange.self, forKey: .mediaRange),
            hostRange: values.decode(RecordingTimeRange.self, forKey: .hostRange),
            frameCount: values.decode(UInt64.self, forKey: .frameCount),
            format: values.decode(CaptureAudioFormat.self, forKey: .format),
            storageObjectID: values.decode(StorageObjectID.self, forKey: .storageObjectID),
            relativePath: values.decode(WorkspaceRelativePath.self, forKey: .relativePath),
            contentHash: values.decode(ContentDigest.self, forKey: .contentHash),
            byteSize: values.decode(UInt64.self, forKey: .byteSize),
            rollingDescriptorDigest: values.decode(
                ContentDigest.self,
                forKey: .rollingDescriptorDigest
            ),
            sealedAt: values.decode(UTCInstant.self, forKey: .sealedAt)
        )
    }
}

public struct RecordingGap: Codable, Hashable, Sendable {
    public let gapID: RecordingGapID
    public let sessionID: RecordingSessionID
    public let epochID: RecordingEpochID?
    public let trackID: RecordingTrackID
    public let mediaRange: RecordingTimeRange?
    public let hostRange: RecordingTimeRange?
    public let reason: RecordingGapReason
    public let detectedBy: RecordingEventActor
    public let detectedAt: UTCInstant
    public let userAcknowledgedAt: UTCInstant?

    public init(
        gapID: RecordingGapID = RecordingGapID(UUID()),
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID?,
        trackID: RecordingTrackID,
        mediaRange: RecordingTimeRange?,
        hostRange: RecordingTimeRange?,
        reason: RecordingGapReason,
        detectedBy: RecordingEventActor,
        detectedAt: UTCInstant,
        userAcknowledgedAt: UTCInstant? = nil
    ) throws {
        guard userAcknowledgedAt == nil || userAcknowledgedAt! >= detectedAt
        else {
            throw RecordingContractError.integrityFailure("A recording gap needs an exact range or an explicit unknown boundary.")
        }
        self.gapID = gapID
        self.sessionID = sessionID
        self.epochID = epochID
        self.trackID = trackID
        self.mediaRange = mediaRange
        self.hostRange = hostRange
        self.reason = reason
        self.detectedBy = detectedBy
        self.detectedAt = detectedAt
        self.userAcknowledgedAt = userAcknowledgedAt
    }

    private enum CodingKeys: String, CodingKey {
        case gapID, sessionID, epochID, trackID, mediaRange, hostRange
        case reason, detectedBy, detectedAt, userAcknowledgedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            gapID: values.decode(RecordingGapID.self, forKey: .gapID),
            sessionID: values.decode(RecordingSessionID.self, forKey: .sessionID),
            epochID: values.decodeIfPresent(RecordingEpochID.self, forKey: .epochID),
            trackID: values.decode(RecordingTrackID.self, forKey: .trackID),
            mediaRange: values.decodeIfPresent(
                RecordingTimeRange.self,
                forKey: .mediaRange
            ),
            hostRange: values.decodeIfPresent(
                RecordingTimeRange.self,
                forKey: .hostRange
            ),
            reason: values.decode(RecordingGapReason.self, forKey: .reason),
            detectedBy: values.decode(RecordingEventActor.self, forKey: .detectedBy),
            detectedAt: values.decode(UTCInstant.self, forKey: .detectedAt),
            userAcknowledgedAt: values.decodeIfPresent(
                UTCInstant.self,
                forKey: .userAcknowledgedAt
            )
        )
    }
}

public struct RecordingTrackCheckpoint: Codable, Hashable, Sendable {
    public let trackID: RecordingTrackID
    public let lastSealedSequence: UInt64
    public let lastCoveredMediaRange: RecordingTimeRange
    public let sealedFrameCount: UInt64
    public let lastSegmentDigest: ContentDigest
    public let rollingDescriptorDigest: ContentDigest

    public init(
        trackID: RecordingTrackID,
        lastSealedSequence: UInt64,
        lastCoveredMediaRange: RecordingTimeRange,
        sealedFrameCount: UInt64,
        lastSegmentDigest: ContentDigest,
        rollingDescriptorDigest: ContentDigest
    ) throws {
        guard lastSealedSequence > 0,
              sealedFrameCount > 0,
              lastSegmentDigest.algorithm == .sha256,
              rollingDescriptorDigest.algorithm == .sha256
        else {
            throw RecordingContractError.invalidCheckpoint("A track checkpoint requires a verified sealed segment.")
        }
        self.trackID = trackID
        self.lastSealedSequence = lastSealedSequence
        self.lastCoveredMediaRange = lastCoveredMediaRange
        self.sealedFrameCount = sealedFrameCount
        self.lastSegmentDigest = lastSegmentDigest
        self.rollingDescriptorDigest = rollingDescriptorDigest
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, lastSealedSequence, lastCoveredMediaRange, sealedFrameCount
        case lastSegmentDigest, rollingDescriptorDigest
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            trackID: values.decode(RecordingTrackID.self, forKey: .trackID),
            lastSealedSequence: values.decode(UInt64.self, forKey: .lastSealedSequence),
            lastCoveredMediaRange: values.decode(
                RecordingTimeRange.self,
                forKey: .lastCoveredMediaRange
            ),
            sealedFrameCount: values.decode(UInt64.self, forKey: .sealedFrameCount),
            lastSegmentDigest: values.decode(
                ContentDigest.self,
                forKey: .lastSegmentDigest
            ),
            rollingDescriptorDigest: values.decode(
                ContentDigest.self,
                forKey: .rollingDescriptorDigest
            )
        )
    }
}

public struct RecordingCheckpoint: Codable, Hashable, Sendable {
    public static let formatIdentifier = "meetingbuddy.recording-checkpoint.v1"
    public static let formatVersion: UInt32 = 1

    public let formatIdentifier: String
    public let formatVersion: UInt32
    public let sessionID: RecordingSessionID
    public let jobID: JobID
    public let meetingID: MeetingID
    public let stateVersion: UInt64
    public let state: RecordingState
    public let lastStateEventID: RecordingStateEventID?
    public let currentEpochID: RecordingEpochID?
    public let requiredTrackIDs: [RecordingTrackID]
    public let tracks: [RecordingTrackCheckpoint]
    public let outstandingGapCount: UInt32
    public let reconciliationRequired: Bool
    public let createdAt: UTCInstant

    public init(
        formatIdentifier: String = Self.formatIdentifier,
        formatVersion: UInt32 = Self.formatVersion,
        sessionID: RecordingSessionID,
        jobID: JobID,
        meetingID: MeetingID,
        stateVersion: UInt64,
        state: RecordingState,
        lastStateEventID: RecordingStateEventID?,
        currentEpochID: RecordingEpochID?,
        requiredTrackIDs: [RecordingTrackID],
        tracks: [RecordingTrackCheckpoint],
        outstandingGapCount: UInt32,
        reconciliationRequired: Bool,
        createdAt: UTCInstant
    ) throws {
        guard formatIdentifier == Self.formatIdentifier,
              formatVersion == Self.formatVersion,
              stateVersion > 0,
              Set(requiredTrackIDs).count == requiredTrackIDs.count,
              Set(tracks.map(\.trackID)).count == tracks.count,
              Set(tracks.map(\.trackID)).isSubset(of: Set(requiredTrackIDs))
        else {
            throw RecordingContractError.invalidCheckpoint("The recording checkpoint version or cursor set is invalid.")
        }
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.sessionID = sessionID
        self.jobID = jobID
        self.meetingID = meetingID
        self.stateVersion = stateVersion
        self.state = state
        self.lastStateEventID = lastStateEventID
        self.currentEpochID = currentEpochID
        self.requiredTrackIDs = requiredTrackIDs.sorted()
        self.tracks = tracks.sorted { $0.trackID < $1.trackID }
        self.outstandingGapCount = outstandingGapCount
        self.reconciliationRequired = reconciliationRequired
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case formatIdentifier, formatVersion, sessionID, jobID, meetingID
        case stateVersion, state, lastStateEventID, currentEpochID
        case requiredTrackIDs, tracks, outstandingGapCount
        case reconciliationRequired, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatIdentifier: values.decode(String.self, forKey: .formatIdentifier),
            formatVersion: values.decode(UInt32.self, forKey: .formatVersion),
            sessionID: values.decode(RecordingSessionID.self, forKey: .sessionID),
            jobID: values.decode(JobID.self, forKey: .jobID),
            meetingID: values.decode(MeetingID.self, forKey: .meetingID),
            stateVersion: values.decode(UInt64.self, forKey: .stateVersion),
            state: values.decode(RecordingState.self, forKey: .state),
            lastStateEventID: values.decodeIfPresent(
                RecordingStateEventID.self,
                forKey: .lastStateEventID
            ),
            currentEpochID: values.decodeIfPresent(
                RecordingEpochID.self,
                forKey: .currentEpochID
            ),
            requiredTrackIDs: values.decode(
                [RecordingTrackID].self,
                forKey: .requiredTrackIDs
            ),
            tracks: values.decode([RecordingTrackCheckpoint].self, forKey: .tracks),
            outstandingGapCount: values.decode(UInt32.self, forKey: .outstandingGapCount),
            reconciliationRequired: values.decode(
                Bool.self,
                forKey: .reconciliationRequired
            ),
            createdAt: values.decode(UTCInstant.self, forKey: .createdAt)
        )
    }

    public func canonicalPayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= JobCheckpoint.maximumPayloadBytes else {
            throw RecordingContractError.invalidCheckpoint("The recording checkpoint exceeds 65,536 bytes.")
        }
        return data
    }
}

public struct RecordingRecoveryOutcome: Codable, Hashable, Sendable {
    public let snapshot: RecordingSessionSnapshot
    public let verifiedSegments: [SealedCaptureSegment]
    public let gaps: [RecordingGap]
    public let quarantinedRelativePaths: [WorkspaceRelativePath]
    public let rebuiltCheckpoint: RecordingCheckpoint?

    public var reconciliationRequired: Bool {
        !quarantinedRelativePaths.isEmpty
            || rebuiltCheckpoint?.reconciliationRequired == true
    }

    public init(
        snapshot: RecordingSessionSnapshot,
        verifiedSegments: [SealedCaptureSegment],
        gaps: [RecordingGap],
        quarantinedRelativePaths: [WorkspaceRelativePath],
        rebuiltCheckpoint: RecordingCheckpoint?
    ) {
        self.snapshot = snapshot
        self.verifiedSegments = verifiedSegments
        self.gaps = gaps
        self.quarantinedRelativePaths = quarantinedRelativePaths
        self.rebuiltCheckpoint = rebuiltCheckpoint
    }
}

public protocol RecordingSessionRepository: Sendable {
    func createIntent(_ intent: RecordingIntent) async throws -> RecordingSessionSnapshot
    func session(_ sessionID: RecordingSessionID) async throws -> RecordingSessionSnapshot?
    func session(jobID: JobID) async throws -> RecordingSessionSnapshot?
    func nonterminalSessions() async throws -> [RecordingSessionSnapshot]
    func transition(_ transition: RecordingTransition) async throws -> RecordingSessionSnapshot
    func registerEpoch(_ epoch: RecordingEpoch) async throws
    func epochs(sessionID: RecordingSessionID) async throws -> [RecordingEpoch]
    func seal(_ segment: SealedCaptureSegment, checkpoint: RecordingCheckpoint) async throws -> RecordingCheckpoint
    func recordGap(_ gap: RecordingGap) async throws
    func segments(sessionID: RecordingSessionID) async throws -> [SealedCaptureSegment]
    func gaps(sessionID: RecordingSessionID) async throws -> [RecordingGap]
    func latestCheckpoint(sessionID: RecordingSessionID) async throws -> RecordingCheckpoint?
    func stateEventChainDigest(sessionID: RecordingSessionID) async throws -> ContentDigest
}

public protocol RecordingRecoveryService: Sendable {
    func recover(_ sessionID: RecordingSessionID) async throws -> RecordingRecoveryOutcome
    func recoverNonterminalSessions() async throws -> [RecordingRecoveryOutcome]
}
