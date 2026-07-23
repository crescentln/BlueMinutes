import CryptoKit
import Foundation
import MeetingBuddyDomain

public enum TranscriptSourceAvailabilityStatus: String, Codable, Hashable, Sendable {
    case unavailable
    case available
    case temporarilyUnavailable = "temporarily_unavailable"
}

/// Provider-owned external/imported source identity. This is not a
/// TranscriptSegment revision and contains no ASR decision.
public struct TranscriptSourceReference:
    Codable,
    Hashable,
    Sendable,
    Comparable,
    DomainValidatable
{
    public let providerIdentifier: String
    public let sourceIdentifier: String
    public let sourceVersionIdentifier: String?
    public let sourceKind: SharedSourceKind
    public let externalReference: HTTPSURL?

    public init(
        providerIdentifier: String,
        sourceIdentifier: String,
        sourceVersionIdentifier: String? = nil,
        sourceKind: SharedSourceKind,
        externalReference: HTTPSURL? = nil
    ) throws {
        self.providerIdentifier = providerIdentifier
        self.sourceIdentifier = sourceIdentifier
        self.sourceVersionIdentifier = sourceVersionIdentifier
        self.sourceKind = sourceKind
        self.externalReference = externalReference
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (
            lhs.providerIdentifier,
            lhs.sourceIdentifier,
            lhs.sourceVersionIdentifier ?? "",
            lhs.sourceKind.encodedValue
        ) < (
            rhs.providerIdentifier,
            rhs.sourceIdentifier,
            rhs.sourceVersionIdentifier ?? "",
            rhs.sourceKind.encodedValue
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = transcriptOpaqueIdentifierIssues(
            providerIdentifier,
            path: "provider_identifier",
            maximumUTF8Bytes: 128
        )
        issues += transcriptOpaqueIdentifierIssues(
            sourceIdentifier,
            path: "source_identifier",
            maximumUTF8Bytes: 512
        )
        if let sourceVersionIdentifier {
            issues += transcriptOpaqueIdentifierIssues(
                sourceVersionIdentifier,
                path: "source_version_identifier",
                maximumUTF8Bytes: 256
            )
        }
        if !sourceKind.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "source_kind",
                    "The transcript-source kind is not supported."
                )
            )
        }
        if let externalReference {
            issues += externalReference.validationIssues()
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providerIdentifier: container.decode(String.self, forKey: .providerIdentifier),
            sourceIdentifier: container.decode(String.self, forKey: .sourceIdentifier),
            sourceVersionIdentifier: container.decodeIfPresent(
                String.self,
                forKey: .sourceVersionIdentifier
            ),
            sourceKind: container.decode(SharedSourceKind.self, forKey: .sourceKind),
            externalReference: container.decodeIfPresent(HTTPSURL.self, forKey: .externalReference)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case providerIdentifier = "provider_identifier"
        case sourceIdentifier = "source_identifier"
        case sourceVersionIdentifier = "source_version_identifier"
        case sourceKind = "source_kind"
        case externalReference = "external_reference"
    }
}

/// Exact Meeting and policy-neutral input supplied to source discovery.
public struct TranscriptSourceContext: Codable, Hashable, Sendable, DomainValidatable {
    public let meetingRevision: SemanticRevisionReference
    public let requestedLanguage: LanguageTag?
    public let canonicalAudioSourceRevision: SemanticRevisionReference?
    public let existingSourceRevisions: [SemanticRevisionReference]
    public let dataClassification: DataClassification

