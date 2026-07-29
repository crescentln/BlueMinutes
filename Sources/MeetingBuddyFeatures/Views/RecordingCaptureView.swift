import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct RecordingCaptureView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @Environment(\.blueMinutesReadingWidth)
    private var readingWidth
    let intelligenceStore:
        IntelligenceConfigurationStore?

    init(
        store: MediaReviewStore,
        sceneState: MediaReviewSceneState,
        intelligenceStore:
            IntelligenceConfigurationStore? = nil
    ) {
        self.store = store
        self.sceneState = sceneState
        self.intelligenceStore =
            intelligenceStore
    }

    var body: some View {
        BlueMinutesDetailScrollView(
            contentMaxWidth: readingWidth.points
        ) {
            VStack(alignment: .leading, spacing: 28) {
                capabilitySection
                captureSection
                if let session = store.recordingSession {
                    sessionSection(session)
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

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Local audio capture boundary",
                detail:
                    "Audio only. BlueMinutes never requests a screen track, all-system audio, multiple applications, hidden capture, or persistent capture authority."
            )
            if let setup = store.recordingSetup {
                microphoneCapability(setup.capability.microphonePermission)
                applicationAudioCapability(setup.capability)
            } else {
                WorkflowStateView(
                    title: "Checking capture capabilities",
                    detail:
                        "BlueMinutes is checking the current microphone permission, device list, and one-application audio picker.",
                    systemImage: "hourglass",
                    tone: .working
                )
            }
        }
    }

    private func microphoneCapability(
        _ permission: CapturePermissionState
    ) -> some View {
        switch permission {
        case .authorized:
            WorkflowStateView(
                title: "Microphone ready",
                detail:
                    "A microphone may be selected explicitly for this recording session.",
                systemImage: "mic.circle",
                tone: .ready
            )
        case .notDetermined:
            WorkflowStateView(
                title: "Microphone permission not determined",
                detail:
                    "Starting a microphone recording will present the visible macOS permission prompt. If access is declined, recording fails closed.",
                systemImage: "questionmark.circle",
                tone: .warning
            )
        case .denied:
            WorkflowStateView(
                title: "Microphone permission denied",
                detail:
                    "Microphone capture is blocked. Application-only capture remains separate when available.",
                systemImage: "mic.slash",
                tone: .failure
            )
        case .restricted:
            WorkflowStateView(
                title: "Microphone access restricted",
                detail:
                    "The current macOS policy prevents microphone capture.",
                systemImage: "lock.circle",
                tone: .failure
            )
        }
    }

    private func applicationAudioCapability(
        _ capability: CaptureCapabilitySnapshot
    ) -> some View {
        if capability.applicationAudioAvailable,
           capability.systemPickerAvailable
        {
            WorkflowStateView(
                title: "One-application audio ready",
                detail:
                    "Apple's foreground system picker will require one exact application selection for this session.",
                systemImage: "macwindow",
                tone: .ready
            )
        } else {
            WorkflowStateView(
                title: "One-application audio unavailable",
                detail:
                    "This macOS build or current capability snapshot cannot provide the bounded system picker.",
                systemImage: "macwindow.badge.exclamationmark",
                tone: .warning
            )
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "New visible recording",
                detail:
                    "Every start and resumed capture epoch requires a fresh visible acknowledgement and exact source selection."
            )
            Form {
                TextField("Meeting title", text: $sceneState.meetingTitle)
                Picker(
                    "Classification",
                    selection: $sceneState.dataClassification
                ) {
                    ForEach(ClassificationChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                TextField(
                    "Language tag (optional)",
                    text: $sceneState.languageTag
                )
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
                        ? "Audio and speech-to-text remain local and separate. Each Codex text request still requires visible authorization."
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
                Picker("Capture mode", selection: $sceneState.captureMode) {
                    ForEach(CaptureModeChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .disabled(store.blocksWorkspaceSwitch)

                if sceneState.captureMode.requestedTrackKinds
                    .contains(.microphone)
                {
                    Picker(
                        "Microphone",
                        selection: $sceneState.selectedMicrophoneDeviceID
                    ) {
                        Text("Select one microphone")
                            .tag(Optional<String>.none)
                        ForEach(
                            store.recordingSetup?.microphones ?? []
                        ) { microphone in
                            Text(microphone.displayName)
                                .tag(Optional(microphone.id))
                        }
                    }
                    Picker(
                        "Microphone speech provenance",
                        selection: $sceneState.microphoneSpeechSourceKind
                    ) {
                        ForEach(SpeechKindChoice.all) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                }
                if sceneState.captureMode.requestedTrackKinds
                    .contains(.applicationAudio)
                {
                    Picker(
                        "Application speech provenance",
                        selection: $sceneState.applicationSpeechSourceKind
                    ) {
                        ForEach(SpeechKindChoice.all) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    Text(
                        "Apple's system picker requires one foreground application selection. The selection is not saved for reuse."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Toggle(
                    "I am starting this visible recording directly and acknowledge responsibility for participant notice, consent, venue rules, organization policy, and applicable law.",
                    isOn: $sceneState.recordingAcknowledged
                )
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: false, vertical: true)
                LabeledContent(
                    "Audio storage and processing",
                    value: "Private local workspace only"
                )
            }
            .formStyle(.columns)

            recordingReadiness

            HStack {
                Button("Refresh Devices") {
                    Task {
                        await store.loadRecordingSetup(using: sceneState)
                    }
                }
                .disabled(store.isWorking || store.blocksWorkspaceSwitch)
                Spacer()
                Button("Start Visible Recording") {
                    Task {
                        await store.startRecording(using: sceneState)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordingStartBlockedReason != nil)
                .accessibilityIdentifier(
                    "BlueMinutes.Recording.StartVisible"
                )
                .accessibilityHint(
                    recordingStartBlockedReason
                        ?? "Create a durable intent, request exact source permission, and then begin local audio capture."
                )
            }
        }
    }

    private var recordingReadiness: some View {
        Group {
            if let recordingStartBlockedReason {
                WorkflowStateView(
                    title: "Recording blocked",
                    detail: recordingStartBlockedReason,
                    systemImage: "exclamationmark.circle",
                    tone: .warning
                )
            } else {
                WorkflowStateView(
                    title: "Ready for visible recording",
                    detail:
                        "Starting will persist the local intent before requesting the exact source selection.",
                    systemImage: "record.circle",
                    tone: .ready
                )
            }
        }
        .accessibilityIdentifier("BlueMinutes.Recording.Readiness")
    }

    private var codexTextProcessingIsEligible: Bool {
        sceneState.dataClassification.restrictionRank
            < DataClassification.sensitive.restrictionRank
    }

    private func sessionSection(
        _ session: RecordingSessionReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Recording status",
                detail:
                    "The root-level Stop control remains visible from every destination while this session is active."
            )
            WorkflowStateView(
                title:
                    IntakeSurfacePresentation.recordingStateTitle(
                        session.state
                    ),
                detail:
                    IntakeSurfacePresentation.recordingStateExplanation(
                        session.state
                    ),
                systemImage: sessionStateIcon(session.state),
                tone: sessionStateTone(session.state)
            )
            if session.state == .incomplete {
                Text("INCOMPLETE")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .accessibilityLabel("Incomplete recording")
            }
            LabeledContent(
                "Tracks",
                value: session.activeTrackKinds
                    .map(trackLabel)
                    .joined(separator: ", ")
            )
            LabeledContent(
                "Durable through",
                value: session.durableThroughNanoseconds
                    .map(durationLabel)
                    ?? "No sealed interval yet"
            )
            LabeledContent(
                "Known gaps",
                value: String(session.knownGapCount)
            )
            if let reason = session.safeReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if session.canStop {
                HStack {
                    if session.state == .interrupted
                        || session.state == .recovering
                    {
                        Button("Resume with New Selection") {
                            Task {
                                await store.resumeRecording(
                                    using: sceneState
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            store.isWorking
                                || !sceneState.recordingAcknowledged
                        )
                        .accessibilityHint(
                            "Request the source again and persist a new provenance epoch before audio resumes."
                        )
                    }
                    Button(
                        session.state == .interrupted
                            || session.state == .recovering
                            ? "Finish Retained Recording"
                            : "Stop Recording"
                    ) {
                        Task { await store.stopRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isStoppingRecording)
                }
            }
            if session.state == .interrupted
                || session.state == .recovering
            {
                Text(
                    "Resume always opens a fresh system source selection and records a new epoch. Leaving this session here retains its verified local bytes without resuming or publishing it as complete."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if session.state == .incomplete {
                Text(
                    "Verified bytes are retained, but this result is not automatically activated for downstream processing. A later explicit reviewed-use action is required."
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }
            if session.state == .completed {
                completedRecordingSection(
                    session
                )
            }
        }
    }

    private func completedRecordingSection(
        _ session: RecordingSessionReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            EditorialSectionHeader(
                "Prepare recorded audio",
                detail:
                    "Choose one verified source track for the canonical local-audio workflow. This step does not upload audio or start speech-to-text."
            )
            if session.completedTracks.count
                > 1
            {
                Picker(
                    "Recorded source track",
                    selection:
                        $store
                        .selectedCompletedRecordingTrackID
                ) {
                    Text("Select one track")
                        .tag(
                            Optional<
                                RecordingTrackID
                            >.none
                        )
                    ForEach(
                        session.completedTracks
                    ) { track in
                        Text(
                            completedTrackLabel(
                                track
                            )
                        )
                        .tag(
                            Optional(
                                track.trackID
                            )
                        )
                    }
                }
                .accessibilityIdentifier(
                    "BlueMinutes.Recording.CompletedTrack"
                )
            } else if let track =
                        session
                        .completedTracks.first
            {
                LabeledContent(
                    "Recorded source track",
                    value:
                        completedTrackLabel(
                            track
                        )
                )
            }
            Text(
                "You may change the Speech-to-Text route above before continuing. The exact provider/model is evaluated again only when you explicitly start transcription; None keeps this as record-only audio."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                if store
                    .processedCompletedRecordingSessionID
                    == session.sessionID,
                   let job = store.job
                {
                    WorkflowStateView(
                        title:
                            "Recorded audio preparation \(job.state.rawValue)",
                        detail:
                            job.safeFailureSummary
                            ?? "BlueMinutes is preparing the selected local recording track.",
                        systemImage:
                            job.state == .succeeded
                            ? "checkmark.circle"
                            : "waveform",
                        tone:
                            job.state == .succeeded
                            ? .success
                            : job.state.isTerminal
                                ? .failure
                                : .working
                    )
                } else {
                    Spacer()
                    Button(
                        "Prepare Selected Track"
                    ) {
                        Task {
                            await store
                                .processCompletedRecording(
                                    using:
                                        sceneState
                                )
                        }
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        store
                            .selectedCompletedRecordingTrackID
                            == nil
                    )
                    .accessibilityIdentifier(
                        "BlueMinutes.Recording.PrepareTrack"
                    )
                    .accessibilityHint(
                        "Start the local canonical-audio job for the exact selected completed recording track."
                    )
                }
            }
        }
    }

    private var recordingStartBlockedReason: String? {
        IntakeSurfacePresentation.recordingStartBlockedReason(
            isInteractionLocked: sceneState.isInteractionLocked,
            isWorking: store.isWorking,
            blocksWorkspaceSwitch: store.blocksWorkspaceSwitch,
            setup: store.recordingSetup,
            meetingTitle: sceneState.meetingTitle,
            languageTag: sceneState.languageTag,
            mode: sceneState.captureMode,
            selectedMicrophoneDeviceID:
                sceneState.selectedMicrophoneDeviceID,
            recordingAcknowledged: sceneState.recordingAcknowledged
        )
    }

    private func sessionStateIcon(_ state: RecordingState) -> String {
        switch state {
        case .preparing:
            "hourglass"
        case .recording:
            "record.circle"
        case .interrupted:
            "bolt.slash.circle"
        case .recovering:
            "arrow.clockwise.circle"
        case .stopping:
            "stop.circle"
        case .finalizing:
            "checkmark.seal"
        case .completed:
            "checkmark.circle"
        case .incomplete:
            "exclamationmark.circle"
        case .failed:
            "xmark.octagon"
        }
    }

    private func sessionStateTone(
        _ state: RecordingState
    ) -> WorkflowStateTone {
        switch state {
        case .preparing, .stopping, .finalizing, .recovering:
            .working
        case .recording:
            .ready
        case .interrupted, .incomplete:
            .warning
        case .completed:
            .success
        case .failed:
            .failure
        }
    }

    private func trackLabel(_ kind: CaptureTrackKind) -> String {
        switch kind {
        case .microphone:
            "Microphone"
        case .applicationAudio:
            "Selected application audio"
        }
    }

    private func completedTrackLabel(
        _ track:
            CompletedRecordingTrackReview
    ) -> String {
        let duration =
            Double(track.durationFrameCount)
            / Double(
                CanonicalAudioProfile.v1
                    .sampleRateHertz
            )
        return String(
            format:
                "%@ · %.1f seconds · %@",
            trackLabel(track.kind),
            duration,
            track.speechSourceKind
                .encodedValue
        )
    }

    private func durationLabel(_ nanoseconds: UInt64) -> String {
        String(
            format: "%.1f seconds",
            Double(nanoseconds) / 1_000_000_000
        )
    }
}
