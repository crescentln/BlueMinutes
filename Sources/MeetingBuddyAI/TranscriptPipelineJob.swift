import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum TranscriptJobTypes {
    public static let pipeline = try! JobType("transcript-pipeline-v1")
}

public struct TranscriptChunkIdentity: Codable, Hashable, Sendable, Comparable {
    public let index: UInt32
    public let transcriptID: TranscriptSegmentID
    public let transcriptRevisionID: RevisionID
    public let translationID: TranslationSegmentID?
    public let translationRevisionID: RevisionID?

    public init(
        index: UInt32,
        transcriptID: TranscriptSegmentID = TranscriptSegmentID(UUID()),
        transcriptRevisionID: RevisionID = RevisionID(UUID()),
        translationID: TranslationSegmentID?,
        translationRevisionID: RevisionID?
    ) throws {
        guard (translationID == nil) == (translationRevisionID == nil) else {
            throw AIProviderContractError.invalidRequest("Translation identifiers must be allocated as a pair.")
        }
        self.index = index
        self.transcriptID = transcriptID
        self.transcriptRevisionID = transcriptRevisionID
        self.translationID = translationID
        self.translationRevisionID = translationRevisionID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }
}

public struct TranscriptPipelineJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.transcript-pipeline"
    public static let inputFormatVersion: UInt32 = 1

    public let meetingID: MeetingID
    public let canonicalSourceRevision: SemanticRevisionReference
    public let canonicalFrameCount: UInt64
    public let speechSourceKind: SpeechSourceKind
    public let sourceLanguage: LanguageTag
    public let targetLanguage: LanguageTag?
    public let dataClassification: DataClassification
    public let createdAt: UTCInstant
    public let transcriptSetID: TranscriptSetID
    public let manifestID: TranscriptCoverageManifestID
    public let transcriptionRoute: ModelRouteDecision
    public let translationRoute: ModelRouteDecision?
    public let chunkIdentities: [TranscriptChunkIdentity]

    public init(
        meetingID: MeetingID,
        canonicalSourceRevision: SemanticRevisionReference,
        canonicalFrameCount: UInt64,
        speechSourceKind: SpeechSourceKind,
        sourceLanguage: LanguageTag,
        targetLanguage: LanguageTag?,
        dataClassification: DataClassification,
        createdAt: UTCInstant,
        transcriptSetID: TranscriptSetID = TranscriptSetID(UUID()),
        manifestID: TranscriptCoverageManifestID = TranscriptCoverageManifestID(UUID()),
        transcriptionRoute: ModelRouteDecision,
        translationRoute: ModelRouteDecision?
    ) throws {
        let chunkPlan = try CanonicalChunkPlanner.plan(totalFrameCount: canonicalFrameCount)
        let identities = try chunkPlan.map { chunk in
            try TranscriptChunkIdentity(
                index: chunk.index,
                translationID: targetLanguage == nil ? nil : TranslationSegmentID(UUID()),
                translationRevisionID: targetLanguage == nil ? nil : RevisionID(UUID())
            )
        }
        guard canonicalSourceRevision.objectType == .sourceAsset,
              canonicalFrameCount > 0,
              speechSourceKind.isKnown,
              dataClassification.isKnown,
              (transcriptionRoute.route == .appleOnDevice
                || transcriptionRoute.route == .deterministicTest),
              transcriptionRoute.route.privacyRoute == .localOnly,
              (targetLanguage == nil) == (translationRoute == nil),
              targetLanguage != sourceLanguage,
              translationRoute.map({
                  $0.route == .appleOnDevice || $0.route == .deterministicTest
              }) ?? true
        else { throw AIProviderContractError.invalidRequest("The transcript pipeline plan has an unauthorized route or invalid source.") }
        self.meetingID = meetingID
        self.canonicalSourceRevision = canonicalSourceRevision
        self.canonicalFrameCount = canonicalFrameCount
        self.speechSourceKind = speechSourceKind
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.dataClassification = dataClassification
        self.createdAt = createdAt
        self.transcriptSetID = transcriptSetID
        self.manifestID = manifestID
        self.transcriptionRoute = transcriptionRoute
        self.translationRoute = translationRoute
        self.chunkIdentities = identities
    }

    private init(validating decoded: Self) throws {
        let expectedPlan = try CanonicalChunkPlanner.plan(totalFrameCount: decoded.canonicalFrameCount)
        let identities = decoded.chunkIdentities.sorted()
        guard decoded.canonicalSourceRevision.objectType == .sourceAsset,
              decoded.canonicalFrameCount > 0,
              decoded.speechSourceKind.isKnown,
              decoded.dataClassification.isKnown,
              (decoded.transcriptionRoute.route == .appleOnDevice
                || decoded.transcriptionRoute.route == .deterministicTest),
              decoded.transcriptionRoute.route.privacyRoute == .localOnly,
              (decoded.targetLanguage == nil) == (decoded.translationRoute == nil),
              decoded.targetLanguage != decoded.sourceLanguage,
              decoded.translationRoute.map({
                  $0.route == .appleOnDevice || $0.route == .deterministicTest
              }) ?? true,
              identities.map(\.index) == expectedPlan.map(\.index),
              Set(identities.map(\.transcriptRevisionID)).count == identities.count,
              identities.allSatisfy({
                  (decoded.targetLanguage == nil)
                      ? ($0.translationID == nil && $0.translationRevisionID == nil)
                      : ($0.translationID != nil && $0.translationRevisionID != nil)
              })
        else { throw AIProviderContractError.invalidRequest("The persisted transcript plan failed validation.") }
        self = decoded
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
        else { throw AIProviderContractError.invalidRequest("The transcript job payload is missing or unsupported.") }
        do {
            return try Self(validating: JSONDecoder().decode(Self.self, from: input.payload))
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError.invalidRequest("The transcript job payload could not be decoded.")
        }
    }
}