    public init(
        meetingRevision: SemanticRevisionReference,
        requestedLanguage: LanguageTag? = nil,
        canonicalAudioSourceRevision: SemanticRevisionReference? = nil,
        existingSourceRevisions: [SemanticRevisionReference] = [],
        dataClassification: DataClassification
    ) throws {
        self.meetingRevision = meetingRevision
        self.requestedLanguage = requestedLanguage
        self.canonicalAudioSourceRevision = canonicalAudioSourceRevision
        self.existingSourceRevisions = existingSourceRevisions.sorted()
        self.dataClassification = dataClassification
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = meetingRevision.validationIssues()
        if meetingRevision.objectType != .meetingProfile {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "meeting_revision.object_type",
                    "Transcript source discovery requires an exact MeetingProfile revision."
                )
            )
        }
        if let requestedLanguage {
            issues += requestedLanguage.validationIssues()
        }
        if let canonicalAudioSourceRevision {
            issues += canonicalAudioSourceRevision.validationIssues()
            if canonicalAudioSourceRevision.objectType != .sourceAsset {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "canonical_audio_source_revision.object_type",
                        "Canonical audio must reference an exact SourceAsset revision."
                    )
                )
            }
        }
        if Set(existingSourceRevisions).count != existingSourceRevisions.count {
            issues.append(
                transcriptIssue(
                    .duplicateValue,
                    "existing_source_revisions",
                    "Existing transcript-source revisions must be unique."
                )
            )
        }
        for reference in existingSourceRevisions {
            issues += reference.validationIssues()
            if ![
                SemanticObjectType.sourceAsset,
                .transcriptSegment,
                .translationSegment
            ].contains(reference.objectType) {
                issues.append(
                    transcriptIssue(
                        .unsupportedValue,
                        "existing_source_revisions.object_type",
                        "Only exact source or transcript revisions belong in source-discovery context."
                    )
                )
            }
        }
        if !dataClassification.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "data_classification",
                    "Transcript source discovery requires a known classification."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            meetingRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .meetingRevision
            ),
            requestedLanguage: container.decodeIfPresent(
                LanguageTag.self,
                forKey: .requestedLanguage
            ),
            canonicalAudioSourceRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .canonicalAudioSourceRevision
            ),
            existingSourceRevisions: container.decodeIfPresent(
                [SemanticRevisionReference].self,
                forKey: .existingSourceRevisions
            ) ?? [],
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case meetingRevision = "meeting_revision"
        case requestedLanguage = "requested_language"
        case canonicalAudioSourceRevision = "canonical_audio_source_revision"
        case existingSourceRevisions = "existing_source_revisions"
        case dataClassification = "data_classification"
    }
}

public struct TranscriptSourceAvailability:
    Codable,
    Hashable,
    Sendable,
    Comparable,
    DomainValidatable
{
    public let reference: TranscriptSourceReference
    public let status: TranscriptSourceAvailabilityStatus
    public let authority: SourceAuthority
    public let completeness: SourceCompleteness
    public let checkedAt: UTCInstant
    public let safeReasonCode: String?

    public init(
        reference: TranscriptSourceReference,
        status: TranscriptSourceAvailabilityStatus,
        authority: SourceAuthority,
        completeness: SourceCompleteness,
        checkedAt: UTCInstant,
        safeReasonCode: String? = nil
    ) throws {
        self.reference = reference
        self.status = status
        self.authority = authority
        self.completeness = completeness
        self.checkedAt = checkedAt
        self.safeReasonCode = safeReasonCode
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.reference < rhs.reference
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = reference.validationIssues()
        if !authority.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "authority",
                    "Unknown future authority cannot participate in source resolution."
                )
            )
        }
        if !completeness.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "completeness",
                    "Unknown future completeness cannot participate in source resolution."
                )
            )
        }
        issues += checkedAt.validationIssues()
        if status == .available, safeReasonCode != nil {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "safe_reason_code",
                    "An available source does not carry an unavailability reason."
                )
            )
        }
        if status != .available, completeness == .complete {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "completeness",
                    "An unavailable source cannot claim complete content."
                )
            )
        }
        if let safeReasonCode {
            issues += transcriptReasonCodeIssues(safeReasonCode, path: "safe_reason_code")
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: container.decode(TranscriptSourceReference.self, forKey: .reference),
            status: container.decode(TranscriptSourceAvailabilityStatus.self, forKey: .status),
            authority: container.decode(SourceAuthority.self, forKey: .authority),
            completeness: container.decode(SourceCompleteness.self, forKey: .completeness),
            checkedAt: container.decode(UTCInstant.self, forKey: .checkedAt),
            safeReasonCode: container.decodeIfPresent(String.self, forKey: .safeReasonCode)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case reference
        case status
        case authority
        case completeness
        case checkedAt = "checked_at"
        case safeReasonCode = "safe_reason_code"
    }
}

