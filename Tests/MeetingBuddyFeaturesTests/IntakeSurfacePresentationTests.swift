import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct IntakeSurfacePresentationTests {
    @Test
    func localMediaPreflightExplainsEveryBlockedActivationBeforeReady()
        throws
    {
        let pending = try pendingMedia(trackCount: 2)
        let track = try MediaTrackIdentifier(1)

        #expect(
            localMediaReason(
                title: "Synthetic meeting",
                pending: nil,
                track: nil
            )
                == "Choose a supported local audio or video file first."
        )
        #expect(
            localMediaReason(
                title: "",
                pending: pending,
                track: track
            )
                == "Enter a meeting title before importing media."
        )
        #expect(
            localMediaReason(
                title: "Synthetic meeting",
                pending: pending,
                track: nil
            )
                == "Select one audio track before processing this media."
        )
        #expect(
            localMediaReason(
                title: "Synthetic meeting",
                pending: pending,
                track: track,
                language: "not a language tag"
            )
                == "Use a valid language tag such as en, fr, or zh-hans."
        )
        #expect(
            localMediaReason(
                title: "Synthetic meeting",
                pending: pending,
                track: track,
                isWorking: true
            )
                == "Wait for the current local operation to finish."
        )
        #expect(
            IntakeSurfacePresentation.localMediaImportBlockedReason(
                isInteractionLocked: false,
                hasUnsavedEditorChanges: true,
                isWorking: false,
                blocksMediaReplacement: false,
                meetingTitle: "Synthetic meeting",
                pendingMedia: pending,
                selectedTrack: track,
                languageTag: "en"
            )
                == IntakeSurfacePresentation.localMediaUnsavedDraftReason
        )
        #expect(
            localMediaReason(
                title: "Synthetic meeting",
                pending: pending,
                track: track
            ) == nil
        )
    }

    @Test
    func recordingPreflightDistinguishesCheckingDeniedUnavailableAndReady()
        throws
    {
        #expect(
            recordingReason(setup: nil)
                == "BlueMinutes is checking microphone and application-audio capabilities."
        )
        #expect(
            recordingReason(
                setup: try recordingSetup(
                    microphonePermission: .notDetermined,
                    applicationAudioAvailable: true,
                    systemPickerAvailable: true
                ),
                mode: .microphoneOnly,
                microphoneID: "synthetic-microphone"
            ) == nil
        )
        #expect(
            recordingReason(
                setup: try recordingSetup(
                    microphonePermission: .denied,
                    applicationAudioAvailable: true,
                    systemPickerAvailable: true
                ),
                mode: .microphoneOnly,
                microphoneID: "synthetic-microphone"
            )
                == "Microphone permission is denied for this capture mode."
        )
        #expect(
            recordingReason(
                setup: try recordingSetup(
                    microphonePermission: .authorized,
                    applicationAudioAvailable: false,
                    systemPickerAvailable: false
                ),
                mode: .applicationAudioOnly
            )
                == "One-application audio is unavailable on this macOS build."
        )
        #expect(
            recordingReason(
                setup: try recordingSetup(
                    microphonePermission: .authorized,
                    applicationAudioAvailable: true,
                    systemPickerAvailable: true
                ),
                mode: .applicationAudioOnly,
                acknowledged: false
            )
                == "A visible recording requires the participant, policy, and legal-responsibility acknowledgement."
        )
        #expect(
            recordingReason(
                setup: try recordingSetup(
                    microphonePermission: .authorized,
                    applicationAudioAvailable: true,
                    systemPickerAvailable: true
                ),
                mode: .applicationAudioOnly
            ) == nil
        )
    }

    @Test
    func recordingLifecycleUsesNineDistinctTextStates() {
        let titles = RecordingState.allCases.map(
            IntakeSurfacePresentation.recordingStateTitle
        )
        let details = RecordingState.allCases.map(
            IntakeSurfacePresentation.recordingStateExplanation
        )

        #expect(titles.count == 9)
        #expect(Set(titles).count == 9)
        #expect(details.count == 9)
        #expect(Set(details).count == 9)
    }

    @Test
    func unWebTVPreflightKeepsInvalidAuthorizationWorkingAndReadyDistinct()
    {
        let validURL =
            "https://webtv.un.org/en/asset/synthetic/synthetic-id"

        #expect(
            IntakeSurfacePresentation.unWebTVFetchBlockedReason(
                url: "https://example.com/not-un",
                isWorking: false,
                networkAuthorized: true
            )
                == "Use an exact official UN Web TV asset URL such as https://webtv.un.org/en/asset/abc/asset-id."
        )
        #expect(
            IntakeSurfacePresentation.unWebTVFetchBlockedReason(
                url: validURL,
                isWorking: false,
                networkAuthorized: false
            )
                == "Authorize this one foreground official-page metadata request."
        )
        #expect(
            IntakeSurfacePresentation.unWebTVFetchBlockedReason(
                url: validURL,
                isWorking: true,
                networkAuthorized: true
            )
                == "Wait for the current local operation to finish."
        )
        #expect(
            IntakeSurfacePresentation.unWebTVFetchBlockedReason(
                url: validURL,
                isWorking: false,
                networkAuthorized: true
            ) == nil
        )
    }

    @Test
    func intakeViewsConsumeOnlyRealContractsAndKeepSafetyBoundaries()
        throws
    {
        let root = try source(
            "Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift"
        )
        let local = try source(
            "Sources/MeetingBuddyFeatures/Views/LocalMediaIntakeView.swift"
        )
        let recording = try source(
            "Sources/MeetingBuddyFeatures/Views/RecordingCaptureView.swift"
        )
        let metadata = try source(
            "Sources/MeetingBuddyFeatures/Views/UNWebTVMetadataView.swift"
        )
        let store = try source(
            "Sources/MeetingBuddyFeatures/Stores/MediaReviewStore.swift"
        )
        let stateComponent = try source(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/WorkflowStateView.swift"
        )

        #expect(root.contains("LocalMediaIntakeView("))
        #expect(root.contains("store.recordingIndicatorIsVisible"))
        #expect(root.contains("Button(\"Stop\")"))
        #expect(root.contains(".disabled(store.isStoppingRecording || !recording.canStop)"))
        #expect(!root.contains(".disabled(store.isWorking || !recording.canStop)"))
        #expect(local.contains("Import blocked"))
        #expect(local.contains("Ready to import"))
        #expect(local.contains("job.privacyRoute.encodedValue"))
        #expect(local.contains("job.canCancel"))
        #expect(local.contains("job.canRetry"))
        #expect(local.contains("importRequestIsDisabled"))
        #expect(!local.contains("sourceURL"))
        #expect(recording.contains("Checking capture capabilities"))
        #expect(recording.contains("Microphone permission denied"))
        #expect(recording.contains("visible macOS permission prompt"))
        #expect(recording.contains("One-application audio unavailable"))
        #expect(
            store.components(
                separatedBy:
                    "sceneState.recordingAcknowledged = false"
            ).count - 1 == 2
        )
        #expect(metadata.contains("Metadata request blocked"))
        #expect(metadata.contains("Candidate requires review"))
        #expect(metadata.contains("Local review draft"))
        #expect(metadata.contains("Safe fallback"))
        #expect(!metadata.contains("Button(\"Save"))
        #expect(!metadata.contains("Button(\"Apply"))
        #expect(!metadata.contains("Button(\"Discard"))
        #expect(!metadata.contains("Button(\"Download"))
        #expect(!metadata.contains("Button(\"Stream"))
        #expect(!metadata.contains("Kaltura"))
        #expect(stateComponent.contains("Text(title)"))
        #expect(stateComponent.contains("Text(detail)"))
        #expect(stateComponent.contains(".accessibilityValue(detail)"))
    }

    private func localMediaReason(
        title: String,
        pending: PendingMediaReview?,
        track: MediaTrackIdentifier?,
        language: String = "",
        isWorking: Bool = false
    ) -> String? {
        IntakeSurfacePresentation.localMediaImportBlockedReason(
            isInteractionLocked: false,
            hasUnsavedEditorChanges: false,
            isWorking: isWorking,
            blocksMediaReplacement: false,
            meetingTitle: title,
            pendingMedia: pending,
            selectedTrack: track,
            languageTag: language
        )
    }

    private func recordingReason(
        setup: RecordingSetupReview?,
        mode: CaptureMode = .microphoneOnly,
        microphoneID: String? = nil,
        acknowledged: Bool = true
    ) -> String? {
        IntakeSurfacePresentation.recordingStartBlockedReason(
            isInteractionLocked: false,
            isWorking: false,
            blocksWorkspaceSwitch: false,
            setup: setup,
            meetingTitle: "Synthetic meeting",
            languageTag: "en",
            mode: mode,
            selectedMicrophoneDeviceID: microphoneID,
            recordingAcknowledged: acknowledged
        )
    }

    private func pendingMedia(
        trackCount: Int
    ) throws -> PendingMediaReview {
        let tracks = try (1 ... trackCount).map { index in
            try AudioTrackDescriptor(
                trackIdentifier: MediaTrackIdentifier(Int32(index)),
                durationFrameCount: 32_000,
                sourceSampleRateHertz: 48_000,
                sourceChannelCount: 1,
                codec: "lpcm"
            )
        }
        return PendingMediaReview(
            displayName: "synthetic.wav",
            inspection: try MediaInspection(
                format: .wav,
                durationFrameCount: 32_000,
                audioTracks: tracks
            )
        )
    }

    private func recordingSetup(
        microphonePermission: CapturePermissionState,
        applicationAudioAvailable: Bool,
        systemPickerAvailable: Bool
    ) throws -> RecordingSetupReview {
        RecordingSetupReview(
            capability: CaptureCapabilitySnapshot(
                microphonePermission: microphonePermission,
                applicationAudioAvailable: applicationAudioAvailable,
                systemPickerAvailable: systemPickerAvailable,
                checkedAt: try UTCInstant(
                    millisecondsSinceUnixEpoch: 2_000_000_000_000
                )
            ),
            microphones: []
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf:
                repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
