import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum StorageDashboardOperation:
    Equatable,
    Sendable
{
    case refreshing
    case restoring
    case deleting

    var progressLabel: String {
        switch self {
        case .refreshing:
            "Refreshing exact storage ledger"
        case .restoring:
            "Restoring from Workspace Trash"
        case .deleting:
            "Deleting from Workspace Trash"
        }
    }
}

enum StorageDashboardPresentationState:
    Equatable,
    Sendable
{
    case initial
    case loading(
        previous: WorkspaceStorageReport?
    )
    case ready(WorkspaceStorageReport)
    case degraded(WorkspaceStorageReport)
    case staleLastSuccess(
        WorkspaceStorageReport,
        message: String
    )
    case failed(message: String)

    var report: WorkspaceStorageReport? {
        switch self {
        case .initial, .failed:
            nil
        case let .loading(previous):
            previous
        case let .ready(report),
             let .degraded(report),
             let .staleLastSuccess(
                 report,
                 _
             ):
            report
        }
    }

    var allowsTrashMutations: Bool {
        switch self {
        case .ready, .degraded:
            true
        case .initial,
             .loading,
             .staleLastSuccess,
             .failed:
            false
        }
    }
}

enum StorageTrashMutationBlockReason:
    Equatable,
    Sendable
{
    case reportNotCurrent
    case operationInProgress
    case retentionActive(
        calculatedAt: UTCInstant,
        purgeEligibleAt: UTCInstant
    )
}

enum StorageDashboardPresentation {
    static func utcDateLabel(
        _ instant: UTCInstant,
        locale: Locale =
            .autoupdatingCurrent,
        calendar: Calendar =
            .autoupdatingCurrent
    ) -> String {
        let value = Date(
            timeIntervalSince1970:
                Double(
                    instant
                        .millisecondsSinceUnixEpoch
                ) / 1_000
        )
        var utcCalendar =
            calendar
        utcCalendar.locale =
            locale
        utcCalendar.timeZone =
            .gmt
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .standard,
            locale: locale,
            calendar:
                utcCalendar,
            timeZone: .gmt
        )
        return
            "\(value.formatted(style)) · \(instant.millisecondsSinceUnixEpoch) ms UTC"
    }

    static func state(
        report: WorkspaceStorageReport?,
        operation: StorageDashboardOperation?,
        failureMessage: String?
    ) -> StorageDashboardPresentationState {
        if operation == .refreshing {
            return .loading(previous: report)
        }
        if let failureMessage {
            if let report {
                return .staleLastSuccess(
                    report,
                    message: failureMessage
                )
            }
            return .failed(
                message: failureMessage
            )
        }
        guard let report else {
            return .initial
        }
        if report.scanTruncated
            || report.permissionIssueCount > 0
        {
            return .degraded(report)
        }
        return .ready(report)
    }

    static func mutationBlockReason(
        reportIsCurrent: Bool,
        isWorking: Bool
    ) -> StorageTrashMutationBlockReason? {
        guard reportIsCurrent else {
            return .reportNotCurrent
        }
        guard !isWorking else {
            return .operationInProgress
        }
        return nil
    }

    static func permanentDeletionBlockReason(
        item: WorkspaceTrashItem,
        report: WorkspaceStorageReport,
        reportIsCurrent: Bool,
        isWorking: Bool
    ) -> StorageTrashMutationBlockReason? {
        if let common = mutationBlockReason(
            reportIsCurrent:
                reportIsCurrent,
            isWorking: isWorking
        ) {
            return common
        }
        guard report.calculatedAt
            < item.purgeEligibleAt
        else { return nil }
        return .retentionActive(
            calculatedAt: report.calculatedAt,
            purgeEligibleAt:
                item.purgeEligibleAt
        )
    }
}
