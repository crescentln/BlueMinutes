import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum HistoricalIndexPresentationState: Equatable {
    case initial
    case loading
    case rebuilding(JobState, completed: UInt64, total: UInt64)
    case ready
    case rebuildRequired
    case disabled
    case staleLastSuccess(String)
    case failed(String)
}

enum HistoricalSearchPresentationState: Equatable {
    case initial
    case loading
    case failure(String)
    case empty(generation: UInt64)
    case staleResults(
        count: Int,
        generation: UInt64,
        reason: String
    )
    case results(
        count: Int,
        generation: UInt64,
        hasNextPage: Bool
    )
}

struct HistoricalSearchFilterSnapshot:
    Equatable,
    Sendable
{
    let actorOrCountry: String
    let topic: String
    let organizationOrBody: String
    let meetingType: String
    let startDate: String
    let endDate: String

    init(
        actorOrCountry: String,
        topic: String,
        organizationOrBody: String,
        meetingType: String,
        startDate: String,
        endDate: String
    ) {
        self.actorOrCountry = actorOrCountry
        self.topic = topic
        self.organizationOrBody =
            organizationOrBody
        self.meetingType = meetingType
        self.startDate = startDate
        self.endDate = endDate
    }

    @MainActor
    init(sceneState: MediaReviewSceneState) {
        self.init(
            actorOrCountry:
                sceneState.historyActorOrCountry,
            topic: sceneState.historyTopic,
            organizationOrBody:
                sceneState.historyBody,
            meetingType:
                sceneState.historyMeetingType,
            startDate:
                sceneState.historyStartDate,
            endDate: sceneState.historyEndDate
        )
    }
}

enum HistoricalSearchPageFreshness:
    Equatable,
    Sendable
{
    case current
    case stale(reason: String)

    var staleReason: String? {
        switch self {
        case .current:
            nil
        case let .stale(reason):
            reason
        }
    }
}

struct HistoricalSearchResultBundle:
    Equatable,
    Sendable
{
    var page: HistoricalSearchPage
    let filter: HistoricalSearchFilterSnapshot
    let workspaceSession: UInt64
    var freshness: HistoricalSearchPageFreshness
    var selectedCurrentRevisionID: RevisionID?
    var selectedPreviousRevisionID: RevisionID?
    var comparison: HistoricalComparisonV1?
    var paginationFailureMessage: String?
}

enum HistoricalReviewPresentation {
    static func indexState(
        status: HistoricalIndexStatus?,
        job: MediaJobReview?,
        isLoading: Bool,
        failureMessage: String?
    ) -> HistoricalIndexPresentationState {
        if let job {
            switch job.state {
            case .queued, .running, .pauseRequested,
                 .paused, .cancellationRequested:
                if let failureMessage {
                    return status == nil
                        ? .failed(failureMessage)
                        : .staleLastSuccess(
                            failureMessage
                        )
                }
                return .rebuilding(
                    job.state,
                    completed: job.completedUnitCount,
                    total: job.totalUnitCount
                )
            case .failed, .cancelled, .interrupted:
                return .failed(
                    job.safeFailureSummary
                        ?? "The local index rebuild did not complete."
                )
            case .succeeded:
                break
            }
        }

        if isLoading {
            return .loading
        }
        if let failureMessage {
            return status == nil
                ? .failed(failureMessage)
                : .staleLastSuccess(failureMessage)
        }
        guard let status else {
            return .initial
        }
        switch status.availability {
        case .ready:
            return .ready
        case .rebuildRequired:
            return .rebuildRequired
        case .disabled:
            return .disabled
        }
    }

