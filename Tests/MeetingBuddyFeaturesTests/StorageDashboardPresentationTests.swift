import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct StorageDashboardPresentationTests {
    @Test
    func utcDateLabelUsesUTCIndependentlyOfTheProcessTimeZone()
        throws
    {
        let instant = try UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_000_000
        )

        let label =
            StorageDashboardPresentation
            .utcDateLabel(
                instant,
                locale:
                    Locale(
                        identifier:
                            "en_US_POSIX"
                    ),
                calendar:
                    Calendar(
                        identifier:
                            .gregorian
                    )
            )

        #expect(
            label.contains(
                "Oct 17, 2031"
            )
        )
        #expect(
            label.contains(
                "10:40:00"
            )
        )
        #expect(
            label.hasSuffix(
                "1950000000000 ms UTC"
            )
        )
    }

    @Test
    func utcDateLabelPreservesTheRequestedUserLocale()
        throws
    {
        let instant = try UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_000_000
        )
        let calendar =
            Calendar(
                identifier:
                    .gregorian
            )
        let english =
            StorageDashboardPresentation
            .utcDateLabel(
                instant,
                locale:
                    Locale(
                        identifier:
                            "en_US_POSIX"
                    ),
                calendar: calendar
            )
        let french =
            StorageDashboardPresentation
            .utcDateLabel(
                instant,
                locale:
                    Locale(
                        identifier:
                            "fr_FR"
                    ),
                calendar: calendar
            )

        #expect(english != french)
        #expect(
            english.hasSuffix(
                "1950000000000 ms UTC"
            )
        )
        #expect(
            french.hasSuffix(
                "1950000000000 ms UTC"
            )
        )
    }

    @Test
    func initialLoadingReadyAndDegradedStatesStayDistinct()
        throws
    {
        let clean = try report()
        let permissionDegraded = try report(
            permissionIssueCount: 2
        )
        let truncated = try report(
            scanTruncated: true
        )

        #expect(
            StorageDashboardPresentation.state(
                report: nil,
                operation: nil,
                failureMessage: nil
            ) == .initial
        )
        #expect(
            StorageDashboardPresentation.state(
                report: nil,
                operation: .refreshing,
                failureMessage: nil
            ) == .loading(previous: nil)
        )
        #expect(
            StorageDashboardPresentation.state(
                report: clean,
                operation: .refreshing,
                failureMessage: nil
            ) == .loading(previous: clean)
        )
        #expect(
            StorageDashboardPresentation.state(
                report: clean,
                operation: nil,
                failureMessage: nil
            ) == .ready(clean)
        )
        #expect(
            StorageDashboardPresentation.state(
                report: permissionDegraded,
                operation: nil,
                failureMessage: nil
            ) == .degraded(
                permissionDegraded
            )
        )
        #expect(
            StorageDashboardPresentation.state(
                report: truncated,
                operation: nil,
                failureMessage: nil
            ) == .degraded(truncated)
        )
    }

    @Test
    func failureWithoutAReportAndStaleLastSuccessRemainDifferent()
        throws
    {
        let clean = try report()
        let failure =
            "Synthetic bounded storage failure."

        #expect(
            StorageDashboardPresentation.state(
                report: nil,
                operation: nil,
                failureMessage: failure
            ) == .failed(message: failure)
        )
        #expect(
            StorageDashboardPresentation.state(
                report: clean,
                operation: nil,
                failureMessage: failure
            ) == .staleLastSuccess(
                clean,
                message: failure
            )
        )
    }

    @Test
    func onlyCurrentReportsAllowTrashMutations()
        throws
    {
        let clean = try report()
        let degraded = try report(
            permissionIssueCount: 1
        )
        let currentStates:
            [StorageDashboardPresentationState] = [
                .ready(clean),
                .degraded(degraded)
            ]
        let readOnlyStates:
            [StorageDashboardPresentationState] = [
                .initial,
                .loading(previous: clean),
                .staleLastSuccess(
                    clean,
                    message: "Synthetic failure."
                ),
                .failed(
                    message: "Synthetic failure."
                )
            ]

        #expect(
            currentStates.allSatisfy {
                $0.allowsTrashMutations
            }
        )
        #expect(
            readOnlyStates.allSatisfy {
                !$0.allowsTrashMutations
            }
        )
    }

    @Test
    func storageOperationLabelsNameTheExactMutation()
    {
        #expect(
            StorageDashboardOperation
                .refreshing.progressLabel
                == "Refreshing exact storage ledger"
        )
        #expect(
            StorageDashboardOperation
                .restoring.progressLabel
                == "Restoring from Workspace Trash"
        )
        #expect(
            StorageDashboardOperation
                .deleting.progressLabel
                == "Deleting from Workspace Trash"
        )
    }

    @Test
    func trashMutationBlocksStaleBusyAndRetentionStatesExactly()
        throws
    {
        let calculatedAt = try UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_000_000
        )
        let purgeEligibleAt = try UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_001_000
        )
        let retainedItem = WorkspaceTrashItem(
            storageObjectID:
                StorageObjectID(UUID()),
            byteSize: 128,
            trashedAt: calculatedAt,
            purgeEligibleAt:
                purgeEligibleAt,
            dataClassification: .sensitive,
            retentionClass: .workspaceManaged
        )
        let currentReport = try report(
            calculatedAt: calculatedAt,
            trashItems: [retainedItem]
        )

        #expect(
            StorageDashboardPresentation
                .mutationBlockReason(
                    reportIsCurrent: false,
                    isWorking: false
                ) == .reportNotCurrent
        )
        #expect(
            StorageDashboardPresentation
                .mutationBlockReason(
                    reportIsCurrent: true,
                    isWorking: true
                ) == .operationInProgress
        )
        #expect(
            StorageDashboardPresentation
                .permanentDeletionBlockReason(
                    item: retainedItem,
                    report: currentReport,
                    reportIsCurrent: true,
                    isWorking: false
                ) == .retentionActive(
                    calculatedAt: calculatedAt,
                    purgeEligibleAt:
                        purgeEligibleAt
                )
        )

        let eligibleItem = WorkspaceTrashItem(
            storageObjectID:
                retainedItem.storageObjectID,
            byteSize: retainedItem.byteSize,
            trashedAt: retainedItem.trashedAt,
            purgeEligibleAt:
                calculatedAt,
            dataClassification:
                retainedItem
                .dataClassification,
            retentionClass:
                retainedItem.retentionClass
        )
        #expect(
            StorageDashboardPresentation
                .permanentDeletionBlockReason(
                    item: eligibleItem,
                    report: currentReport,
                    reportIsCurrent: true,
                    isWorking: false
                ) == nil
        )
    }

    private func report(
        calculatedAt: UTCInstant? = nil,
        trashItems: [WorkspaceTrashItem] = [],
        permissionIssueCount: UInt64 = 0,
        scanTruncated: Bool = false
    ) throws -> WorkspaceStorageReport {
        let resolvedCalculatedAt: UTCInstant
        if let calculatedAt {
            resolvedCalculatedAt =
                calculatedAt
        } else {
            resolvedCalculatedAt =
                try UTCInstant(
                    millisecondsSinceUnixEpoch:
                        1_950_000_000_000
                )
        }
        return try WorkspaceStorageReport(
            calculatedAt:
                resolvedCalculatedAt,
            totalByteCount: 128,
            categories: [
                WorkspaceStorageCategoryUsage(
                    category: .trash,
                    byteCount: 128,
                    fileCount: 1
                )
            ],
            trashItems: trashItems,
            permissionIssueCount:
                permissionIssueCount,
            scanTruncated: scanTruncated
        )
    }
}
