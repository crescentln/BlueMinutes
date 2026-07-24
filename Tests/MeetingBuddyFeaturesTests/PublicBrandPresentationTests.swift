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
        let readme = try source("README.md")
        #expect(
            readme.contains(
                "> **For diplomats, multilateral practitioners, and policy researchers"
            )
        )
        #expect(!readme.contains("> **By a diplomat, for diplomats.**"))
        #expect(readme.contains("The `v0.2.0` milestone is a source release"))
        #expect(readme.contains("Every related capability remains disabled by default"))
        #expect(readme.contains("legacy `MeetingBuddy` identifier"))
        #expect(readme.contains("./script/build_and_run.sh --stage-only"))
        #expect(
            readme.contains("stops an existing development instance")
        )
        #expect(!readme.contains("open dist/MeetingBuddy.app"))
        #expect(!readme.contains("source-only internal alpha"))

        let changelog = try source("CHANGELOG.md")
        #expect(changelog.contains("## [0.2.0] - 2026-07-23"))
        #expect(changelog.contains("## [0.1.0] - 2026-07-22"))
        #expect(
            changelog.contains(
                "Retried bounded cancellation transitions when concurrent checkpoint"
            )
        )

        let roadmap = try source("ROADMAP.md")
        #expect(
            roadmap.contains(
                "Published `v0.2.0` as a source-only, default-off Meeting / Research"
            )
        )

        let currentReleaseNotes = try source("docs/RELEASE_NOTES_0.2.0.md")
        #expect(
            currentReleaseNotes.contains(
                "# BlueMinutes v0.2.0 — Default-Off Meeting / Research Foundation"
            )
        )
        #expect(
            currentReleaseNotes.contains(
                "Task cancellation re-reads and retries bounded optimistic-lock conflicts"
            )
        )

        let publicReleaseNotes = try source("docs/RELEASE_NOTES_0.1.0.md")
        #expect(
            publicReleaseNotes.contains(
                "# BlueMinutes v0.1.0 — First Public Source Release"
            )
        )

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

    @Test
    func readmePublishesPublicSafeProductPreview() throws {
        let readme = try source("README.md")
        let normalizedReadme = readme
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        #expect(readme.contains("## Product preview"))
        #expect(normalizedReadme.contains("disposable synthetic empty workspace"))
        #expect(normalizedReadme.contains("no real meeting or user data"))
        #expect(
            normalizedReadme.contains(
                "not a Developer ID-signed or notarized app download"
            )
        )

        let screenshotPaths = [
            "docs/assets/screenshots/local-media.png",
            "docs/assets/screenshots/un-web-tv-metadata.png",
        ]
        let pngSignature = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

        for path in screenshotPaths {
            #expect(readme.contains("(\(path))"))
            let screenshot = try Data(
                contentsOf: repositoryRoot.appendingPathComponent(path)
            )
            #expect(screenshot.count > 500_000)
            #expect(screenshot.prefix(pngSignature.count) == pngSignature)
        }
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
