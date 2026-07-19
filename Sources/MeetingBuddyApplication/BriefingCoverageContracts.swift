import CryptoKit
import Foundation
import MeetingBuddyDomain

public enum BriefingCoverageError: Error, Equatable, Sendable {
    case invalidLedger(String)
    case publicationConflict
    case reviewUnavailable
    case lockedSection
    case staleSection
}

public enum BriefingLedgerStatus: String, Codable, Hashable, Sendable {
    case incomplete
    case published
}

public enum BriefingSegmentDisposition: String, Codable, Hashable, Sendable {
    case represented
    case reviewedNotRendered = "reviewed_not_rendered"
    case nonSubstantive = "non_substantive"
    case failed
    case missing
}

/// Exact link from an upstream segment to a nested matrix or section item.
public struct BriefingConclusionReference: Codable, Hashable, Sendable, Comparable {
    public let outputRevision: SemanticRevisionReference
    public let itemID: BriefingItemID

    public init(
        outputRevision: SemanticRevisionReference,
        itemID: BriefingItemID
    ) throws {
        guard [.issuePositionGraph, .briefingSection].contains(outputRevision.objectType) else {
            throw BriefingCoverageError.invalidLedger(
                "A conclusion link must target a matrix or briefing-section revision."
            )
        }
        self.outputRevision = outputRevision
        self.itemID = itemID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.outputRevision, lhs.itemID) < (rhs.outputRevision, rhs.itemID)
    }
}

public struct BriefingSegmentCoverage: Codable, Hashable, Sendable, Comparable {
    public let segmentRevision: SemanticRevisionReference
    public let analysisOutputRevisions: [SemanticRevisionReference]
    public let evidenceRevisions: [SemanticRevisionReference]
    public let conclusionReferences: [BriefingConclusionReference]
    public let disposition: BriefingSegmentDisposition
    public let safeReasonCode: String?

    public init(
        segmentRevision: SemanticRevisionReference,
        analysisOutputRevisions: [SemanticRevisionReference],
        evidenceRevisions: [SemanticRevisionReference],
        conclusionReferences: [BriefingConclusionReference],
        disposition: BriefingSegmentDisposition,
        safeReasonCode: String? = nil
    ) throws {
        let outputs = analysisOutputRevisions.sorted()
        let evidence = evidenceRevisions.sorted()
        let conclusions = conclusionReferences.sorted()
        guard segmentRevision.objectType == .transcriptSegment,
              Set(outputs).count == outputs.count,
              outputs.allSatisfy({ Self.allowedAnalysisOutputTypes.contains($0.objectType) }),
              Set(evidence).count == evidence.count,
              evidence.allSatisfy({ $0.objectType == .evidenceRef }),
              Set(conclusions).count == conclusions.count,
              conclusions.count <= 4,
              safeReasonCode.map(Self.validReason) ?? true
        else {
            throw BriefingCoverageError.invalidLedger(
                "A per-segment briefing coverage record is malformed or exceeds bounded fan-out."
            )
        }
        switch disposition {
        case .represented:
            guard !outputs.isEmpty,
                  !evidence.isEmpty,
                  !conclusions.isEmpty,
                  safeReasonCode == nil
            else {
                throw BriefingCoverageError.invalidLedger(
                    "Represented material needs exact analysis outputs, evidence, and conclusion items."
                )
            }
        case .reviewedNotRendered:
            guard !outputs.isEmpty,
                  !evidence.isEmpty,
                  conclusions.isEmpty,
                  safeReasonCode != nil
            else {
                throw BriefingCoverageError.invalidLedger(
                    "Reviewed omitted material needs exact inputs and an explicit bounded reason."
                )
            }
        case .nonSubstantive:
            guard outputs.isEmpty,
                  !evidence.isEmpty,
                  conclusions.isEmpty,
                  safeReasonCode != nil
            else {
                throw BriefingCoverageError.invalidLedger(
                    "Inherited non-substantive coverage needs evidence and an explicit safe reason."
                )
            }
        case .failed:
            guard conclusions.isEmpty, safeReasonCode != nil else {
                throw BriefingCoverageError.invalidLedger(
                    "Failed briefing coverage needs an explicit safe reason."
                )
            }
        case .missing:
            guard outputs.isEmpty,
                  evidence.isEmpty,
                  conclusions.isEmpty,
                  safeReasonCode == nil
            else {
                throw BriefingCoverageError.invalidLedger(
                    "Missing coverage cannot imply any processed result."
                )
            }
        }
        self.segmentRevision = segmentRevision
        self.analysisOutputRevisions = outputs
        self.evidenceRevisions = evidence
        self.conclusionReferences = conclusions
        self.disposition = disposition
        self.safeReasonCode = safeReasonCode
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.segmentRevision < rhs.segmentRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            segmentRevision: container.decode(SemanticRevisionReference.self, forKey: .segmentRevision),
            analysisOutputRevisions: container.decode([SemanticRevisionReference].self, forKey: .analysisOutputRevisions),
            evidenceRevisions: container.decode([SemanticRevisionReference].self, forKey: .evidenceRevisions),
            conclusionReferences: container.decode([BriefingConclusionReference].self, forKey: .conclusionReferences),
            disposition: container.decode(BriefingSegmentDisposition.self, forKey: .disposition),
            safeReasonCode: container.decodeIfPresent(String.self, forKey: .safeReasonCode)
        )
    }

    private static let allowedAnalysisOutputTypes: Set<SemanticObjectType> = [
        .participant, .organization, .issue, .position, .commitment, .decision,
        .interventionCard, .delegationPositionCard
    ]

    private static func validReason(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 96
            && value.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
            }
    }

    private enum CodingKeys: String, CodingKey {
        case segmentRevision = "segment_revision"
        case analysisOutputRevisions = "analysis_output_revisions"
        case evidenceRevisions = "evidence_revisions"
        case conclusionReferences = "conclusion_references"
        case disposition
        case safeReasonCode = "safe_reason_code"
    }
}

