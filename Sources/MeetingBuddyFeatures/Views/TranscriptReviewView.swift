import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct TranscriptReviewView: View {
    @Bindable var store: MediaReviewStore
    @State private var selectedTranscriptRevisionID: RevisionID?
    @State private var transcriptDraft = ""
    @State private var translationDraft = ""
    @State private var speakerName = ""

    var body: some View {
        Group {
            if let review = store.transcriptReview {
                reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onChange(of: selectedTranscriptRevisionID) { _, _ in
            loadSelectionDrafts()
        }
        .onChange(of: store.transcriptReview?.manifest.manifestID) { _, _ in
            reconcileSelection()
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeCard
                GroupBox("Languages") {
                    Form {
                        TextField("Source language", text: $store.transcriptSourceLanguageTag)
                        TextField(
                            "Target language (optional)",
                            text: $store.transcriptTargetLanguageTag
                        )
                    }
                    .formStyle(.grouped)
                    HStack {
                        Button("Check Installed Models") {
                            Task { await store.refreshTranscriptRoute() }
                        }
                        Button("Transcribe On Device") {
                            Task { await store.startTranscript() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.routeReview?.isOnDeviceReady != true || store.isWorking)
                    }
                    .padding([.horizontal, .bottom])
                }
                if let job = store.transcriptJob {
                    transcriptJobCard(job)
                }
                manualFallbackCard
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var routeCard: some View {
        GroupBox("Privacy route") {
            VStack(alignment: .leading, spacing: 10) {
                if let route = store.routeReview {
                    routeLine("Transcription", decision: route.transcription)
                    if let translation = route.translation {
                        routeLine("Translation", decision: translation)
                    }
                } else {
                    Label("Check the installed local models", systemImage: "lock.shield")
                }
                Divider()
                Text("Meeting content remains on this Mac. Task 005B has no outbound provider adapter and never downloads a model during processing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func routeLine(_ label: String, decision: ModelRouteDecision) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            LabeledContent(label) {
                Label(
                    decision.route == .appleOnDevice
                        ? "Apple on-device model installed"
                        : "Manual local fallback",
                    systemImage: decision.route == .appleOnDevice
                        ? "checkmark.shield.fill"
                        : "person.text.rectangle"
                )
                .foregroundStyle(decision.route == .appleOnDevice ? .green : .orange)
            }
            LabeledContent("Execution boundary", value: decision.route.privacyRoute.encodedValue)
            LabeledContent(
                "Data categories",
                value: decision.request.dataCategories.map(\.rawValue).joined(separator: ", ")
            )
            LabeledContent("Destination", value: destinationLabel(decision.request.destination))
            LabeledContent("Retention", value: decision.request.retentionPolicy.rawValue)
            LabeledContent(
                "Policy authority",
                value: decision.request.organizationAllowsExternalProcessing
                    ? "application router + organization allows external"
                    : "application router + organization local-only"
            )
            LabeledContent(
                "Visible user authorization",
                value: decision.request.visibleUserAuthorization ? "granted" : "not granted"
            )
            LabeledContent(
                "No-outbound mode",
                value: decision.request.securityPolicy?.noOutboundMode == false
                    ? "disabled" : "enforced"
            )
            if let policy = decision.request.securityPolicy {
                LabeledContent(
                    "Exact access-policy revision",
                    value: String(policy.accessPolicyRevision.revisionID.canonicalString.prefix(12))
                        + "…"
                )
            }
            LabeledContent("Decision", value: decision.reasonCode)
        }
    }

    private func destinationLabel(_ destination: ModelDestinationPolicy) -> String {
        switch destination {
        case .localDevice:
            "this Mac"
        case let .approvedProvider(identifier):
            "approved provider: \(identifier)"
        }
    }

    private func transcriptJobCard(_ job: MediaJobReview) -> some View {
        GroupBox("Local transcript task") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("State", value: job.state.rawValue.replacingOccurrences(of: "_", with: " "))
                ProgressView(value: job.progressFraction)
                LabeledContent("Privacy", value: job.privacyRoute.encodedValue)
                if let failure = job.safeFailureSummary {
                    Text(failure).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private var manualFallbackCard: some View {
        GroupBox("Manual local fallback") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use this when an on-device model or language pair is unavailable. The text is labeled human-entered and receives complete timeline coverage; no provider is invoked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Transcript")
                    .font(.headline)
                TextEditor(text: $store.manualTranscriptText)
                    .frame(minHeight: 120)
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                if !store.transcriptTargetLanguageTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Translation")
                        .font(.headline)
                    TextEditor(text: $store.manualTranslationText)
                        .frame(minHeight: 100)
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                }
                Toggle(
                    "I confirm this manual text accounts for the complete recording timeline",
                    isOn: $store.manualCoverageConfirmed
                )
                Button("Publish Manual Transcript") {
                    Task { await store.publishManualTranscript() }
                }
                .disabled(store.isWorking || !store.manualCoverageConfirmed)
            }
            .padding()
        }
    }

    private func reviewWorkspace(_ review: TranscriptReviewBundle) -> some View {
        VStack(spacing: 0) {
            reviewHeader(review)
            Divider()
            HSplitView {
                segmentList(review)
                    .frame(minWidth: 280, idealWidth: 340)
                segmentInspector(review)
                    .frame(minWidth: 420)
            }
        }
    }

    private func reviewHeader(_ review: TranscriptReviewBundle) -> some View {
        HStack(spacing: 18) {
            Label("100% deterministic core coverage", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            LabeledContent("Route", value: review.manifest.transcriptionRoute.route.rawValue)
            LabeledContent("Chunks", value: String(review.manifest.chunks.count))
            LabeledContent("Uncertain speakers", value: String(uncertainCount(review)))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func segmentList(_ review: TranscriptReviewBundle) -> some View {
        List(review.transcriptSegments, id: \.revision.revisionID, selection: $selectedTranscriptRevisionID) { segment in
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .lineLimit(2)
                HStack {
                    Text(timeLabel(segment.timeRange))
                    Text(segment.reviewStatus.encodedValue.replacingOccurrences(of: "_", with: " "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .tag(segment.revision.revisionID)
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func segmentInspector(_ review: TranscriptReviewBundle) -> some View {
        if let segment = selectedSegment(review) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Source transcript revision") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Time", value: timeLabel(segment.timeRange))
                            LabeledContent("Language", value: segment.detectedLanguage.value)
                            LabeledContent("Provenance", value: segment.revision.createdBy.encodedValue)
                            TextEditor(text: $transcriptDraft)
                                .frame(minHeight: 140)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Button("Save Transcript Correction") {
                                Task {
                                    await store.correctTranscript(
                                        revisionID: segment.revision.revisionID,
                                        text: transcriptDraft
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isWorking || transcriptDraft == segment.text)
                        }
                        .padding()
                    }
                    if let translation = translation(for: segment, in: review) {
                        GroupBox("Separate translation revision") {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent("Target", value: translation.targetLanguage.value)
                                TextEditor(text: $translationDraft)
                                    .frame(minHeight: 120)
                                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                                Button("Save Translation Correction") {
                                    Task {
                                        await store.correctTranslation(
                                            revisionID: translation.revision.revisionID,
                                            text: translationDraft
                                        )
                                    }
                                }
                                .disabled(store.isWorking || translationDraft == translation.translatedText)
                            }
                            .padding()
                        }
                    }
                    GroupBox("Speaker review") {
                        VStack(alignment: .leading, spacing: 10) {
                            if hasAssignment(for: segment, in: review) {
                                Label("Speaker assignment confirmed", systemImage: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Uncertain speaker — confirmation required", systemImage: "person.crop.circle.badge.questionmark")
                                    .foregroundStyle(.orange)
                                TextField("Speaker name", text: $speakerName)
                                Button("Confirm Speaker") {
                                    Task {
                                        await store.confirmSpeaker(
                                            transcriptRevisionID: segment.revision.revisionID,
                                            displayName: speakerName
                                        )
                                    }
                                }
                                .disabled(store.isWorking || speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding()
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select a Transcript Segment",
                systemImage: "text.bubble",
                description: Text("Review source text, separate translations, and uncertain speakers.")
            )
        }
    }

    private func selectedSegment(_ review: TranscriptReviewBundle) -> TranscriptSegmentV1? {
        review.transcriptSegments.first { $0.revision.revisionID == selectedTranscriptRevisionID }
    }

    private func translation(
        for segment: TranscriptSegmentV1,
        in review: TranscriptReviewBundle
    ) -> TranslationSegmentV1? {
        review.translations.first {
            $0.sourceSegmentRevision.revisionID == segment.revision.revisionID
        }
    }

    private func hasAssignment(
        for segment: TranscriptSegmentV1,
        in review: TranscriptReviewBundle
    ) -> Bool {
        review.speakerAssignments.contains { assignment in
            assignment.certainty == .confirmed
                && assignment.reviewStatus == .confirmed
                && assignment.userConfirmed
                && assignment.transcriptSegmentRevisions.contains {
                    $0.revisionID == segment.revision.revisionID
                }
        }
    }

    private func uncertainCount(_ review: TranscriptReviewBundle) -> Int {
        review.transcriptSegments.filter { !hasAssignment(for: $0, in: review) }.count
    }

    private func reconcileSelection() {
        guard let review = store.transcriptReview else {
            selectedTranscriptRevisionID = nil
            return
        }
        if selectedSegment(review) == nil {
            selectedTranscriptRevisionID = review.transcriptSegments.first?.revision.revisionID
        }
        loadSelectionDrafts()
    }

    private func loadSelectionDrafts() {
        guard let review = store.transcriptReview,
              let segment = selectedSegment(review)
        else {
            transcriptDraft = ""
            translationDraft = ""
            speakerName = ""
            return
        }
        transcriptDraft = segment.text
        translationDraft = translation(for: segment, in: review)?.translatedText ?? ""
        speakerName = ""
    }

    private func timeLabel(_ range: MediaTimeRange) -> String {
        let start = Double(range.startMilliseconds) / 1_000
        let end = Double(range.endMilliseconds) / 1_000
        return "\(start.formatted(.number.precision(.fractionLength(1))))–\(end.formatted(.number.precision(.fractionLength(1)))) s"
    }
}
