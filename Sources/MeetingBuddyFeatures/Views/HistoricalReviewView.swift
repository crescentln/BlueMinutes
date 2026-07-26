import SwiftUI

struct HistoricalReviewView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorialSectionHeader(
                    "Meeting History",
                    detail:
                        "Search confirmed published Positions in the current local index, then compare exact evidence-qualified revisions."
                )
                HistoricalIndexSearchView(
                    status: store.historicalIndex,
                    job: store.historicalIndexJob,
                    isLoading:
                        store
                        .historicalReviewIsLoading,
                    failureMessage:
                        store
                        .historicalIndexFailureMessage,
                    isWorking: store.isWorking,
                    actorOrCountry:
                        $sceneState
                        .historyActorOrCountry,
                    topic: $sceneState.historyTopic,
                    organizationOrBody:
                        $sceneState.historyBody,
                    meetingType:
                        $sceneState
                        .historyMeetingType,
                    startDate:
                        $sceneState.historyStartDate,
                    endDate:
                        $sceneState.historyEndDate,
                    reloadStatus: {
                        Task {
                            await store
                                .loadHistoricalReview(
                                    using: sceneState
                                )
                        }
                    },
                    rebuildIndex: {
                        Task {
                            await store
                                .rebuildHistoricalIndex(
                                    using: sceneState
                                )
                        }
                    },
                    search: {
                        Task {
                            await store
                                .searchMeetingHistory(
                                    using: sceneState
                                )
                        }
                    }
                )
                HistoricalResultsView(
                    page: store.historicalSearchPage,
                    isLoading:
                        store
                        .historicalSearchIsLoading,
                    failureMessage:
                        store
                        .historicalSearchFailureMessage
                        ?? store
                        .historicalIndexFailureMessage,
                    lastSuccessfulFilter:
                        store
                        .historicalSearchFilterSnapshot,
                    currentFilter: currentFilter,
                    selectedCurrentRevisionID:
                        sceneState
                        .selectedCurrentHistoryRevisionID,
                    selectedPreviousRevisionID:
                        sceneState
                        .selectedPriorHistoryRevisionID,
                    selectCurrent: {
                        store
                            .selectHistoricalCurrentRevision(
                                $0,
                                using: sceneState
                            )
                    },
                    selectPrevious: {
                        store
                            .selectHistoricalPreviousRevision(
                                $0,
                                using: sceneState
                            )
                    }
                )
                HistoricalComparisonView(
                    comparison:
                        store.historicalComparison,
                    currentRevisionID:
                        sceneState
                        .selectedCurrentHistoryRevisionID,
                    previousRevisionID:
                        sceneState
                        .selectedPriorHistoryRevisionID,
                    isWorking: store.isWorking,
                    resultsAreCurrent:
                        historicalResultsAreCurrent,
                    compare: {
                        Task {
                            await store
                                .compareSelectedHistoricalPositions(
                                    using: sceneState
                                )
                        }
                    },
                    requestConfirmation: {
                        sceneState
                            .confirmHistoricalChange = true
                    }
                )
            }
            .padding(24)
            .frame(
                maxWidth: 1_100,
                alignment: .leading
            )
        }
        .confirmationDialog(
            "Confirm this possible historical change?",
            isPresented:
                $sceneState.confirmHistoricalChange,
            titleVisibility: .visible
        ) {
            Button(
                "Confirm Evidence-Linked Change"
            ) {
                Task {
                    await store
                        .confirmHistoricalChange(
                            using: sceneState
                        )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This creates a new immutable user-authored revision. It does not modify either source position."
            )
        }
    }

    private var currentFilter:
        HistoricalSearchFilterSnapshot
    {
        HistoricalSearchFilterSnapshot(
            sceneState: sceneState
        )
    }

    private var historicalResultsAreCurrent:
        Bool
    {
        store.historicalSearchPage != nil
            && store
            .historicalSearchFailureMessage == nil
            && store
            .historicalIndexFailureMessage == nil
            && store
            .historicalSearchFilterSnapshot
                == currentFilter
    }
}