/// One source text segment with truthful optional timing.
public struct TranscriptSourceSegment:
    Codable,
    Hashable,
    Sendable,
    Comparable,
    DomainValidatable
{
    public let sequence: UInt64
    public let text: String
    public let timeRange: MediaTimeRange?

    public init(sequence: UInt64, text: String, timeRange: MediaTimeRange? = nil) throws {
        self.sequence = sequence
        self.text = text
        self.timeRange = timeRange
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sequence < rhs.sequence
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if sequence == 0 {
            issues.append(
                transcriptIssue(
                    .invalidRange,
                    "sequence",
                    "Transcript source segments use one-based sequence numbers."
                )
            )
        }
        issues += transcriptTextIssues(text, path: "text", maximumUTF8Bytes: 65_536)
        if let timeRange {
            issues += timeRange.validationIssues()
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sequence: container.decode(UInt64.self, forKey: .sequence),
            text: container.decode(String.self, forKey: .text),
            timeRange: container.decodeIfPresent(MediaTimeRange.self, forKey: .timeRange)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case text
        case timeRange = "time_range"
    }
}

/// A binding created only after an explicit compatibility adapter validates an
/// already-published canonical-audio TranscriptCoverageManifest.
///
/// It references proof; it never constructs a coverage manifest from text.
public struct TranscriptAudioCoverageBinding:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let coverageManifestID: TranscriptCoverageManifestID
    public let coverageManifestHash: ContentDigest
    public let canonicalSourceRevision: SemanticRevisionReference
    public let verifiedCompleteFrameCoverage: Bool
    public let verifier: VersionedComponent

    public init(
        coverageManifestID: TranscriptCoverageManifestID,
        coverageManifestHash: ContentDigest,
        canonicalSourceRevision: SemanticRevisionReference,
        verifiedCompleteFrameCoverage: Bool,
        verifier: VersionedComponent
    ) throws {
        self.coverageManifestID = coverageManifestID
        self.coverageManifestHash = coverageManifestHash
        self.canonicalSourceRevision = canonicalSourceRevision
        self.verifiedCompleteFrameCoverage = verifiedCompleteFrameCoverage
        self.verifier = verifier
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = coverageManifestHash.validationIssues()
        issues += canonicalSourceRevision.validationIssues()
        if canonicalSourceRevision.objectType != .sourceAsset {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "canonical_source_revision.object_type",
                    "Audio coverage must bind an exact SourceAsset revision."
                )
            )
        }
        if !verifiedCompleteFrameCoverage {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "verified_complete_frame_coverage",
                    "Only independently verified complete canonical-frame coverage can bind a source snapshot."
                )
            )
        }
        issues += verifier.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            coverageManifestID: container.decode(
                TranscriptCoverageManifestID.self,
                forKey: .coverageManifestID
            ),
            coverageManifestHash: container.decode(
                ContentDigest.self,
                forKey: .coverageManifestHash
            ),
            canonicalSourceRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .canonicalSourceRevision
            ),
            verifiedCompleteFrameCoverage: container.decode(
                Bool.self,
                forKey: .verifiedCompleteFrameCoverage
            ),
            verifier: container.decode(VersionedComponent.self, forKey: .verifier)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case coverageManifestID = "coverage_manifest_id"
        case coverageManifestHash = "coverage_manifest_hash"
        case canonicalSourceRevision = "canonical_source_revision"
        case verifiedCompleteFrameCoverage = "verified_complete_frame_coverage"
        case verifier
    }
}

