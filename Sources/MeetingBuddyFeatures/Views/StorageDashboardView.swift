import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct StorageDashboardView: View {
    @Bindable var store: MediaReviewStore
    let requestPermanentDeletion: (WorkspaceTrashItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let report = store.storageReport {
                    categoryGrid(report)
                    integrityCard(report)
                    trashCard(report)
                } else {
                    ContentUnavailableView(
                        "Storage Report Not Loaded",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("Refresh to inspect this local workspace without sending data anywhere.")
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Storage")
                    .font(.title2.bold())
                Text("Local, bounded accounting. Filenames and sensitive paths are not displayed.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task { await store.loadStorageReport() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(store.isWorking)
            .accessibilityHint("Recalculate bounded local workspace storage usage.")
        }
    }

    private func categoryGrid(_ report: WorkspaceStorageReport) -> some View {
        GroupBox("Usage by storage class") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                GridRow {
                    Text("Total")
                    Text(bytes(report.totalByteCount)).bold()
                    Text("all inspected files").foregroundStyle(.secondary)
                }
                Divider().gridCellColumns(3)
                ForEach(report.categories, id: \.category) { usage in
                    GridRow {
                        Text(label(usage.category))
                        Text(bytes(usage.byteCount))
                        Text("\(usage.fileCount) files")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workspace storage usage by category")
        }
    }

    private func integrityCard(_ report: WorkspaceStorageReport) -> some View {
        GroupBox("Inspection status") {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    report.scanTruncated ? "Scan reached its safety bound" : "Bounded scan complete",
                    systemImage: report.scanTruncated
                        ? "exclamationmark.triangle" : "checkmark.seal"
                )
                Label(
                    report.permissionIssueCount == 0
                        ? "Private filesystem permissions verified"
                        : "\(report.permissionIssueCount) permission issues require review",
                    systemImage: report.permissionIssueCount == 0
                        ? "lock.shield" : "lock.trianglebadge.exclamationmark"
                )
                Text("Workspace directories must deny group/other access; managed files, logs, exports, and the database must remain private.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func trashCard(_ report: WorkspaceStorageReport) -> some View {
        GroupBox("Workspace Trash") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Trash items are retained for at least 30 days and remain restorable during that interval.")
                    .foregroundStyle(.secondary)
                if report.trashItems.isEmpty {
                    Label("Workspace Trash is empty", systemImage: "trash")
                } else {
                    ForEach(report.trashItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Managed asset \(short(item.storageObjectID.canonicalString))")
                                    .font(.headline)
                                Spacer()
                                Text(bytes(item.byteSize))
                            }
                            LabeledContent("Classification", value: item.dataClassification.encodedValue)
                            LabeledContent("Purge eligible", value: date(item.purgeEligibleAt))
                            HStack {
                                Button("Restore") {
                                    Task { await store.restoreTrashItem(item.storageObjectID) }
                                }
                                .disabled(store.isWorking)
                                Button("Delete Permanently", role: .destructive) {
                                    requestPermanentDeletion(item)
                                }
                                .disabled(
                                    store.isWorking || report.calculatedAt < item.purgeEligibleAt
                                )
                                .accessibilityHint(
                                    "Requires visible confirmation and performs a filesystem unlink after retention. It does not guarantee forensic erasure."
                                )
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                deletionSemantics
            }
            .padding()
        }
    }

    private var deletionSemantics: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("Will remove").bold()
                Text("The verified managed file at its opaque Workspace Trash location.")
            }
            GridRow {
                Text("Will not remove").bold()
                Text("Immutable semantic history, audit receipts, migration backups, or external system snapshots.")
            }
            GridRow {
                Text("Erasure limit").bold()
                Text("APFS, SSD wear leveling, snapshots, and backups prevent a forensic-erasure guarantee.")
            }
        }
        .font(.callout)
    }

    private func label(_ category: WorkspaceStorageCategory) -> String {
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

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    private func short(_ value: String) -> String {
        String(value.prefix(8)) + "…"
    }

    private func date(_ instant: UTCInstant) -> String {
        Date(
            timeIntervalSince1970: Double(instant.millisecondsSinceUnixEpoch) / 1_000
        ).formatted(date: .abbreviated, time: .shortened)
    }
}
