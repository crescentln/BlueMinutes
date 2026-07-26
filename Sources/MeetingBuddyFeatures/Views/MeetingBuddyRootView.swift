import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI
import UniformTypeIdentifiers

public struct MeetingBuddyRootView: View {
    @Bindable private var store: MediaReviewStore
    @State private var sceneState: MediaReviewSceneState
    @State private var fileImporterPurpose = LocalFileImporterPurpose.workspace
    @State private var showFileImporter = false
    @FocusState private var sidebarIsFocused: Bool
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
                            : "Current local workspace.",
                        availability: globalSidebarAvailability
                    )
                    Button("Choose Workspace…") {
                        presentFileImporter(.workspace)
                    }
                    .disabled(store.isWorking || store.blocksWorkspaceSwitch)
                    .accessibilityHint("Open an existing local workspace or create one in an empty folder.")
                }
                Section("Workflow") {
                    WorkspaceSidebarRow(
                        title: "Local Media",
                        icon: .intake,
                        enabledHint: "Open Local Media.",
                        availability: globalSidebarAvailability
                    )
                        .tag(MediaReviewSection.intake)
                    WorkspaceSidebarRow(
                        title: "Record Audio",
                        icon: .recording,
                        enabledHint: "Open Record Audio.",
                        availability: globalSidebarAvailability
                    )
                        .tag(MediaReviewSection.recording)
                    WorkspaceSidebarRow(
                        title: "UN Web TV Metadata",
                        icon: .webMetadata,
                        enabledHint: "Open UN Web TV Metadata.",
                        availability: globalSidebarAvailability
                    )
                        .tag(MediaReviewSection.webMetadata)
                    WorkspaceSidebarRow(
                        title: "Transcript Review",
                        icon: .transcript,
                        enabledHint: "Open Transcript Review.",
                        availability: sidebarAvailability(
                            for: .transcript,
                            prerequisiteReason:
                            "Available after local media processing succeeds."
                        )
                    )
                        .tag(MediaReviewSection.transcript)
                        .disabled(
                            !sceneState.isDestinationAvailable(.transcript)
                        )
                    WorkspaceSidebarRow(
                        title: "Analysis Review",
                        icon: .analysis,
                        enabledHint: "Open Analysis Review.",
                        availability: sidebarAvailability(
                            for: .analysis,
                            prerequisiteReason:
                            "Available after local media processing succeeds and transcript review is loaded."
                        )
                    )
                        .tag(MediaReviewSection.analysis)
                        .disabled(
                            !sceneState.isDestinationAvailable(.analysis)
                        )
                    WorkspaceSidebarRow(
                        title: "Briefing",
                        icon: .briefing,
                        enabledHint: "Open Briefing.",
                        availability: sidebarAvailability(
                            for: .briefing,
                            prerequisiteReason:
                            "Available after local media processing succeeds, transcript review is loaded, and analysis is human-confirmed."
                        )
                    )
                        .tag(MediaReviewSection.briefing)
                        .disabled(
                            !sceneState.isDestinationAvailable(.briefing)
                        )
                }
                Section("Library") {
                    WorkspaceSidebarRow(
                        title: "Meeting History",
                        icon: .history,
                        enabledHint: "Open Meeting History.",
                        availability: globalSidebarAvailability
                    )
                        .tag(MediaReviewSection.history)
                    WorkspaceSidebarRow(
                        title: "Storage",
                        icon: .storage,
                        enabledHint: "Open Storage.",
                        availability: globalSidebarAvailability
                    )
                        .tag(MediaReviewSection.storage)
                }
            }
            .navigationTitle("BlueMinutes")
            .listStyle(.sidebar)
            .disabled(
                sceneState.isInteractionLocked || store.isWorking
                    || store.isStoppingRecording
            )
            .focused($sidebarIsFocused)
            .navigationSplitViewColumnWidth(
                min: BlueMinutesLayout.sidebarMinimumWidth,
                ideal: BlueMinutesLayout.sidebarIdealWidth,
                max: BlueMinutesLayout.sidebarMaximumWidth
            )
        } detail: {
            BlueMinutesEditorialCanvas {
                detailContent
                    .disabled(
                        sceneState.isInteractionLocked || store.isWorking
                            || store.isStoppingRecording
                    )
            }
            .navigationTitle(navigationTitle)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let recording = store.recordingSession,
                   store.recordingIndicatorIsVisible
                {
                    recordingBanner(recording)
                }
            }
            .toolbar {
                BlueMinutesEditorialToolbarContent(
                    workspaceTitle: store.workspace?.displayName,
                    canChooseWorkspace: canChooseWorkspace,
                    workspaceSwitchUnavailableReason:
                        workspaceSwitchUnavailableReason,
                    isWorking: store.isWorking,
                    chooseWorkspace: chooseWorkspace
                )
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .focusedSceneValue(
            \.blueMinutesShellCommandActions,
            BlueMinutesShellCommandActions(
                canChooseWorkspace: canChooseWorkspace,
                chooseWorkspace: chooseWorkspace
            )
        )
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
            .disabled(store.isStoppingRecording || !recording.canStop)
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
                LocalMediaIntakeView(
                    store: store,
                    sceneState: sceneState,
                    chooseMedia: {
                        presentFileImporter(.media)
                    },
                    requestImport: {
                        resolveNavigationEffect(
                            sceneState.requestMediaImport()
                        )
                    }
                )
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

    private func presentFileImporter(_ purpose: LocalFileImporterPurpose) {
        fileImporterPurpose = purpose
        showFileImporter = true
    }

    private var canChooseWorkspace: Bool {
        workspaceSwitchUnavailableReason == nil
    }

    private var workspaceSwitchUnavailableReason: String? {
        if sceneState.isInteractionLocked {
            return "Temporarily unavailable while BlueMinutes completes a save or workspace change."
        }
        if store.isWorking {
            return "Temporarily unavailable while BlueMinutes completes the current operation."
        }
        if store.blocksWorkspaceSwitch {
            return "Finish or retain the current recording before switching workspaces."
        }
        return nil
    }

    private func chooseWorkspace() {
        presentFileImporter(.workspace)
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
            let workspaceSessionBeforeChange = store.workspaceSession
            Task {
                await sceneState.resolveWorkspaceChange(operation) { selectedURL in
                    await store.openOrCreateWorkspace(
                        at: selectedURL,
                        using: sceneState
                    )
                }
                reconcileDestination()
                if store.workspaceSession != workspaceSessionBeforeChange {
                    sidebarIsFocused = true
                }
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

    private var globalSidebarAvailability: WorkspaceSidebarRowAvailability {
        .resolve(
            prerequisiteReason: nil,
            temporaryReason: sidebarTemporaryUnavailableReason
        )
    }

    private func sidebarAvailability(
        for destination: MediaReviewSection,
        prerequisiteReason: String
    ) -> WorkspaceSidebarRowAvailability {
        .resolve(
            prerequisiteReason: sceneState.isDestinationAvailable(destination)
                ? nil
                : prerequisiteReason,
            temporaryReason: sidebarTemporaryUnavailableReason
        )
    }

    private var sidebarTemporaryUnavailableReason: String? {
        if sceneState.isInteractionLocked {
            return "Temporarily unavailable while BlueMinutes completes a save or workspace change."
        }
        if store.isWorking {
            return "Temporarily unavailable while BlueMinutes completes the current operation."
        }
        return nil
    }

}
