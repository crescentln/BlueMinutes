import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct SpeechToTextRoutePicker: View {
    @Bindable var sceneState: MediaReviewSceneState
    let intelligenceStore:
        IntelligenceConfigurationStore?
    let existingMeeting: Bool
    let requiresExecutionAuthorization: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(
                "Speech-to-text route",
                selection: selection
            ) {
                ForEach(availableOptions) { option in
                    Text(option.label)
                        .tag(option.selection)
                }
            }
            .accessibilityIdentifier(
                "BlueMinutes.STT.Route"
            )

            if let option = selectedOption {
                LabeledContent(
                    "Readiness",
                    value: option.detail
                )
            } else {
                Label(
                    "The saved STT route is no longer ready. Choose another route or Record only.",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }

            if let remoteProvider {
                Divider()
                Text(
                    "Remote STT sends bounded audio chunks to \(remoteProvider.displayName) at api.openai.com and uses the user's API account for billing. API content is not used for training by default; standard abuse-monitoring retention may be up to 30 days unless the account has an approved retention control."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if existingMeeting {
                    Label(
                        sceneState
                            .approvedRemoteSTTProviderIdentifier
                            == remoteProvider.identifier
                            ? "This provider was approved when the meeting was created."
                            : "This meeting did not approve this remote provider; use Local STT or Record only.",
                        systemImage:
                            sceneState
                            .approvedRemoteSTTProviderIdentifier
                            == remoteProvider.identifier
                            ? "checkmark.shield"
                            : "xmark.shield"
                    )
                    .foregroundStyle(
                        sceneState
                            .approvedRemoteSTTProviderIdentifier
                            == remoteProvider.identifier
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.orange)
                    )
                } else {
                    Toggle(
                        "Allow this remote STT provider for this meeting",
                        isOn:
                            $sceneState
                            .remoteSpeechToTextAllowed
                    )
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier(
                        "BlueMinutes.STT.MeetingAuthorization"
                    )
                }

                if requiresExecutionAuthorization {
                    Toggle(
                        "Authorize this audio upload now",
                        isOn:
                            $sceneState
                            .remoteAudioUploadAcknowledged
                    )
                    .toggleStyle(.checkbox)
                    .disabled(
                        sceneState
                            .approvedRemoteSTTProviderIdentifier
                            != remoteProvider.identifier
                    )
                    .accessibilityIdentifier(
                        "BlueMinutes.STT.UploadAuthorization"
                    )
                }
            } else if sceneState.transcriptionSelection?
                .providerIdentifier == "apple-speech"
            {
                Label(
                    "Local STT keeps audio on this Mac and uses no API billing.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Record only: audio remains local and BlueMinutes will not claim that transcription is running.",
                    systemImage: "record.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(
                "Codex provides text analysis, chat and research only. It never receives audio and is not an STT option."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            reconcileSelection()
        }
        .onChange(
            of: intelligenceStore?.state?.revision
        ) { _, _ in
            reconcileSelection()
        }
    }

    private var selection:
        Binding<ProviderModelSelectionRecord?>
    {
        Binding(
            get: {
                sceneState.transcriptionSelection
            },
            set: { next in
                sceneState.transcriptionSelection =
                    next
                sceneState
                    .remoteAudioUploadAcknowledged =
                    false
                guard let next,
                      next.providerIdentifier
                          != "apple-speech"
                else {
                    sceneState
                        .remoteSpeechToTextAllowed =
                        false
                    return
                }
                if existingMeeting {
                    sceneState
                        .remoteSpeechToTextAllowed =
                        sceneState
                        .approvedRemoteSTTProviderIdentifier
                        == next.providerIdentifier
                }
            }
        )
    }

    private var availableOptions:
        [IntelligenceRouteOption]
    {
        let options =
            intelligenceStore?.routeOptions(
                for: .speechToTextBatch,
                codexConnected: false
            ) ?? [
                IntelligenceRouteOption(
                    selection: nil,
                    label: "None / Record only",
                    detail: "No fallback",
                    isReady: true
                )
            ]
        return options.filter { option in
            guard option.selection == nil
                    || option.isReady
            else { return false }
            guard let selection =
                    option.selection
            else { return true }
            if sceneState.dataClassification
                .restrictionRank
                >= DataClassification.sensitive
                .restrictionRank
            {
                return selection
                    .providerIdentifier
                    == "apple-speech"
            }
            if existingMeeting,
               selection.providerIdentifier
                    != "apple-speech"
            {
                return selection
                    .providerIdentifier
                    == sceneState
                    .approvedRemoteSTTProviderIdentifier
            }
            return true
        }
    }

    private var selectedOption:
        IntelligenceRouteOption?
    {
        availableOptions.first {
            $0.selection
                == sceneState.transcriptionSelection
        }
    }

    private var remoteProvider:
        RemoteProviderConfiguration?
    {
        guard let selection =
                sceneState.transcriptionSelection,
              selection.providerIdentifier
                  != "apple-speech"
        else { return nil }
        return intelligenceStore?.state?
            .providers.first {
                $0.identifier
                    == selection.providerIdentifier
                    && $0.modelIdentifier
                        == selection.modelIdentifier
                    && $0.purpose
                        == .speechToText
            }
    }

    private func reconcileSelection() {
        guard selectedOption == nil else {
            return
        }
        sceneState.transcriptionSelection = nil
        sceneState.remoteSpeechToTextAllowed =
            false
        sceneState
            .remoteAudioUploadAcknowledged =
            false
    }
}
