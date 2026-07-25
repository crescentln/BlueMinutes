import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI
import UniformTypeIdentifiers

public struct MeetingBuddyRootView: View {
    @Bindable private var store: MediaReviewStore
    @State private var sceneState: MediaReviewSceneState
    @State private var fileImporterPurpose = LocalFileImporterPurpose.workspace
    @State private var showFileImporter = false
    private let onSceneStateAvailable:
        @MainActor (MediaReviewSceneState) -> Void

    public init(
        store: MediaReviewStore,
        onSceneStateAvailable:
            @escaping @MainActor (MediaReviewSceneState) -> Void = { _ in }
    ) {
        _store = Bindable(wrappedValue: store)
        _sceneState = State(initialValue: MediaReviewSceneState())
        self.onSceneStateAvailable = onSceneStateAvailable
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: sectionSelection) {
                Section("Workspace") {
                    WorkspaceSidebarRow(
                        title: store.workspace?.displayName ?? "No workspace open",
                        icon: store.workspace == nil
                            ? .workspaceUnavailable
                            : .workspace,
                        enabledHint: store.workspace == nil
                            ? "No local workspace is open."
                            : "Current local workspace."
                    )
                    Button("Choose Workspace…") {
                        presentFileImporter(.workspace)
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(store.isWorking || store.blocksWorkspaceSwitch)
                    .accessibilityHint("Open an existing local workspace or create one in an empty folder.")
                }
                Section("Workflow") {
                    WorkspaceSidebarRow(
                        title: "Local Media",
                        icon: .intake,
                        enabledHint: "Open Local Media."
                    )
                        .tag(MediaReviewSection.intake)
                    WorkspaceSidebarRow(
                        title: "Record Audio",
                        icon: .recording,
                        enabledHint: "Open Record Audio."
                    )
                        .tag(MediaReviewSection.recording)
                    WorkspaceSidebarRow(
                        title: "UN Web TV Metadata",
                        icon: .webMetadata,
                        enabledHint: "Open UN Web TV Metadata."
                    )
                        .tag(MediaReviewSection.webMetadata)
                    WorkspaceSidebarRow(
                        title: "Transcript Review",
                        icon: .transcript,
                        enabledHint: "Open Transcript Review.",
                        disabledReason:
                            "Available after local media processing succeeds."
                    )
                        .tag(MediaReviewSection.transcript)
                        .disabled(
                            !sceneState.isDestinationAvailable(.transcript)
                        )
                    WorkspaceSidebarRow(
                        title: "Analysis Review",
                        icon: .analysis,
                        enabledHint: "Open Analysis Review.",
                        disabledReason:
                            "Available after local media processing succeeds and transcript review is loaded."
                    )
                        .tag(MediaReviewSection.analysis)
                        .disabled(
                            !sceneState.isDestinationAvailable(.analysis)
                        )
                    WorkspaceSidebarRow(
                        title: "Briefing",
                        icon: .briefing,
                        enabledHint: "Open Briefing.",
                        disabledReason:
                            "Available after local media processing succeeds, transcript review is loaded, and analysis is human-confirmed."
                    )
                        .tag(MediaReviewSection.briefing)
                        .disabled(
                            !sceneState.isDestinationAvailable(.briefing)
                        )
                    WorkspaceSidebarRow(
                        title: "Meeting History",
                        icon: .history,
                        enabledHint: "Open Meeting History."
                    )
                        .tag(MediaReviewSection.history)
                    WorkspaceSidebarRow(
                        title: "Storage",
                        icon: .storage,
                        enabledHint: "Open Storage."
                    )
                        .tag(MediaReviewSection.storage)
                }
            }
            .navigationTitle("BlueMinutes")
            .listStyle(.sidebar)
        } detail: {
            detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BlueMinutesColors.canvas)
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
        .disabled(sceneState.isInteractionLocked || store.isWorking)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            onSceneStateAvailable(sceneState)
        }
        .task {
            await store.restoreWorkspace(using: sceneState)
            reconcileDestination()
        }
        .onChange(of: sceneState.selectedSection) { _, section in
            Task {
                switch section {
                case .recording:
                    await store.loadRecordingSetup(using: sceneState)
                case .transcript:
                    await store.loadTranscriptReview()
                    await store.refreshTranscriptRoute(using: sceneState)
                case .analysis:
                    await store.loadAnalysisReview()
                    await store.refreshAnalysisRoute()
                case .briefing:
                    await store.loadBriefingReview()
                    await store.refreshBriefingRoute()
                case .history:
                    await store.loadHistoricalReview(using: sceneState)
                case .storage:
                    await store.loadStorageReport()
                case .intake, .webMetadata, nil:
                    break
                }
            }
        }
        .onChange(of: store.job?.state) { _, _ in reconcileDestination() }
        .onChange(of: store.transcriptReview?.manifest.manifestID) { _, _ in
            reconcileDestination()
        }
        .onChange(of: store.analysisReview?.isHumanConfirmed) { _, _ in
            reconcileDestination()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileImporterPurpose.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            switch fileImporterPurpose {
            case .workspace:
                resolveNavigationEffect(sceneState.requestWorkspaceChange(to: url))
            case .media:
                Task { await store.inspectMedia(at: url, using: sceneState) }
            }
        }
        .alert(
            "BlueMinutes",
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
            "Unsaved Editor Changes",
            isPresented: Binding(
                get: { sceneState.isNavigationConfirmationPresented },
                set: {
                    sceneState.navigationConfirmationPresentationChanged(
                        isPresented: $0
                    )
                }
            ),
            titleVisibility: .visible
        ) {
            if sceneState.canSavePendingChanges {
                Button("Save and Continue") {
                    if let operation = sceneState.beginPendingNavigationSave() {
                        Task {
                            await savePendingDraftAndResolve(operation)
                        }
                    }
                }
            }
            Button("Discard Changes", role: .destructive) {
                resolveNavigationEffect(
                    sceneState.discardChangesAndResolvePending()
                )
            }
            Button("Keep Editing", role: .cancel) {
                sceneState.cancelPendingNavigation()
            }
        } message: {
            Text(sceneState.navigationConfirmationMessage)
        }
        .confirmationDialog(
            "Permanently delete this managed file?",
            isPresented: Binding(
                get: { sceneState.pendingPermanentDeletion != nil },
                set: { if !$0 { sceneState.pendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = sceneState.pendingPermanentDeletion {
                Button("Delete Permanently", role: .destructive) {
                    sceneState.pendingPermanentDeletion = nil
                    Task {
                        await store.permanentlyDeleteTrashItem(
                            item.storageObjectID,
                            confirmedByVisibleDialog: true
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                sceneState.pendingPermanentDeletion = nil
            }
        } message: {
            Text("This removes the verified Workspace Trash file after its retention interval. It preserves immutable audit history and does not guarantee forensic erasure on APFS, SSDs, snapshots, or backups.")
        }
    }

    private func recordingBanner(_ recording: RecordingSessionReview) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(BlueMinutesColors.recording)
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
        .background(BlueMinutesColors.recordingSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visible recording state: \(recording.state.rawValue)")
    }

    @ViewBuilder
    private var detailContent: some View {
        if store.workspace == nil {
            workspaceOnboarding
        } else {
            switch sceneState.selectedSection ?? .intake {
            case .intake:
                intakeView
            case .recording:
                RecordingCaptureView(store: store, sceneState: sceneState)
            case .webMetadata:
                UNWebTVMetadataView(store: store, sceneState: sceneState)
            case .transcript:
                TranscriptReviewView(store: store, sceneState: sceneState)
            case .analysis:
                AnalysisReviewView(store: store, sceneState: sceneState)
            case .briefing:
                BriefingReviewView(store: store, sceneState: sceneState)
            case .history:
                HistoricalReviewView(store: store, sceneState: sceneState)
            case .storage:
                StorageDashboardView(store: store) { item in
                    sceneState.pendingPermanentDeletion = item
                }
            }
        }
    }

    private var workspaceOnboarding: some View {
        ContentUnavailableView {
            Label(
                "Choose a Workspace",
                systemImage: BlueMinutesIconRole.chooseWorkspace
                    .resolvedSystemName()
            )
        } description: {
            Text(
                "Select an existing BlueMinutes workspace or an empty folder for a new local workspace."
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
        switch sceneState.selectedSection {
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
                TextField("Meeting title", text: $sceneState.meetingTitle)
                Picker("Classification", selection: $sceneState.dataClassification) {
                    ForEach(ClassificationChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                TextField("Language tag (optional)", text: $sceneState.languageTag)
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

    private var sectionSelection: Binding<MediaReviewSection?> {
        Binding(
            get: { sceneState.selectedSection },
            set: { sceneState.requestSection($0) }
        )
    }

    private func reconcileDestination() {
        sceneState.reconcileDestinationAvailability(
            canonicalJobSucceeded: store.job?.state == .succeeded,
            hasTranscriptReview: store.transcriptReview != nil,
            hasHumanConfirmedAnalysis: store.analysisReview?.isHumanConfirmed == true
        )
    }

    private func resolveNavigationEffect(_ effect: MediaReviewNavigationEffect?) {
        guard let effect else { return }
        switch effect {
        case .none:
            reconcileEditorDrafts()
        case let .openWorkspace(url):
            guard let operation = sceneState.beginWorkspaceChange(to: url) else {
                return
            }
            Task {
                await sceneState.resolveWorkspaceChange(operation) { selectedURL in
                    await store.openOrCreateWorkspace(
                        at: selectedURL,
                        using: sceneState
                    )
                }
                reconcileDestination()
            }
        case .importPendingMedia:
            Task {
                await store.importAndProcess(using: sceneState)
                reconcileEditorDrafts()
                reconcileDestination()
            }
        }
    }

    private func savePendingDraftAndResolve(
        _ operation: MediaReviewEditorSaveOperation
    ) async {
        let effect = await sceneState.resolvePendingNavigationSave(
            operation,
            updatedReviews: { store.editorReviewSnapshot }
        ) { request in
            await store.saveEditorDraft(request)
        }
        if effect != nil {
            reconcileEditorDrafts()
        }
        resolveNavigationEffect(effect)
    }

    private func reconcileEditorDrafts() {
        sceneState.transcript.reconcile(with: store.transcriptReview)
        sceneState.analysis.reconcile(with: store.analysisReview)
        sceneState.briefing.reconcile(with: store.briefingReview)
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
                Picker("Audio track", selection: $sceneState.selectedTrack) {
                    if pending.inspection.audioTracks.count > 1 {
                        Text("Select a track").tag(Optional<MediaTrackIdentifier>.none)
                    }
                    ForEach(pending.inspection.audioTracks) { track in
                        Text(trackLabel(track)).tag(Optional(track.trackIdentifier))
                    }
                }
                Picker("Speech provenance", selection: $sceneState.speechSourceKind) {
                    ForEach(SpeechKindChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                HStack {
                    Button("Import and Process") {
                        resolveNavigationEffect(
                            sceneState.requestMediaImport()
                        )
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.isWorking || store.blocksMediaReplacement
                    )
                    .accessibilityHint("Copy, hash, register, and process the selected source locally.")
                    Button("Clear", role: .cancel) {
                        store.discardPendingMedia(using: sceneState)
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
                    Label(
                        job.state.rawValue
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized,
                        systemImage: statusIcon(job.state)
                            .resolvedSystemName()
                    )
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
                        .foregroundStyle(BlueMinutesColors.error)
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

    private func statusIcon(_ state: JobState) -> BlueMinutesIconRole {
        switch state {
        case .succeeded: .success
        case .failed, .interrupted: .failure
        case .cancelled: .cancelled
        case .paused, .pauseRequested: .paused
        default: .working
        }
    }
}
