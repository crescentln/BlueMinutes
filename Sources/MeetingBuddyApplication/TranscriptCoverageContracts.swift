import CryptoKit
import Foundation
import MeetingBuddyDomain

public enum TranscriptCoverageError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case publicationConflict
    case reviewUnavailable
}

public enum TranscriptManifestStatus: String, Codable, Hashable, Sendable {
    case incomplete
    case published
}

public enum TranscriptChunkDisposition: String, Codable, Hashable, Sendable {
    case transcribed
    case noSpeech = "no_speech"
    case failed
    case missing
}

/// Application-owned proof for a no-speech disposition. Provider output alone
/// is never sufficient because it could silently omit spoken source material.
public enum TranscriptNoSpeechVerificationMethod: String, Codable, Hashable, Sendable {
    case exactDigitalSilence = "exact_digital_silence"
}

public struct TranscriptNoSpeechConfirmation: Codable, Hashable, Sendable {
    public static let verifierVersion: UInt32 = 1

    public let method: TranscriptNoSpeechVerificationMethod
    public let verifiedCoreRange: MediaFrameRange
    public let verifierVersion: UInt32

    public init(
        method: TranscriptNoSpeechVerificationMethod = .exactDigitalSilence,
        verifiedCoreRange: MediaFrameRange,
        verifierVersion: UInt32 = Self.verifierVersion
    ) throws {
        guard verifierVersion == Self.verifierVersion else {
            throw TranscriptCoverageError.invalidManifest(
                "The no-speech verifier version is unsupported."
            )
        }
        self.method = method
        self.verifiedCoreRange = verifiedCoreRange
        self.verifierVersion = verifierVersion
    }
}

public struct TranscriptChunkCoverage: Codable, Hashable, Sendable, Comparable {
    public let index: UInt32
    public let coreRange: MediaFrameRange
    public let physicalRange: MediaFrameRange
    public let disposition: TranscriptChunkDisposition
    public let attemptCount: UInt32
    public let provider: ProviderMetadata?
    public let machineSegmentRevision: SemanticRevisionReference?
    public let reviewedSegmentRevision: SemanticRevisionReference?
    public let translationRevision: SemanticRevisionReference?
    public let safeFailureCode: String?
    public let noSpeechConfirmation: TranscriptNoSpeechConfirmation?

    public init(
        index: UInt32,
        coreRange: MediaFrameRange,
        physicalRange: MediaFrameRange,
        disposition: TranscriptChunkDisposition,
        attemptCount: UInt32,
        provider: ProviderMetadata? = nil,
        machineSegmentRevision: SemanticRevisionReference? = nil,
        reviewedSegmentRevision: SemanticRevisionReference? = nil,
        translationRevision: SemanticRevisionReference? = nil,
        safeFailureCode: String? = nil,
        noSpeechConfirmation: TranscriptNoSpeechConfirmation? = nil
    ) throws {
        guard physicalRange.startFrame <= coreRange.startFrame,
              physicalRange.endFrame >= coreRange.endFrame,
              attemptCount <= 100,
              machineSegmentRevision.map({ $0.objectType == .transcriptSegment }) ?? true,
              reviewedSegmentRevision.map({ $0.objectType == .transcriptSegment }) ?? true,
              translationRevision.map({ $0.objectType == .translationSegment }) ?? true,
              safeFailureCode.map({ !$0.isEmpty && $0.utf8.count <= 96 }) ?? true,
              noSpeechConfirmation.map({ $0.verifiedCoreRange == coreRange }) ?? true
        else {
            throw TranscriptCoverageError.invalidManifest("A chunk coverage record is malformed.")
        }
        switch disposition {
        case .transcribed:
            guard reviewedSegmentRevision != nil,
                  safeFailureCode == nil,
                  noSpeechConfirmation == nil,
                  attemptCount > 0
            else { throw TranscriptCoverageError.invalidManifest("A transcribed chunk needs a reviewed segment and no failure code.") }
        case .noSpeech:
            guard machineSegmentRevision == nil,
                  reviewedSegmentRevision == nil,
                  translationRevision == nil,
                  safeFailureCode == nil,
                  attemptCount > 0
            else { throw TranscriptCoverageError.invalidManifest("No-speech must be explicit and contain no semantic segment.") }
        case .failed:
            guard safeFailureCode != nil,
                  reviewedSegmentRevision == nil,
                  noSpeechConfirmation == nil
            else {
                throw TranscriptCoverageError.invalidManifest("A failed chunk needs a safe code and no reviewed segment.")
            }
        case .missing:
            guard attemptCount == 0,
                  provider == nil,
                  machineSegmentRevision == nil,
                  reviewedSegmentRevision == nil,
                  translationRevision == nil,
                  noSpeechConfirmation == nil
            else { throw TranscriptCoverageError.invalidManifest("A missing chunk has no provider result.") }
        }
        self.index = index
        self.coreRange = coreRange
        self.physicalRange = physicalRange
        self.disposition = disposition
        self.attemptCount = attemptCount
        self.provider = provider
        self.machineSegmentRevision = machineSegmentRevision
        self.reviewedSegmentRevision = reviewedSegmentRevision
        self.translationRevision = translationRevision
        self.safeFailureCode = safeFailureCode
        self.noSpeechConfirmation = noSpeechConfirmation
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }
}

