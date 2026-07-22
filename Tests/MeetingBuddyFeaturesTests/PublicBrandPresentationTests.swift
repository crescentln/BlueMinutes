import Foundation
import Testing

@Suite
struct PublicBrandPresentationTests {
    @Test
    func bundlePresentsBlueMinutesWithReviewedIcon() throws {
        let repository = repositoryRoot
        let plistURL = repository.appendingPathComponent(
            "Configuration/MeetingBuddy-Info.plist"
        )
        let plistData = try Data(contentsOf: plistURL)
        let decoded = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let info = try #require(decoded as? [String: Any])

        #expect(info["CFBundleDisplayName"] as? String == "BlueMinutes")
        #expect(info["CFBundleName"] as? String == "BlueMinutes")
        #expect(info["CFBundleIconFile"] as? String == "BlueMinutes.icns")

        let iconURL = repository.appendingPathComponent(
            "Configuration/Branding/BlueMinutes.icns"
        )
        let icon = try Data(contentsOf: iconURL)
        #expect(!icon.isEmpty)
    }

    @Test
    func visibleBrandChangesPreserveCompatibilityIdentifiers() throws {
        let rootView = try source(
            "Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift"
        )
        #expect(rootView.contains(".navigationTitle(\"BlueMinutes\")"))
        #expect(rootView.contains("\"BlueMinutes\","))

        let recording = try source(
            "Sources/MeetingBuddyFeatures/Views/RecordingCaptureView.swift"
        )
        #expect(recording.contains("Audio only. BlueMinutes never requests"))

        let package = try source("Package.swift")
        #expect(package.contains("name: \"MeetingBuddy\""))
        #expect(package.contains("name: \"MeetingBuddyApp\""))

        let workspace = try source(
            "Sources/MeetingBuddyPersistence/LocalWorkspaceService.swift"
        )
        #expect(workspace.contains("Database/meetingbuddy.sqlite"))

        let automation = try source(
            "Sources/MeetingBuddyAutomation/AutomationMCPAdapter.swift"
        )
        #expect(automation.contains("meetingbuddy-mcp-stdio-v1"))
        #expect(automation.contains("\"name\": .string(\"meetingbuddy\")"))

        let plist = try source("Configuration/MeetingBuddy-Info.plist")
        #expect(plist.contains("<string>com.meetingbuddy.desktop</string>"))
        #expect(plist.contains("<string>MeetingBuddyApp</string>"))

        let scalarValues = try source(
            "Sources/MeetingBuddyDomain/ScalarValues.swift"
        )
        #expect(
            scalarValues.contains(
                "Contract timestamps cannot precede the Unix epoch."
            )
        )
        #expect(!scalarValues.contains("MeetingBuddy contract timestamps"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
