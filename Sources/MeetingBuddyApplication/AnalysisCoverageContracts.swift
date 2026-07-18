import CryptoKit
import Foundation
import MeetingBuddyDomain

public enum AnalysisCoverageError: Error, Equatable, Sendable {
    case invalidLedger(String)
    case publicationConflict
    case reviewUnavailable
}

public enum AnalysisLedgerStatus: String, Codable, Hashable, Sendable {
    case incomplete
    case published
}

public enum AnalysisSegmentDisposition: String, Codable, Hashable, Sendable {
    case substantive
    case nonSubstantive = "non_substantive"
    case failed
    case missing
}

public struct AnalysisRuntimeEvidence: Codable, Hashable, Sendable {
    public let operatingSystemVersion: String
    public let frameworkIdentifier: String
    public let adapterVersion: String
    public let localeIdentifier: String
    public let modelAvailable: Bool
    public let noOutboundMode: Bool

    public init(
        operatingSystemVersion: String,
        frameworkIdentifier: String,
        adapterVersion: String,
        localeIdentifier: String,
        modelAvailable: Bool,
        noOutboundMode: Bool
    ) throws {
        let values = [
            operatingSystemVersion,
            frameworkIdentifier,
            adapterVersion,
            localeIdentifier
        ]
        guard values.allSatisfy(Self.validLabel) else {
            throw AnalysisCoverageError.invalidLedger("Analysis runtime evidence is missing or unbounded.")
        }
        self.operatingSystemVersion = operatingSystemVersion
        self.frameworkIdentifier = frameworkIdentifier
        self.adapterVersion = adapterVersion
        self.localeIdentifier = localeIdentifier
        self.modelAvailable = modelAvailable
        self.noOutboundMode = noOutboundMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operatingSystemVersion: container.decode(
                String.self,
                forKey: .operatingSystemVersion
            ),
            frameworkIdentifier: container.decode(String.self, forKey: .frameworkIdentifier),
            adapterVersion: container.decode(String.self, forKey: .adapterVersion),
            localeIdentifier: container.decode(String.self, forKey: .localeIdentifier),
            modelAvailable: container.decode(Bool.self, forKey: .modelAvailable),
            noOutboundMode: container.decode(Bool.self, forKey: .noOutboundMode)
        )
    }

    private static func validLabel(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 256
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private enum CodingKeys: String, CodingKey {
        case operatingSystemVersion
        case frameworkIdentifier
        case adapterVersion
        case localeIdentifier
        case modelAvailable
        case noOutboundMode
    }
}

public struct AnalysisFixtureProvenance: Codable, Hashable, Sendable {
    public let fixtureIdentifier: String
    public let fixtureVersion: String
    public let fixtureHash: ContentDigest
    public let synthetic: Bool
    public let licensingStatus: String

    public init(
        fixtureIdentifier: String,
        fixtureVersion: String,
        fixtureHash: ContentDigest,
        synthetic: Bool,
        licensingStatus: String
    ) throws {
        let values = [fixtureIdentifier, fixtureVersion, licensingStatus]
        guard values.allSatisfy({ value in
            !value.isEmpty
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && value.utf8.count <= 256
                && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }) else {
            throw AnalysisCoverageError.invalidLedger("Fixture provenance is missing or unbounded.")
        }
        self.fixtureIdentifier = fixtureIdentifier
        self.fixtureVersion = fixtureVersion
        self.fixtureHash = fixtureHash
        self.synthetic = synthetic
        self.licensingStatus = licensingStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fixtureIdentifier: container.decode(String.self, forKey: .fixtureIdentifier),
            fixtureVersion: container.decode(String.self, forKey: .fixtureVersion),
            fixtureHash: container.decode(ContentDigest.self, forKey: .fixtureHash),
            synthetic: container.decode(Bool.self, forKey: .synthetic),
            licensingStatus: container.decode(String.self, forKey: .licensingStatus)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case fixtureIdentifier
        case fixtureVersion
        case fixtureHash
        case synthetic
        case licensingStatus
    }
}

public struct AnalysisSegmentCoverage: Codable, Hashable, Sendable, Comparable {
    public let segmentRevision: SemanticRevisionReference
    public let translationRevision: SemanticRevisionReference?
    public let speakerAssignmentRevision: SemanticRevisionReference?
    public let disposition: AnalysisSegmentDisposition
    public let attemptCount: UInt32
    public let provider: ProviderMetadata?
    public let evidenceRevisions: [SemanticRevisionReference]
    public let outputRevisions: [SemanticRevisionReference]
    public let safeReasonCode: String?