/// Immutable proof that every canonical source frame has one deterministic core owner.
public struct TranscriptCoverageManifest: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt32 = 1
    public static let chunkPlanIdentifier = "meetingbuddy.canonical-chunks.v1"

    public let manifestID: TranscriptCoverageManifestID
    public let transcriptSetID: TranscriptSetID
    public let supersedesManifestID: TranscriptCoverageManifestID?
    public let meetingID: MeetingID
    public let canonicalSourceRevision: SemanticRevisionReference
    public let canonicalFrameCount: UInt64
    public let chunkPlanIdentifier: String
    public let chunkPlanVersion: UInt32
    public let transcriptionRoute: ModelRouteDecision
    public let translationRoute: ModelRouteDecision?
    public let status: TranscriptManifestStatus
    public let chunks: [TranscriptChunkCoverage]
    public let createdAt: UTCInstant
    public let contentHash: ContentDigest

    public init(
        manifestID: TranscriptCoverageManifestID = TranscriptCoverageManifestID(UUID()),
        transcriptSetID: TranscriptSetID,
        supersedesManifestID: TranscriptCoverageManifestID? = nil,
        meetingID: MeetingID,
        canonicalSourceRevision: SemanticRevisionReference,
        canonicalFrameCount: UInt64,
        transcriptionRoute: ModelRouteDecision,
        translationRoute: ModelRouteDecision? = nil,
        status: TranscriptManifestStatus,
        chunks: [TranscriptChunkCoverage],
        createdAt: UTCInstant,
        contentHash: ContentDigest? = nil
    ) throws {
        self.manifestID = manifestID
        self.transcriptSetID = transcriptSetID
        self.supersedesManifestID = supersedesManifestID
        self.meetingID = meetingID
        self.canonicalSourceRevision = canonicalSourceRevision
        self.canonicalFrameCount = canonicalFrameCount
        self.chunkPlanIdentifier = Self.chunkPlanIdentifier
        self.chunkPlanVersion = Self.schemaVersion
        self.transcriptionRoute = transcriptionRoute
        self.translationRoute = translationRoute
        self.status = status
        self.chunks = chunks.sorted()
        self.createdAt = createdAt
        self.contentHash = try contentHash ?? Self.hash(
            Projection(
                manifestID: manifestID,
                transcriptSetID: transcriptSetID,
                supersedesManifestID: supersedesManifestID,
                meetingID: meetingID,
                canonicalSourceRevision: canonicalSourceRevision,
                canonicalFrameCount: canonicalFrameCount,
                chunkPlanIdentifier: Self.chunkPlanIdentifier,
                chunkPlanVersion: Self.schemaVersion,
                transcriptionRoute: transcriptionRoute,
                translationRoute: translationRoute,
                status: status,
                chunks: chunks.sorted(),
                createdAt: createdAt
            )
        )
        try validate()
    }

    public func validate() throws {
        let transcriptionRouteIsValid: Bool = {
            guard transcriptionRoute.request.capability == .transcription,
                  transcriptionRoute.request.dataCategories == [.canonicalAudio]
            else {
                return false
            }
            guard transcriptionRoute.route == .approvedExternal else {
                return transcriptionRoute.route.privacyRoute == .localOnly
            }
            guard let providerIdentifier = transcriptionRoute.providerIdentifier,
                  transcriptionRoute.request.dataClassification.restrictionRank
                    < DataClassification.sensitive.restrictionRank,
                  transcriptionRoute.request.retentionPolicy
                    == .approvedProviderRetention,
                  let authorization = try? ModelPolicyRouter().authorizeExternal(
                      transcriptionRoute.request,
                      expectedProviderIdentifier: providerIdentifier
                  )
            else {
                return false
            }
            return authorization.decision == transcriptionRoute
        }()
        guard canonicalSourceRevision.objectType == .sourceAsset,
              canonicalFrameCount > 0,
              chunkPlanIdentifier == Self.chunkPlanIdentifier,
              chunkPlanVersion == Self.schemaVersion,
              transcriptionRouteIsValid,
              translationRoute.map({
                  $0.route.privacyRoute == .localOnly
                      && $0.request.capability == .translation
                      && $0.request.dataCategories == [.transcriptText]
              }) ?? true,
              contentHash == (try Self.hash(projection))
        else { throw TranscriptCoverageError.invalidManifest("The manifest identity, route, or content hash is invalid.") }

        let expected = try CanonicalChunkPlanner.plan(totalFrameCount: canonicalFrameCount)
        guard chunks.count == expected.count,
              Set(chunks.map(\.index)).count == chunks.count
        else { throw TranscriptCoverageError.invalidManifest("Coverage does not contain each deterministic chunk exactly once.") }
        for (stored, planned) in zip(chunks, expected) {
            guard stored.index == planned.index,
                  stored.coreRange == planned.coreRange,
                  stored.physicalRange == planned.physicalRange
            else { throw TranscriptCoverageError.invalidManifest("Coverage ranges do not match the canonical chunk plan.") }
        }
        if let expectedProvider =
            transcriptionRoute
            .providerIdentifier
        {
            guard chunks.allSatisfy({
                $0.disposition == .missing
                    || $0.provider?
                        .providerIdentifier
                        == expectedProvider
            }),
                chunks.allSatisfy({
                    $0.disposition
                        != .transcribed
                        || $0
                        .machineSegmentRevision
                        != nil
                })
            else {
                throw TranscriptCoverageError
                    .invalidManifest(
                        "Attempted provider coverage must retain the authorized provider and exact machine segment."
                    )
            }
        } else {
            guard chunks.allSatisfy({
                $0.provider == nil
                    && $0
                    .machineSegmentRevision
                    == nil
            }) else {
                throw TranscriptCoverageError
                    .invalidManifest(
                        "Manual coverage cannot claim machine-provider provenance."
                    )
            }
        }
        let machine = chunks.compactMap(\.machineSegmentRevision)
        guard Set(machine).count == machine.count
        else { throw TranscriptCoverageError.invalidManifest("A semantic revision cannot own more than one core chunk.") }
        if status == .published {
            guard chunks.allSatisfy({ $0.disposition == .transcribed || $0.disposition == .noSpeech }) else {
                throw TranscriptCoverageError.invalidManifest("Published coverage fails closed unless every core is transcribed or explicitly no-speech.")
            }
        }
    }

    public var transcriptRevisionReferences: [SemanticRevisionReference] {
        Array(Set(chunks.compactMap(\.reviewedSegmentRevision))).sorted()
    }

    public var translationRevisionReferences: [SemanticRevisionReference] {
        Array(Set(chunks.compactMap(\.translationRevision))).sorted()
    }

    private var projection: Projection {
        Projection(
            manifestID: manifestID,
            transcriptSetID: transcriptSetID,
            supersedesManifestID: supersedesManifestID,
            meetingID: meetingID,
            canonicalSourceRevision: canonicalSourceRevision,
            canonicalFrameCount: canonicalFrameCount,
            chunkPlanIdentifier: chunkPlanIdentifier,
            chunkPlanVersion: chunkPlanVersion,
            transcriptionRoute: transcriptionRoute,
            translationRoute: translationRoute,
            status: status,
            chunks: chunks,
            createdAt: createdAt
        )
    }

    private static func hash<T: Encodable>(_ value: T) throws -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(value))
        return try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private struct Projection: Codable {
        let manifestID: TranscriptCoverageManifestID
        let transcriptSetID: TranscriptSetID
        let supersedesManifestID: TranscriptCoverageManifestID?
        let meetingID: MeetingID
        let canonicalSourceRevision: SemanticRevisionReference
        let canonicalFrameCount: UInt64
        let chunkPlanIdentifier: String
        let chunkPlanVersion: UInt32
        let transcriptionRoute: ModelRouteDecision
        let translationRoute: ModelRouteDecision?
        let status: TranscriptManifestStatus
        let chunks: [TranscriptChunkCoverage]
        let createdAt: UTCInstant
    }
}

