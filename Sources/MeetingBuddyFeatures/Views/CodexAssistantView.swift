import Foundation
import MeetingBuddyAI
import MeetingBuddyDomain
import SwiftUI

struct CodexAssistantView: View {
    @Bindable var mediaStore: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @Bindable var codexStore: CodexConnectionStore

    @State private var prompt = ""
    @State private var authorizesSelectedText = false
    @State private var confirmNewThread = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer
        }
        .alert(
            "Codex",
            isPresented: Binding(
                get: { codexStore.safeErrorMessage != nil },
                set: { if !$0 { codexStore.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                codexStore.clearError()
            }
        } message: {
            Text(codexStore.safeErrorMessage ?? "")
        }
        .confirmationDialog(
            "Start a new Codex thread?",
            isPresented: $confirmNewThread,
            titleVisibility: .visible
        ) {
            Button("Start New Thread", role: .destructive) {
                guard let conversationScope else { return }
                Task {
                    await codexStore.clearThread(
                        scope: conversationScope
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This clears the current in-app conversation and deletes its isolated Codex thread. Meeting audio, transcripts, and revisions are not changed."
            )
        }
        .accessibilityIdentifier(
            "blueminutes.codex-assistant"
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Assistant")
                    .font(.headline)
                Text(connectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if codexStore.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            if codexStore.isConnected {
                Button("Test Connection") {
                    Task {
                        await codexStore.testConnection()
                    }
                }
                .disabled(codexStore.isWorking)
            } else {
                Button("Connect") {
                    Task {
                        await codexStore.connect()
                    }
                }
                .disabled(codexStore.isWorking)
            }
            if !messages.isEmpty {
                Button("New Thread") {
                    confirmNewThread = true
                }
                .disabled(hasActiveTurn)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var conversation: some View {
        if messages.isEmpty {
            ContentUnavailableView {
                Label(
                    "Ask About Selected Transcript Text",
                    systemImage: "sparkles"
                )
            } description: {
                Text(
                    "Select a transcript segment, write a prompt, and explicitly approve that bounded text for this request. Codex never receives meeting audio."
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedSegment {
                LabeledContent(
                    "Selected context",
                    value:
                        "\(formattedTime(selectedSegment.timeRange.startMilliseconds))–\(formattedTime(selectedSegment.timeRange.endMilliseconds)) · \(selectedSegment.text.utf8.count) bytes"
                )
                Text(selectedSegment.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            } else {
                Text(
                    "Select one transcript segment in Transcript Review before sending a Codex request."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Toggle(
                "For this request, send only the selected transcript segment and my prompt to Codex",
                isOn: $authorizesSelectedText
            )
            .disabled(selectedSegment == nil)
            .accessibilityIdentifier(
                "blueminutes.codex-assistant.authorization"
            )

            TextField(
                "Ask a question about the selected transcript text",
                text: $prompt,
                axis: .vertical
            )
            .lineLimit(3...8)
            .disabled(hasActiveTurn)
            .accessibilityIdentifier(
                "blueminutes.codex-assistant.prompt"
            )

            HStack {
                Button("Send") {
                    send()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .accessibilityIdentifier(
                    "blueminutes.codex-assistant.send"
                )

                if hasActiveTurn,
                   let conversationScope
                {
                    Button("Stop", role: .cancel) {
                        Task {
                            await codexStore.interrupt(
                                scope: conversationScope
                            )
                        }
                    }
                } else if lastUserPrompt != nil
                {
                    Button("Retry with Current Selection") {
                        retryLastRequest()
                    }
                    .disabled(
                        !canRetryLastRequest
                    )
                }

                Spacer()
                Text(
                    "Codex subscription · text only · no silent fallback"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func messageView(
        _ message: CodexConversationMessage
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(
                    message.role == .user
                        ? "You"
                        : "Codex"
                )
                .font(.caption.weight(.semibold))
                Spacer()
                if message.status == .streaming {
                    ProgressView()
                        .controlSize(.mini)
                } else if message.status != .completed {
                    Text(statusLabel(message.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(
                message.text.isEmpty
                    ? "Waiting for text…"
                    : message.text
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            message.role == .user
                ? Color.accentColor.opacity(0.08)
                : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var meetingID: MeetingID? {
        selectedSegment?.meetingID
            ?? mediaStore.transcriptReview?
                .transcriptSegments.first?.meetingID
    }

    private var selectedSegment: TranscriptSegmentV1? {
        guard let selectedSegmentID =
                sceneState.transcript.selectedSegmentID
        else { return nil }
        return mediaStore.transcriptReview?
            .transcriptSegments.first {
                $0.segmentID == selectedSegmentID
            }
    }

    private var conversationScope:
        CodexConversationScope?
    {
        guard let workspaceID =
                mediaStore.workspace?.workspaceID,
              let meetingID
        else { return nil }
        return CodexConversationScope(
            workspaceID: workspaceID,
            meetingID: meetingID
        )
    }

    private var messages: [CodexConversationMessage] {
        codexStore.messages(for: conversationScope)
    }

    private var hasActiveTurn: Bool {
        codexStore.hasActiveTurn(
            for: conversationScope
        )
    }

    private var canSend: Bool {
        codexStore.isConnected
            && selectedSegment != nil
            && authorizesSelectedText
            && !prompt.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && prompt.utf8.count <= 16 * 1_024
            && !hasActiveTurn
    }

    private var lastUserPrompt: String? {
        messages.last {
            $0.role == .user
        }?.text
    }

    private var canRetryLastRequest: Bool {
        codexStore.isConnected
            && selectedSegment != nil
            && authorizesSelectedText
            && lastUserPrompt != nil
            && !hasActiveTurn
    }

    private var connectionDescription: String {
        switch codexStore.snapshot.phase {
        case .connected:
            "Connected through the isolated official Codex app-server runtime."
        case .signedOut:
            "Runtime connected. Complete official ChatGPT sign-in in Settings."
        case .connecting:
            "Checking the signed and pinned Codex runtime."
        case .runtimeMissing:
            "The exact supported official Codex runtime was not found."
        case .runtimeUntrusted:
            "The detected runtime failed signature verification."
        case .runtimeIncompatible:
            "The detected Codex runtime version is not the tested version."
        case .failed:
            "Connection failed. Reconnect without sending meeting text."
        case .disconnected:
            "Disconnected. Connect here or in Intelligence Settings."
        }
    }

    private func send() {
        guard let selectedSegment,
              canSend
        else { return }
        let submittedPrompt = prompt
        Task {
            guard let request =
                    await mediaStore.codexTurnRequest(
                        selectedSegmentIDs: [
                            selectedSegment.segmentID
                        ],
                        prompt: submittedPrompt,
                        visibleUserAuthorization:
                            authorizesSelectedText
                    )
            else { return }
            let accepted = await codexStore.send(request)
            if accepted {
                prompt = ""
                authorizesSelectedText = false
            }
        }
    }

    private func retryLastRequest() {
        guard let selectedSegment,
              let lastUserPrompt,
              canRetryLastRequest
        else { return }
        Task {
            guard let request =
                    await mediaStore.codexTurnRequest(
                        selectedSegmentIDs: [
                            selectedSegment.segmentID
                        ],
                        prompt: lastUserPrompt,
                        visibleUserAuthorization:
                            authorizesSelectedText
                    )
            else { return }
            let accepted = await codexStore.send(
                request
            )
            if accepted {
                authorizesSelectedText = false
            }
        }
    }

    private func statusLabel(
        _ status: CodexConversationMessageStatus
    ) -> String {
        switch status {
        case .pending:
            "Sending"
        case .streaming:
            "Streaming"
        case .completed:
            "Completed"
        case .interrupted:
            "Stopped"
        case .failed:
            "Failed"
        }
    }

    private func formattedTime(
        _ milliseconds: Int64
    ) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(
                format: "%lld:%02lld:%02lld",
                hours,
                minutes,
                seconds
            )
        }
        return String(
            format: "%lld:%02lld",
            minutes,
            seconds
        )
    }
}