    public init(
        segmentRevision: SemanticRevisionReference,
        translationRevision: SemanticRevisionReference? = nil,
        speakerAssignmentRevision: SemanticRevisionReference? = nil,
        disposition: AnalysisSegmentDisposition,
        attemptCount: UInt32,
        provider: ProviderMetadata? = nil,
        evidenceRevisions: [SemanticRevisionReference] = [],
        outputRevisions: [SemanticRevisionReference] = [],
        safeReasonCode: String? = nil
    ) throws {
        let evidence = evidenceRevisions.sorted()
        let outputs = outputRevisions.sorted()
        guard segmentRevision.objectType == .transcriptSegment,
              translationRevision.map({ $0.objectType == .translationSegment }) ?? true,
              speakerAssignmentRevision.map({ $0.objectType == .speakerAssignment }) ?? true,
              evidence.allSatisfy({ $0.objectType == .evidenceRef }),
              Set(evidence).count == evidence.count,
              outputs.allSatisfy({ Self.allowedOutputTypes.contains($0.objectType) }),
              Set(outputs).count == outputs.count,
              attemptCount <= 100,
              safeReasonCode.map(Self.validReason) ?? true
        else {
            throw AnalysisCoverageError.invalidLedger("An analysis segment coverage record is malformed.")
        }
        switch disposition {
        case .substantive:
            guard !evidence.isEmpty,
                  !outputs.isEmpty,
                  outputs.contains(where: { $0.objectType == .interventionCard }),
                  safeReasonCode == nil,
                  (attemptCount == 0) == (provider == nil)
            else {
                throw AnalysisCoverageError.invalidLedger("Substantive coverage requires evidence, typed outputs, and a consistent route attempt.")
            }
        case .nonSubstantive:
            guard !evidence.isEmpty,
                  outputs.isEmpty,
                  safeReasonCode != nil,
                  (attemptCount == 0) == (provider == nil)
            else {
                throw AnalysisCoverageError.invalidLedger("Non-substantive coverage needs evidence and an explicit safe reason.")
            }
        case .failed:
            guard attemptCount > 0,
                  provider != nil,
                  outputs.isEmpty,
                  safeReasonCode != nil
            else {
                throw AnalysisCoverageError.invalidLedger("A failed analysis unit needs provider history and a safe code.")
            }
        case .missing:
            guard attemptCount == 0,
                  provider == nil,
                  evidence.isEmpty,
                  outputs.isEmpty,
                  safeReasonCode == nil
            else {
                throw AnalysisCoverageError.invalidLedger("A missing unit has no attempted result.")
            }
        }
        self.segmentRevision = segmentRevision
        self.translationRevision = translationRevision
        self.speakerAssignmentRevision = speakerAssignmentRevision
        self.disposition = disposition
        self.attemptCount = attemptCount
        self.provider = provider
        self.evidenceRevisions = evidence
        self.outputRevisions = outputs
        self.safeReasonCode = safeReasonCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            segmentRevision: container.decode(
                SemanticRevisionReference.self,
                forKey: .segmentRevision
            ),
            translationRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .translationRevision
            ),
            speakerAssignmentRevision: container.decodeIfPresent(
                SemanticRevisionReference.self,
                forKey: .speakerAssignmentRevision
            ),
            disposition: container.decode(AnalysisSegmentDisposition.self, forKey: .disposition),
            attemptCount: container.decode(UInt32.self, forKey: .attemptCount),
            provider: container.decodeIfPresent(ProviderMetadata.self, forKey: .provider),
            evidenceRevisions: container.decode(
                [SemanticRevisionReference].self,
                forKey: .evidenceRevisions
            ),
            outputRevisions: container.decode(
                [SemanticRevisionReference].self,
                forKey: .outputRevisions
            ),
            safeReasonCode: container.decodeIfPresent(String.self, forKey: .safeReasonCode)
        )
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.segmentRevision < rhs.segmentRevision
    }

    private static let allowedOutputTypes: Set<SemanticObjectType> = [
        .participant,
        .organization,
        .issue,
        .position,
        .commitment,
        .decision,
        .interventionCard,
        .delegationPositionCard
    ]

    private static func validReason(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 96
            && value.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
            }
    }

    private enum CodingKeys: String, CodingKey {
        case segmentRevision
        case translationRevision
        case speakerAssignmentRevision
        case disposition
        case attemptCount
        case provider
        case evidenceRevisions
        case outputRevisions
        case safeReasonCode
    }
}

