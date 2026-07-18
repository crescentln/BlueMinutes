import Foundation
import MeetingBuddyDomain

public enum JobIDTag: Sendable {}
public typealias JobID = StableID<JobIDTag>

public enum JobContractError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case invalidRequest(String)
    case invalidProgress(String)
    case invalidCheckpoint(String)
    case invalidState(String)
    case transitionNotAllowed(from: JobState, to: JobState)
    case retryLimitReached(JobID)
    case optimisticLockFailed(JobID)
    case jobNotFound(JobID)
    case duplicateIdempotencyKey
    case staleInput(RevisionID)
}

public struct JobType: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard JobContractValidation.isOpaqueIdentifier(rawValue, maximumBytes: 96) else {
            throw JobContractError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct JobRequester: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard JobContractValidation.isOpaqueIdentifier(rawValue, maximumBytes: 128) else {
            throw JobContractError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A caller-calculated SHA-256 digest over stable job inputs and policy.
///
/// Requiring a digest keeps source text, paths, and credentials out of the
/// idempotency index while still allowing duplicate submissions to converge.
public struct JobIdempotencyKey: Codable, Hashable, Sendable {
    public let lowercaseHex: String

    public init(lowercaseHex: String) throws {
        guard lowercaseHex.utf8.count == 64,
              lowercaseHex == lowercaseHex.lowercased(),
              lowercaseHex.utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
              })
        else {
            throw JobContractError.invalidIdentifier(lowercaseHex)
        }
        self.lowercaseHex = lowercaseHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(lowercaseHex: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lowercaseHex)
    }
}

public enum JobOrigin: String, Codable, Hashable, Sendable {
    case user
    case application
    case automation
    case recovery
}

public enum JobState: String, Codable, Hashable, Sendable, CaseIterable {
    case queued
    case running
    case pauseRequested = "pause_requested"
    case paused
    case cancellationRequested = "cancellation_requested"
    case succeeded
    case failed
    case cancelled
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .interrupted:
            true
        default:
            false
        }
    }

    public var isActiveExecution: Bool {
        switch self {
        case .running, .pauseRequested, .paused, .cancellationRequested:
            true
        default:
            false
        }
    }
}

public enum JobResumeCapability: String, Codable, Hashable, Sendable {
    case restartOnly = "restart_only"
    case checkpointed
}

public struct JobProgress: Codable, Hashable, Sendable {
    public let completedUnitCount: UInt64
    public let totalUnitCount: UInt64
    public let currentNode: String?

    public init(
        completedUnitCount: UInt64,
        totalUnitCount: UInt64,
        currentNode: String? = nil
    ) throws {
        guard totalUnitCount > 0, completedUnitCount <= totalUnitCount else {
            throw JobContractError.invalidProgress(
                "Progress must have a nonzero total and cannot exceed that total."
            )
        }
        if let currentNode,
           !JobContractValidation.isOpaqueIdentifier(currentNode, maximumBytes: 128)
        {
            throw JobContractError.invalidProgress(
                "The current node must be a bounded opaque identifier."
            )
        }
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.currentNode = currentNode
    }

    public var millionthsComplete: UInt32 {
        let quotient = completedUnitCount.multipliedFullWidth(by: 1_000_000)
        let divided = totalUnitCount.dividingFullWidth(quotient).quotient
        return UInt32(min(divided, 1_000_000))
    }
}

public struct JobCheckpoint: Codable, Hashable, Sendable {
    public static let maximumPayloadBytes = 65_536

    public let formatVersion: UInt32
    public let payload: Data

    public init(formatVersion: UInt32, payload: Data) throws {
        guard formatVersion > 0,
              !payload.isEmpty,
              payload.count <= Self.maximumPayloadBytes
        else {
            throw JobContractError.invalidCheckpoint(
                "A checkpoint needs a positive version and 1–65,536 bytes."
            )
        }
        self.formatVersion = formatVersion
        self.payload = payload
    }
}

/// A bounded, versioned feature-specific input carried by a durable job.
///
/// The Task Manager treats this as opaque data. Executors decode only their
/// own format, which keeps feature state out of the operational schema while
/// allowing an interrupted job to reconstruct the exact approved inputs.
public struct JobInputPayload: Codable, Hashable, Sendable {
    public static let maximumPayloadBytes = 65_536

