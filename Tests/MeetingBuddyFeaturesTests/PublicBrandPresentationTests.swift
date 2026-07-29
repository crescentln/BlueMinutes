import CryptoKit
import Foundation
import ImageIO
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
        #expect(info["CFBundleShortVersionString"] as? String == "0.4.0")
        #expect(info["CFBundleVersion"] as? String == "4")
        #expect(info["CFBundleExecutable"] as? String == "MeetingBuddyApp")
        #expect(info["CFBundleIdentifier"] as? String == "com.meetingbuddy.desktop")

        let iconURL = repository.appendingPathComponent(
            "Configuration/Branding/BlueMinutes.icns"
        )
        let icon = try Data(contentsOf: iconURL)
        #expect(!icon.isEmpty)
    }

    @Test
    func reviewedBrandSourcesAndDerivedAssetsRemainBound() throws {
        let repository = repositoryRoot
        let iconSourceURL = repository.appendingPathComponent(
            "Configuration/Branding/Sources/BlueMinutes-AppIcon-Source.png"
        )
        let logoSourceURL = repository.appendingPathComponent(
            "Configuration/Branding/Sources/BlueMinutes-Logo-Source.png"
        )
        let iconMasterURL = repository.appendingPathComponent(
            "Configuration/Branding/BlueMinutes-AppIcon-1024.png"
        )
        let iconURL = repository.appendingPathComponent(
            "Configuration/Branding/BlueMinutes.icns"
        )
        let publicLogoURL = repository.appendingPathComponent(
            "docs/assets/BlueMinutes-logo.png"
        )

        #expect(
            sha256(iconSourceURL)
                == "a36fa53503c95047a04c5e3ba9d5f0e6619789f19eb2bbf1225f61d318cadbd4"
        )
        #expect(
            sha256(logoSourceURL)
                == "d0f0e05164a84b14533e2a3f2f83486baab544f2c6029a14911c5a4ba95fcd39"
        )
        #expect(
            sha256(iconMasterURL)
                == "6bb1f6f61ea536e83433fe979eb8749b4b3745270ba7b1da6bb08e893bee289a"
        )
        #expect(
            sha256(iconURL)
                == "87459e6a19758af87eb34884b2f06066413000298c7ec6468f6eb0046aa06bca"
        )
        #expect(try Data(contentsOf: logoSourceURL) == Data(contentsOf: publicLogoURL))
        #expect(try pixelSize(iconSourceURL) == [1254, 1254])
        #expect(try pixelSize(logoSourceURL) == [1448, 1086])
        #expect(try pixelSize(iconMasterURL) == [1024, 1024])
        #expect(try profileName(iconMasterURL).contains("sRGB"))

        let readme = try source("README.md")
        #expect(readme.contains("docs/assets/BlueMinutes-logo.png"))
        #expect(!readme.contains("docs/assets/BlueMinutes-logo.jpg"))

        let generator = try source("script/generate_brand_assets.sh")
        #expect(generator.contains("EXPECTED_ICON_SOURCE_SHA256"))
        #expect(generator.contains("EXPECTED_LOGO_SOURCE_SHA256"))
        #expect(generator.contains("EXPECTED_ICON_MASTER_SHA256"))
        #expect(generator.contains("EXPECTED_ICON_OUTPUT_SHA256"))
        #expect(generator.contains("/usr/bin/iconutil -c icns"))
        #expect(generator.contains("No tracked output changes until every derived artifact"))
    }

    @Test
    func visibleBrandChangesPreserveCompatibilityIdentifiers() throws {
        let readme = try source("README.md")
        let normalizedReadme = readme
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        #expect(
            readme.contains(
                "> **For diplomats, multilateral practitioners, and policy researchers"
            )
        )
        #expect(!readme.contains("> **By a diplomat, for diplomats.**"))
        #expect(
            readme.contains(
                "Application version `0.4.0` (build `4`) is the formal software-testing"
            )
        )
        #expect(
            readme.contains(
                "source-only GitHub Release `v0.4.0`"
            )
        )
        #expect(!readme.contains("latest public source Release remains `v0.3.0`"))
        #expect(
            normalizedReadme.contains(
                "Every related capability remains disabled by default"
            )
        )
        #expect(readme.contains("legacy `MeetingBuddy` identifier"))
        #expect(readme.contains("./script/build_and_run.sh --stage-only"))
        #expect(
            readme.contains(
                "MEETINGBUDDY_SIGN_IDENTITY=- ./script/package_release_candidate.sh"
            )
        )
        #expect(readme.contains("dist/BlueMinutes-0.4.0-development"))
        #expect(readme.contains("GitHub Releases remain"))
        #expect(readme.contains("zero maintainer-uploaded app assets"))
        #expect(
            readme.contains("stops an existing development instance")
        )
        #expect(!readme.contains("open dist/MeetingBuddy.app"))
        #expect(!readme.contains("source-only internal alpha"))

        let changelog = try source("CHANGELOG.md")
        #expect(
            changelog.contains(
                "## [0.4.0] - 2026-07-28"
            )
        )
        #expect(
            changelog.contains(
                "The GitHub `v0.4.0` Release is source-only"
            )
        )
        #expect(!changelog.contains("latest public source Release remains `v0.3.0`"))
        #expect(changelog.contains("## [0.3.0] - 2026-07-28"))
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
        #expect(
            roadmap.contains(
                "Published `v0.3.0` as a source-only UI Foundation release"
            )
        )
        #expect(
            roadmap.contains(
                "Completed milestone: v0.4.0 formal-testing baseline"
            )
        )
        #expect(
            roadmap.contains(
                "Published application version `0.4.0` build `4`"
            )
        )
        #expect(
            roadmap.contains(
                "Close each future large functional or architecture round with a distinct"
            )
        )

        let releaseChecklist = try source("docs/RELEASE_CHECKLIST.md")
        #expect(
            releaseChecklist.contains(
                "After `v0.4.0`, do not leave a completed large functional or architecture"
            )
        )

        let executionLedger = try source("docs/CODEX_EXECUTION_STATE.md")
        #expect(executionLedger.contains("version: \"v0.3.0\""))
        #expect(
            executionLedger.contains(
                "bundle_version_status: \"exact release baseline Configuration/MeetingBuddy-Info.plist is public version 0.3.0 build 3"
            )
        )
        #expect(
            executionLedger.contains(
                "candidate_version: \"0.4.0\""
            )
        )
        #expect(executionLedger.contains("candidate_build: \"4\""))
        #expect(executionLedger.contains("version: \"v0.4.0\""))
        #expect(
            executionLedger.contains(
                "status: \"authorized_pending_pr_62_merge_exact_new_main_gates_tag_and_release\""
            )
        )
        #expect(executionLedger.contains("current_task: \"v4-prebeta\""))
        #expect(
            executionLedger.contains(
                "tracking_issue: \"Issue #60 at https://github.com/crescentln/BlueMinutes/issues/60\""
            )
        )
        #expect(
            executionLedger.contains(
                "Do not start U1, production billing, website deployment"
            )
        )
        #expect(
            !executionLedger.contains(
                "remains the separately gated 0.1.0 internal-alpha application-bundle version"
            )
        )

        let currentReleaseNotes = try source("docs/RELEASE_NOTES_0.4.0.md")
        let normalizedCurrentReleaseNotes = currentReleaseNotes
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        #expect(
            currentReleaseNotes.contains(
                "# BlueMinutes v0.4.0 — Formal Software-Testing Baseline"
            )
        )
        #expect(
            currentReleaseNotes.contains(
                "Source state: protected `main`, annotated tag `v0.4.0`"
            )
        )
        #expect(
            normalizedCurrentReleaseNotes.contains(
                "classification: DEVELOPMENT"
            )
        )
        #expect(
            normalizedCurrentReleaseNotes.contains(
                "distribution_authorized: false"
            )
        )
        #expect(
            currentReleaseNotes.contains(
                "The GitHub Release contains only\nGitHub-generated source archives"
            )
        )

        let previousReleaseNotes = try source("docs/RELEASE_NOTES_0.3.0.md")
        #expect(
            previousReleaseNotes.contains(
                "# BlueMinutes v0.3.0 — Editorial Dossier Foundation"
            )
        )
        #expect(
            previousReleaseNotes.contains(
                "Distribution scope: source code only; zero uploaded assets"
            )
        )

        let earlierReleaseNotes = try source("docs/RELEASE_NOTES_0.2.0.md")
        #expect(
            earlierReleaseNotes.contains(
                "# BlueMinutes v0.2.0 — Default-Off Meeting / Research Foundation"
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
        #expect(plist.contains("<string>0.4.0</string>"))
        #expect(plist.contains("<string>4</string>"))

        let packager = try source("script/package_release_candidate.sh")
        #expect(packager.contains("APP_BUNDLE_NAME=\"$PUBLIC_PRODUCT_NAME.app\""))
        #expect(
            packager.contains(
                "RELEASE_SET_NAME=\"$PUBLIC_PRODUCT_NAME-$BUNDLE_VERSION-development\""
            )
        )
        #expect(packager.contains("schema_version: 2"))
        #expect(packager.contains("classification: \"DEVELOPMENT\""))
        #expect(packager.contains("distribution_authorized: false"))
        #expect(!packager.contains("MeetingBuddy-0.1.0-internal-alpha"))

        let verifier = try source("script/verify_release_candidate.sh")
        #expect(verifier.contains("development|distribution"))
        #expect(verifier.contains("distribution verification rejects an ad-hoc signature"))
        #expect(verifier.contains("source inventory does not cover the exact tracked tree"))
        #expect(
            verifier.contains(
                ".source.package_resolved_sha256 == $package_resolved_sha"
            )
        )
        #expect(
            verifier.contains(
                ".signing.team_identifier == $team_identifier"
            )
        )
        #expect(
            verifier.contains(
                "archive checksum file is not the exact reviewed record"
            )
        )
        #expect(
            verifier.contains(
                "bundled Info.plist differs from the reviewed source Info.plist"
            )
        )
        #expect(
            verifier.contains(
                "manifest exact tag differs from the available exact tag"
            )
        )
        #expect(
            verifier.contains(
                "extracted app bundle differs from the release manifest"
            )
        )
        #expect(
            verifier.contains(
                "the current release-source checkout must be clean"
            )
        )
        #expect(
            verifier.contains(
                "manifest Git head differs from the current release-source checkout"
            )
        )
        #expect(
            verifier.contains(
                "manifest Git tree differs from the current release-source checkout"
            )
        )
        #expect(!verifier.contains("internal-alpha|distribution"))

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

    private func sha256(_ url: URL) -> String {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func pixelSize(_ url: URL) throws -> [Int] {
        let source = try #require(
            CGImageSourceCreateWithURL(url as CFURL, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        return [width, height]
    }

    private func profileName(_ url: URL) throws -> String {
        let source = try #require(
            CGImageSourceCreateWithURL(url as CFURL, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        )
        return try #require(
            properties[kCGImagePropertyProfileName] as? String
        )
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