/// Provider-returned transcript source data. Optional timing stays optional,
/// and no provider-owned field decides whether local ASR runs.
public struct TranscriptSourceSnapshot: Codable, Hashable, Sendable, DomainValidatable {
    public let reference: TranscriptSourceReference
    public let authority: SourceAuthority
    public let completeness: SourceCompleteness
    public let language: LanguageTag
    public let segments: [TranscriptSourceSegment]
    public let contentDigest: ContentDigest
    public let dataClassification: DataClassification
    public let fetchedAt: UTCInstant

    public init(
        reference: TranscriptSourceReference,
        authority: SourceAuthority,
        completeness: SourceCompleteness,
        language: LanguageTag,
        segments: [TranscriptSourceSegment],
        contentDigest: ContentDigest,
        dataClassification: DataClassification,
        fetchedAt: UTCInstant
    ) throws {
        self.reference = reference
        self.authority = authority
        self.completeness = completeness
        self.language = language
        self.segments = segments.sorted()
        self.contentDigest = contentDigest
        self.dataClassification = dataClassification
        self.fetchedAt = fetchedAt
        try validate()
    }

    public var hasCompleteTiming: Bool {
        !segments.isEmpty
            && segments.allSatisfy { $0.timeRange != nil }
            && zip(segments, segments.dropFirst()).allSatisfy { lhs, rhs in
                guard let lhsRange = lhs.timeRange, let rhsRange = rhs.timeRange else {
                    return false
                }
                return lhsRange.endMilliseconds <= rhsRange.startMilliseconds
            }
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = reference.validationIssues()
        if !authority.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "authority",
                    "Unknown future authority cannot be trusted."
                )
            )
        }
        if !completeness.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "completeness",
                    "Unknown future completeness cannot be trusted."
                )
            )
        }
        issues += language.validationIssues()
        if segments.isEmpty || segments.count > 100_000 {
            issues.append(
                transcriptIssue(
                    .invalidRange,
                    "segments",
                    "A transcript source snapshot requires 1 through 100,000 bounded segments."
                )
            )
        }
        if Set(segments.map(\.sequence)).count != segments.count {
            issues.append(
                transcriptIssue(
                    .duplicateValue,
                    "segments.sequence",
                    "Transcript source segment sequence numbers must be unique."
                )
            )
        }
        for (index, segment) in segments.enumerated() {
            issues += segment.validationIssues()
            if segment.sequence != UInt64(index + 1) {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "segments[\(index)].sequence",
                        "Transcript source segments must form one contiguous sequence."
                    )
                )
            }
            if index > 0,
               let priorRange = segments[index - 1].timeRange,
               let range = segment.timeRange,
               priorRange.endMilliseconds > range.startMilliseconds
            {
                issues.append(
                    transcriptIssue(
                        .invalidRange,
                        "segments[\(index)].time_range",
                        "Timed transcript source segments cannot overlap."
                    )
                )
            }
        }
        issues += contentDigest.validationIssues()
        if !dataClassification.isKnown {
            issues.append(
                transcriptIssue(
                    .unsupportedValue,
                    "data_classification",
                    "Transcript source snapshots require a known classification."
                )
            )
        }
        issues += fetchedAt.validationIssues()
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: container.decode(TranscriptSourceReference.self, forKey: .reference),
            authority: container.decode(SourceAuthority.self, forKey: .authority),
            completeness: container.decode(SourceCompleteness.self, forKey: .completeness),
            language: container.decode(LanguageTag.self, forKey: .language),
            segments: container.decode([TranscriptSourceSegment].self, forKey: .segments),
            contentDigest: container.decode(ContentDigest.self, forKey: .contentDigest),
            dataClassification: container.decode(
                DataClassification.self,
                forKey: .dataClassification
            ),
            fetchedAt: container.decode(UTCInstant.self, forKey: .fetchedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case reference
        case authority
        case completeness
        case language
        case segments
        case contentDigest = "content_digest"
        case dataClassification = "data_classification"
        case fetchedAt = "fetched_at"
    }
}

