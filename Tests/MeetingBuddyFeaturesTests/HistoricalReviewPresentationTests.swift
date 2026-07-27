import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct HistoricalReviewPresentationTests {
    @Test
    func indexInitialLoadingAndPolicyStatesStayDistinct() {
        #expect(
            HistoricalReviewPresentation.indexState(
                status: nil,
                job: nil,
                isLoading: false,
                failureMessage: nil
            ) == .initial
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: nil,
                job: nil,
                isLoading: true,
                failureMessage: nil
            ) == .loading
        )

        #expect(
            HistoricalReviewPresentation.indexState(
                status: status(.ready),
                job: nil,
                isLoading: false,
                failureMessage: nil
            ) == .ready
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: status(.rebuildRequired),
                job: nil,
                isLoading: false,
                failureMessage: nil
            ) == .rebuildRequired
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: status(.disabled),
                job: nil,
                isLoading: false,
                failureMessage: nil
            ) == .disabled
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: status(.ready),
                job: nil,
                isLoading: true,
                failureMessage:
                    "Synthetic failure."
            ) == .loading
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: status(.ready),
                job: nil,
                isLoading: false,
                failureMessage:
                    "Synthetic failure."
            ) == .staleLastSuccess(
                "Synthetic failure."
            )
        )
        #expect(
            HistoricalReviewPresentation.indexState(
                status: nil,
                job: nil,
                isLoading: false,
                failureMessage:
                    "Synthetic failure."
            ) == .failed("Synthetic failure.")
        )
    }

    @Test
    @MainActor
    func searchInitialLoadingEmptyFailureAndStaleRemainDifferent() {
        let current = HistoricalSearchFilterSnapshot(
            sceneState: MediaReviewSceneState()
        )
        let empty = HistoricalSearchPage(
            results: [],
            nextCursor: nil,
            indexGeneration: 7
        )

        #expect(
            HistoricalReviewPresentation.searchState(
                page: nil,
                isLoading: false,
                searchFailureMessage: nil,
                pageStaleReason: nil,
                lastSuccessfulFilter: nil,
                currentFilter: current
            ) == .initial
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: nil,
                isLoading: true,
                searchFailureMessage: nil,
                pageStaleReason: nil,
                lastSuccessfulFilter: nil,
                currentFilter: current
            ) == .loading
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: empty,
                isLoading: false,
                searchFailureMessage: nil,
                pageStaleReason: nil,
                lastSuccessfulFilter: current,
                currentFilter: current
            ) == .empty(generation: 7)
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: nil,
                isLoading: false,
                searchFailureMessage:
                    "Synthetic local failure.",
                pageStaleReason: nil,
                lastSuccessfulFilter: nil,
                currentFilter: current
            ) == .failure(
                "Synthetic local failure."
            )
        )

        let changed = HistoricalSearchFilterSnapshot(
            actorOrCountry: "Synthetic actor",
            topic: "",
            organizationOrBody: "",
            meetingType: "",
            startDate: "",
            endDate: ""
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: empty,
                isLoading: false,
                searchFailureMessage: nil,
                pageStaleReason: nil,
                lastSuccessfulFilter: current,
                currentFilter: changed
            ) == .staleResults(
                count: 0,
                generation: 7,
                reason:
                    "The filters changed after this bounded result page was loaded. Search again before treating it as current."
            )
        )
        #expect(
            HistoricalReviewPresentation.searchState(
                page: empty,
                isLoading: false,
                searchFailureMessage:
                    "A separate operation failed.",
                pageStaleReason:
                    "The accepted page is stale for a precise reason.",
                lastSuccessfulFilter: current,
                currentFilter: current
            ) == .staleResults(
                count: 0,
                generation: 7,
                reason:
                    "The accepted page is stale for a precise reason."
            )
        )
    }

    @Test
    func unavailableReasonsNameTheSmallestRealRemedy() {
        #expect(
            HistoricalReviewPresentation
                .searchUnavailableReason(
                    index: nil,
                    indexRebuildIsActive: false,
                    isWorking: false
                )
                == "Load the local index status before searching."
        )
        #expect(
            HistoricalReviewPresentation
                .searchUnavailableReason(
                    index: status(.rebuildRequired),
                    indexRebuildIsActive: false,
                    isWorking: false
                )
                == "Rebuild the local index before searching."
        )
        #expect(
            HistoricalReviewPresentation
                .searchUnavailableReason(
                    index: status(.ready),
                    indexRebuildIsActive: false,
                    isWorking: false
                ) == nil
        )
        #expect(
            HistoricalReviewPresentation
                .searchUnavailableReason(
                    index: status(.ready),
                    indexRebuildIsActive: true,
                    isWorking: false
                )
                == "Wait for the local index rebuild to finish before searching."
        )

        let revisionID = RevisionID(UUID())
        let previousRevisionID =
            RevisionID(UUID())
        #expect(
            HistoricalReviewPresentation
                .comparisonUnavailableReason(
                    current: revisionID,
                    previous: revisionID,
                    isWorking: false,
                    resultsAreCurrent: true
                )
                == "Current and previous must be different revisions."
        )
        #expect(
            HistoricalReviewPresentation
                .comparisonMatchesSelection(
                    comparisonCurrentRevisionID:
                        revisionID,
                    comparisonPreviousRevisionID:
                        previousRevisionID,
                    selectedCurrentRevisionID:
                        revisionID,
                    selectedPreviousRevisionID:
                        previousRevisionID
                )
        )
        #expect(
            !HistoricalReviewPresentation
                .comparisonMatchesSelection(
                    comparisonCurrentRevisionID:
                        revisionID,
                    comparisonPreviousRevisionID:
                        previousRevisionID,
                    selectedCurrentRevisionID:
                        previousRevisionID,
                    selectedPreviousRevisionID:
                        previousRevisionID
                )
        )
    }

    @Test @MainActor
    func dedicatedPreferenceEditorRetainsSceneCompatibilityAndResets() {
        let sceneState = MediaReviewSceneState()
        sceneState.learnedPreferenceKind = .grouping
        sceneState.learnedPreferenceValue =
            "chronological"
        sceneState.confirmPreferenceReset = true

        #expect(
            sceneState.learnedPreferenceEditor.kind
                == .grouping
        )
        #expect(
            sceneState.learnedPreferenceEditor.value
                == "chronological"
        )
        #expect(
            sceneState.learnedPreferenceEditor
                .isResetConfirmationPresented
        )

        sceneState.learnedPreferenceEditor.reset()
        #expect(
            sceneState.learnedPreferenceKind
                == .briefingLength
        )
        #expect(sceneState.learnedPreferenceValue.isEmpty)
        #expect(!sceneState.confirmPreferenceReset)
    }

    private func status(
        _ availability: HistoricalIndexAvailability
    ) -> HistoricalIndexStatus {
        HistoricalIndexStatus(
            availability: availability,
            generation: 7,
            normalizerVersion: 1,
            indexedPositionCount: 0,
            rebuiltAt: nil,
            sourceFingerprint: nil
        )
    }
}
