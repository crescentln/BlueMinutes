import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct LocalMediaIntakeView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @Environment(\.blueMinutesReadingWidth)
    private var readingWidth
    let intelligenceStore:
        IntelligenceConfigurationStore?

    let chooseMedia: @MainActor () -> Void
    let requestImport: @MainActor () -> Void

    init(
        store: MediaReviewStore,
        sceneState: MediaReviewSceneState,
        intelligenceStore:
            IntelligenceConfigurationStore? = nil,
        chooseMedia:
            @escaping @MainActor () -> Void,
        requestImport:
            @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.sceneState = sceneState
        self.intelligenceStore =
            intelligenceStore
        self.chooseMedia = chooseMedia
        self.requestImport = requestImport
    }

    var body: some View {
        BlueMinutesDetailScrollView(
            contentMaxWidth: readingWidth.points
        ) {
            VStack(alignment: .leading, spacing: 28) {
                newMeetingSection
                sourceSection
                if let pending = store.pendingMedia {
                    selectedSourceSection(pending)
                }
                if let recovery =
                        store.sourceReselectionJob
                {
                    sourceReselectionSection(
                        recovery
                    )
                }
                if let source = store.importedSource {
                    managedSourceSection(source)
                }
                if let job = store.job {
                    processingSection(job)
                }
            }
            .padding(28)
        }
        .onChange(of: sceneState.dataClassification) { _, _ in
            if !codexTextProcessingIsEligible {
                sceneState.codexTextProcessingAllowed = false
                if sceneState
                    .transcriptionSelection?
                    .providerIdentifier
                    != "apple-speech"
                {
                    sceneState.transcriptionSelection =
                        nil
                    sceneState
                        .remoteSpeechToTextAllowed =
                        false
                }
            }
        }
    }

    private var newMeetingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Start a New Meeting",
                detail:
                    "Choose the existing BlueMinutes workflow that matches the source. Every path keeps the same meeting policy, STT routing, local storage, and review gates."
            )
            HStack {
                Button("Import Local Media…") {
                    chooseMedia()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
                .accessibilityIdentifier(
                    "BlueMinutes.NewMeeting.Import"
                )
                Button("Record Live Audio") {
                    sceneState.requestSection(
                        .recording
                    )
                }
                .disabled(
                    sceneState
                        .isInteractionLocked
                        || store.isWorking
                )
                .accessibilityIdentifier(
                    "BlueMinutes.NewMeeting.Record"
                )
                Button("Use UN Web TV Metadata") {
                    sceneState.requestSection(
                        .webMetadata
                    )
                }
                .disabled(
                    sceneState
                        .isInteractionLocked
                        || store.isWorking
                )
                .accessibilityIdentifier(
                    "BlueMinutes.NewMeeting.UNWebTV"
                )
            }
            Text(
                "This coordinator reuses the current pages; it does not create a second copy of their forms or start any capture, network request, upload, or model task."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Meeting and source policy",
                detail:
                    "Describe the meeting, then choose one local audio or video file for bounded inspection."
            )
            Form {
                TextField("Meeting title", text: $sceneState.meetingTitle)
                Picker("Classification", selection: $sceneState.dataClassification) {
                    ForEach(ClassificationChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                TextField("Language tag (optional)", text: $sceneState.languageTag)
                Toggle(
                    "Allow explicitly selected transcript text to use Codex",
                    isOn:
                        $sceneState
                        .codexTextProcessingAllowed
                )
                .toggleStyle(.checkbox)
                .disabled(!codexTextProcessingIsEligible)
                Text(
                    codexTextProcessingIsEligible
                        ? "Audio and speech-to-text stay separate. Each Codex request still requires visible authorization."
                        : "Sensitive and Restricted meetings keep all text processing on this Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                SpeechToTextRoutePicker(
                    sceneState: sceneState,
                    intelligenceStore:
                        intelligenceStore,
                    existingMeeting: false,
                    requiresExecutionAuthorization:
                        false
                )
                LabeledContent(
                    "Audio processing route",
                    value:
                        sceneState
                        .transcriptionSelection?
                        .providerIdentifier
                        == "openai-stt"
                        ? "Local recording; explicit remote STT after canonical processing"
                        : "Private local workspace"
                )
            }
            .formStyle(.columns)

            HStack {
                Button("Choose Audio or Video…") {
                    chooseMedia()
                }
                .keyboardShortcut("i", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
                .accessibilityIdentifier(
                    "BlueMinutes.LocalMedia.ChooseSource"
                )
                .accessibilityHint(
                    "Choose one local audio or video file for bounded inspection."
                )
                Text("MOV, MP4, M4A, MP3, or WAV")
                    .foregroundStyle(.secondary)
            }

            importReadiness
        }
    }

    private var importReadiness: some View {
        Group {
            if let importBlockedReason {
                WorkflowStateView(
                    title: "Import blocked",
                    detail: importBlockedReason,
                    systemImage: "exclamationmark.circle",
                    tone: .warning
                )
            } else {
                WorkflowStateView(
                    title: "Ready to import",
                    detail:
                        "The selected source can be copied, hashed, registered, and processed through the local Task Manager.",
                    systemImage: "checkmark.circle",
                    tone: .ready
                )
            }
        }
        .accessibilityIdentifier("BlueMinutes.LocalMedia.ImportReadiness")
    }

    private func selectedSourceSection(
        _ pending: PendingMediaReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Selected source",
                detail:
                    "This is a transient inspection. The original source path is neither displayed nor persisted."
            )
            LabeledContent("File", value: pending.displayName)
            LabeledContent(
                "Format",
                value: pending.inspection.format.rawValue.uppercased()
            )
            LabeledContent(
                "Duration",
                value: durationLabel(pending.inspection.durationFrameCount)
            )
            Picker("Audio track", selection: $sceneState.selectedTrack) {
                if pending.inspection.audioTracks.count > 1 {
                    Text("Select a track")
                        .tag(Optional<MediaTrackIdentifier>.none)
                }
                ForEach(pending.inspection.audioTracks) { track in
                    Text(trackLabel(track))
                        .tag(Optional(track.trackIdentifier))
                }
            }
            Picker(
                "Speech provenance",
                selection: $sceneState.speechSourceKind
            ) {
                ForEach(SpeechKindChoice.all) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
            HStack {
                Button("Import and Process") {
                    requestImport()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(importRequestIsDisabled)
                .accessibilityIdentifier(
                    "BlueMinutes.LocalMedia.ImportAndProcess"
                )
                .accessibilityHint(
                    importBlockedReason
                        ?? "Copy, hash, register, and process the selected source locally."
                )
                Button("Clear", role: .cancel) {
                    store.discardPendingMedia(using: sceneState)
                }
                .disabled(store.isWorking)
            }
        }
    }

    private func managedSourceSection(
        _ source: ImportedSourceReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Managed source proof",
                detail:
                    "BlueMinutes copied the selected bytes into the private workspace and verified the managed object."
            )
            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 8
            ) {
                GridRow {
                    Text("Status")
                    Label(
                        "Copied and hash verified",
                        systemImage: "checkmark.seal"
                    )
                }
                GridRow {
                    Text("Format")
                    Text(source.format.rawValue.uppercased())
                }
                GridRow {
                    Text("Size")
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(source.byteSize),
                            countStyle: .file
                        )
                    )
                }
                GridRow {
                    Text("SHA-256")
                    Text(
                        String(source.sourceHash.lowercaseHex.prefix(16)) + "…"
                    )
                    .monospaced()
                }
                GridRow {
                    Text("Track")
                    Text(source.selectedTrack.description)
                }
                GridRow {
                    Text("Provenance")
                    Text(
                        source.speechSourceKind.encodedValue
                            .replacingOccurrences(of: "_", with: " ")
                    )
                }
            }
        }
    }

    private func sourceReselectionSection(
        _ recovery: MediaJobReview
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            EditorialSectionHeader(
                "Source selection required",
                detail:
                    "A previous import stopped before the selected file was safely copied into this workspace."
            )
            WorkflowStateView(
                title: "Choose the source again",
                detail:
                    recovery.safeFailureSummary
                    ?? "BlueMinutes does not retain source-file authority across launches. Select the intended local file again to restart the import.",
                systemImage:
                    "arrow.clockwise.circle",
                tone: .warning
            )
        }
    }

    private func processingSection(_ job: MediaJobReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Canonical audio and chunks",
                detail:
                    "Progress, cancellation, and retry remain owned by the local Task Manager."
            )
            WorkflowStateView(
                title: job.state.rawValue
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized,
                detail: job.currentNode ?? "Waiting for the next verified stage.",
                systemImage: statusIcon(job.state).resolvedSystemName(),
                tone: statusTone(job.state)
            )
            ProgressView(value: job.progressFraction)
                .accessibilityLabel("Canonical audio progress")
                .accessibilityValue(
                    "\(job.completedUnitCount) of \(job.totalUnitCount) verified stages"
                )
            Text(
                "\(job.completedUnitCount) of \(job.totalUnitCount) verified stages"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            LabeledContent(
                "Privacy route",
                value: job.privacyRoute.encodedValue
            )
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
    }

    private var importBlockedReason: String? {
        IntakeSurfacePresentation.localMediaImportBlockedReason(
            isInteractionLocked: sceneState.isInteractionLocked,
            hasUnsavedEditorChanges: sceneState.hasUnsavedEditorChanges,
            isWorking: store.isWorking,
            blocksMediaReplacement: store.blocksMediaReplacement,
            meetingTitle: sceneState.meetingTitle,
            pendingMedia: store.pendingMedia,
            selectedTrack: sceneState.selectedTrack,
            languageTag: sceneState.languageTag
        )
    }

    private var codexTextProcessingIsEligible: Bool {
        sceneState.dataClassification.restrictionRank
            < DataClassification.sensitive.restrictionRank
    }

    private var importRequestIsDisabled: Bool {
        guard let importBlockedReason else { return false }
        return importBlockedReason
            != IntakeSurfacePresentation.localMediaUnsavedDraftReason
    }

    private func durationLabel(_ frames: UInt64) -> String {
        let seconds =
            Double(frames)
                / Double(CanonicalAudioProfile.v1.sampleRateHertz)
        return seconds.formatted(
            .number.precision(.fractionLength(2))
        ) + " s"
    }

    private func trackLabel(_ track: AudioTrackDescriptor) -> String {
        var details = ["Track \(track.trackIdentifier.rawValue)"]
        if let language = track.language?.value {
            details.append(language)
        }
        if let channels = track.sourceChannelCount {
            details.append("\(channels) ch")
        }
        if let rate = track.sourceSampleRateHertz {
            details.append("\(rate) Hz")
        }
        return details.joined(separator: " · ")
    }

    private func statusIcon(_ state: JobState) -> BlueMinutesIconRole {
        switch state {
        case .succeeded:
            .success
        case .failed, .interrupted:
            .failure
        case .cancelled:
            .cancelled
        case .paused, .pauseRequested:
            .paused
        default:
            .working
        }
    }

    private func statusTone(_ state: JobState) -> WorkflowStateTone {
        switch state {
        case .succeeded:
            .success
        case .failed, .interrupted:
            .failure
        case .cancelled, .paused, .pauseRequested:
            .warning
        default:
            .working
        }
    }
}