/// Source discovery only. This interface has no method that returns an ASR
/// skip decision and does not replace TranscriptionProvider.
public protocol TranscriptSourceProviding: Sendable {
    func probe(_ context: TranscriptSourceContext) async throws -> TranscriptSourceAvailability
    func fetch(_ reference: TranscriptSourceReference) async throws -> TranscriptSourceSnapshot
    func refresh(_ reference: TranscriptSourceReference) async throws -> TranscriptSourceSnapshot
}

/// Non-overridable application inputs used by a resolver.
public struct TranscriptResolutionPolicySnapshot:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let policyVersion: VersionedComponent
    public let localASRAllowed: Bool
    public let localASRAvailable: Bool
    public let externalSourceUseAllowed: Bool
    public let requireCanonicalAudioCoverageToSkipASR: Bool
    public let userRequestedLocalASRComparison: Bool

    public init(
        policyVersion: VersionedComponent,
        localASRAllowed: Bool,
        localASRAvailable: Bool,
        externalSourceUseAllowed: Bool,
        requireCanonicalAudioCoverageToSkipASR: Bool = true,
        userRequestedLocalASRComparison: Bool = false
    ) throws {
        self.policyVersion = policyVersion
        self.localASRAllowed = localASRAllowed
        self.localASRAvailable = localASRAvailable
        self.externalSourceUseAllowed = externalSourceUseAllowed
        self.requireCanonicalAudioCoverageToSkipASR =
            requireCanonicalAudioCoverageToSkipASR
        self.userRequestedLocalASRComparison = userRequestedLocalASRComparison
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = policyVersion.validationIssues()
        if !requireCanonicalAudioCoverageToSkipASR {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "require_canonical_audio_coverage_to_skip_asr",
                    "Phase 1 never permits transcript text alone to satisfy canonical-audio coverage."
                )
            )
        }
        if userRequestedLocalASRComparison, !localASRAllowed {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "user_requested_local_asr_comparison",
                    "A local comparison request requires local ASR policy authority."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            policyVersion: container.decode(VersionedComponent.self, forKey: .policyVersion),
            localASRAllowed: container.decode(Bool.self, forKey: .localASRAllowed),
            localASRAvailable: container.decode(Bool.self, forKey: .localASRAvailable),
            externalSourceUseAllowed: container.decode(
                Bool.self,
                forKey: .externalSourceUseAllowed
            ),
            requireCanonicalAudioCoverageToSkipASR: container.decode(
                Bool.self,
                forKey: .requireCanonicalAudioCoverageToSkipASR
            ),
            userRequestedLocalASRComparison: container.decode(
                Bool.self,
                forKey: .userRequestedLocalASRComparison
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case localASRAllowed = "local_asr_allowed"
        case localASRAvailable = "local_asr_available"
        case externalSourceUseAllowed = "external_source_use_allowed"
        case requireCanonicalAudioCoverageToSkipASR =
            "require_canonical_audio_coverage_to_skip_asr"
        case userRequestedLocalASRComparison = "user_requested_local_asr_comparison"
    }
}