/// Hash-bound proof that Task 006B consumed, but did not re-chunk or rewrite,
/// the exact Task 005B/006A eligible transcript set.
public struct BriefingCoverageLedger: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt32 = 1
    public static let overlapPolicy = "zero_source_text_overlap.v1"
    public static let maximumConclusionFanOut: UInt16 = 4

    public let ledgerID: BriefingCoverageLedgerID
    public let supersedesLedgerID: BriefingCoverageLedgerID?
    public let meetingID: MeetingID
    public let transcriptManifestID: TranscriptCoverageManifestID
    public let transcriptManifestHash: ContentDigest
    public let analysisLedgerID: AnalysisCoverageLedgerID
    public let analysisLedgerHash: ContentDigest
    public let eligibleSegmentRevisions: [SemanticRevisionReference]
    public let templateRevision: SemanticRevisionReference
    public let graphRevision: SemanticRevisionReference
    public let sectionRevisions: [SemanticRevisionReference]
    public let sourceTextOverlapUTF8Bytes: UInt64
    public let overlapPolicyIdentifier: String
    public let maximumConclusionFanOut: UInt16
    public let status: BriefingLedgerStatus
    public let segments: [BriefingSegmentCoverage]
    public let createdAt: UTCInstant
    public let contentHash: ContentDigest

    public init(
        ledgerID: BriefingCoverageLedgerID = BriefingCoverageLedgerID(UUID()),
        supersedesLedgerID: BriefingCoverageLedgerID? = nil,
        meetingID: MeetingID,
        transcriptManifestID: TranscriptCoverageManifestID,
        transcriptManifestHash: ContentDigest,
        analysisLedgerID: AnalysisCoverageLedgerID,
        analysisLedgerHash: ContentDigest,
        eligibleSegmentRevisions: [SemanticRevisionReference],
        templateRevision: SemanticRevisionReference,
        graphRevision: SemanticRevisionReference,
        sectionRevisions: [SemanticRevisionReference],
        sourceTextOverlapUTF8Bytes: UInt64 = 0,
        overlapPolicyIdentifier: String = BriefingCoverageLedger.overlapPolicy,
        maximumConclusionFanOut: UInt16 = BriefingCoverageLedger.maximumConclusionFanOut,
        status: BriefingLedgerStatus,
        segments: [BriefingSegmentCoverage],
        createdAt: UTCInstant,
        contentHash: ContentDigest? = nil
    ) throws {
        let eligible = eligibleSegmentRevisions.sorted()
        let sortedSegments = segments.sorted()
        self.ledgerID = ledgerID
        self.supersedesLedgerID = supersedesLedgerID
        self.meetingID = meetingID
        self.transcriptManifestID = transcriptManifestID
        self.transcriptManifestHash = transcriptManifestHash
        self.analysisLedgerID = analysisLedgerID
        self.analysisLedgerHash = analysisLedgerHash
        self.eligibleSegmentRevisions = eligible
        self.templateRevision = templateRevision
        self.graphRevision = graphRevision
        self.sectionRevisions = sectionRevisions
        self.sourceTextOverlapUTF8Bytes = sourceTextOverlapUTF8Bytes
        self.overlapPolicyIdentifier = overlapPolicyIdentifier
        self.maximumConclusionFanOut = maximumConclusionFanOut
        self.status = status
        self.segments = sortedSegments
        self.createdAt = createdAt
        let projection = Projection(
            ledgerID: ledgerID,
            supersedesLedgerID: supersedesLedgerID,
            meetingID: meetingID,
            transcriptManifestID: transcriptManifestID,
            transcriptManifestHash: transcriptManifestHash,
            analysisLedgerID: analysisLedgerID,
            analysisLedgerHash: analysisLedgerHash,
            eligibleSegmentRevisions: eligible,
            templateRevision: templateRevision,
            graphRevision: graphRevision,
            sectionRevisions: sectionRevisions,
            sourceTextOverlapUTF8Bytes: sourceTextOverlapUTF8Bytes,
            overlapPolicyIdentifier: overlapPolicyIdentifier,
            maximumConclusionFanOut: maximumConclusionFanOut,
            status: status,
            segments: sortedSegments,
            createdAt: createdAt
        )
        self.contentHash = try contentHash ?? Self.hash(projection)
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ledgerID: container.decode(BriefingCoverageLedgerID.self, forKey: .ledgerID),
            supersedesLedgerID: container.decodeIfPresent(BriefingCoverageLedgerID.self, forKey: .supersedesLedgerID),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            transcriptManifestID: container.decode(TranscriptCoverageManifestID.self, forKey: .transcriptManifestID),
            transcriptManifestHash: container.decode(ContentDigest.self, forKey: .transcriptManifestHash),
            analysisLedgerID: container.decode(AnalysisCoverageLedgerID.self, forKey: .analysisLedgerID),
            analysisLedgerHash: container.decode(ContentDigest.self, forKey: .analysisLedgerHash),
            eligibleSegmentRevisions: container.decode([SemanticRevisionReference].self, forKey: .eligibleSegmentRevisions),
            templateRevision: container.decode(SemanticRevisionReference.self, forKey: .templateRevision),
            graphRevision: container.decode(SemanticRevisionReference.self, forKey: .graphRevision),
            sectionRevisions: container.decode([SemanticRevisionReference].self, forKey: .sectionRevisions),
            sourceTextOverlapUTF8Bytes: container.decode(UInt64.self, forKey: .sourceTextOverlapUTF8Bytes),
            overlapPolicyIdentifier: container.decode(String.self, forKey: .overlapPolicyIdentifier),
            maximumConclusionFanOut: container.decode(UInt16.self, forKey: .maximumConclusionFanOut),
            status: container.decode(BriefingLedgerStatus.self, forKey: .status),
            segments: container.decode([BriefingSegmentCoverage].self, forKey: .segments),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            contentHash: container.decode(ContentDigest.self, forKey: .contentHash)
        )
    }

    public func validate() throws {
        guard supersedesLedgerID != ledgerID,
              !eligibleSegmentRevisions.isEmpty,
              eligibleSegmentRevisions.allSatisfy({ $0.objectType == .transcriptSegment }),
              Set(eligibleSegmentRevisions).count == eligibleSegmentRevisions.count,
              templateRevision.objectType == .meetingTemplate,
              graphRevision.objectType == .issuePositionGraph,
              sectionRevisions.count == 3,
              Set(sectionRevisions).count == 3,
              sectionRevisions.allSatisfy({ $0.objectType == .briefingSection }),
              sourceTextOverlapUTF8Bytes == 0,
              overlapPolicyIdentifier == Self.overlapPolicy,
              maximumConclusionFanOut == Self.maximumConclusionFanOut,
              Set(segments.map(\.segmentRevision)).count == segments.count,
              segments.allSatisfy({ $0.conclusionReferences.count <= Int(maximumConclusionFanOut) }),
              contentHash == (try Self.hash(projection))
        else {
            throw BriefingCoverageError.invalidLedger(
                "The briefing ledger identity, inputs, no-overlap proof, fan-out, or content hash is invalid."
            )
        }
        let allowedConclusionRevisions = Set(sectionRevisions + [graphRevision])
        guard segments.flatMap(\.conclusionReferences).allSatisfy({
            allowedConclusionRevisions.contains($0.outputRevision)
        }) else {
            throw BriefingCoverageError.invalidLedger(
                "A conclusion link targets an unbound output revision."
            )
        }
        if status == .published {
            guard segments.map(\.segmentRevision) == eligibleSegmentRevisions,
                  segments.allSatisfy({
                      $0.disposition == .represented
                          || $0.disposition == .reviewedNotRendered
                          || $0.disposition == .nonSubstantive
                  })
            else {
                throw BriefingCoverageError.invalidLedger(
                    "Publication requires one terminal accounting record for every eligible segment."
                )
            }
        }
    }

    public var conclusionReferences: [BriefingConclusionReference] {
        Array(Set(segments.flatMap(\.conclusionReferences))).sorted()
    }

    private var projection: Projection {
        Projection(
            ledgerID: ledgerID,
            supersedesLedgerID: supersedesLedgerID,
            meetingID: meetingID,
            transcriptManifestID: transcriptManifestID,
            transcriptManifestHash: transcriptManifestHash,
            analysisLedgerID: analysisLedgerID,
            analysisLedgerHash: analysisLedgerHash,
            eligibleSegmentRevisions: eligibleSegmentRevisions,
            templateRevision: templateRevision,
            graphRevision: graphRevision,
            sectionRevisions: sectionRevisions,
            sourceTextOverlapUTF8Bytes: sourceTextOverlapUTF8Bytes,
            overlapPolicyIdentifier: overlapPolicyIdentifier,
            maximumConclusionFanOut: maximumConclusionFanOut,
            status: status,
            segments: segments,
            createdAt: createdAt
        )
    }

    private static func hash<T: Encodable>(_ value: T) throws -> ContentDigest {
        let data = try CanonicalJSON.encode(value)
        let digest = SHA256.hash(data: data)
        return try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private struct Projection: Codable {
        let ledgerID: BriefingCoverageLedgerID
        let supersedesLedgerID: BriefingCoverageLedgerID?
        let meetingID: MeetingID
        let transcriptManifestID: TranscriptCoverageManifestID
        let transcriptManifestHash: ContentDigest
        let analysisLedgerID: AnalysisCoverageLedgerID
        let analysisLedgerHash: ContentDigest
        let eligibleSegmentRevisions: [SemanticRevisionReference]
        let templateRevision: SemanticRevisionReference
        let graphRevision: SemanticRevisionReference
        let sectionRevisions: [SemanticRevisionReference]
        let sourceTextOverlapUTF8Bytes: UInt64
        let overlapPolicyIdentifier: String
        let maximumConclusionFanOut: UInt16
        let status: BriefingLedgerStatus
        let segments: [BriefingSegmentCoverage]
        let createdAt: UTCInstant
    }

    private enum CodingKeys: String, CodingKey {
        case ledgerID = "ledger_id"
        case supersedesLedgerID = "supersedes_ledger_id"
        case meetingID = "meeting_id"
        case transcriptManifestID = "transcript_manifest_id"
        case transcriptManifestHash = "transcript_manifest_hash"
        case analysisLedgerID = "analysis_ledger_id"
        case analysisLedgerHash = "analysis_ledger_hash"
        case eligibleSegmentRevisions = "eligible_segment_revisions"
        case templateRevision = "template_revision"
        case graphRevision = "graph_revision"
        case sectionRevisions = "section_revisions"
        case sourceTextOverlapUTF8Bytes = "source_text_overlap_utf8_bytes"
        case overlapPolicyIdentifier = "overlap_policy_identifier"
        case maximumConclusionFanOut = "maximum_conclusion_fan_out"
        case status
        case segments
        case createdAt = "created_at"
        case contentHash = "content_hash"
    }
}