public struct TranscriptPipelineJobFactory: Sendable {
    public init() {}

    public func request(
        plan: TranscriptPipelineJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester,
        maximumRetryCount: UInt32 = 2
    ) throws -> JobRequest {
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }
            .joined()
        let maximumChunkBytes = (CanonicalChunkPlanner.coreDurationFrames
            + (CanonicalChunkPlanner.contextFrames * 2)) * 2
        return try JobRequest(
            jobID: jobID,
            jobType: TranscriptJobTypes.pipeline,
            meetingID: plan.meetingID,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            inputRevisionIDs: [plan.canonicalSourceRevision],
            privacyRoute: .localOnly,
            dataClassification: plan.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .checkpointed,
            maximumRetryCount: maximumRetryCount,
            totalUnitCount: UInt64(plan.chunkIdentities.count),
            diskBudgetBytes: max(maximumChunkBytes * 2, 32 * 1_024 * 1_024)
        )
    }
}

struct TranscriptPipelineChunkOutput: Codable, Hashable, Sendable {
    let index: UInt32
    let disposition: TranscriptChunkDisposition
    let text: String?
    let confidence: ConfidenceScore?
    let translation: TranslationResponse?
    let attemptCount: UInt32
    let noSpeechConfirmation: TranscriptNoSpeechConfirmation?

    init(
        index: UInt32,
        disposition: TranscriptChunkDisposition,
        text: String?,
        confidence: ConfidenceScore?,
        translation: TranslationResponse?,
        attemptCount: UInt32,
        noSpeechConfirmation: TranscriptNoSpeechConfirmation? = nil
    ) throws {
        guard attemptCount > 0,
              attemptCount <= 100,
              (disposition == .transcribed)
                ? (text?.isEmpty == false
                    && confidence != nil
                    && noSpeechConfirmation == nil)
                : (disposition == .noSpeech
                    && text == nil
                    && confidence == nil
                    && translation == nil
                    && noSpeechConfirmation != nil)
        else { throw AIProviderContractError.invalidResponse("A validated pipeline chunk is internally inconsistent.") }
        self.index = index
        self.disposition = disposition
        self.text = text
        self.confidence = confidence
        self.translation = translation
        self.attemptCount = attemptCount
        self.noSpeechConfirmation = noSpeechConfirmation
    }
}

struct TranscriptPipelineCheckpoint: Codable, Hashable, Sendable {
    static let formatVersion: UInt32 = 1
    let artifacts: [UInt32: TaskTemporaryFileDescriptor]

    func jobCheckpoint() throws -> JobCheckpoint {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try JobCheckpoint(formatVersion: Self.formatVersion, payload: encoder.encode(self))
    }

    static func decode(_ checkpoint: JobCheckpoint?) throws -> Self {
        guard let checkpoint else { return Self(artifacts: [:]) }
        guard checkpoint.formatVersion == formatVersion else {
            throw AIProviderContractError.invalidRequest("The transcript checkpoint version is unsupported.")
        }
        return try PropertyListDecoder().decode(Self.self, from: checkpoint.payload)
    }
}