public struct TranscriptResolutionCandidate:
    Codable,
    Hashable,
    Sendable,
    Comparable,
    DomainValidatable
{
    public let availability: TranscriptSourceAvailability
    public let snapshot: TranscriptSourceSnapshot?
    public let applicationAudioCoverageBinding: TranscriptAudioCoverageBinding?

    public init(
        availability: TranscriptSourceAvailability,
        snapshot: TranscriptSourceSnapshot? = nil,
        applicationAudioCoverageBinding: TranscriptAudioCoverageBinding? = nil
    ) throws {
        self.availability = availability
        self.snapshot = snapshot
        self.applicationAudioCoverageBinding = applicationAudioCoverageBinding
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.availability < rhs.availability
    }

    /// Provider text and timing never satisfy audio coverage by themselves.
    /// Only the application-owned candidate assembly can attach exact proof.
    public var canSatisfyCanonicalAudioCoverage: Bool {
        availability.completeness == .complete
            && snapshot?.hasCompleteTiming == true
            && applicationAudioCoverageBinding?.verifiedCompleteFrameCoverage == true
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = availability.validationIssues()
        if let snapshot {
            issues += snapshot.validationIssues()
            if availability.status != .available
                || snapshot.reference != availability.reference
                || snapshot.authority != availability.authority
                || snapshot.completeness != availability.completeness
            {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "snapshot",
                        "A fetched snapshot must exactly match its available source claim."
                    )
                )
            }
        }
        if availability.status != .available, snapshot != nil {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "snapshot",
                    "Unavailable sources cannot carry fetched transcript content."
                )
            )
        }
        if let applicationAudioCoverageBinding {
            issues += applicationAudioCoverageBinding.validationIssues()
            if availability.status != .available
                || availability.completeness != .complete
                || snapshot?.hasCompleteTiming != true
            {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "application_audio_coverage_binding",
                        "Application audio coverage requires a complete, timed, available source snapshot."
                    )
                )
            }
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            availability: container.decode(
                TranscriptSourceAvailability.self,
                forKey: .availability
            ),
            snapshot: container.decodeIfPresent(
                TranscriptSourceSnapshot.self,
                forKey: .snapshot
            ),
            applicationAudioCoverageBinding: container.decodeIfPresent(
                TranscriptAudioCoverageBinding.self,
                forKey: .applicationAudioCoverageBinding
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case availability
        case snapshot
        case applicationAudioCoverageBinding = "application_audio_coverage_binding"
    }
}

/// Immutable, hash-bound input facts for an application-owned resolution
/// decision. Candidate order does not encode source priority.
public struct TranscriptResolutionInputSnapshot:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let context: TranscriptSourceContext
    public let policy: TranscriptResolutionPolicySnapshot
    public let candidates: [TranscriptResolutionCandidate]
    public let capturedAt: UTCInstant
    public let contentHash: ContentDigest

    public init(
        context: TranscriptSourceContext,
        policy: TranscriptResolutionPolicySnapshot,
        candidates: [TranscriptResolutionCandidate],
        capturedAt: UTCInstant,
        contentHash: ContentDigest? = nil
    ) throws {
        self.context = context
        self.policy = policy
        self.candidates = candidates.sorted()
        self.capturedAt = capturedAt
        self.contentHash = try contentHash ?? transcriptCanonicalHash(
            HashProjection(
                context: context,
                policy: policy,
                candidates: candidates.sorted(),
                capturedAt: capturedAt
            )
        )
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = context.validationIssues()
        issues += policy.validationIssues()
        if Set(candidates.map(\.availability.reference)).count != candidates.count {
            issues.append(
                transcriptIssue(
                    .duplicateValue,
                    "candidates.reference",
                    "Transcript resolution candidates must be unique."
                )
            )
        }
        for candidate in candidates {
            issues += candidate.validationIssues()
            let candidateRestrictionRank =
                candidate.snapshot?.dataClassification.restrictionRank
                    ?? context.dataClassification.restrictionRank
            if candidateRestrictionRank < context.dataClassification.restrictionRank {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "candidates.snapshot.data_classification",
                        "A transcript source snapshot cannot downgrade Meeting classification."
                    )
                )
            }
            if let binding = candidate.applicationAudioCoverageBinding,
               binding.canonicalSourceRevision != context.canonicalAudioSourceRevision
            {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "candidates.application_audio_coverage_binding.canonical_source_revision",
                        "Application audio coverage must bind the exact canonical source in the resolution context."
                    )
                )
            }
        }
        issues += capturedAt.validationIssues()
        issues += contentHash.validationIssues()
        if contentHash != (try? transcriptCanonicalHash(
            HashProjection(
                context: context,
                policy: policy,
                candidates: candidates,
                capturedAt: capturedAt
            )
        )) {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "content_hash",
                    "The transcript-resolution input hash must match exact canonical facts."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            context: container.decode(TranscriptSourceContext.self, forKey: .context),
            policy: container.decode(
                TranscriptResolutionPolicySnapshot.self,
                forKey: .policy
            ),
            candidates: container.decode(
                [TranscriptResolutionCandidate].self,
                forKey: .candidates
            ),
            capturedAt: container.decode(UTCInstant.self, forKey: .capturedAt),
            contentHash: container.decode(ContentDigest.self, forKey: .contentHash)
        )
    }

    private struct HashProjection: Codable {
        let context: TranscriptSourceContext
        let policy: TranscriptResolutionPolicySnapshot
        let candidates: [TranscriptResolutionCandidate]
        let capturedAt: UTCInstant

        private enum CodingKeys: String, CodingKey {
            case context
            case policy
            case candidates
            case capturedAt = "captured_at"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case context
        case policy
        case candidates
        case capturedAt = "captured_at"
        case contentHash = "content_hash"
    }
}

