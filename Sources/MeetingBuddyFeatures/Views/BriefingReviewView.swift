import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct BriefingReviewView: View {
    @Bindable var store: MediaReviewStore
    @State private var selectedSectionType: BriefingSectionType?
    @State private var itemDrafts: [BriefingItemID: String] = [:]
    @State private var lockRevision = false

    var body: some View {
        Group {
                if let review = store.briefingReview {
                    reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onChange(of: selectedSectionType) { _, _ in loadDrafts() }
        .onChange(
            of: store.briefingReview?.publication.sections.map(\.revision.revisionID)
        ) { _, _ in reconcileSelection() }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeCard
                if let job = store.briefingJob { jobCard(job) }
                GroupBox("Create validated diplomatic briefing") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Generate Briefing is explicit authorization for three independent on-device section runs over validated intelligence claims and evidence identifiers. Publication is atomic and fails closed unless every source segment and conclusion is traceable.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Check Local Briefing Model") {
                                Task { await store.refreshBriefingRoute() }
                            }
                            Button("Generate Briefing") {
                                Task { await store.startBriefing() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                store.briefingRouteReview?.isOnDeviceReady != true
                                    || store.isWorking
                            )
                        }
                    }
                    .padding()
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var routeCard: some View {
        GroupBox("Briefing privacy route") {
            VStack(alignment: .leading, spacing: 9) {
                if let route = store.briefingRouteReview {
                    LabeledContent(
                        "Route",
                        value: route.briefing.route == .appleOnDevice
                            ? "Apple Foundation Models on device"
                            : "No automatic local model"
                    )
                    LabeledContent("Destination", value: "this Mac")
                    LabeledContent(
                        "Provider inputs",
                        value: route.briefing.request.dataCategories
                            .map(\.rawValue).joined(separator: ", ")
                    )
                    LabeledContent("Policy decision", value: route.briefing.reasonCode)
                    LabeledContent(
                        "Runtime",
                        value: "\(route.runtimeEvidence.operatingSystemVersion) · \(route.runtimeEvidence.adapterVersion)"
                    )
                } else {
                    Label("Check the local model after validating analysis", systemImage: "lock.shield")
                }
                Divider()
                Text("No raw transcript, audio, cloud adapter, network tool, credential, or provider-retention path is added by this workflow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func jobCard(_ job: MediaJobReview) -> some View {
        GroupBox("Local briefing task") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent(
                    "State",
                    value: job.state.rawValue.replacingOccurrences(of: "_", with: " ")
                )
                ProgressView(value: job.progressFraction)
                LabeledContent(
                    "Independent sections",
                    value: "\(job.completedUnitCount) / \(job.totalUnitCount)"
                )
                if let failure = job.safeFailureSummary {
                    Text(failure).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private func reviewWorkspace(_ review: BriefingReviewBundle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !review.isCurrent {
                    Label(
                        "This briefing is stale after an upstream correction. Review or regenerate it before export.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Stale briefing warning")
                }
                publicationProof(review)
                sectionEditor(review)
                markdownPreview(review)
                exportCard(review)
            }
            .padding(24)
            .frame(maxWidth: 1_080, alignment: .leading)
        }
    }

    private func publicationProof(_ review: BriefingReviewBundle) -> some View {
        GroupBox("Published briefing proof") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Validation")
                    Label(
                        "\(review.publication.validationReport.checks.count) / \(review.publication.validationReport.checks.count) checks passed",
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                }
                GridRow {
                    Text("Source coverage")
                    Text("\(review.publication.ledger.segments.count) / \(review.publication.ledger.eligibleSegmentRevisions.count) eligible segments")
                }
                GridRow {
                    Text("Conclusion links")
                    Text(String(review.publication.ledger.conclusionReferences.count))
                }
                GridRow {
                    Text("Issue matrix")
                    Text("\(review.publication.graph.rows.count) issues · \(review.publication.graph.cells.count) stated-position cells")
                }
                GridRow {
                    Text("Current")
                    Text(review.isCurrent ? "yes" : "no")
                }
                GridRow {
                    Text("Markdown digest")
                    Text(short(review.publication.finalBriefing.markdownDigest.lowercaseHex))
                        .monospaced()
                }
            }
            .padding()
        }
    }

    private func sectionEditor(_ review: BriefingReviewBundle) -> some View {
        GroupBox("Independent sections") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Section", selection: $selectedSectionType) {
                    Text("Select a section").tag(BriefingSectionType?.none)
                    ForEach(review.publication.sections, id: \.sectionType) { section in
                        Text(section.title).tag(Optional(section.sectionType))
                    }
                }
                if let section = selectedSection(in: review) {
                    HStack {
                        Label(
                            section.manualEditStatus == .userEdited
                                ? "Preserved user revision" : "Generated revision",
                            systemImage: section.manualEditStatus == .userEdited
                                ? "person.crop.circle.badge.checkmark" : "apple.intelligence"
                        )
                        Spacer()
                        Toggle("Lock this revision", isOn: $lockRevision)
                            .toggleStyle(.switch)
                    }
                    ForEach(section.items, id: \.itemID) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Evidence-linked item · \(item.claim.evidenceRevisions.count) evidence refs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: itemBinding(item))
                                .font(.body)
                                .frame(minHeight: 74)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }
                    }
                    HStack {
                        Button("Save Manual Revision") {
                            Task {
                                await store.updateBriefingSection(
                                    section.sectionType,
                                    editedTextByItemID: itemDrafts,
                                    locked: lockRevision
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draftsAreComplete(section) || store.isWorking)
                        Button("Regenerate Only This Section") {
                            Task { await store.regenerateBriefingSection(section.sectionType) }
                        }
                        .disabled(
                            section.locked
                                || section.manualEditStatus == .userEdited
                                || store.isWorking
                        )
                    }
                    if section.locked || section.manualEditStatus == .userEdited {
                        Text("Automatic regeneration cannot overwrite this preserved user revision.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func markdownPreview(_ review: BriefingReviewBundle) -> some View {
        GroupBox("Deterministic Markdown preview") {
            ScrollView(.horizontal) {
                Text(review.publication.finalBriefing.markdown)
                    .textSelection(.enabled)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .padding()
        }
    }

    private func exportCard(_ review: BriefingReviewBundle) -> some View {
        GroupBox("Explicit local Markdown export") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("File name", text: $store.briefingExportFileName)
                LabeledContent(
                    "Destination",
                    value: "Meetings/\(review.publication.finalBriefing.meetingID.canonicalString)/exports/"
                )
                Button("Export Validated Markdown") {
                    Task { await store.exportBriefing() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!review.isCurrent || store.isWorking)
                if let record = store.lastBriefingExport {
                    Label(record.relativePath.rawValue, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    private func selectedSection(in review: BriefingReviewBundle) -> BriefingSectionV1? {
        review.publication.sections.first { $0.sectionType == selectedSectionType }
    }

    private func itemBinding(_ item: BriefingSectionItem) -> Binding<String> {
        Binding(
            get: { itemDrafts[item.itemID] ?? item.claim.text },
            set: { itemDrafts[item.itemID] = $0 }
        )
    }

    private func draftsAreComplete(_ section: BriefingSectionV1) -> Bool {
        Set(itemDrafts.keys) == Set(section.items.map(\.itemID))
            && itemDrafts.values.allSatisfy {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && value == $0 && value.utf8.count <= 16_384
            }
    }

    private func reconcileSelection() {
        guard let sections = store.briefingReview?.publication.sections else {
            selectedSectionType = nil
            itemDrafts = [:]
            return
        }
        if !sections.contains(where: { $0.sectionType == selectedSectionType }) {
            selectedSectionType = sections.first?.sectionType
        }
        loadDrafts()
    }

    private func loadDrafts() {
        guard let review = store.briefingReview,
              let section = selectedSection(in: review) else {
            itemDrafts = [:]
            lockRevision = false
            return
        }
        itemDrafts = Dictionary(uniqueKeysWithValues: section.items.map {
            ($0.itemID, $0.claim.text)
        })
        lockRevision = section.locked
    }

    private func short(_ value: String) -> String {
        value.count > 18 ? String(value.prefix(18)) + "…" : value
    }
}
