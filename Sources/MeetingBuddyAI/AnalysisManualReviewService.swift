import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// Converts the exact active provider candidate into a user-confirmed ledger.
/// Semantic objects are not rewritten; the new immutable ledger binds the
/// confirmation to the candidate ID and content hash.
public struct AnalysisManualReviewService: Sendable {
    private let repository: any AnalysisRepository

    public init(repository: any AnalysisRepository) {
        self.repository = repository
    }

    public func confirmCurrent(
        meetingID: MeetingID,
        confirmsEveryClaim: Bool,
        confirmedAt: UTCInstant
    ) throws -> AnalysisReviewBundle {
        guard confirmsEveryClaim,
              let candidate = try repository.activeAnalysisReview(meetingID: meetingID),
              candidate.ledger.status == .published,
              !candidate.isHumanConfirmed
        else { throw AnalysisCoverageError.reviewUnavailable }

        let confirmation = try AnalysisReviewConfirmation(
            candidateLedgerID: candidate.ledger.ledgerID,
            candidateContentHash: candidate.ledger.contentHash,
            confirmedAt: confirmedAt,
            confirmsEveryClaim: confirmsEveryClaim
        )
        let confirmedLedger = try AnalysisCoverageLedger(
            ledgerID: AnalysisCoverageLedgerID(Self.deterministicUUID(
                "task012-analysis-confirmation-v1:\(candidate.ledger.ledgerID.canonicalString):\(candidate.ledger.contentHash.lowercaseHex):\(confirmedAt.millisecondsSinceUnixEpoch)"
            )),
            supersedesLedgerID: candidate.ledger.ledgerID,
            meetingID: candidate.ledger.meetingID,
            transcriptManifestID: candidate.ledger.transcriptManifestID,
            transcriptManifestHash: candidate.ledger.transcriptManifestHash,
            eligibleSegmentRevisions: candidate.ledger.eligibleSegmentRevisions,
            analysisRoute: candidate.ledger.analysisRoute,
            runtimeEvidence: candidate.ledger.runtimeEvidence,
            promptModules: candidate.ledger.promptModules,
            protectedRulesDigest: candidate.ledger.protectedRulesDigest,
            outputSchemaVersion: candidate.ledger.outputSchemaVersion,
            inputPackageDigest: candidate.ledger.inputPackageDigest,
            fixtureProvenance: candidate.ledger.fixtureProvenance,
            reviewConfirmation: confirmation,
            status: candidate.ledger.status,
            segments: candidate.ledger.segments,
            createdAt: confirmedAt
        )
        let publication = try AnalysisPublication(
            ledger: confirmedLedger,
            evidence: candidate.evidence,
            participants: candidate.participants,
            organizations: candidate.organizations,
            issues: candidate.issues,
            positions: candidate.positions,
            commitments: candidate.commitments,
            decisions: candidate.decisions,
            interventionCards: candidate.interventionCards,
            delegationPositionCards: candidate.delegationPositionCards
        )
        try repository.publishAnalysis(publication, validatingInputRevisions: [])
        guard let confirmed = try repository.activeAnalysisReview(meetingID: meetingID),
              confirmed.ledger.ledgerID == confirmedLedger.ledgerID,
              confirmed.isHumanConfirmed
        else { throw AnalysisCoverageError.publicationConflict }
        return confirmed
    }

    private static func deterministicUUID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