/// Immutable route, prompt, input and per-segment proof for one analysis publication.
public struct AnalysisCoverageLedger: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt32 = 1

    public let ledgerID: AnalysisCoverageLedgerID
    public let supersedesLedgerID: AnalysisCoverageLedgerID?
    public let meetingID: MeetingID
    public let transcriptManifestID: TranscriptCoverageManifestID
    public let transcriptManifestHash: ContentDigest
    public let eligibleSegmentRevisions: [SemanticRevisionReference]
    public let analysisRoute: ModelRouteDecision
    public let runtimeEvidence: AnalysisRuntimeEvidence
    public let promptModules: [VersionedComponent]
    public let protectedRulesDigest: ContentDigest
    public let outputSchemaVersion: SchemaVersion
    public let inputPackageDigest: ContentDigest
    public let fixtureProvenance: AnalysisFixtureProvenance?
    public let status: AnalysisLedgerStatus
    public let segments: [AnalysisSegmentCoverage]
    public let createdAt: UTCInstant
    public let contentHash: ContentDigest

    public init(
        ledgerID: AnalysisCoverageLedgerID = AnalysisCoverageLedgerID(UUID()),
        supersedesLedgerID: AnalysisCoverageLedgerID? = nil,
        meetingID: MeetingID,
        transcriptManifestID: TranscriptCoverageManifestID,
        transcriptManifestHash: ContentDigest,
        eligibleSegmentRevisions: [SemanticRevisionReference],
        analysisRoute: ModelRouteDecision,
        runtimeEvidence: AnalysisRuntimeEvidence,
        promptModules: [VersionedComponent],
        protectedRulesDigest: ContentDigest,
        outputSchemaVersion: SchemaVersion = .v1,
        inputPackageDigest: ContentDigest,
        fixtureProvenance: AnalysisFixtureProvenance? = nil,
        status: AnalysisLedgerStatus,
        segments: [AnalysisSegmentCoverage],
        createdAt: UTCInstant,
        contentHash: ContentDigest? = nil
    ) throws {
        self.ledgerID = ledgerID
        self.supersedesLedgerID = supersedesLedgerID
        self.meetingID = meetingID
        self.transcriptManifestID = transcriptManifestID
        self.transcriptManifestHash = transcriptManifestHash
        self.eligibleSegmentRevisions = eligibleSegmentRevisions.sorted()
        self.analysisRoute = analysisRoute
        self.runtimeEvidence = runtimeEvidence
        self.promptModules = promptModules.sorted()
        self.protectedRulesDigest = protectedRulesDigest
        self.outputSchemaVersion = outputSchemaVersion
        self.inputPackageDigest = inputPackageDigest
        self.fixtureProvenance = fixtureProvenance
        self.status = status
        self.segments = segments.sorted()
        self.createdAt = createdAt
        self.contentHash = try contentHash ?? Self.hash(
            Projection(
                ledgerID: ledgerID,
                supersedesLedgerID: supersedesLedgerID,
                meetingID: meetingID,
                transcriptManifestID: transcriptManifestID,
                transcriptManifestHash: transcriptManifestHash,
                eligibleSegmentRevisions: eligibleSegmentRevisions.sorted(),
                analysisRoute: analysisRoute,
                runtimeEvidence: runtimeEvidence,
                promptModules: promptModules.sorted(),
                protectedRulesDigest: protectedRulesDigest,
                outputSchemaVersion: outputSchemaVersion,
                inputPackageDigest: inputPackageDigest,
                fixtureProvenance: fixtureProvenance,
                status: status,
                segments: segments.sorted(),
                createdAt: createdAt
            )
        )
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ledgerID: container.decode(AnalysisCoverageLedgerID.self, forKey: .ledgerID),
            supersedesLedgerID: container.decodeIfPresent(
                AnalysisCoverageLedgerID.self,
                forKey: .supersedesLedgerID
            ),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            transcriptManifestID: container.decode(
                TranscriptCoverageManifestID.self,
                forKey: .transcriptManifestID
            ),
            transcriptManifestHash: container.decode(
                ContentDigest.self,
                forKey: .transcriptManifestHash
            ),
            eligibleSegmentRevisions: container.decode(
                [SemanticRevisionReference].self,
                forKey: .eligibleSegmentRevisions
            ),
            analysisRoute: container.decode(ModelRouteDecision.self, forKey: .analysisRoute),
            runtimeEvidence: container.decode(
                AnalysisRuntimeEvidence.self,
                forKey: .runtimeEvidence
            ),
            promptModules: container.decode([VersionedComponent].self, forKey: .promptModules),
            protectedRulesDigest: container.decode(
                ContentDigest.self,
                forKey: .protectedRulesDigest
            ),
            outputSchemaVersion: container.decode(SchemaVersion.self, forKey: .outputSchemaVersion),
            inputPackageDigest: container.decode(ContentDigest.self, forKey: .inputPackageDigest),
            fixtureProvenance: container.decodeIfPresent(
                AnalysisFixtureProvenance.self,
                forKey: .fixtureProvenance
            ),
            status: container.decode(AnalysisLedgerStatus.self, forKey: .status),
            segments: container.decode([AnalysisSegmentCoverage].self, forKey: .segments),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            contentHash: container.decode(ContentDigest.self, forKey: .contentHash)
        )
    }

    public func validate() throws {
        let expectedCategories: Set<ProviderDataCategory> = [
            .transcriptText,
            .translationText,
            .speakerContext,
            .evidenceIdentifiers
        ]
        let actualCategories = Set(analysisRoute.request.dataCategories)
        guard supersedesLedgerID != ledgerID,
              !eligibleSegmentRevisions.isEmpty,
              eligibleSegmentRevisions.allSatisfy({ $0.objectType == .transcriptSegment }),
              Set(eligibleSegmentRevisions).count == eligibleSegmentRevisions.count,
              analysisRoute.request.capability == .analysis,
              analysisRoute.route.privacyRoute == .localOnly,
              analysisRoute.route == .appleOnDevice
                || analysisRoute.route == .deterministicTest
                || analysisRoute.route == .manualFallback,
              [.localWorkspaceOnly, .noProviderRetention].contains(
                  analysisRoute.request.retentionPolicy
              ),
              actualCategories.isSubset(of: expectedCategories),
              [.transcriptText, .speakerContext, .evidenceIdentifiers]
                .allSatisfy(actualCategories.contains),
              runtimeEvidence.noOutboundMode,
              !promptModules.isEmpty,
              Set(promptModules).count == promptModules.count,
              promptModules.allSatisfy({ $0.validationIssues().isEmpty }),
              outputSchemaVersion == .v1,
              Set(segments.map(\.segmentRevision)).count == segments.count,
              contentHash == (try Self.hash(projection))
        else {
            throw AnalysisCoverageError.invalidLedger("The analysis ledger identity, route, prompt history, or content hash is invalid.")
        }
        switch analysisRoute.route {
        case .appleOnDevice, .deterministicTest:
            guard (status == .incomplete || runtimeEvidence.modelAvailable),
                  analysisRoute.providerIdentifier != nil,
                  segments.allSatisfy({ segment in
                      segment.provider.map(\.providerIdentifier)
                          == analysisRoute.providerIdentifier
                          || segment.disposition == .missing
                  })
            else {
                throw AnalysisCoverageError.invalidLedger("Provider history does not match the approved analysis route.")
            }
        case .manualFallback:
            guard analysisRoute.providerIdentifier == nil,
                  segments.allSatisfy({ $0.provider == nil && $0.attemptCount == 0 })
            else {
                throw AnalysisCoverageError.invalidLedger("Manual analysis cannot claim provider use.")
            }
        case .approvedExternal:
            throw AnalysisCoverageError.invalidLedger("Task 006A authorizes no external analysis route.")
        }
        if status == .published {
            guard segments.map(\.segmentRevision) == eligibleSegmentRevisions,
                  segments.allSatisfy({
                      $0.disposition == .substantive || $0.disposition == .nonSubstantive
                  })
            else {
                throw AnalysisCoverageError.invalidLedger("Publication requires exactly one terminal result for every eligible segment.")
            }
        }
    }

    public var outputRevisionReferences: [SemanticRevisionReference] {
        Array(Set(segments.flatMap(\.outputRevisions))).sorted()
    }

    public var evidenceRevisionReferences: [SemanticRevisionReference] {
        Array(Set(segments.flatMap(\.evidenceRevisions))).sorted()
    }

    private var projection: Projection {
        Projection(
            ledgerID: ledgerID,
            supersedesLedgerID: supersedesLedgerID,
            meetingID: meetingID,
            transcriptManifestID: transcriptManifestID,
            transcriptManifestHash: transcriptManifestHash,
            eligibleSegmentRevisions: eligibleSegmentRevisions,
            analysisRoute: analysisRoute,
            runtimeEvidence: runtimeEvidence,
            promptModules: promptModules,
            protectedRulesDigest: protectedRulesDigest,
            outputSchemaVersion: outputSchemaVersion,
            inputPackageDigest: inputPackageDigest,
            fixtureProvenance: fixtureProvenance,
            status: status,
            segments: segments,
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
        let ledgerID: AnalysisCoverageLedgerID
        let supersedesLedgerID: AnalysisCoverageLedgerID?
        let meetingID: MeetingID
        let transcriptManifestID: TranscriptCoverageManifestID
        let transcriptManifestHash: ContentDigest
        let eligibleSegmentRevisions: [SemanticRevisionReference]
        let analysisRoute: ModelRouteDecision
        let runtimeEvidence: AnalysisRuntimeEvidence
        let promptModules: [VersionedComponent]
        let protectedRulesDigest: ContentDigest
        let outputSchemaVersion: SchemaVersion
        let inputPackageDigest: ContentDigest
        let fixtureProvenance: AnalysisFixtureProvenance?
        let status: AnalysisLedgerStatus
        let segments: [AnalysisSegmentCoverage]
        let createdAt: UTCInstant
    }

    private enum CodingKeys: String, CodingKey {
        case ledgerID
        case supersedesLedgerID
        case meetingID
        case transcriptManifestID
        case transcriptManifestHash
        case eligibleSegmentRevisions
        case analysisRoute
        case runtimeEvidence
        case promptModules
        case protectedRulesDigest
        case outputSchemaVersion
        case inputPackageDigest
        case fixtureProvenance
        case status
        case segments
        case createdAt
        case contentHash
    }
}

