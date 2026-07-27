import MeetingBuddyApplication
import SwiftUI

struct HistoricalIndexSearchView: View {
    let status: HistoricalIndexStatus?
    let job: MediaJobReview?
    let isLoading: Bool
    let failureMessage: String?
    let isWorking: Bool
    @Binding var actorOrCountry: String
    @Binding var topic: String
    @Binding var organizationOrBody: String
    @Binding var meetingType: String
    @Binding var startDate: String
    @Binding var endDate: String
    let reloadStatus: () -> Void
    let rebuildIndex: () -> Void
    let search: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                indexCard
                searchCard
            }
            VStack(alignment: .leading, spacing: 18) {
                indexCard
                searchCard
            }
        }
        .accessibilityIdentifier(
            "blueminutes.history.index-search"
        )
    }

    private var indexCard: some View {
        GroupBox("Meeting History Index") {
            VStack(alignment: .leading, spacing: 12) {
                indexStateView
                if let status {
                    Divider()
                    LabeledContent(
                        "Generation",
                        value: String(status.generation)
                    )
                    LabeledContent(
                        "Confirmed positions",
                        value:
                            String(status.indexedPositionCount)
                    )
                    if let fingerprint =
                        status.sourceFingerprint
                    {
                        LabeledContent(
                            "Source fingerprint",
                            value:
                                fingerprint.lowercaseHex
                        )
                        .textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Reload Status") {
                        reloadStatus()
                    }
                    .accessibilityIdentifier(
                        "blueminutes.history.reload-index"
                    )
                    .disabled(
                        isWorking
                            || (
                                job?.state.isTerminal == false
                                    && failureMessage == nil
                            )
                    )

                    Button("Rebuild Local Index") {
                        rebuildIndex()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "blueminutes.history.rebuild-index"
                    )
                    .disabled(
                        isWorking
                            || job?.state.isTerminal == false
                    )
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Meeting History local index"
        )
    }

    @ViewBuilder
    private var indexStateView: some View {
        switch HistoricalReviewPresentation.indexState(
            status: status,
            job: job,
            isLoading: isLoading,
            failureMessage: failureMessage
        ) {
        case .initial:
            WorkflowStateView(
                title: "Index status not loaded",
                detail:
                    "Load the current local index status before searching.",
                systemImage: "clock.badge.questionmark",
                tone: .neutral
            )
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView()
                Text("Loading the local index status…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Loading Meeting History local index status"
            )
        case let .rebuilding(
            state,
            completed,
            total
        ):
            WorkflowStateView(
                title: "Local index rebuild in progress",
                detail:
                    "\(label(state.rawValue)); \(completed) of \(total) confirmed position(s) indexed.",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .working
            )
        case .ready:
            WorkflowStateView(
                title: "Local index ready",
                detail:
                    "Searches use the current deterministic generation and recheck exact access policy before returning content or counts.",
                systemImage: "checkmark.circle",
                tone: .success
            )
        case .rebuildRequired:
            WorkflowStateView(
                title: "Local index rebuild required",
                detail:
                    "The rebuildable search projection is not current. Rebuild it before searching.",
                systemImage: "arrow.clockwise.circle",
                tone: .warning
            )
        case .disabled:
            WorkflowStateView(
                title: "Meeting History is disabled",
                detail:
                    "The current local policy does not allow the history index.",
                systemImage: "lock.shield",
                tone: .warning
            )
        case let .staleLastSuccess(message):
            WorkflowStateView(
                title:
                    "Last successful index status",
                detail:
                    "The cached metadata below is not current with the latest index-status operation or accepted search generation. \(message)",
                systemImage:
                    "exclamationmark.arrow.triangle.2.circlepath",
                tone: .warning
            )
        case let .failed(message):
            WorkflowStateView(
                title: "Local index status unavailable",
                detail: message,
                systemImage:
                    "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    private var searchCard: some View {
        GroupBox("Historical Context Search") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 12,
                    verticalSpacing: 10
                ) {
                    searchRow(
                        "Actor or country",
                        text: $actorOrCountry
                    )
                    searchRow(
                        "Topic or issue",
                        text: $topic
                    )
                    searchRow(
                        "Organization or body",
                        text: $organizationOrBody
                    )
                    searchRow(
                        "Meeting type",
                        text: $meetingType
                    )
                    searchRow(
                        "Start date",
                        text: $startDate,
                        prompt: "YYYY-MM-DD"
                    )
                    searchRow(
                        "End date",
                        text: $endDate,
                        prompt: "YYYY-MM-DD"
                    )
                }
            Button(
                "Search Confirmed Published History"
                ) {
                    search()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchUnavailableReason != nil)
                .accessibilityHint(
                    searchUnavailableReason
                        ?? "Searches only the current local generation and rechecks each exact access policy before returning content or counts."
                )
                .accessibilityIdentifier(
                    "blueminutes.history.search"
                )

                if let searchUnavailableReason {
                    Label(
                        searchUnavailableReason,
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Search unavailable: \(searchUnavailableReason)"
                    )
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var searchUnavailableReason: String? {
        HistoricalReviewPresentation
            .searchUnavailableReason(
                index: status,
                indexRebuildIsActive:
                    job?.state.isTerminal
                        == false,
                isWorking: isWorking
            )
    }

    private func searchRow(
        _ label: String,
        text: Binding<String>,
        prompt: String = "Optional"
    ) -> some View {
        GridRow {
            Text(label)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
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
