import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// Applies a user edit or lock as a new immutable section revision, then
/// rebuilds and atomically publishes the exact validation/final/coverage chain.
public struct BriefingManualReviewService: Sendable {
    private let repository: any BriefingRepository

    public init(repository: any BriefingRepository) {
        self.repository = repository
    }

    public func updateSection(
        meetingID: MeetingID,
        sectionType: BriefingSectionType,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool,
        changedAt: UTCInstant
    ) throws -> BriefingReviewBundle {
        guard let active = try repository.activeBriefingReview(meetingID: meetingID),
              active.isCurrent,
              let priorSection = active.publication.sections.first(where: {
                  $0.sectionType == sectionType
              }),
              let meetingReference = active.publication.graph.revision.inputRevisions
                .first(where: { $0.objectType == .meetingProfile })
        else { throw BriefingCoverageError.reviewUnavailable }

        let source = try repository.briefingSourceBundle(
            meetingRevision: meetingReference,
            template: active.publication.template,
            analysisLedgerID: active.publication.ledger.analysisLedgerID
        )
        let replacement = try BriefingSemanticFactory.makeManualSectionRevision(
            prior: priorSection,
            editedTextByItemID: editedTextByItemID,
            locked: locked,
            changedAt: changedAt
        )
        let sections = active.publication.sections.map {
            $0.sectionType == sectionType ? replacement : $0
        }
        let publication = try BriefingSemanticFactory.makePublication(
            source: source,
            graph: active.publication.graph,
            sections: sections,
            prior: BriefingAssemblyPriorState(
                ledgerID: active.publication.ledger.ledgerID,
                validationReport: active.publication.validationReport,
                finalBriefing: active.publication.finalBriefing
            ),
            createdAt: changedAt
        )
        try repository.replaceBriefingSection(
            publication,
            replacing: priorSection.revision.revisionID,
            changedAt: changedAt
        )
        guard let updated = try repository.activeBriefingReview(meetingID: meetingID),
              updated.isCurrent,
              updated.publication.sections.contains(where: {
                  $0.sectionType == sectionType
                      && $0.revision.revisionID == replacement.revision.revisionID
              })
        else { throw BriefingCoverageError.publicationConflict }
        return updated
    }
}
