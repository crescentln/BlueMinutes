import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI
import UniformTypeIdentifiers

public struct MeetingBuddyRootView: View {
    @State private var store: MediaReviewStore
    @State private var fileImporterPurpose = LocalFileImporterPurpose.workspace
    @State private var showFileImporter = false
    @State private var pendingPermanentDeletion: WorkspaceTrashItem?

    public init(store: MediaReviewStore) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSection) {
                Section("Workspace") {
                    Label(
                        store.workspace?.displayName ?? "No workspace open",
                        systemImage: store.workspace == nil ? "folder.badge.questionmark" : "folder"
                    )
                    Button("Choose Workspace…") {
                        presentFileImporter(.workspace)
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(store.isWorking || store.blocksWorkspaceSwitch)
                    .accessibilityHint("Open an existing local workspace or create one in an empty folder.")
                }
                Section("Workflow") {
                    Label("Local Media", systemImage: "waveform")
                        .tag(MediaReviewSection.intake)
                    Label("Record Audio", systemImage: "record.circle")
                        .tag(MediaReviewSection.recording)
                    Label("UN Web TV Metadata", systemImage: "link.badge.plus")
                        .tag(MediaReviewSection.webMetadata)
                    Label("Transcript Review", systemImage: "text.bubble")
                        .tag(MediaReviewSection.transcript)
                        .disabled(store.job?.state != .succeeded)
                    Label("Analysis Review", systemImage: "checklist.checked")
                        .tag(MediaReviewSection.analysis)
                        .disabled(store.transcriptReview == nil)
                    Label("Briefing", systemImage: "doc.text.magnifyingglass")
                        .tag(MediaReviewSection.briefing)
                        .disabled(store.analysisReview == nil)
                    Label("Meeting History", systemImage: "clock.arrow.circlepath")
                        .tag(MediaReviewSection.history)
                    Label("Storage", systemImage: "externaldrive")
                        .tag(MediaReviewSection.storage)
                }
            }
            .navigationTitle("MeetingBuddy")
            .listStyle(.sidebar)
        } detail: {
            detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(navigationTitle)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let recording = store.recordingSession,
                   store.recordingIndicatorIsVisible
                {
                    recordingBanner(recording)
                }
            }
            .toolbar {
                if store.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .task {
            await store.restoreWorkspace()
        }
        .onChange(of: store.selectedSection) { _, section in
            Task {
                switch section {
                case .recording:
                    await store.loadRecordingSetup()
                case .transcript:
                    await store.loadTranscriptReview()
                    await store.refreshTranscriptRoute()
                case .analysis:
                    await store.loadAnalysisReview()
                    await store.refreshAnalysisRoute()
                case .briefing:
                    await store.loadBriefingReview()
                    await store.refreshBriefingRoute()
                case .history:
                    await store.loadHistoricalReview()
                case .storage:
                    await store.loadStorageReport()
                case .intake, .webMetadata, nil:
                    break
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileImporterPurpose.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            switch fileImporterPurpose {
            case .workspace:
                Task { await store.openOrCreateWorkspace(at: url) }
            case .media:
                Task { await store.inspectMedia(at: url) }
            }
        }
        .alert(
            "MeetingBuddy",
            isPresented: Binding(
                get: { store.safeErrorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.safeErrorMessage ?? "")
        }
        .confirmationDialog(
            "Permanently delete this managed file?",
            isPresented: Binding(
                get: { pendingPermanentDeletion != nil },
                set: { if !$0 { pendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingPermanentDeletion {
                Button("Delete Permanently", role: .destructive) {
                    pendingPermanentDeletion = nil
                    Task {
                        await store.permanentlyDeleteTrashItem(
                            item.storageObjectID,
                            confirmedByVisibleDialog: true
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPermanentDeletion = nil
            }
        } message: {
            Text("This removes the verified Workspace Trash file after its retention interval. It preserves immutable audit history and does not guarantee forensic erasure on APFS, SSDs, snapshots, or backups.")
        }
    }

    private func recordingBanner(_ recording: RecordingSessionReview) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(recording.state == .recording ? "Recording" : recording.state.rawValue)
                .font(.callout.weight(.semibold))
            Button("Stop") {
                Task { await store.stopRecording() }
            }
            .disabled(store.isWorking || !recording.canStop)
            .accessibilityHint(
                "Stop packet admission, seal valid audio, and verify the retained result."
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visible recording state: \(recording.state.rawValue)")
    }

    @ViewBuilder
    private var detailContent: some View {
        if store.workspace == nil {
            workspaceOnboarding
        } else {
            switch store.selectedSection ?? .intake {
            case .intake:
                intakeView
            case .recording:
                RecordingCaptureView(store: store)
            case .webMetadata:
                UNWebTVMetadataView(store: store)
            case .transcript:
                TranscriptReviewView(store: store)
            case .analysis:
                AnalysisReviewView(store: store)
            case .briefing:
                BriefingReviewView(store: store)
            case .history:
                HistoricalReviewView(store: store)
            case .storage:
                StorageDashboardView(store: store) { item in
                    pendingPermanentDeletion = item
                }
            }
        }
    }

    private var workspaceOnboarding: some View {
        ContentUnavailableView {
            Label("Choose a Workspace", systemImage: "folder.badge.plus")
        } description: {
            Text(
                "Select an existing MeetingBuddy workspace or an empty folder for a new local workspace."
            )
        } actions: {
            Button("Choose Workspace…") {
                presentFileImporter(.workspace)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isWorking || store.blocksWorkspaceSwitch)
        }
    }

    private var navigationTitle: String {
        switch store.selectedSection {
        case .recording: "Record Audio"
        case .webMetadata: "UN Web TV Metadata"
        case .transcript: "Transcript Review"
        case .analysis: "Analysis Review"
        case .briefing: "Briefing"
        case .history: "Meeting History"
        case .storage: "Storage"
        case .intake, nil: "Local Media Intake"
        }
    }

    private var intakeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourceForm
                if let pending = store.pendingMedia {
                    pendingMediaCard(pending)
                }
                if let source = store.importedSource {
                    importedSourceCard(source)
                }
                if let job = store.job {
                    processingCard(job)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var sourceForm: some View {
        GroupBox("Meeting and source policy") {
            Form {
                TextField("Meeting title", text: $store.meetingTitle)
                Picker("Classification", selection: $store.dataClassification) {
                    ForEach(ClassificationChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                TextField("Language tag (optional)", text: $store.languageTag)
                LabeledContent("Processing route", value: "Local only")
            }
            .formStyle(.grouped)
            HStack {
                Button("Choose Audio or Video…") {
                    presentFileImporter(.media)
                }
                .keyboardShortcut("i", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
                .accessibilityHint("Choose one local audio or video file for bounded inspection.")
                Text("MOV, MP4, M4A, MP3, or WAV")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .bottom])
        }
    }

    private func presentFileImporter(_ purpose: LocalFileImporterPurpose) {
        fileImporterPurpose = purpose
        showFileImporter = true
    }

    private func pendingMediaCard(_ pending: PendingMediaReview) -> some View {
        GroupBox("Selected source") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("File", value: pending.displayName)
                LabeledContent("Format", value: pending.inspection.format.rawValue.uppercased())
                LabeledContent(
                    "Duration",
                    value: durationLabel(pending.inspection.durationFrameCount)
                )
                Picker("Audio track", selection: $store.selectedTrack) {
                    if pending.inspection.audioTracks.count > 1 {
                        Text("Select a track").tag(Optional<MediaTrackIdentifier>.none)
                    }
                    ForEach(pending.inspection.audioTracks) { track in
                        Text(trackLabel(track)).tag(Optional(track.trackIdentifier))
                    }
                }
                Picker("Speech provenance", selection: $store.speechSourceKind) {
                    ForEach(SpeechKindChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                HStack {
                    Button("Import and Process") {
                        Task { await store.importAndProcess() }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)
                    .accessibilityHint("Copy, hash, register, and process the selected source locally.")
                    Button("Clear", role: .cancel) {
                        store.discardPendingMedia()
                    }
                    .disabled(store.isWorking)
                }
            }
            .padding()
        }
    }

    private func importedSourceCard(_ source: ImportedSourceReview) -> some View {
        GroupBox("Managed source") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { Text("Status"); Label("Copied and hash verified", systemImage: "checkmark.seal") }
                GridRow { Text("Format"); Text(source.format.rawValue.uppercased()) }
                GridRow { Text("Size"); Text(ByteCountFormatter.string(fromByteCount: Int64(source.byteSize), countStyle: .file)) }
                GridRow { Text("SHA-256"); Text(String(source.sourceHash.lowercaseHex.prefix(16)) + "…").monospaced() }
                GridRow { Text("Track"); Text(source.selectedTrack.description) }
                GridRow { Text("Provenance"); Text(source.speechSourceKind.encodedValue.replacingOccurrences(of: "_", with: " ")) }
            }
            .padding()
        }
    }

    private func processingCard(_ job: MediaJobReview) -> some View {
        GroupBox("Canonical audio and chunks") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(job.state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: statusSymbol(job.state))
                    Spacer()
                    Text(job.currentNode ?? "Waiting")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: job.progressFraction)
                    .accessibilityLabel("Canonical audio progress")
                    .accessibilityValue("\(job.completedUnitCount) of \(job.totalUnitCount) verified stages")
                Text("\(job.completedUnitCount) of \(job.totalUnitCount) verified stages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failure = job.safeFailureSummary {
                    Text(failure)
                        .foregroundStyle(.red)
                }
                HStack {
                    if job.canCancel {
                        Button("Cancel", role: .cancel) {
                            Task { await store.cancelJob() }
                        }
                    }
                    if job.canRetry {
                        Button("Retry") {
                            Task { await store.retryJob() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
    }

    private func durationLabel(_ frames: UInt64) -> String {
        let seconds = Double(frames) / Double(CanonicalAudioProfile.v1.sampleRateHertz)
        return seconds.formatted(.number.precision(.fractionLength(2))) + " s"
    }

    private func trackLabel(_ track: AudioTrackDescriptor) -> String {
        var details = ["Track \(track.trackIdentifier.rawValue)"]
        if let language = track.language?.value { details.append(language) }
        if let channels = track.sourceChannelCount { details.append("\(channels) ch") }
        if let rate = track.sourceSampleRateHertz { details.append("\(rate) Hz") }
        return details.joined(separator: " · ")
    }

    private func statusSymbol(_ state: JobState) -> String {
        switch state {
        case .succeeded: "checkmark.circle.fill"
        case .failed, .interrupted: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        case .paused, .pauseRequested: "pause.circle"
        default: "gearshape.2"
        }
    }
}