public struct TranscriptPublication: Sendable {
    public let manifest: TranscriptCoverageManifest
    public let transcriptSegments: [TranscriptSegmentV1]
    public let translations: [TranslationSegmentV1]

    public init(
        manifest: TranscriptCoverageManifest,
        transcriptSegments: [TranscriptSegmentV1],
        translations: [TranslationSegmentV1]
    ) throws {
        try manifest.validate()
        let transcriptPairs =
            try transcriptSegments.map {
                (
                    try SemanticRevisionReference(
                        logicalID: $0.segmentID,
                        revisionID:
                            $0.revision
                            .revisionID
                    ),
                    $0
                )
            }
        let transcriptReferences =
            transcriptPairs.map(\.0).sorted()
        let translationPairs =
            try translations.map {
                (
                    try SemanticRevisionReference(
                        logicalID:
                            $0.translationID,
                        revisionID:
                            $0.revision
                            .revisionID
                    ),
                    $0
                )
            }
        let translationReferences =
            translationPairs.map(\.0).sorted()
        let transcriptByReference =
            Dictionary(
                transcriptPairs,
                uniquingKeysWith: {
                    current, _ in current
                }
            )
        let translationByReference =
            Dictionary(
                translationPairs,
                uniquingKeysWith: {
                    current, _ in current
                }
            )
        let providerProvenanceMatches =
            manifest.chunks.allSatisfy {
                chunk in
                guard chunk.disposition
                        == .transcribed,
                      let reviewed =
                        chunk
                        .reviewedSegmentRevision,
                      let transcript =
                        transcriptByReference[
                            reviewed
                        ]
                else {
                    return chunk.disposition
                        == .noSpeech
                }
                if manifest.transcriptionRoute
                    .providerIdentifier
                    != nil
                {
                    guard let machine =
                            chunk
                            .machineSegmentRevision,
                          machine == reviewed,
                          transcript
                            .transcriptionProvider
                            == chunk.provider,
                          transcript.revision
                            .generationMetadata?
                            .privacyRoute
                            == manifest
                            .transcriptionRoute
                            .route
                            .privacyRoute
                    else { return false }
                } else if transcript.revision
                    .generationMetadata != nil
                {
                    return false
                }
                guard let translationReference =
                        chunk.translationRevision
                else { return true }
                guard let translation =
                        translationByReference[
                            translationReference
                        ]
                else { return false }
                if let expectedProvider =
                    manifest.translationRoute?
                    .providerIdentifier
                {
                    return translation.provider?
                        .providerIdentifier
                        == expectedProvider
                        && translation.revision
                            .generationMetadata?
                            .privacyRoute
                            == manifest
                            .translationRoute?
                            .route
                            .privacyRoute
                }
                return translation.revision
                    .generationMetadata == nil
            }
        guard manifest.status == .published,
              manifest.chunks.allSatisfy({ chunk in
                  chunk.disposition != .noSpeech || chunk.noSpeechConfirmation != nil
              }),
              transcriptReferences == manifest.transcriptRevisionReferences.sorted(),
              translationReferences == manifest.translationRevisionReferences.sorted(),
              providerProvenanceMatches,
              transcriptSegments.allSatisfy({
                  $0.meetingID == manifest.meetingID
                      && $0.sourceAssetRevision == manifest.canonicalSourceRevision
                      && $0.revision.lifecycleStatus == .published
                      && $0.revision.validationState == .valid
              }),
              translations.allSatisfy({
                  $0.meetingID == manifest.meetingID
                      && $0.revision.lifecycleStatus == .published
                      && $0.revision.validationState == .valid
              })
        else { throw TranscriptCoverageError.invalidManifest("Publication objects do not exactly match the coverage manifest.") }
        self.manifest = manifest
        self.transcriptSegments = transcriptSegments
        self.translations = translations
    }
}

