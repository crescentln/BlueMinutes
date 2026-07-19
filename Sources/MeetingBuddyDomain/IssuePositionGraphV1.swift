import Foundation

/// A deterministic sparse issue-by-represented-entity matrix. Missing cells
/// mean that no reviewed position cell exists; they never imply alignment.
public struct IssuePositionGraphV1: SemanticRevisionContract {
    public let revision: RevisionEnvelope<IssuePositionGraphIDTag>
    public let meetingID: MeetingID
    public let templateRevision: SemanticRevisionReference
    public let analysisLedgerID: AnalysisCoverageLedgerID
    public let analysisLedgerHash: ContentDigest
    public let rows: [IssuePositionMatrixRow]
    public let reviewStatus: ReviewStatus
    public let userConfirmed: Bool

    public init(
        revision: RevisionEnvelope<IssuePositionGraphIDTag>,
        meetingID: MeetingID,
        templateRevision: SemanticRevisionReference,
        analysisLedgerID: AnalysisCoverageLedgerID,
        analysisLedgerHash: ContentDigest,
        rows: [IssuePositionMatrixRow],
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.templateRevision = templateRevision
        self.analysisLedgerID = analysisLedgerID
        self.analysisLedgerHash = analysisLedgerHash
        self.rows = rows.sorted()
        self.reviewStatus = reviewStatus
        self.userConfirmed = userConfirmed
        try validate()
    }

    public var graphID: IssuePositionGraphID { revision.logicalID }
    public var cells: [IssuePositionMatrixCell] { rows.flatMap(\.cells) }

    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try IntelligenceRevisionSupport.hash(revision: revision, content: Content(self))
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = IntelligenceRevisionSupport.commonIssues(
            revision: revision,
            expectedType: .issuePositionGraph,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed,
            calculatedHash: calculatedSemanticContentHash,
            objectName: "IssuePositionGraph.v1"
        )
        issues += IntelligenceRevisionSupport.meetingInputIssues(
            meetingID: meetingID,
            revisionInputs: revision.inputRevisions
        )
        issues += IntelligenceRevisionSupport.exactInputIssues(
            templateRevision,
            expectedTypes: [.meetingTemplate],
            revisionInputs: revision.inputRevisions,
            path: "template_revision",
            noun: "MeetingTemplate revision"
        )
        issues += analysisLedgerHash.validationIssues()
        if rows.isEmpty {
            issues.append(Self.issue(.missingRequiredValue, "rows", "The first vertical slice requires at least one reviewed position row."))
        }
        issues += duplicateIssues(in: rows.map(\.issueRevision), path: "rows.issue_revision")
        issues += duplicateIssues(in: cells.map(\.itemID), path: "rows.cells.item_id")
        for row in rows {
            issues += row.validationIssues()
            issues += IntelligenceRevisionSupport.exactInputIssues(
                row.issueRevision,
                expectedTypes: [.issue],
                revisionInputs: revision.inputRevisions,
                path: "rows.issue_revision",
                noun: "Issue revision"
            )
            issues += duplicateIssues(
                in: row.cells.map(\.representedEntityRevision),
                path: "rows.cells.represented_entity_revision"
            )
            for cell in row.cells {
                issues += IntelligenceRevisionSupport.exactInputIssues(
                    cell.representedEntityRevision,
                    expectedTypes: [.participant, .organization],
                    revisionInputs: revision.inputRevisions,
                    path: "rows.cells.represented_entity_revision",
                    noun: "represented entity revision"
                )
                for position in cell.positionRevisions {
                    issues += IntelligenceRevisionSupport.exactInputIssues(
                        position,
                        expectedTypes: [.position],
                        revisionInputs: revision.inputRevisions,
                        path: "rows.cells.position_revisions",
                        noun: "Position revision"
                    )
                }
                if let card = cell.delegationCardRevision {
                    issues += IntelligenceRevisionSupport.exactInputIssues(
                        card,
                        expectedTypes: [.delegationPositionCard],
                        revisionInputs: revision.inputRevisions,
                        path: "rows.cells.delegation_card_revision",
                        noun: "DelegationPositionCard revision"
                    )
                }
            }
        }
        let claims = cells.flatMap(\.materialClaims)
        issues += IntelligenceRevisionSupport.evidenceClosureIssues(
            claims: claims,
            revisionEvidence: revision.evidenceRevisions,
            lifecycle: revision.lifecycleStatus,
            createdBy: revision.createdBy,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
        if Set(claims.flatMap(\.evidenceRevisions)) != Set(revision.evidenceRevisions) {
            issues.append(Self.issue(.inconsistentValue, "revision.evidence_revisions", "The graph evidence envelope must exactly equal its material claim evidence."))
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            revision: container.decode(RevisionEnvelope<IssuePositionGraphIDTag>.self, forKey: .revision),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            templateRevision: container.decode(SemanticRevisionReference.self, forKey: .templateRevision),
            analysisLedgerID: container.decode(AnalysisCoverageLedgerID.self, forKey: .analysisLedgerID),
            analysisLedgerHash: container.decode(ContentDigest.self, forKey: .analysisLedgerHash),
            rows: container.decode([IssuePositionMatrixRow].self, forKey: .rows),
            reviewStatus: container.decode(ReviewStatus.self, forKey: .reviewStatus),
            userConfirmed: container.decode(Bool.self, forKey: .userConfirmed)
        )
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Content: Codable, Hashable, Sendable {
        let meetingID: MeetingID
        let templateRevision: SemanticRevisionReference
        let analysisLedgerID: AnalysisCoverageLedgerID
        let analysisLedgerHash: ContentDigest
        let rows: [IssuePositionMatrixRow]
        let reviewStatus: ReviewStatus
        let userConfirmed: Bool

        init(_ value: IssuePositionGraphV1) {
            meetingID = value.meetingID
            templateRevision = value.templateRevision
            analysisLedgerID = value.analysisLedgerID
            analysisLedgerHash = value.analysisLedgerHash
            rows = value.rows
            reviewStatus = value.reviewStatus
            userConfirmed = value.userConfirmed
        }

        private enum CodingKeys: String, CodingKey {
            case meetingID = "meeting_id"
            case templateRevision = "template_revision"
            case analysisLedgerID = "analysis_ledger_id"
            case analysisLedgerHash = "analysis_ledger_hash"
            case rows
            case reviewStatus = "review_status"
            case userConfirmed = "user_confirmed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case templateRevision = "template_revision"
        case analysisLedgerID = "analysis_ledger_id"
        case analysisLedgerHash = "analysis_ledger_hash"
        case rows
        case reviewStatus = "review_status"
        case userConfirmed = "user_confirmed"
    }
}