    static func searchState(
        page: HistoricalSearchPage?,
        isLoading: Bool,
        searchFailureMessage: String?,
        pageStaleReason: String?,
        lastSuccessfulFilter:
            HistoricalSearchFilterSnapshot?,
        currentFilter:
            HistoricalSearchFilterSnapshot
    ) -> HistoricalSearchPresentationState {
        if isLoading {
            return .loading
        }
        guard let page else {
            if let searchFailureMessage {
                return .failure(
                    searchFailureMessage
                )
            }
            return .initial
        }
        if let pageStaleReason {
            return .staleResults(
                count: page.results.count,
                generation: page.indexGeneration,
                reason: pageStaleReason
            )
        }
        if lastSuccessfulFilter != currentFilter {
            return .staleResults(
                count: page.results.count,
                generation: page.indexGeneration,
                reason:
                    "The filters changed after this bounded result page was loaded. Search again before treating it as current."
            )
        }
        if page.results.isEmpty {
            return .empty(
                generation: page.indexGeneration
            )
        }
        return .results(
            count: page.results.count,
            generation: page.indexGeneration,
            hasNextPage: page.nextCursor != nil
        )
    }

    static func searchUnavailableReason(
        index: HistoricalIndexStatus?,
        indexRebuildIsActive: Bool,
        isWorking: Bool
    ) -> String? {
        if isWorking {
            return "Wait for the current local operation to finish."
        }
        if indexRebuildIsActive {
            return "Wait for the local index rebuild to finish before searching."
        }
        guard let index else {
            return "Load the local index status before searching."
        }
        switch index.availability {
        case .ready:
            return nil
        case .rebuildRequired:
            return "Rebuild the local index before searching."
        case .disabled:
            return "Meeting History is disabled by the current local policy."
        }
    }

    static func comparisonUnavailableReason(
        current: RevisionID?,
        previous: RevisionID?,
        isWorking: Bool,
        resultsAreCurrent: Bool
    ) -> String? {
        if isWorking {
            return "Wait for the current local operation to finish."
        }
        if !resultsAreCurrent {
            return "Run a successful search for the current filters before comparing positions."
        }
        guard current != nil, previous != nil else {
            return "Choose one current and one previous position."
        }
        guard current != previous else {
            return "Current and previous must be different revisions."
        }
        return nil
    }

    static func comparisonMatchesSelection(
        comparisonCurrentRevisionID:
            RevisionID,
        comparisonPreviousRevisionID:
            RevisionID,
        selectedCurrentRevisionID:
            RevisionID?,
        selectedPreviousRevisionID:
            RevisionID?
    ) -> Bool {
        comparisonCurrentRevisionID
            == selectedCurrentRevisionID
            && comparisonPreviousRevisionID
            == selectedPreviousRevisionID
    }

    static func dateLabel(
        _ date: CalendarDate?
    ) -> String {
        guard let date else {
            return "Unknown effective date"
        }
        return String(
            format: "%04d-%02d-%02d",
            Int(date.year),
            Int(date.month),
            Int(date.day)
        )
    }

    static func timeRangeLabel(
        _ range: MediaTimeRange?
    ) -> String {
        guard let range else {
            return "No media-relative time range"
        }
        return
            "\(range.startMilliseconds)–\(range.endMilliseconds) ms"
    }
}

enum LearnedPreferencePresentation {
    static func label(
        _ kind: LearnedPreferenceKind
    ) -> String {
        switch kind {
        case .actorCountryOrder:
            "Actor and country order"
        case .briefingLength:
            "Briefing length"
        case .sectionOrder:
            "Section order"
        case .quotationPolicy:
            "Quotation policy"
        case .grouping:
            "Grouping"
        case .terminology:
            "Terminology"
        case .frequentTemplates:
            "Frequent templates"
        }
    }

    static func prompt(
        _ kind: LearnedPreferenceKind
    ) -> String {
        switch kind {
        case .actorCountryOrder:
            "Comma-separated actor or country labels"
        case .briefingLength:
            "Word limit, 100–20000"
        case .sectionOrder:
            "Comma-separated stable section identifiers"
        case .quotationPolicy:
            "exact_only, exact_with_translation, or paraphrase_with_evidence"
        case .grouping:
            "by_actor, by_issue, or chronological"
        case .terminology:
            "Comma-separated source=display mappings"
        case .frequentTemplates:
            "Comma-separated template UUIDs"
        }
    }
}