public struct BriefingPublication: Sendable {
    public let template: MeetingTemplateV1
    public let graph: IssuePositionGraphV1
    public let sections: [BriefingSectionV1]
    public let validationReport: ValidationReportV1
    public let finalBriefing: FinalBriefingV1
    public let ledger: BriefingCoverageLedger

    public init(
        template: MeetingTemplateV1,
        graph: IssuePositionGraphV1,
        sections: [BriefingSectionV1],
        validationReport: ValidationReportV1,
        finalBriefing: FinalBriefingV1,
        ledger: BriefingCoverageLedger
    ) throws {
        try template.validate()
        try graph.validate()
        for section in sections { try section.validate() }
        try validationReport.validate()
        try finalBriefing.validate()
        try ledger.validate()
        let templateReference = try Self.reference(template)
        let graphReference = try Self.reference(graph)
        let orderedSections = sections.sorted { $0.order < $1.order }
        let sectionReferences = try orderedSections.map(Self.reference)
        let reportReference = try Self.reference(validationReport)
        let templatePublished = template.revision.lifecycleStatus == .published
            && template.revision.validationState == .valid
        let graphPublished = graph.revision.lifecycleStatus == .published
            && graph.revision.validationState == .valid
        let reportPublished = validationReport.revision.lifecycleStatus == .published
            && validationReport.revision.validationState == .valid
        let finalPublished = finalBriefing.revision.lifecycleStatus == .published
            && finalBriefing.revision.validationState == .valid
        let sectionsPublished = orderedSections.allSatisfy {
            $0.revision.lifecycleStatus == .published
                && $0.revision.validationState == .valid
        }
        guard templatePublished,
              graphPublished,
              reportPublished,
              finalPublished,
              orderedSections.count == 3,
              sectionsPublished,
              templateReference == ledger.templateRevision,
              graphReference == ledger.graphRevision,
              sectionReferences == ledger.sectionRevisions,
              graph.templateRevision == templateReference,
              Set(orderedSections.map(\.templateRevision)) == [templateReference],
              Set(orderedSections.map(\.graphRevision)) == [graphReference],
              orderedSections.map(\.sectionType) == template.sections.map(\.sectionType),
              orderedSections.map(\.order) == template.sections.map(\.order),
              validationReport.passed,
              validationReport.templateRevision == templateReference,
              validationReport.graphRevision == graphReference,
              validationReport.sectionRevisions == sectionReferences,
              validationReport.coverageLedgerID == ledger.ledgerID,
              validationReport.coverageLedgerHash == ledger.contentHash,
              finalBriefing.templateRevision == templateReference,
              finalBriefing.sectionRevisions == sectionReferences,
              finalBriefing.validationReportRevision == reportReference,
              Set(orderedSections.map(\.outputLanguage)) == [finalBriefing.outputLanguage],
              ledger.meetingID == graph.meetingID,
              Set(orderedSections.map(\.meetingID)) == [graph.meetingID],
              validationReport.meetingID == graph.meetingID,
              finalBriefing.meetingID == graph.meetingID
        else {
            throw BriefingCoverageError.invalidLedger(
                "The briefing semantic objects do not form one exact validated publication chain."
            )
        }
        var expectedConclusions: Set<BriefingConclusionReference> = []
        for cell in graph.cells {
            expectedConclusions.insert(
                try BriefingConclusionReference(
                    outputRevision: graphReference,
                    itemID: cell.itemID
                )
            )
        }
        for section in orderedSections {
            let sectionReference = try Self.reference(section)
            for item in section.items {
                expectedConclusions.insert(
                    try BriefingConclusionReference(
                        outputRevision: sectionReference,
                        itemID: item.itemID
                    )
                )
            }
        }
        guard Set(ledger.conclusionReferences) == expectedConclusions else {
            throw BriefingCoverageError.invalidLedger(
                "Every material matrix and briefing item must trace to at least one eligible source segment."
            )
        }
        let inheritedClassification = DataClassification.mostRestrictive(
            [graph.revision.dataClassification]
                + orderedSections.map(\.revision.dataClassification)
        )
        guard inheritedClassification == graph.revision.dataClassification,
              orderedSections.allSatisfy({
                  $0.revision.dataClassification == graph.revision.dataClassification
              }),
              validationReport.revision.dataClassification == graph.revision.dataClassification,
              finalBriefing.revision.dataClassification == graph.revision.dataClassification
        else {
            throw BriefingCoverageError.invalidLedger(
                "Briefing publication classification must inherit the same most-restrictive meeting value."
            )
        }
        self.template = template
        self.graph = graph
        self.sections = orderedSections
        self.validationReport = validationReport
        self.finalBriefing = finalBriefing
        self.ledger = ledger
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

public struct BriefingReviewBundle: Sendable {
    public let publication: BriefingPublication
    public let staleMarks: [PersistedStaleMark]

    public init(publication: BriefingPublication, staleMarks: [PersistedStaleMark]) {
        self.publication = publication
        self.staleMarks = staleMarks
    }

    public var isCurrent: Bool { staleMarks.isEmpty }
}

public struct BriefingSourceBundle: Sendable {
    public let meeting: MeetingProfileV1
    public let template: MeetingTemplateV1
    public let transcriptReview: TranscriptReviewBundle
    public let analysis: AnalysisReviewBundle

    public init(
        meeting: MeetingProfileV1,
        template: MeetingTemplateV1,
        transcriptReview: TranscriptReviewBundle,
        analysis: AnalysisReviewBundle
    ) throws {
        try meeting.validate()
        try template.validate()
        try transcriptReview.manifest.validate()
        try analysis.ledger.validate()
        guard analysis.ledger.status == .published,
              analysis.ledger.meetingID == meeting.meetingID,
              transcriptReview.manifest.meetingID == meeting.meetingID,
              transcriptReview.manifest.manifestID == analysis.ledger.transcriptManifestID,
              transcriptReview.manifest.contentHash == analysis.ledger.transcriptManifestHash,
              transcriptReview.manifest.transcriptRevisionReferences
                == analysis.ledger.eligibleSegmentRevisions,
              meeting.briefingTemplateID.map({ $0 == template.templateID }) ?? true,
              template.revision.lifecycleStatus == .published,
              template.revision.validationState == .valid
        else {
            throw BriefingCoverageError.reviewUnavailable
        }
        let exactOutputs = Set(analysis.ledger.outputRevisionReferences)
        let nonPositionReferences = try Self.references(analysis.participants)
            + Self.references(analysis.organizations)
            + Self.references(analysis.issues)
            + Self.references(analysis.commitments)
            + Self.references(analysis.decisions)
            + Self.references(analysis.interventionCards)
            + Self.references(analysis.delegationPositionCards)
        guard Set(nonPositionReferences) == Set(
            exactOutputs.filter { $0.objectType != .position }
        ) else {
            throw BriefingCoverageError.reviewUnavailable
        }
        let ledgerPositions = exactOutputs.filter { $0.objectType == .position }
        guard analysis.positions.count == ledgerPositions.count,
              analysis.positions.allSatisfy({ position in
                  ledgerPositions.contains(where: { historical in
                      historical.logicalID.canonicalString == position.positionID.canonicalString
                          && (historical.revisionID == position.revision.revisionID
                              || (position.revision.createdBy == .user
                                  && position.reviewStatus == .confirmed
                                  && position.userConfirmed
                                  && position.revision.supersedesRevisionID != nil))
                  })
              })
        else {
            throw BriefingCoverageError.reviewUnavailable
        }
        self.meeting = meeting
        self.template = template
        self.transcriptReview = transcriptReview
        self.analysis = analysis
    }

    private static func references<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws -> [SemanticRevisionReference] {
        try values.map {
            try SemanticRevisionReference(
                logicalID: $0.revision.logicalID,
                revisionID: $0.revision.revisionID
            )
        }
    }
}

public protocol BriefingRepository: Sendable {
    func briefingSourceBundle(
        meetingRevision: SemanticRevisionReference,
        template: MeetingTemplateV1,
        analysisLedgerID: AnalysisCoverageLedgerID
    ) throws -> BriefingSourceBundle
    func recordIncompleteBriefing(_ ledger: BriefingCoverageLedger) throws
    func publishBriefing(
        _ publication: BriefingPublication,
        validatingInputRevisions inputRevisions: [SemanticRevisionReference]
    ) throws
    func activeBriefingReview(meetingID: MeetingID) throws -> BriefingReviewBundle?
    func briefingCoverageLedgers(meetingID: MeetingID) throws -> [BriefingCoverageLedger]
    func replaceBriefingSection(
        _ publication: BriefingPublication,
        replacing expectedSectionRevisionID: RevisionID,
        changedAt: UTCInstant
    ) throws
}
