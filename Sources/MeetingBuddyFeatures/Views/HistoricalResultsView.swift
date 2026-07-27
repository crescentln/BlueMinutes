import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct HistoricalResultsView: View {
    let page: HistoricalSearchPage?
    let isLoading: Bool
    let failureMessage: String?
    let pageStaleReason: String?
    let paginationFailureMessage:
        String?
    let lastSuccessfulFilter:
        HistoricalSearchFilterSnapshot?
    let currentFilter:
        HistoricalSearchFilterSnapshot
    let selectedCurrentRevisionID: RevisionID?
    let selectedPreviousRevisionID: RevisionID?
    let isLoadingNextPage: Bool
    let canSelectResults: Bool
    let canLoadNextPage: Bool
    let selectCurrent: (RevisionID) -> Void
    let selectPrevious: (RevisionID) -> Void
    let loadNextPage: () -> Void

    var body: some View {
        let state =
            HistoricalReviewPresentation.searchState(
                page: page,
                isLoading: isLoading,
                searchFailureMessage:
                    failureMessage,
                pageStaleReason:
                    pageStaleReason,
                lastSuccessfulFilter:
                    lastSuccessfulFilter,
                currentFilter: currentFilter
            )
        GroupBox("Confirmed Published Results") {
            VStack(alignment: .leading, spacing: 14) {
                stateHeader(state)
                if showsResultRows(state),
                   let page
                {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(page.results) { result in
                            resultRow(result)
                        }
                    }
                    if page.nextCursor != nil {
                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            if let paginationFailureMessage {
                                Label(
                                    "The next page did not load. The accepted results above remain current. \(paginationFailureMessage)",
                                    systemImage:
                                        "exclamationmark.arrow.triangle.2.circlepath"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .accessibilityIdentifier(
                                    "blueminutes.history.pagination-error"
                                )
                            }
                            HStack(spacing: 10) {
                                if isLoadingNextPage {
                                    ProgressView()
                                        .controlSize(
                                            .small
                                        )
                                }
                                Button(
                                    isLoadingNextPage
                                        ? "Loading More…"
                                        : paginationFailureMessage
                                            == nil
                                            ? "Load More"
                                            : "Retry Load More"
                                ) {
                                    loadNextPage()
                                }
                                .disabled(
                                    !canLoadNextPage
                                        || isLoadingNextPage
                                )
                                .accessibilityIdentifier(
                                    "blueminutes.history.load-more"
                                )
                                .accessibilityHint(
                                    "Loads the next generation-bound page using the unchanged deterministic filters."
                                )
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .accessibilityIdentifier(
            "blueminutes.history.results"
        )
    }

    @ViewBuilder
    private func stateHeader(
        _ state: HistoricalSearchPresentationState
    ) -> some View {
        switch state {
        case .initial:
            WorkflowStateView(
                title: "No history search has run",
                detail:
                    "Choose optional deterministic filters, then search confirmed published positions.",
                systemImage: "magnifyingglass",
                tone: .neutral
            )
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(
                    "Searching the current authorized local generation…"
                )
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Searching confirmed published history"
            )
        case let .failure(message):
            WorkflowStateView(
                title: "History search did not complete",
                detail: message,
                systemImage:
                    "exclamationmark.triangle",
                tone: .failure
            )
        case let .empty(generation):
            ContentUnavailableView(
                "No Authorized History Results",
                systemImage:
                    "clock.badge.questionmark",
                description: Text(
                    "Generation \(generation) returned no matches for the current deterministic filters. Unauthorized records are not included in content, counts, or facets."
                )
            )
        case let .staleResults(
            count,
            generation,
            reason
        ):
            WorkflowStateView(
                title:
                    "Last successful results are not current",
                detail:
                    "\(count) result(s) from local index generation \(generation). \(reason)",
                systemImage: "clock.badge.exclamationmark",
                tone: .warning
            )
        case let .results(
            count,
            generation,
            hasNextPage
        ):
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "\(count) authorized result(s)"
                )
                .font(.headline)
                Text(
                    "Local index generation \(generation). Each result was rechecked against its exact access policy."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if hasNextPage {
                    Text(
                        "Additional authorized matches are available in the next generation-bound page."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func showsResultRows(
        _ state: HistoricalSearchPresentationState
    ) -> Bool {
        switch state {
        case .results, .staleResults:
            true
        case .initial, .loading, .failure, .empty:
            false
        }
    }

    private func resultRow(
        _ result: HistoricalPositionResult
    ) -> some View {
        let revisionID =
            result.position.revision.revisionID
        let isCurrent =
            selectedCurrentRevisionID == revisionID
        let isPrevious =
            selectedPreviousRevisionID == revisionID
        let dateLabel =
            HistoricalReviewPresentation.dateLabel(
                result.meeting.meetingDate
            )
        let evidenceLabel =
            String(result.evidence.count)
                + " exact revision(s)"
        let confidenceLabel =
            String(
                result.position.statement
                    .confidence.millionths
            )
                + "/1,000,000"
        let classificationLabel =
            result.effectiveClassification.encodedValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.actor.displayName)
                        .font(.headline)
                    Text(result.issue.title.text)
                        .font(
                            .subheadline.weight(.semibold)
                        )
                }
                Spacer()
                Text(dateLabel)
                .foregroundStyle(.secondary)
            }

            Text(result.position.statement.text)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

            HStack(spacing: 8) {
                if isCurrent {
                    Label(
                        "Selected as Current",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
                if isPrevious {
                    Label(
                        "Selected as Previous",
                        systemImage:
                            "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use as Current") {
                    selectCurrent(revisionID)
                }
                .disabled(!canSelectResults)
                .accessibilityLabel(
                    "Use \(result.actor.displayName) at \(dateLabel) as current position"
                )
                .accessibilityHint(
                    canSelectResults
                        ? "Selects this exact revision as the current position."
                        : "Run a successful search for the current filters before changing the comparison selection."
                )
                .accessibilityIdentifier(
                    selectionIdentifier(
                        revisionID,
                        role: "current"
                    )
                )
                Button("Use as Previous") {
                    selectPrevious(revisionID)
                }
                .disabled(!canSelectResults)
                .accessibilityLabel(
                    "Use \(result.actor.displayName) at \(dateLabel) as previous position"
                )
                .accessibilityHint(
                    canSelectResults
                        ? "Selects this exact revision as the previous position."
                        : "Run a successful search for the current filters before changing the comparison selection."
                )
                .accessibilityIdentifier(
                    selectionIdentifier(
                        revisionID,
                        role: "previous"
                    )
                )
            }

            Divider()
            Grid(
                alignment: .leading,
                horizontalSpacing: 10,
                verticalSpacing: 4
            ) {
                metadataRow(
                    "Position revision",
                    value: revisionID.canonicalString
                )
                metadataRow(
                    "Evidence",
                    value: evidenceLabel
                )
                metadataRow(
                    "Confidence",
                    value: confidenceLabel
                )
                metadataRow(
                    "Classification",
                    value: classificationLabel
                )
            }
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isCurrent || isPrevious
                        ? Color.accentColor
                            .opacity(0.08)
                        : Color.primary.opacity(0.025)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isCurrent || isPrevious
                        ? Color.accentColor
                            .opacity(0.55)
                        : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            resultAccessibilityLabel(
                result,
                isCurrent: isCurrent,
                isPrevious: isPrevious
            )
        )
    }

    private func metadataRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func resultAccessibilityLabel(
        _ result: HistoricalPositionResult,
        isCurrent: Bool,
        isPrevious: Bool
    ) -> String {
        var states: [String] = []
        if isCurrent {
            states.append("selected as current")
        }
        if isPrevious {
            states.append("selected as previous")
        }
        let selection = states.isEmpty
            ? "not selected for comparison"
            : states.joined(separator: " and ")
        return
            "\(result.actor.displayName), \(result.issue.title.text), \(selection)"
    }

    private func selectionIdentifier(
        _ revisionID: RevisionID,
        role: String
    ) -> String {
        "blueminutes.history.result."
            + revisionID.canonicalString
            + ".use-"
            + role
    }
}