public struct TranscriptReviewBundle: Sendable, Hashable {
    public let manifest: TranscriptCoverageManifest
    public let transcriptSegments: [TranscriptSegmentV1]
    public let translations: [TranslationSegmentV1]
    public let speakerAssignments: [SpeakerAssignmentV1]
    public let evidenceRefs: [EvidenceRefV1]

    public init(
        manifest: TranscriptCoverageManifest,
        transcriptSegments: [TranscriptSegmentV1],
        translations: [TranslationSegmentV1],
        speakerAssignments: [SpeakerAssignmentV1] = [],
        evidenceRefs: [EvidenceRefV1] = []
    ) {
        self.manifest = manifest
        self.transcriptSegments = transcriptSegments
        self.translations = translations
        self.speakerAssignments = speakerAssignments
        self.evidenceRefs = evidenceRefs.sorted { lhs, rhs in
            (
                lhs.revision.createdAt,
                lhs.revision.revisionID.canonicalString
            ) < (
                rhs.revision.createdAt,
                rhs.revision.revisionID.canonicalString
            )
        }
    }
}

public protocol TranscriptReviewRepository: Sendable {
    func sourceAsset(revisionID: RevisionID) throws -> SourceAssetV1?
    func recordIncompleteCoverage(_ manifest: TranscriptCoverageManifest) throws
    func publishTranscript(_ publication: TranscriptPublication) throws
    func publishTranscript(
        _ publication: TranscriptPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws
    func activeTranscriptReview(meetingID: MeetingID) throws -> TranscriptReviewBundle?
    func saveTranscriptCorrection(
        _ correction: TranscriptSegmentV1,
        replacing expectedRevisionID: RevisionID,
        updatedManifest: TranscriptCoverageManifest,
        changedAt: UTCInstant
    ) throws
    func saveTranslationCorrection(
        _ correction: TranslationSegmentV1,
        replacing expectedRevisionID: RevisionID,
        updatedManifest: TranscriptCoverageManifest,
        changedAt: UTCInstant
    ) throws
    func publishSpeakerConfirmation(
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        evidence: EvidenceRefV1,
        assignment: SpeakerAssignmentV1,
        changedAt: UTCInstant
    ) throws
}

public extension TranscriptReviewRepository {
    func publishTranscript(
        _ publication: TranscriptPublication,
        validatingInputRevisions _: [SemanticRevisionReference]
    ) throws {
        try publishTranscript(publication)
    }
}
