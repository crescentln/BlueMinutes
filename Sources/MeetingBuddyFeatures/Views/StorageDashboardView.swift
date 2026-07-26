import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct StorageDashboardView: View {
    @Bindable var store: MediaReviewStore
    let requestPermanentDeletion:
        (WorkspaceTrashItem) -> Void

    private var presentationState:
        StorageDashboardPresentationState
    {
        StorageDashboardPresentation.state(
            report: store.storageReport,
            operation: store.storageOperation,
            failureMessage:
                store.storageFailureMessage
        )
    }

    var body: some View {
        let state = presentationState
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stateSummary(state)
                if let operation = store.storageOperation,
                   operation != .refreshing
                {
                    WorkflowStateView(
                        title:
                            operation.progressLabel,
                        detail:
                            "The current report remains visible and read-only until the Storage Service returns a replacement snapshot.",
                        systemImage:
                            "arrow.triangle.2.circlepath",
                        tone: .working
                    )
                }
                if let report = state.report {
                    usageLedger(report)
                    integrityLedger(report)
                    trashLedger(
                        report,
                        allowsMutations:
                            state
                            .allowsTrashMutations
                    )
                }
                deletionBoundary
            }
            .padding(28)
            .frame(
                maxWidth: 980,
                alignment: .leading
            )
        }
        .accessibilityIdentifier(
            "blueminutes.storage.dashboard"
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Workspace Storage",
                detail:
                    "Review an exact, bounded local usage ledger and manage only verified opaque Workspace Trash objects."
            )
            HStack(alignment: .firstTextBaseline) {
                Label(
                    "Filenames, sensitive paths, and meeting content are never displayed.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh Exact Ledger") {
                    Task {
                        await store
                            .loadStorageReport()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isWorking)
                .accessibilityIdentifier(
                    "blueminutes.storage.refresh"
                )
                .accessibilityHint(
                    "Recalculate bounded local workspace storage usage without sending data anywhere."
                )
            }
        }
    }

    @ViewBuilder
    private func stateSummary(
        _ state:
            StorageDashboardPresentationState
    ) -> some View {
        switch state {
        case .initial:
            WorkflowStateView(
                title:
                    "Storage ledger not loaded",
                detail:
                    "Refresh to calculate a bounded local snapshot before reviewing usage or changing Workspace Trash.",
                systemImage:
                    "externaldrive.badge.questionmark",
                tone: .neutral
            )
            .accessibilityIdentifier(
                "blueminutes.storage.state.initial"
            )
        case let .loading(previous):
            if let previous {
                WorkflowStateView(
                    title:
                        "Refreshing exact storage ledger",
                    detail:
                        "The snapshot calculated \(date(previous.calculatedAt)) remains visible and read-only until refresh completes.",
                    systemImage:
                        "arrow.triangle.2.circlepath",
                    tone: .working
                )
                .accessibilityIdentifier(
                    "blueminutes.storage.state.loading"
                )
            } else {
                WorkflowStateView(
                    title:
                        "Calculating the first bounded local storage snapshot",
                    detail:
                        "No previous report is available; Workspace Trash actions are unavailable.",
                    systemImage:
                        "arrow.triangle.2.circlepath",
                    tone: .working
                )
                .accessibilityIdentifier(
                    "blueminutes.storage.state.loading"
                )
            }
        case let .ready(report):
            WorkflowStateView(
                title:
                    "Exact local ledger ready",
                detail:
                    "Calculated \(date(report.calculatedAt)). The current snapshot passed its configured scan and permission checks.",
                systemImage: "checkmark.seal",
                tone: .ready
            )
            .accessibilityIdentifier(
                "blueminutes.storage.state.ready"
            )
        case let .degraded(report):
            WorkflowStateView(
                title:
                    "Storage integrity needs review",
                detail:
                    degradedDetail(report),
                systemImage:
                    "exclamationmark.shield",
                tone: .warning
            )
            .accessibilityIdentifier(
                "blueminutes.storage.state.degraded"
            )
        case let .staleLastSuccess(
            report,
            message
        ):
            WorkflowStateView(
                title:
                    "Last successful ledger is read-only",
                detail:
                    "\(message) Retained snapshot: \(date(report.calculatedAt)).",
                systemImage:
                    "exclamationmark.arrow.triangle.2.circlepath",
                tone: .warning
            )
            .accessibilityIdentifier(
                "blueminutes.storage.state.stale"
            )
        case let .failed(message):
            WorkflowStateView(
                title:
                    "Storage ledger unavailable",
                detail: message,
                systemImage:
                    "exclamationmark.triangle",
                tone: .failure
            )
            .accessibilityIdentifier(
                "blueminutes.storage.state.failed"
            )
        }
    }

    private func usageLedger(
        _ report: WorkspaceStorageReport
    ) -> some View {
        GroupBox("Exact Usage Ledger") {
            Grid(
                alignment: .leading,
                horizontalSpacing: 24,
                verticalSpacing: 9
            ) {
                GridRow {
                    Text("Storage class")
                        .font(.caption.weight(.semibold))
                    Text("Exact bytes")
                        .font(.caption.weight(.semibold))
                    Text("Files")
                        .font(.caption.weight(.semibold))
                }
                Divider().gridCellColumns(3)
                GridRow {
                    Text("Total").bold()
                    Text(
                        exactBytes(
                            report.totalByteCount
                        )
                    )
                    .bold()
                    Text(
                        String(
                            totalFileCount(report)
                        )
                    )
                    .bold()
                }
                Divider().gridCellColumns(3)
                ForEach(
                    report.categories,
                    id: \.category
                ) { usage in
                    GridRow {
                        Text(label(usage.category))
                        Text(
                            exactBytes(
                                usage.byteCount
                            )
                        )
                        Text(
                            String(usage.fileCount)
                        )
                    }
                }
            }
            .padding()
            .accessibilityElement(
                children: .contain
            )
            .accessibilityIdentifier(
                "blueminutes.storage.usage-ledger"
            )
            .accessibilityLabel(
                "Exact workspace storage usage ledger"
            )
        }
    }

    private func integrityLedger(
        _ report: WorkspaceStorageReport
    ) -> some View {
        GroupBox("Integrity and Bounds") {
            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 8
            ) {
                GridRow {
                    Text("Calculated")
                    Text(date(report.calculatedAt))
                }
                GridRow {
                    Text("Bounded scan")
                    Text(
                        report.scanTruncated
                            ? "Safety bound reached; totals may be incomplete"
                            : "Complete within the configured safety bound"
                    )
                }
                GridRow {
                    Text("Permission issues")
                    Text(
                        String(
                            report
                                .permissionIssueCount
                        )
                    )
                }
                GridRow {
                    Text("Privacy")
                    Text(
                        "Workspace directories and managed files must remain private; no filename or path is projected here."
                    )
                }
            }
            .padding()
            .accessibilityElement(
                children: .contain
            )
            .accessibilityIdentifier(
                "blueminutes.storage.integrity"
            )
        }
    }

    private func trashLedger(
        _ report: WorkspaceStorageReport,
        allowsMutations: Bool
    ) -> some View {
        GroupBox("Workspace Trash") {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Trash items remain restorable during retention. Permanent deletion is available only from a current report after the exact eligibility instant."
                )
                .foregroundStyle(.secondary)
                if report.trashItems.isEmpty {
                    WorkflowStateView(
                        title:
                            "Workspace Trash is empty",
                        detail:
                            "No verified managed object is currently awaiting restore or retention-qualified deletion.",
                        systemImage: "trash",
                        tone: .neutral
                    )
                    .accessibilityIdentifier(
                        "blueminutes.storage.trash.empty"
                    )
                } else {
                    ForEach(report.trashItems) {
                        item in
                        trashRow(
                            item,
                            report: report,
                            allowsMutations:
                                allowsMutations
                        )
                        Divider()
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier(
            "blueminutes.storage.trash"
        )
    }

    private func trashRow(
        _ item: WorkspaceTrashItem,
        report: WorkspaceStorageReport,
        allowsMutations: Bool
    ) -> some View {
        let mutationReason =
            StorageDashboardPresentation
            .mutationBlockReason(
                reportIsCurrent:
                    allowsMutations,
                isWorking: store.isWorking
            )
            .map(blockReasonMessage)
        let deletionReason =
            StorageDashboardPresentation
            .permanentDeletionBlockReason(
                item: item,
                report: report,
                reportIsCurrent:
                    allowsMutations,
                isWorking: store.isWorking
            )
            .map(blockReasonMessage)

        return VStack(
            alignment: .leading,
            spacing: 9
        ) {
            LabeledContent("Opaque managed object") {
                Text(
                    item.storageObjectID
                        .canonicalString
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
            LabeledContent(
                "Exact size",
                value: exactBytes(item.byteSize)
            )
            LabeledContent(
                "Classification",
                value:
                    item.dataClassification
                    .encodedValue
            )
            LabeledContent(
                "Retention class",
                value:
                    item.retentionClass
                    .encodedValue
            )
            LabeledContent(
                "Trashed",
                value: date(item.trashedAt)
            )
            LabeledContent(
                "Purge eligible",
                value:
                    date(item.purgeEligibleAt)
            )
            HStack {
                Button("Restore") {
                    Task {
                        await store.restoreTrashItem(
                            item.storageObjectID
                        )
                    }
                }
                .disabled(mutationReason != nil)
                .accessibilityIdentifier(
                    trashIdentifier(
                        item,
                        action: "restore"
                    )
                )
                .accessibilityLabel(
                    "Restore opaque managed object "
                        + item.storageObjectID
                        .canonicalString
                )
                .accessibilityHint(
                    mutationReason
                        ?? "Restore this exact opaque managed object through the Storage Service."
                )

                Button(
                    "Delete Permanently…",
                    role: .destructive
                ) {
                    requestPermanentDeletion(
                        item
                    )
                }
                .disabled(deletionReason != nil)
                .accessibilityIdentifier(
                    trashIdentifier(
                        item,
                        action: "delete"
                    )
                )
                .accessibilityLabel(
                    "Delete opaque managed object "
                        + item.storageObjectID
                        .canonicalString
                        + " permanently"
                )
                .accessibilityHint(
                    deletionReason
                        ?? "Requires visible confirmation and performs a filesystem unlink after retention. It does not guarantee forensic erasure."
                )
            }
            if let deletionReason {
                Label(
                    "Permanent deletion unavailable: \(deletionReason)",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            trashIdentifier(
                item,
                action: "row"
            )
        )
    }

    private var deletionBoundary: some View {
        GroupBox("Deletion Boundary") {
            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 7
            ) {
                GridRow {
                    Text("Will remove").bold()
                    Text(
                        "Only the verified managed file at its opaque Workspace Trash location."
                    )
                }
                GridRow {
                    Text("Will not remove").bold()
                    Text(
                        "Immutable semantic history, audit receipts, migration backups, or external system snapshots."
                    )
                }
                GridRow {
                    Text("Erasure limit").bold()
                    Text(
                        "APFS, SSD wear leveling, snapshots, and backups prevent a forensic-erasure guarantee."
                    )
                }
            }
            .font(.callout)
            .padding()
        }
        .accessibilityIdentifier(
            "blueminutes.storage.deletion-boundary"
        )
    }

    private func blockReasonMessage(
        _ reason:
            StorageTrashMutationBlockReason
    ) -> String {
        switch reason {
        case .reportNotCurrent:
            "Refresh the exact ledger before changing Workspace Trash."
        case .operationInProgress:
            "Wait for the current local operation to finish."
        case let .retentionActive(
            calculatedAt,
            purgeEligibleAt
        ):
            "Retention remains active until \(date(purgeEligibleAt)); this report was calculated \(date(calculatedAt))."
        }
    }

    private func degradedDetail(
        _ report: WorkspaceStorageReport
    ) -> String {
        let scan = report.scanTruncated
            ? "The configured scan safety bound was reached."
            : "The bounded scan completed."
        return
            "\(scan) Permission issues: \(report.permissionIssueCount). The exact snapshot remains visible without exposing filenames or paths."
    }

    private func label(
        _ category: WorkspaceStorageCategory
    ) -> String {
        switch category {
        case .meetings: "Meetings"
        case .audio: "Audio and media"
        case .documents: "Documents"
        case .models: "Models"
        case .database: "Database"
        case .indexes: "Indexes"
        case .backups: "Backups"
        case .temporary: "Temporary files"
        case .logsAndCache: "Logs and cache"
        case .trash: "Workspace Trash"
        case .other: "Other"
        }
    }

    private func totalFileCount(
        _ report: WorkspaceStorageReport
    ) -> UInt64 {
        report.categories.reduce(0) {
            partial,
            usage in
            let (sum, overflow) =
                partial.addingReportingOverflow(
                    usage.fileCount
                )
            return overflow ? UInt64.max : sum
        }
    }

    private func exactBytes(
        _ value: UInt64
    ) -> String {
        "\(value) bytes"
    }

    private func trashIdentifier(
        _ item: WorkspaceTrashItem,
        action: String
    ) -> String {
        "blueminutes.storage.trash."
            + item.storageObjectID
            .canonicalString
            + "."
            + action
    }

    private func date(
        _ instant: UTCInstant
    ) -> String {
        let date = Date(
            timeIntervalSince1970:
                Double(
                    instant
                        .millisecondsSinceUnixEpoch
                ) / 1_000
        )
        return
            "\(date.formatted(date: .abbreviated, time: .standard)) · \(instant.millisecondsSinceUnixEpoch) ms UTC"
    }
}