    public let formatIdentifier: String
    public let formatVersion: UInt32
    public let payload: Data

    public init(
        formatIdentifier: String,
        formatVersion: UInt32,
        payload: Data
    ) throws {
        guard JobContractValidation.isOpaqueIdentifier(
            formatIdentifier,
            maximumBytes: 96
        ),
            formatVersion > 0,
            !payload.isEmpty,
            payload.count <= Self.maximumPayloadBytes
        else {
            throw JobContractError.invalidRequest(
                "A job input needs a bounded format, positive version, and 1–65,536 bytes."
            )
        }
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case formatIdentifier = "format_identifier"
        case formatVersion = "format_version"
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatIdentifier: container.decode(String.self, forKey: .formatIdentifier),
            formatVersion: container.decode(UInt32.self, forKey: .formatVersion),
            payload: container.decode(Data.self, forKey: .payload)
        )
    }
}

public struct ProviderUsageMetadata: Codable, Hashable, Sendable {
    public let provider: ProviderMetadata
    public let inputUnitCount: UInt64?
    public let outputUnitCount: UInt64?

    public init(
        provider: ProviderMetadata,
        inputUnitCount: UInt64? = nil,
        outputUnitCount: UInt64? = nil
    ) throws {
        try provider.validate()
        self.provider = provider
        self.inputUnitCount = inputUnitCount
        self.outputUnitCount = outputUnitCount
    }
}

public struct JobFailureRecord: Codable, Hashable, Sendable {
    public let code: String
    public let safeSummary: String
    public let retryable: Bool
    public let occurredAt: UTCInstant

    public init(
        code: String,
        safeSummary: String,
        retryable: Bool,
        occurredAt: UTCInstant
    ) throws {
        guard JobContractValidation.isOpaqueIdentifier(code, maximumBytes: 96),
              JobContractValidation.isSafeSummary(safeSummary)
        else {
            throw JobContractError.invalidIdentifier(code)
        }
        self.code = code
        self.safeSummary = safeSummary
        self.retryable = retryable
        self.occurredAt = occurredAt
    }
}

public struct TaskDirectoryLease: Codable, Hashable, Sendable {
    public let jobID: JobID
    public let relativePath: WorkspaceRelativePath
    public let diskBudgetBytes: UInt64

    public init(
        jobID: JobID,
        relativePath: WorkspaceRelativePath,
        diskBudgetBytes: UInt64
    ) throws {
        let expected = ".tasks/\(jobID.canonicalString)"
        guard relativePath.rawValue == expected,
              diskBudgetBytes > 0,
              diskBudgetBytes <= JobRequest.maximumDiskBudgetBytes
        else {
            throw JobContractError.invalidRequest(
                "A task lease must use its canonical task path and an approved disk budget."
            )
        }
        self.jobID = jobID
        self.relativePath = relativePath
        self.diskBudgetBytes = diskBudgetBytes
    }
}

public struct JobRequest: Sendable {
    public static let maximumDiskBudgetBytes: UInt64 = 1_099_511_627_776

    public let jobID: JobID
    public let jobType: JobType
    public let meetingID: MeetingID?
    public let origin: JobOrigin
    public let requestedBy: JobRequester
    public let inputPayload: JobInputPayload?
    public let inputRevisionIDs: [SemanticRevisionReference]
    public let dependencyJobIDs: [JobID]
    public let privacyRoute: PrivacyRoute
    public let dataClassification: DataClassification
    public let idempotencyKey: JobIdempotencyKey
    public let resumeCapability: JobResumeCapability
    public let maximumRetryCount: UInt32
    public let totalUnitCount: UInt64
    public let diskBudgetBytes: UInt64