public struct AnalysisPublication: Sendable {
    public let ledger: AnalysisCoverageLedger
    public let evidence: [EvidenceRefV1]
    public let participants: [ParticipantV1]
    public let organizations: [OrganizationV1]
    public let issues: [IssueV1]
    public let positions: [PositionV1]
    public let commitments: [CommitmentV1]
    public let decisions: [DecisionV1]
    public let interventionCards: [InterventionCardV1]
    public let delegationPositionCards: [DelegationPositionCardV1]

    public init(
        ledger: AnalysisCoverageLedger,
        evidence: [EvidenceRefV1],
        participants: [ParticipantV1],
        organizations: [OrganizationV1],
        issues: [IssueV1],
        positions: [PositionV1],
        commitments: [CommitmentV1] = [],
        decisions: [DecisionV1] = [],
        interventionCards: [InterventionCardV1],
        delegationPositionCards: [DelegationPositionCardV1]
    ) throws {
        try ledger.validate()
        try Self.validatePublished(evidence)
        try Self.validatePublished(participants)
        try Self.validatePublished(organizations)
        try Self.validatePublished(issues)
        try Self.validatePublished(positions)
        try Self.validatePublished(commitments)
        try Self.validatePublished(decisions)
        try Self.validatePublished(interventionCards)
        try Self.validatePublished(delegationPositionCards)
        let outputReferences = try (
            Self.references(participants)
                + Self.references(organizations)
                + Self.references(issues)
                + Self.references(positions)
                + Self.references(commitments)
                + Self.references(decisions)
                + Self.references(interventionCards)
                + Self.references(delegationPositionCards)
        ).sorted()
        let evidenceReferences = try Self.references(evidence)
        guard ledger.status == .published,
              outputReferences == ledger.outputRevisionReferences,
              Set(ledger.evidenceRevisionReferences).isSubset(of: Set(evidenceReferences))
        else {
            throw AnalysisCoverageError.invalidLedger("Analysis objects do not exactly match the published coverage ledger.")
        }
        self.ledger = ledger
        self.evidence = evidence
        self.participants = participants
        self.organizations = organizations
        self.issues = issues
        self.positions = positions
        self.commitments = commitments
        self.decisions = decisions
        self.interventionCards = interventionCards
        self.delegationPositionCards = delegationPositionCards
    }

