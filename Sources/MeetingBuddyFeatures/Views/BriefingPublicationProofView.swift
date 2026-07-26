import MeetingBuddyApplication
import SwiftUI

struct BriefingPublicationProofView: View {
    let review: BriefingReviewBundle

    var body: some View {
        DisclosureGroup("Published briefing proof") {
            VStack(alignment: .leading, spacing: 14) {
                proofGrid
                Divider()
                validationChecks
                validationFindings
            }
            .padding(.top, 10)
        }
    }

    private var proofGrid: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: 18,
            verticalSpacing: 8
        ) {
            GridRow {
                Text("Validation")
                Text(
                    "\(passedCheckCount) / \(review.publication.validationReport.checks.count) checks passed"
                )
            }
            GridRow {
                Text("Source coverage")
                Text(
                    "\(review.publication.ledger.segments.count) / \(review.publication.ledger.eligibleSegmentRevisions.count) eligible segments"
                )
            }
            GridRow {
                Text("Conclusion links")
                Text(
                    String(
                        review.publication.ledger
                            .conclusionReferences.count
                    )
                )
            }
            GridRow {
                Text("Issue matrix")
                Text(
                    "\(review.publication.graph.rows.count) issues · \(review.publication.graph.cells.count) stated-position cells"
                )
            }
            GridRow {
                Text("Current")
                Text(review.isCurrent ? "yes" : "no")
            }
            GridRow {
                Text("Human confirmation")
                Text(
                    review.isHumanConfirmed
                    ? "all sections confirmed"
                    : "incomplete"
                )
            }
            GridRow {
                Text("Markdown digest")
                Text(
                    short(
                        review.publication.finalBriefing
                            .markdownDigest.lowercaseHex
                    )
                )
                .monospaced()
            }
        }
    }

    private var validationChecks: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorialSectionHeader(
                "Validation checks",
                detail:
                    "Every protected category remains visible and independent."
            )
            ForEach(
                review.publication.validationReport.checks,
                id: \.category
            ) { check in
                LabeledContent(
                    label(check.category.encodedValue),
                    value: label(check.status.encodedValue)
                )
            }
        }
    }

    @ViewBuilder
    private var validationFindings: some View {
        if !review.publication.validationReport
            .findings.isEmpty
        {
            EditorialSectionHeader(
                "Validation findings"
            )
            ForEach(
                review.publication.validationReport.findings,
                id: \.findingID
            ) { finding in
                WorkflowStateView(
                    title: finding.code,
                    detail: finding.message,
                    systemImage:
                        finding.blocking
                        ? "xmark.octagon"
                        : "exclamationmark.triangle",
                    tone:
                        finding.blocking
                        ? .failure
                        : .warning
                )
            }
        }
    }

    private var passedCheckCount: Int {
        review.publication.validationReport
            .checks.filter {
                $0.status == .passed
            }.count
    }

    private func label(
        _ rawValue: String
    ) -> String {
        rawValue
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .capitalized
    }

    private func short(
        _ value: String
    ) -> String {
        value.count > 18
            ? String(value.prefix(18)) + "…"
            : value
    }
}