    public init(
        jobID: JobID = JobID(UUID()),
        jobType: JobType,
        meetingID: MeetingID? = nil,
        origin: JobOrigin,
        requestedBy: JobRequester,
        inputPayload: JobInputPayload? = nil,
        inputRevisionIDs: [SemanticRevisionReference] = [],
        dependencyJobIDs: [JobID] = [],
        privacyRoute: PrivacyRoute = .localOnly,
        dataClassification: DataClassification,
        idempotencyKey: JobIdempotencyKey,
        resumeCapability: JobResumeCapability = .restartOnly,
        maximumRetryCount: UInt32 = 0,
        totalUnitCount: UInt64 = 1,
        diskBudgetBytes: UInt64
    ) throws {
        let sortedInputs = inputRevisionIDs.sorted()
        let sortedDependencies = dependencyJobIDs.sorted()
        guard Set(sortedInputs).count == sortedInputs.count,
              Set(sortedDependencies).count == sortedDependencies.count,
              !sortedDependencies.contains(jobID),
              privacyRoute.isKnown,
              dataClassification.isKnown,
              !(dataClassification == .restricted && privacyRoute == .approvedCloud),
              maximumRetryCount <= 100,
              totalUnitCount > 0,
              diskBudgetBytes > 0,
              diskBudgetBytes <= Self.maximumDiskBudgetBytes
        else {
            throw JobContractError.invalidRequest(
                "The job request contains duplicate, unsafe, unknown, or out-of-range values."
            )
        }
        self.jobID = jobID
        self.jobType = jobType
        self.meetingID = meetingID
        self.origin = origin
        self.requestedBy = requestedBy
        self.inputPayload = inputPayload
        self.inputRevisionIDs = sortedInputs
        self.dependencyJobIDs = sortedDependencies
        self.privacyRoute = privacyRoute
        self.dataClassification = dataClassification
        self.idempotencyKey = idempotencyKey
        self.resumeCapability = resumeCapability
        self.maximumRetryCount = maximumRetryCount
        self.totalUnitCount = totalUnitCount
        self.diskBudgetBytes = diskBudgetBytes
    }
}

