import Foundation
import Testing

@Suite
struct Task008BViewAccessibilityTests {
    @Test
    func recordingControlsKeepVisibleStatusStopResumeAndIncompleteDisclosure() throws {
        let root = try source("Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift")
        #expect(root.contains("store.recordingIndicatorIsVisible"))
        #expect(root.contains("Button(\"Stop\")"))
        #expect(root.contains(".accessibilityLabel(\"Visible recording state:"))
        #expect(root.contains("store.blocksWorkspaceSwitch"))

        let recording = try source("Sources/MeetingBuddyFeatures/Views/RecordingCaptureView.swift")
        #expect(recording.contains("Start Visible Recording"))
        #expect(recording.contains("participant notice, consent, venue rules"))
        #expect(recording.contains("Resume with New Selection"))
        #expect(recording.contains("persist a new provenance epoch"))
        #expect(recording.contains("INCOMPLETE"))
        #expect(recording.contains("not automatically activated"))
        #expect(recording.contains("never requests a screen track"))
    }

    @Test
    func webMetadataUIAndConfigurationExposeOnlyTheAcceptedBoundary() throws {
        let metadata = try source("Sources/MeetingBuddyFeatures/Views/UNWebTVMetadataView.swift")
        #expect(metadata.contains("Authorize one foreground GET"))
        #expect(metadata.contains("Do not fetch player, media, playlists, scripts, or subresources"))
        #expect(metadata.contains("Media acquisition\", value: \"Not authorized and not implemented"))
        #expect(metadata.contains("Universal UN Web TV support is not claimed"))
        #expect(metadata.contains("user-selected file"))

        let info = try source("Configuration/MeetingBuddy-Info.plist")
        #expect(info.contains("<key>NSMicrophoneUsageDescription</key>"))
        #expect(info.contains("<key>NSAudioCaptureUsageDescription</key>"))
        let entitlements = try source("Configuration/MeetingBuddy.entitlements")
        #expect(entitlements.contains("com.apple.security.device.audio-input"))
        #expect(entitlements.contains("com.apple.security.network.client"))
        #expect(!entitlements.contains("com.apple.developer.persistent-content-capture"))

        let app = try source("Sources/MeetingBuddyApp/MeetingBuddyApp.swift")
        #expect(app.contains("applicationShouldTerminate"))
        #expect(app.contains("Stop, Finalize, and Quit"))
        #expect(app.contains("return .terminateLater"))
        #expect(app.contains("Force-quitting may leave the session for restart recovery"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