public struct TranscriptResolutionReason: Codable, Hashable, Sendable, DomainValidatable {
    public let code: String
    public let displayText: String

    public init(code: String, displayText: String) throws {
        self.code = code
        self.displayText = displayText
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        transcriptReasonCodeIssues(code, path: "code")
            + transcriptDisplayTextIssues(
                displayText,
                path: "display_text",
                maximumUTF8Bytes: 1_024
            )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            code: container.decode(String.self, forKey: .code),
            displayText: container.decode(String.self, forKey: .displayText)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case displayText = "display_text"
    }
}

/// Application-owned decision. A provider result is only one input and cannot
/// directly suppress local ASR.
public struct TranscriptResolutionDecision:
    Codable,
    Hashable,
    Sendable,
    DomainValidatable
{
    public let selectedPrimarySource: TranscriptSourceReference?
    public let authoritativeReference: TranscriptSourceReference?
    public let shouldRunLocalASR: Bool
    public let reason: TranscriptResolutionReason
    public let consideredAlternatives: [TranscriptSourceReference]
    public let inputSnapshot: TranscriptResolutionInputSnapshot

    public init(
        selectedPrimarySource: TranscriptSourceReference?,
        authoritativeReference: TranscriptSourceReference? = nil,
        shouldRunLocalASR: Bool,
        reason: TranscriptResolutionReason,
        consideredAlternatives: [TranscriptSourceReference],
        inputSnapshot: TranscriptResolutionInputSnapshot
    ) throws {
        self.selectedPrimarySource = selectedPrimarySource
        self.authoritativeReference = authoritativeReference
        self.shouldRunLocalASR = shouldRunLocalASR
        self.reason = reason
        self.consideredAlternatives = consideredAlternatives.sorted()
        self.inputSnapshot = inputSnapshot
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = reason.validationIssues()
        issues += inputSnapshot.validationIssues()
        if Set(consideredAlternatives).count != consideredAlternatives.count {
            issues.append(
                transcriptIssue(
                    .duplicateValue,
                    "considered_alternatives",
                    "Considered transcript-source alternatives must be unique."
                )
            )
        }
        for reference in consideredAlternatives {
            issues += reference.validationIssues()
        }
        let candidateReferences = inputSnapshot.candidates.map(\.availability.reference)
        if consideredAlternatives != candidateReferences.sorted() {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "considered_alternatives",
                    "A decision must retain every exact candidate from its input snapshot."
                )
            )
        }
        if let selectedPrimarySource,
           !consideredAlternatives.contains(selectedPrimarySource)
        {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "selected_primary_source",
                    "The selected primary source must be one of the considered alternatives."
                )
            )
        }
        if let authoritativeReference,
           !consideredAlternatives.contains(authoritativeReference)
        {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "authoritative_reference",
                    "The authoritative reference must be one of the considered alternatives."
                )
            )
        }

        if !shouldRunLocalASR {
            guard
                let selectedPrimarySource,
                inputSnapshot.policy.externalSourceUseAllowed,
                !inputSnapshot.policy.userRequestedLocalASRComparison,
                let selected = inputSnapshot.candidates.first(where: {
                    $0.availability.reference == selectedPrimarySource
                }),
                selected.availability.status == .available,
                selected.canSatisfyCanonicalAudioCoverage
            else {
                issues.append(
                    transcriptIssue(
                        .inconsistentValue,
                        "should_run_local_asr",
                        "Skipping local ASR requires an application-owned, complete canonical-audio coverage proof."
                    )
                )
                return issues
            }
        } else if !inputSnapshot.policy.localASRAllowed
            || !inputSnapshot.policy.localASRAvailable
        {
            issues.append(
                transcriptIssue(
                    .inconsistentValue,
                    "should_run_local_asr",
                    "A decision cannot run local ASR when policy or availability denies it."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            selectedPrimarySource: container.decodeIfPresent(
                TranscriptSourceReference.self,
                forKey: .selectedPrimarySource
            ),
            authoritativeReference: container.decodeIfPresent(
                TranscriptSourceReference.self,
                forKey: .authoritativeReference
            ),
            shouldRunLocalASR: container.decode(Bool.self, forKey: .shouldRunLocalASR),
            reason: container.decode(TranscriptResolutionReason.self, forKey: .reason),
            consideredAlternatives: container.decode(
                [TranscriptSourceReference].self,
                forKey: .consideredAlternatives
            ),
            inputSnapshot: container.decode(
                TranscriptResolutionInputSnapshot.self,
                forKey: .inputSnapshot
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedPrimarySource = "selected_primary_source"
        case authoritativeReference = "authoritative_reference"
        case shouldRunLocalASR = "should_run_local_asr"
        case reason
        case consideredAlternatives = "considered_alternatives"
        case inputSnapshot = "input_snapshot"
    }
}

public protocol TranscriptSourceResolving: Sendable {
    func resolve(_ input: TranscriptResolutionInputSnapshot) throws -> TranscriptResolutionDecision
}

private func transcriptIssue(
    _ code: ValidationIssueCode,
    _ path: String,
    _ message: String
) -> ValidationIssue {
    ValidationIssue(code: code, path: path, message: message)
}

private func transcriptOpaqueIdentifierIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        value == trimmed,
        !value.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.contains("/"),
        !value.contains("\\"),
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
        return [
            transcriptIssue(
                .invalidFormat,
                path,
                "The value must be a bounded opaque identifier, not a path."
            )
        ]
    }
    return []
}