/// The current immutable snapshot of a mutable operational job.
///
/// Repositories replace the snapshot with optimistic locking and retain
/// immutable state-transition events. Semantic revisions remain separately
/// immutable and are never represented by this operational record.
public struct JobRecord: Codable, Hashable, Sendable {
    public let jobID: JobID
    public let jobType: JobType
    public let meetingID: MeetingID?
    public let origin: JobOrigin
    public let requestedBy: JobRequester
    public let inputPayload: JobInputPayload?
    public let createdAt: UTCInstant
    public let startedAt: UTCInstant?
    public let finishedAt: UTCInstant?
    public let state: JobState
    public let progress: JobProgress
    public let inputRevisionIDs: [SemanticRevisionReference]
    public let outputRevisionIDs: [SemanticRevisionReference]
    public let dependencyJobIDs: [JobID]
    public let providerUsage: [ProviderUsageMetadata]
    public let privacyRoute: PrivacyRoute
    public let dataClassification: DataClassification
    public let retryCount: UInt32
    public let maximumRetryCount: UInt32
    public let checkpoint: JobCheckpoint?
    public let idempotencyKey: JobIdempotencyKey
    public let temporaryDirectory: TaskDirectoryLease
    public let resumeCapability: JobResumeCapability
    public let errorRecord: JobFailureRecord?
    public let recordVersion: UInt64

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case jobType = "job_type"
        case meetingID = "meeting_id"
        case origin
        case requestedBy = "requested_by"
        case inputPayload = "input_payload"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case state
        case progress
        case inputRevisionIDs = "input_revision_ids"
        case outputRevisionIDs = "output_revision_ids"
        case dependencyJobIDs = "dependency_job_ids"
        case providerUsage = "provider_usage"
        case privacyRoute = "privacy_route"
        case dataClassification = "data_classification"
        case retryCount = "retry_count"
        case maximumRetryCount = "maximum_retry_count"
        case checkpoint
        case idempotencyKey = "idempotency_key"
        case temporaryDirectory = "temporary_directory"
        case resumeCapability = "resume_capability"
        case errorRecord = "error_record"
        case recordVersion = "record_version"
    }

    public init(request: JobRequest, lease: TaskDirectoryLease, createdAt: UTCInstant) throws {
        guard lease.jobID == request.jobID,
              lease.diskBudgetBytes == request.diskBudgetBytes
        else {
            throw JobContractError.invalidRequest("The task lease does not match the job request.")
        }
        self.jobID = request.jobID
        self.jobType = request.jobType
        self.meetingID = request.meetingID
        self.origin = request.origin
        self.requestedBy = request.requestedBy
        self.inputPayload = request.inputPayload
        self.createdAt = createdAt
        self.startedAt = nil
        self.finishedAt = nil
        self.state = .queued
        self.progress = try JobProgress(
            completedUnitCount: 0,
            totalUnitCount: request.totalUnitCount
        )
        self.inputRevisionIDs = request.inputRevisionIDs
        self.outputRevisionIDs = []
        self.dependencyJobIDs = request.dependencyJobIDs
        self.providerUsage = []
        self.privacyRoute = request.privacyRoute
        self.dataClassification = request.dataClassification
        self.retryCount = 0
        self.maximumRetryCount = request.maximumRetryCount
        self.checkpoint = nil
        self.idempotencyKey = request.idempotencyKey
        self.temporaryDirectory = lease
        self.resumeCapability = request.resumeCapability
        self.errorRecord = nil
        self.recordVersion = 1
        try validate()
    }

    public func updatingProgress(
        _ progress: JobProgress,
        checkpoint: JobCheckpoint?
    ) throws -> JobRecord {
        guard state == .running || state == .pauseRequested,
              progress.totalUnitCount == self.progress.totalUnitCount,
              progress.completedUnitCount >= self.progress.completedUnitCount,
              checkpoint == nil || resumeCapability == .checkpointed
        else {
            throw JobContractError.invalidProgress(
                "Progress must be monotonic within an active attempt."
            )
        }
        let nextCheckpoint: JobCheckpoint? = checkpoint ?? self.checkpoint
        return try replacing(progress: progress, checkpoint: .some(nextCheckpoint))
    }

    public func transitioning(
        to newState: JobState,
        at timestamp: UTCInstant,
        failure: JobFailureRecord? = nil,
        outputRevisionIDs: [SemanticRevisionReference]? = nil,
        providerUsage: [ProviderUsageMetadata]? = nil
    ) throws -> JobRecord {
        guard JobStateMachine.allows(from: state, to: newState) else {
            throw JobContractError.transitionNotAllowed(from: state, to: newState)
        }
        var nextProgress = progress
        if newState == .succeeded {
            nextProgress = try JobProgress(
                completedUnitCount: progress.totalUnitCount,
                totalUnitCount: progress.totalUnitCount,
                currentNode: progress.currentNode
            )
        }
        let nextStartedAt = newState == .running ? (startedAt ?? timestamp) : startedAt
        let nextFinishedAt = newState.isTerminal ? timestamp : nil
        let nextFailure: JobFailureRecord?
        switch newState {
        case .failed, .interrupted:
            guard let failure else {
                throw JobContractError.invalidState(
                    "Failed and interrupted jobs require a safe error record."
                )
            }
            nextFailure = failure
        default:
            nextFailure = nil
        }
        return try replacing(
            startedAt: .some(nextStartedAt),
            finishedAt: .some(nextFinishedAt),
            state: newState,
            progress: nextProgress,
            outputRevisionIDs: outputRevisionIDs ?? self.outputRevisionIDs,
            providerUsage: providerUsage ?? self.providerUsage,
            errorRecord: .some(nextFailure)
        )
    }

    public func retrying() throws -> JobRecord {
        guard state == .failed || state == .cancelled || state == .interrupted else {
            throw JobContractError.transitionNotAllowed(from: state, to: .queued)
        }
        guard retryCount < maximumRetryCount else {
            throw JobContractError.retryLimitReached(jobID)
        }
        if state != .cancelled, errorRecord?.retryable != true {
            throw JobContractError.invalidState(
                "A non-retryable failure cannot be queued for another attempt."
            )
        }
        let canResume = (state == .failed || state == .interrupted)
            && resumeCapability == .checkpointed
            && checkpoint != nil
        let nextProgress = canResume
            ? progress
            : try JobProgress(completedUnitCount: 0, totalUnitCount: progress.totalUnitCount)
        return try replacing(
            startedAt: .some(nil),
            finishedAt: .some(nil),
            state: .queued,
            progress: nextProgress,
            outputRevisionIDs: [],
            providerUsage: [],
            retryCount: retryCount + 1,
            checkpoint: .some(canResume ? checkpoint : nil),
            errorRecord: .some(nil)
        )
    }

    public func validate() throws {
        guard recordVersion > 0,
              retryCount <= maximumRetryCount,
              temporaryDirectory.jobID == jobID,
              temporaryDirectory.relativePath.rawValue == ".tasks/\(jobID.canonicalString)",
              temporaryDirectory.diskBudgetBytes > 0,
              temporaryDirectory.diskBudgetBytes <= JobRequest.maximumDiskBudgetBytes,
              progress.totalUnitCount > 0,
              progress.completedUnitCount <= progress.totalUnitCount,
              progress.currentNode.map({
                  JobContractValidation.isOpaqueIdentifier($0, maximumBytes: 128)
              }) ?? true,
              Set(inputRevisionIDs).count == inputRevisionIDs.count,
              inputRevisionIDs == inputRevisionIDs.sorted(),
              Set(outputRevisionIDs).count == outputRevisionIDs.count,
              outputRevisionIDs == outputRevisionIDs.sorted(),
              Set(dependencyJobIDs).count == dependencyJobIDs.count,
              dependencyJobIDs == dependencyJobIDs.sorted(),
              !dependencyJobIDs.contains(jobID),
              privacyRoute.isKnown,
              dataClassification.isKnown,
              !(dataClassification == .restricted && privacyRoute == .approvedCloud)
        else {
            throw JobContractError.invalidState("The job snapshot violates stable invariants.")
        }
        if let startedAt, startedAt < createdAt {
            throw JobContractError.invalidState("A job cannot start before creation.")
        }
        if let finishedAt {
            guard state.isTerminal,
                  finishedAt >= (startedAt ?? createdAt)
            else {
                throw JobContractError.invalidState("A job has an invalid finish timestamp.")
            }
        } else if state.isTerminal {
            throw JobContractError.invalidState("A terminal job requires a finish timestamp.")
        }
        if state.isActiveExecution, startedAt == nil {
            throw JobContractError.invalidState("An active job requires a start timestamp.")
        }
        if state == .paused,
           (resumeCapability != .checkpointed || checkpoint == nil)
        {
            throw JobContractError.invalidState(
                "A paused job requires a durable checkpoint and checkpointed resume support."
            )
        }
        if (state == .failed || state == .interrupted) != (errorRecord != nil) {
            throw JobContractError.invalidState(
                "Only failed or interrupted jobs retain an error record."
            )
        }
        if let errorRecord,
           (!JobContractValidation.isOpaqueIdentifier(errorRecord.code, maximumBytes: 96)
               || !JobContractValidation.isSafeSummary(errorRecord.safeSummary))
        {
            throw JobContractError.invalidState("The persisted error record is not safely bounded.")
        }
        if state == .succeeded {
            guard progress.completedUnitCount == progress.totalUnitCount else {
                throw JobContractError.invalidState("A succeeded job must report complete progress.")
            }
        } else if !outputRevisionIDs.isEmpty {
            throw JobContractError.invalidState(
                "Only a succeeded job may publish output revision references."
            )
        }
    }

    private func replacing(
        startedAt: UTCInstant?? = nil,
        finishedAt: UTCInstant?? = nil,
        state: JobState? = nil,
        progress: JobProgress? = nil,
        outputRevisionIDs: [SemanticRevisionReference]? = nil,
        providerUsage: [ProviderUsageMetadata]? = nil,
        retryCount: UInt32? = nil,
        checkpoint: JobCheckpoint?? = nil,
        errorRecord: JobFailureRecord?? = nil
    ) throws -> JobRecord {
        let (nextVersion, overflow) = recordVersion.addingReportingOverflow(1)
        guard !overflow else {
            throw JobContractError.invalidState("The job record version overflowed.")
        }
        let replacement = JobRecord(
            jobID: jobID,
            jobType: jobType,
            meetingID: meetingID,
            origin: origin,
            requestedBy: requestedBy,
            inputPayload: inputPayload,
            createdAt: createdAt,
            startedAt: startedAt ?? self.startedAt,
            finishedAt: finishedAt ?? self.finishedAt,
            state: state ?? self.state,
            progress: progress ?? self.progress,
            inputRevisionIDs: inputRevisionIDs,
            outputRevisionIDs: (outputRevisionIDs ?? self.outputRevisionIDs).sorted(),
            dependencyJobIDs: dependencyJobIDs,
            providerUsage: providerUsage ?? self.providerUsage,
            privacyRoute: privacyRoute,
            dataClassification: dataClassification,
            retryCount: retryCount ?? self.retryCount,
            maximumRetryCount: maximumRetryCount,
            checkpoint: checkpoint ?? self.checkpoint,
            idempotencyKey: idempotencyKey,
            temporaryDirectory: temporaryDirectory,
            resumeCapability: resumeCapability,
            errorRecord: errorRecord ?? self.errorRecord,
            recordVersion: nextVersion
        )
        try replacement.validate()
        return replacement
    }

    private init(
        jobID: JobID,
        jobType: JobType,
        meetingID: MeetingID?,
        origin: JobOrigin,
        requestedBy: JobRequester,
        inputPayload: JobInputPayload?,
        createdAt: UTCInstant,
        startedAt: UTCInstant?,
        finishedAt: UTCInstant?,
        state: JobState,
        progress: JobProgress,
        inputRevisionIDs: [SemanticRevisionReference],
        outputRevisionIDs: [SemanticRevisionReference],
        dependencyJobIDs: [JobID],
        providerUsage: [ProviderUsageMetadata],
        privacyRoute: PrivacyRoute,
        dataClassification: DataClassification,
        retryCount: UInt32,
        maximumRetryCount: UInt32,
        checkpoint: JobCheckpoint?,
        idempotencyKey: JobIdempotencyKey,
        temporaryDirectory: TaskDirectoryLease,
        resumeCapability: JobResumeCapability,
        errorRecord: JobFailureRecord?,
        recordVersion: UInt64
    ) {
        self.jobID = jobID
        self.jobType = jobType
        self.meetingID = meetingID
        self.origin = origin
        self.requestedBy = requestedBy
        self.inputPayload = inputPayload
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.state = state
        self.progress = progress
        self.inputRevisionIDs = inputRevisionIDs.sorted()
        self.outputRevisionIDs = outputRevisionIDs.sorted()
        self.dependencyJobIDs = dependencyJobIDs.sorted()
        self.providerUsage = providerUsage
        self.privacyRoute = privacyRoute
        self.dataClassification = dataClassification
        self.retryCount = retryCount
        self.maximumRetryCount = maximumRetryCount
        self.checkpoint = checkpoint
        self.idempotencyKey = idempotencyKey
        self.temporaryDirectory = temporaryDirectory
        self.resumeCapability = resumeCapability
        self.errorRecord = errorRecord
        self.recordVersion = recordVersion
    }
}

public enum JobStateMachine {
    public static func allows(from: JobState, to: JobState) -> Bool {
        switch (from, to) {
        case (.queued, .running),
             (.queued, .cancelled),
             (.running, .pauseRequested),
             (.running, .cancellationRequested),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .interrupted),
             (.pauseRequested, .paused),
             (.pauseRequested, .running),
             (.pauseRequested, .cancellationRequested),
             (.pauseRequested, .succeeded),
             (.pauseRequested, .failed),
             (.pauseRequested, .interrupted),
             (.paused, .running),
             (.paused, .cancellationRequested),
             (.paused, .interrupted),
             (.cancellationRequested, .succeeded),
             (.cancellationRequested, .cancelled),
             (.cancellationRequested, .failed),
             (.cancellationRequested, .interrupted),
             (.failed, .cancelled),
             (.interrupted, .cancelled):
            true
        default:
            false
        }
    }
}

private enum JobContractValidation {
    static func isOpaqueIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed
            && !value.isEmpty
            && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.contains("/")
            && !value.contains("\\")
    }

    static func isSafeSummary(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed
            && !value.isEmpty
            && value.utf8.count <= 256
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
