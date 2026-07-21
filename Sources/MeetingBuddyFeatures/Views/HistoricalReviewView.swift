import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct HistoricalReviewView: View {
    @Bindable var store: MediaReviewStore
    @State private var confirmChange = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                indexCard
                searchCard
                resultsCard
                comparisonCard
                preferencesCard
            }
            .padding(24)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .confirmationDialog(
            "Confirm this possible historical change?",
            isPresented: $confirmChange,
            titleVisibility: .visible
        ) {
            Button("Confirm Evidence-Linked Change") {
                Task { await store.confirmHistoricalChange() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a new immutable user-authored revision. It does not modify either source position.")
        }
        .confirmationDialog(
            "Reset all learned preferences?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                Task { await store.resetLearnedPreferences(confirmedByVisibleDialog: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All active and disabled preference values will be removed. Content-free action and digest audit events remain visible, but cannot restore a preference value.")
        }
    }

    private var indexCard: some View {
        GroupBox("Meeting History Index") {
            VStack(alignment: .leading, spacing: 10) {
                if let status = store.historicalIndex {
                    LabeledContent("Status", value: status.availability.rawValue)
                    LabeledContent("Generation", value: String(status.generation))
                    LabeledContent("Confirmed positions", value: String(status.indexedPositionCount))
                    if let fingerprint = status.sourceFingerprint {
                        LabeledContent("Source fingerprint", value: fingerprint.lowercaseHex)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Load the local index status before searching.")
                        .foregroundStyle(.secondary)
                }
                if let job = store.historicalIndexJob {
                    LabeledContent("Rebuild job", value: job.state.rawValue)
                }
                HStack {
                    Button("Reload Status") {
                        Task { await store.loadHistoricalReview() }
                    }
                    Button("Rebuild Local Index") {
                        Task { await store.rebuildHistoricalIndex() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting History local index")
    }

    private var searchCard: some View {
        GroupBox("Historical Context Search") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                searchRow("Actor or country", text: $store.historyActorOrCountry)
                searchRow("Topic or issue", text: $store.historyTopic)
                searchRow("Organization or body", text: $store.historyBody)
                searchRow("Meeting type", text: $store.historyMeetingType)
                searchRow("Start date", text: $store.historyStartDate, prompt: "YYYY-MM-DD")
                searchRow("End date", text: $store.historyEndDate, prompt: "YYYY-MM-DD")
            }
            .padding(.top, 6)
            Button("Search Confirmed Published History") {
                Task { await store.searchMeetingHistory() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isWorking || store.historicalIndex?.availability != .ready)
            .padding(.top, 10)
            .accessibilityHint("Searches only the current local generation and rechecks each exact access policy before returning content or counts.")
        }
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

    @ViewBuilder
    private var resultsCard: some View {
        GroupBox("Confirmed Published Results") {
            if let page = store.historicalSearchPage, !page.results.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(page.results.count) authorized result(s), index generation \(page.indexGeneration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(page.results) { result in
                        resultRow(result)
                        Divider()
                    }
                }
                .padding(.top, 6)
            } else {
                ContentUnavailableView(
                    "No Authorized History Results",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Rebuild the index or adjust deterministic filters. Unauthorized records are not included in content, counts, or facets.")
                )
            }
        }
    }

    private func resultRow(_ result: HistoricalPositionResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.actor.displayName).font(.headline)
                Spacer()
                Text(dateLabel(result.meeting.meetingDate))
                    .foregroundStyle(.secondary)
            }
            Text(result.issue.title.text).font(.subheadline.weight(.semibold))
            Text(result.position.statement.text).lineLimit(4)
            HStack {
                Button("Use as Current") {
                    store.selectedCurrentHistoryRevisionID = result.position.revision.revisionID
                }
                .accessibilityLabel("Use \(result.actor.displayName) at \(dateLabel(result.meeting.meetingDate)) as current position")
                Button("Use as Previous") {
                    store.selectedPriorHistoryRevisionID = result.position.revision.revisionID
                }
                .accessibilityLabel("Use \(result.actor.displayName) at \(dateLabel(result.meeting.meetingDate)) as previous position")
                if store.selectedCurrentHistoryRevisionID == result.position.revision.revisionID {
                    Label("Current", systemImage: "checkmark.circle.fill")
                }
                if store.selectedPriorHistoryRevisionID == result.position.revision.revisionID {
                    Label("Previous", systemImage: "clock.arrow.circlepath")
                }
            }
            Text("Position revision: \(result.position.revision.revisionID.canonicalString)")
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("Evidence: \(result.evidence.count) exact revision(s); confidence \(result.position.statement.confidence.millionths)/1,000,000")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var comparisonCard: some View {
        GroupBox("Historical Comparison") {
            VStack(alignment: .leading, spacing: 10) {
                Button("Compare Selected Positions") {
                    Task { await store.compareSelectedHistoricalPositions() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.selectedCurrentHistoryRevisionID == nil
                        || store.selectedPriorHistoryRevisionID == nil
                        || store.selectedCurrentHistoryRevisionID
                            == store.selectedPriorHistoryRevisionID
                )
                if let comparison = store.historicalComparison {
                    Text(comparison.qualifiedSummary)
                        .font(.headline)
                    LabeledContent("Finding", value: comparison.finding.encodedValue)
                    LabeledContent("Difference state", value: comparison.differenceState.encodedValue)
                    comparisonSide(
                        "Current",
                        date: comparison.currentEffectiveDate,
                        timeRange: comparison.currentEffectiveTimeRange,
                        position: comparison.currentPositionRevision,
                        evidence: comparison.currentEvidenceRevisions,
                        confidence: comparison.currentConfidence
                    )
                    comparisonSide(
                        "Previous",
                        date: comparison.historicalEffectiveDate,
                        timeRange: comparison.historicalEffectiveTimeRange,
                        position: comparison.historicalPositionRevision,
                        evidence: comparison.historicalEvidenceRevisions,
                        confidence: comparison.historicalConfidence
                    )
                    if comparison.differenceState == .possibleDifference {
                        Button("Confirm Possible Change…") { confirmChange = true }
                            .accessibilityHint("Creates a superseding user-confirmed comparison; source positions remain immutable.")
                    }
                } else {
                    Text("Select a current and previous result. Wording differences, silence, and group membership never establish a policy change.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private func comparisonSide(
        _ title: String,
        date: CalendarDate?,
        timeRange: MediaTimeRange?,
        position: SemanticRevisionReference,
        evidence: [SemanticRevisionReference],
        confidence: ConfidenceScore
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("Date: \(dateLabel(date))")
            Text("Position effective time: \(timeRangeLabel(timeRange))")
            Text("Position: \(position.revisionID.canonicalString)")
            Text("Evidence: \(evidence.map(\.revisionID.canonicalString).joined(separator: ", "))")
            Text("Confidence: \(confidence.millionths)/1,000,000")
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) evidence and exact revisions")
    }

    @ViewBuilder
    private var preferencesCard: some View {
        GroupBox("Learned Preferences") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preferences are created only from explicit actions. They affect presentation, never access policy, model routing, evidence requirements, classification, or protected diplomatic rules.")
                    .foregroundStyle(.secondary)
                if let state = store.learnedPreferences {
                    Toggle(
                        "Apply learned preferences",
                        isOn: Binding(
                            get: { state.globallyEnabled },
                            set: { enabled in
                                Task { await store.setLearnedPreferencesGloballyEnabled(enabled) }
                            }
                        )
                    )
                    .accessibilityHint("Disabled preferences remain visible and editable but do not affect presentation.")
                    ForEach(state.preferences) { preference in
                        preferenceRow(preference)
                        Divider()
                    }
                    if state.preferences.isEmpty {
                        Text("No learned preferences are stored.")
                            .foregroundStyle(.secondary)
                    }
                    if !state.recentEvents.isEmpty {
                        DisclosureGroup("Recent Preference Audit") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(state.recentEvents) { event in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.action.rawValue)
                                            .font(.caption.weight(.semibold))
                                        Text(
                                            "Source: \(event.sourceAction); recorded "
                                                + "\(event.recordedAt.millisecondsSinceUnixEpoch)"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        if let prior = event.priorValueDigest {
                                            Text("Prior digest: \(prior.lowercaseHex)")
                                                .font(.caption.monospaced())
                                                .textSelection(.enabled)
                                        }
                                        if let replacement = event.replacementValueDigest {
                                            Text("Replacement digest: \(replacement.lowercaseHex)")
                                                .font(.caption.monospaced())
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(
                                        "Preference audit action \(event.action.rawValue), source \(event.sourceAction)"
                                    )
                                }
                            }
                            .padding(.top, 6)
                        }
                        .accessibilityHint("Shows immutable action metadata and digests, never deleted raw preference values.")
                    }
                }
                Divider()
                Picker("Preference type", selection: $store.learnedPreferenceKind) {
                    ForEach(LearnedPreferenceKind.allCases, id: \.rawValue) { kind in
                        Text(preferenceLabel(kind)).tag(kind)
                    }
                }
                TextField(preferencePrompt(store.learnedPreferenceKind), text: $store.learnedPreferenceValue)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Learned preference value")
                HStack {
                    Button(store.editingLearnedPreferenceID == nil ? "Add Preference" : "Save Edit") {
                        Task { await store.saveLearnedPreference() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset All…", role: .destructive) { confirmReset = true }
                        .disabled(store.learnedPreferences?.preferences.isEmpty != false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private func preferenceRow(_ record: LearnedPreferenceRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(preferenceLabel(record.kind)).font(.subheadline.weight(.semibold))
                Text(record.enabled ? "Enabled" : "Disabled")
                    .foregroundStyle(record.enabled ? .green : .secondary)
                Spacer()
                Button("Edit") { store.editLearnedPreference(record) }
                Button(record.enabled ? "Disable" : "Enable") {
                    Task { await store.toggleLearnedPreference(record) }
                }
                Button("Remove", role: .destructive) {
                    Task { await store.removeLearnedPreference(record) }
                }
            }
            Text(record.value.displaySummary).textSelection(.enabled)
            Text("Source: \(record.sourceAction); version \(record.version); updated \(record.updatedAt.millisecondsSinceUnixEpoch)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(preferenceLabel(record.kind)), \(record.enabled ? "enabled" : "disabled")")
    }

    private func preferenceLabel(_ kind: LearnedPreferenceKind) -> String {
        switch kind {
        case .actorCountryOrder: "Actor and country order"
        case .briefingLength: "Briefing length"
        case .sectionOrder: "Section order"
        case .quotationPolicy: "Quotation policy"
        case .grouping: "Grouping"
        case .terminology: "Terminology"
        case .frequentTemplates: "Frequent templates"
        }
    }

    private func preferencePrompt(_ kind: LearnedPreferenceKind) -> String {
        switch kind {
        case .actorCountryOrder: "Comma-separated actor or country labels"
        case .briefingLength: "Word limit, 100–20000"
        case .sectionOrder: "Comma-separated stable section identifiers"
        case .quotationPolicy: "exact_only, exact_with_translation, or paraphrase_with_evidence"
        case .grouping: "by_actor, by_issue, or chronological"
        case .terminology: "Comma-separated source=display mappings"
        case .frequentTemplates: "Comma-separated template UUIDs"
        }
    }

    private func dateLabel(_ date: CalendarDate?) -> String {
        guard let date else { return "Unknown effective date" }
        return String(format: "%04d-%02d-%02d", Int(date.year), Int(date.month), Int(date.day))
    }

    private func timeRangeLabel(_ range: MediaTimeRange?) -> String {
        guard let range else { return "No media-relative time range" }
        return "\(range.startMilliseconds)–\(range.endMilliseconds) ms"
    }
}
