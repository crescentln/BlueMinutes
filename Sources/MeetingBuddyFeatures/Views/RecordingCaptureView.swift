import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct RecordingCaptureView: View {
    @Bindable var store: MediaReviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                capabilityCard
                captureForm
                if let session = store.recordingSession {
                    sessionCard(session)
                }
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }

    private var capabilityCard: some View {
        GroupBox("Local audio capture boundary") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(
                    "Microphone permission",
                    value: store.recordingSetup?.capability.microphonePermission.rawValue
                        ?? "Checking"
                )
                LabeledContent(
                    "One-application audio",
                    value: store.recordingSetup?.capability.applicationAudioAvailable == true
                        ? "Available with system picker" : "Unavailable on this macOS build"
                )
                Text(
                    "Audio only. MeetingBuddy never requests a screen track, all-system audio, multiple applications, hidden capture, or persistent capture authority."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var captureForm: some View {
        GroupBox("New visible recording") {
            Form {
                TextField("Meeting title", text: $store.meetingTitle)
                Picker("Classification", selection: $store.dataClassification) {
                    ForEach(ClassificationChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                TextField("Language tag (optional)", text: $store.languageTag)
                Picker("Capture mode", selection: $store.captureMode) {
                    ForEach(CaptureModeChoice.all) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .disabled(store.blocksWorkspaceSwitch)

                if store.captureMode.requestedTrackKinds.contains(.microphone) {
                    Picker("Microphone", selection: $store.selectedMicrophoneDeviceID) {
                        Text("Select one microphone")
                            .tag(Optional<String>.none)
                        ForEach(store.recordingSetup?.microphones ?? []) { microphone in
                            Text(microphone.displayName).tag(Optional(microphone.id))
                        }
                    }
                    Picker("Microphone speech provenance", selection: $store.microphoneSpeechSourceKind) {
                        ForEach(SpeechKindChoice.all) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                }
                if store.captureMode.requestedTrackKinds.contains(.applicationAudio) {
                    Picker("Application speech provenance", selection: $store.applicationSpeechSourceKind) {
                        ForEach(SpeechKindChoice.all) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    Text("Apple's system picker will require one foreground application selection. The selection is not saved for reuse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(
                    "I am starting this visible recording directly and acknowledge responsibility for participant notice, consent, venue rules, organization policy, and applicable law.",
                    isOn: $store.recordingAcknowledged
                )
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Storage and processing", value: "Private local workspace only")
            }
            .formStyle(.grouped)

            HStack {
                Button("Refresh Devices") {
                    Task { await store.loadRecordingSetup() }
                }
                .disabled(store.isWorking || store.blocksWorkspaceSwitch)
                Spacer()
                Button("Start Visible Recording") {
                    Task { await store.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.isWorking
                        || store.blocksWorkspaceSwitch
                        || !store.recordingAcknowledged
                )
                .accessibilityHint(
                    "Create a durable intent, request exact source permission, and then begin local audio capture."
                )
            }
            .padding([.horizontal, .bottom])
        }
    }

    private func sessionCard(_ session: RecordingSessionReview) -> some View {
        GroupBox("Recording status") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if !session.state.isTerminal {
                        Circle().fill(.red).frame(width: 10, height: 10)
                    }
                    Text(stateTitle(session.state))
                        .font(.headline)
                    if session.state == .incomplete {
                        Text("INCOMPLETE")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                }
                Text(stateExplanation(session.state))
                    .foregroundStyle(session.state == .incomplete ? .orange : .secondary)
                LabeledContent(
                    "Tracks",
                    value: session.activeTrackKinds.map(trackLabel).joined(separator: ", ")
                )
                LabeledContent(
                    "Durable through",
                    value: session.durableThroughNanoseconds.map(durationLabel) ?? "No sealed interval yet"
                )
                LabeledContent("Known gaps", value: String(session.knownGapCount))
                if let reason = session.safeReason {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                if session.canStop {
                    HStack {
                        if session.state == .interrupted || session.state == .recovering {
                            Button("Resume with New Selection") {
                                Task { await store.resumeRecording() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isWorking || !store.recordingAcknowledged)
                            .accessibilityHint(
                                "Request the source again and persist a new provenance epoch before audio resumes."
                            )
                        }
                        Button(
                            session.state == .interrupted || session.state == .recovering
                                ? "Finish Retained Recording" : "Stop Recording"
                        ) {
                            Task { await store.stopRecording() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                    }
                }
                if session.state == .interrupted || session.state == .recovering {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func stateTitle(_ state: RecordingState) -> String {
        switch state {
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .interrupted: "Interrupted"
        case .recovering: "Recovering retained audio"
        case .stopping: "Stopping"
        case .finalizing: "Finalizing and verifying"
        case .completed: "Completed"
        case .incomplete: "Incomplete recording retained"
        case .failed: "Recording failed"
        }
    }

    private func stateExplanation(_ state: RecordingState) -> String {
        switch state {
        case .preparing:
            "The intent and exact source policy are durable; audio is not yet claimed as recording."
        case .recording:
            "Bounded audio packets are active and five-second CAF segments are sealed incrementally."
        case .interrupted:
            "Source continuity is no longer trusted. No device or application was substituted."
        case .recovering:
            "Sealed rows and CAF files are being re-proved after an interruption."
        case .stopping:
            "New packet admission is closed while bounded writers drain."
        case .finalizing:
            "Hashes, gaps, manifest, and local managed assets are being verified."
        case .completed:
            "All required selected tracks were verified and published with exact manifest provenance."
        case .incomplete:
            "Usable verified audio survives, but a gap or publication precondition prevents a complete claim."
        case .failed:
            "No verified usable audio was published; no zero-byte source was created."
        }
    }

    private func trackLabel(_ kind: CaptureTrackKind) -> String {
        switch kind {
        case .microphone: "Microphone"
        case .applicationAudio: "Selected application audio"
        }
    }

    private func durationLabel(_ nanoseconds: UInt64) -> String {
        String(format: "%.1f seconds", Double(nanoseconds) / 1_000_000_000)
    }
}
