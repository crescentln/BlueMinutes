import Foundation
import MeetingBuddyDomain
import SwiftUI

struct HistoricalComparisonView: View {
    let comparison: HistoricalComparisonV1?
    let currentRevisionID: RevisionID?
    let previousRevisionID: RevisionID?
    let isWorking: Bool
    let resultsAreCurrent: Bool
    let compare: () -> Void
    let requestConfirmation: () -> Void

    var body: some View {
        GroupBox("Historical Comparison") {
            VStack(alignment: .leading, spacing: 14) {
                EditorialSectionHeader(
                    "Evidence-qualified comparison",
                    detail:
                        "Compare two exact published Position revisions without converting wording differences, silence, or group membership into a policy change."
                )

                HStack {
                    Button(
                        "Compare Selected Positions"
                    ) {
                        compare()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "blueminutes.history.compare"
                    )
                    .disabled(
                        comparisonUnavailableReason
                            != nil
                    )
                    .accessibilityHint(
                        comparisonUnavailableReason
                            ?? "Compare the selected exact current and previous revisions."
                    )
                    if let comparisonUnavailableReason {
                        Label(
                            comparisonUnavailableReason,
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let comparison {
                    comparisonContent(comparison)
                } else {
                    WorkflowStateView(
                        title: "No comparison result",
                        detail:
                            "Choose a current and previous result. Wording differences, silence, and group membership never establish a policy change.",
                        systemImage:
                            "arrow.left.arrow.right",
                        tone: .neutral
                    )
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .accessibilityIdentifier(
            "blueminutes.history.comparison"
        )
    }

    private var comparisonUnavailableReason: String? {
        HistoricalReviewPresentation
            .comparisonUnavailableReason(
                current: currentRevisionID,
                previous: previousRevisionID,
                isWorking: isWorking,
                resultsAreCurrent:
                    resultsAreCurrent
            )
    }

    @ViewBuilder
    private func comparisonContent(
        _ comparison: HistoricalComparisonV1
    ) -> some View {
        Divider()
        if !resultsAreCurrent {
            WorkflowStateView(
                title:
                    "Comparison belongs to the last successful result set",
                detail:
                    "Run a successful search for the current filters before creating or confirming another comparison.",
                systemImage:
                    "clock.badge.exclamationmark",
                tone: .warning
            )
        }
        if !comparisonMatchesSelection(
            comparison
        ) {
            WorkflowStateView(
                title:
                    "Comparison does not match the visible selection",
                detail:
                    "Compare the visible current and previous revisions again before confirmation.",
                systemImage:
                    "exclamationmark.triangle",
                tone: .warning
            )
        }
        WorkflowStateView(
            title: comparison.qualifiedSummary,
            detail:
                "Finding: \(label(comparison.finding.encodedValue)); difference state: \(label(comparison.differenceState.encodedValue)).",
            systemImage: comparison
                .differenceState == .possibleDifference
                ? "exclamationmark.bubble"
                : "checkmark.shield",
            tone: comparison
                .differenceState == .possibleDifference
                ? .warning
                : .success
        )

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                comparisonSide(
                    "Current",
                    date:
                        comparison.currentEffectiveDate,
                    timeRange:
                        comparison
                        .currentEffectiveTimeRange,
                    position:
                        comparison
                        .currentPositionRevision,
                    evidence:
                        comparison
                        .currentEvidenceRevisions,
                    confidence:
                        comparison.currentConfidence
                )
                comparisonSide(
                    "Previous",
                    date:
                        comparison
                        .historicalEffectiveDate,
                    timeRange:
                        comparison
                        .historicalEffectiveTimeRange,
                    position:
                        comparison
                        .historicalPositionRevision,
                    evidence:
                        comparison
                        .historicalEvidenceRevisions,
                    confidence:
                        comparison
                        .historicalConfidence
                )
            }
            VStack(alignment: .leading, spacing: 14) {
                comparisonSide(
                    "Current",
                    date:
                        comparison.currentEffectiveDate,
                    timeRange:
                        comparison
                        .currentEffectiveTimeRange,
                    position:
                        comparison
                        .currentPositionRevision,
                    evidence:
                        comparison
                        .currentEvidenceRevisions,
                    confidence:
                        comparison.currentConfidence
                )
                comparisonSide(
                    "Previous",
                    date:
                        comparison
                        .historicalEffectiveDate,
                    timeRange:
                        comparison
                        .historicalEffectiveTimeRange,
                    position:
                        comparison
                        .historicalPositionRevision,
                    evidence:
                        comparison
                        .historicalEvidenceRevisions,
                    confidence:
                        comparison
                        .historicalConfidence
                )
            }
        }

        if comparison.differenceState
            == .possibleDifference
        {
            Button("Confirm Possible Change…") {
                requestConfirmation()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(
                "blueminutes.history.confirm-change"
            )
            .disabled(
                isWorking
                    || !resultsAreCurrent
                    || !comparisonMatchesSelection(
                        comparison
                    )
            )
            .accessibilityHint(
                "Creates a superseding user-confirmed comparison; source positions remain immutable."
            )
        }
    }

    private func comparisonMatchesSelection(
        _ comparison: HistoricalComparisonV1
    ) -> Bool {
        HistoricalReviewPresentation
            .comparisonMatchesSelection(
                comparisonCurrentRevisionID:
                    comparison
                    .currentPositionRevision
                    .revisionID,
                comparisonPreviousRevisionID:
                    comparison
                    .historicalPositionRevision
                    .revisionID,
                selectedCurrentRevisionID:
                    currentRevisionID,
                selectedPreviousRevisionID:
                    previousRevisionID
            )
    }

    private func comparisonSide(
        _ title: String,
        date: CalendarDate?,
        timeRange: MediaTimeRange?,
        position: SemanticRevisionReference,
        evidence: [SemanticRevisionReference],
        confidence: ConfidenceScore
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
            Divider()
            LabeledContent(
                "Effective date",
                value:
                    HistoricalReviewPresentation
                    .dateLabel(date)
            )
            LabeledContent(
                "Position effective time",
                value:
                    HistoricalReviewPresentation
                    .timeRangeLabel(timeRange)
            )
            LabeledContent(
                "Position revision",
                value: position.revisionID
                    .canonicalString
            )
            LabeledContent(
                "Evidence revisions",
                value: evidence
                    .map(\.revisionID.canonicalString)
                    .joined(separator: ", ")
            )
            LabeledContent(
                "Confidence",
                value:
                    "\(confidence.millionths)/1,000,000"
            )
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title) evidence and exact revisions"
        )
    }

    private func label(
        _ value: String
    ) -> String {
        value.replacingOccurrences(
            of: "_",
            with: " "
        )
    }
}