    public var semanticObjects: [any SemanticRevisionContract] {
        evidence + participants + organizations + issues + positions + commitments + decisions
            + interventionCards + delegationPositionCards
    }

    private static func references<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws -> [SemanticRevisionReference] {
        try values.map {
            try SemanticRevisionReference(
                logicalID: $0.revision.logicalID,
                revisionID: $0.revision.revisionID
            )
        }.sorted()
    }

    private static func validatePublished<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws {
        for value in values {
            try value.validate()
            guard value.revision.lifecycleStatus == .published,
                  value.revision.validationState == .valid
            else {
                throw AnalysisCoverageError.invalidLedger("Analysis publication contains a draft or invalid semantic revision.")
            }
        }
    }
}

public struct AnalysisReviewBundle: Sendable {
    public let ledger: AnalysisCoverageLedger
    public let evidence: [EvidenceRefV1]
    public let participants: [ParticipantV1]
    public let organizations: [OrganizationV1]
    public let issues: [IssueV1]
    public let positions: [PositionV1]
    public let commitments: [CommitmentV1]
    public let decisions: [DecisionV1]
    public let interventionCards: [InterventionCardV1]
    public let delegationPositionCards: [DelegationPositionCardV1]

    public init(publication: AnalysisPublication) {
        ledger = publication.ledger
        evidence = publication.evidence
        participants = publication.participants
        organizations = publication.organizations
        issues = publication.issues
        positions = publication.positions
        commitments = publication.commitments
        decisions = publication.decisions
        interventionCards = publication.interventionCards
        delegationPositionCards = publication.delegationPositionCards
    }