private func transcriptReasonCodeIssues(_ value: String, path: String) -> [ValidationIssue] {
    let bytes = Array(value.utf8)
    let allowed = bytes.allSatisfy { byte in
        (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
            || byte == 45
            || byte == 95
    }
    guard
        !bytes.isEmpty,
        bytes.count <= 96,
        allowed,
        bytes.first != 45,
        bytes.first != 95,
        bytes.last != 45,
        bytes.last != 95
    else {
        return [
            transcriptIssue(
                .invalidFormat,
                path,
                "Reason codes must be bounded lowercase machine-readable identifiers."
            )
        ]
    }
    return []
}

private func transcriptTextIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    guard
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.contains("\0")
    else {
        return [
            transcriptIssue(
                .invalidFormat,
                path,
                "Text must be non-empty, bounded, and contain no null byte."
            )
        ]
    }
    return []
}

private func transcriptDisplayTextIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int
) -> [ValidationIssue] {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        value == trimmed,
        !value.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
        return [
            transcriptIssue(
                .invalidFormat,
                path,
                "Display text must be trimmed, bounded, and contain no control characters."
            )
        ]
    }
    return []
}

private func transcriptCanonicalHash<Value: Encodable>(_ value: Value) throws -> ContentDigest {
    let digest = SHA256.hash(data: try CanonicalJSON.encode(value))
    let lowercaseHex = digest.map { String(format: "%02x", $0) }.joined()
    return try ContentDigest(algorithm: .sha256, lowercaseHex: lowercaseHex)
}