    public init(
        ledger: AnalysisCoverageLedger,
        evidence: [EvidenceRefV1],
        participants: [ParticipantV1],
        organizations: [OrganizationV1],
        issues: [IssueV1],
        positions: [PositionV1],
        commitments: [CommitmentV1],
        decisions: [DecisionV1],
        interventionCards: [InterventionCardV1],
        delegationPositionCards: [DelegationPositionCardV1]
    ) {
        self.ledger = ledger
        self.evidence = evidence
        self.participants = participants
        self.organizations = organizations
        self.issues = issues
        self.positions = positions
        self.commitments = commitments
        self.decisions = decisions
        self.interventionCards = interventionCards
        self.delegationPositionCards = delegationPositionCards
    }
}

public struct AnalysisSourceBundle: Sendable {
    public let meeting: MeetingProfileV1
    public let transcriptReview: TranscriptReviewBundle
    public let sourceAssets: [SourceAssetV1]
    public let actors: [ActorV1]
    public let capacities: [SpeakingCapacityV1]

    public init(
        meeting: MeetingProfileV1,
        transcriptReview: TranscriptReviewBundle,
        sourceAssets: [SourceAssetV1],
        actors: [ActorV1],
        capacities: [SpeakingCapacityV1]
    ) throws {
        try meeting.validate()
        try transcriptReview.manifest.validate()
        for sourceAsset in sourceAssets { try sourceAsset.validate() }
        for actor in actors { try actor.validate() }
        for capacity in capacities { try capacity.validate() }
        let actorReferences = try actors.map(Self.reference)
        let capacityReferences = try capacities.map(Self.reference)
        let sourceReferences = try sourceAssets.map(Self.reference)
        let requiredSourceReferences = Set(
            transcriptReview.transcriptSegments.flatMap(\.revision.sourceAssetRevisions)
                + transcriptReview.translations.flatMap(\.revision.sourceAssetRevisions)
        )
        guard meeting.meetingID == transcriptReview.manifest.meetingID,
              Set(sourceReferences) == requiredSourceReferences,
              Set(sourceReferences).count == sourceReferences.count,
              Set(actorReferences).count == actorReferences.count,
              Set(capacityReferences).count == capacityReferences.count,
              transcriptReview.speakerAssignments.allSatisfy({ assignment in
                  actorReferences.contains(assignment.actorRevision)
                      && capacityReferences.contains(assignment.speakingCapacityRevision)
              })
        else {
            throw AnalysisCoverageError.invalidLedger(
                "The resolved analysis source bundle has incomplete identity or capacity inputs."
            )
        }
        self.meeting = meeting
        self.transcriptReview = transcriptReview
        self.sourceAssets = sourceAssets
        self.actors = actors
        self.capacities = capacities
    }

    private static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }
}

public protocol AnalysisRepository: Sendable {
    func analysisSourceBundle(
        meetingRevision: SemanticRevisionReference,
        transcriptManifestID: TranscriptCoverageManifestID
    ) throws -> AnalysisSourceBundle
    func recordIncompleteAnalysis(_ ledger: AnalysisCoverageLedger) throws
    func publishAnalysis(
        _ publication: AnalysisPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws
    func activeAnalysisReview(meetingID: MeetingID) throws -> AnalysisReviewBundle?
    func savePositionCorrection(
        _ correction: PositionV1,
        replacing expectedRevisionID: RevisionID,
        changedAt: UTCInstant
    ) throws
}
