import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing
@testable import MeetingBuddyFeatures

@Suite(.serialized)
struct BlueMinutesSettingsTests {
    @Test
    func compiledDefaultsAndUnknownStoredValuesRemainSafe() {
        #expect(
            BlueMinutesAppearancePreference.resolve(nil)
                == .compiledDefault
        )
        #expect(
            BlueMinutesInterfaceDensityPreference.resolve(nil)
                == .compiledDefault
        )
        #expect(
            BlueMinutesReadingWidthPreference.resolve(nil)
                == .compiledDefault
        )

        #expect(
            BlueMinutesAppearancePreference.resolve("future-appearance")
                == .system
        )
        #expect(
            BlueMinutesInterfaceDensityPreference.resolve("future-density")
                == .comfortable
        )
        #expect(
            BlueMinutesReadingWidthPreference.resolve("future-width")
                == .comfortable
        )

        #expect(BlueMinutesAppearancePreference.system.colorScheme == nil)
        #expect(BlueMinutesAppearancePreference.light.colorScheme == .light)
        #expect(BlueMinutesAppearancePreference.dark.colorScheme == .dark)
        #expect(
            BlueMinutesInterfaceDensityPreference.comfortable.controlSize
                == .regular
        )
        #expect(
            BlueMinutesInterfaceDensityPreference.compact.controlSize
                == .small
        )
        let readingWidths =
            BlueMinutesReadingWidthPreference.allCases.map(\.points)
        #expect(readingWidths == [640, 760, 880])
        #expect(Set(readingWidths).count == readingWidths.count)
    }

    @Test
    func exactUIKeyRoundTripAndResetPreserveProtectedSentinels() throws {
        let suiteName = "BlueMinutesSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            BlueMinutesUIPreferenceKeys.all == [
                "meetingbuddy.ui.appearance.v1",
                "meetingbuddy.ui.interface-density.v1",
                "meetingbuddy.ui.reading-width.v1"
            ]
        )
        #expect(
            Set(BlueMinutesUIPreferenceKeys.all).count
                == BlueMinutesUIPreferenceKeys.all.count
        )

        let protectedSentinels: [String: Data] = [
            "meetingbuddy.workspace.security-scoped-bookmark.v1":
                Data("synthetic bookmark sentinel".utf8),
            "synthetic.credentials.sentinel":
                Data("synthetic credential boundary".utf8),
            "synthetic.meeting-policy.sentinel":
                Data("synthetic meeting policy boundary".utf8),
            "synthetic.provider-consent-evidence.sentinel":
                Data("synthetic provider consent evidence boundary".utf8),
            "synthetic.research-prompt.sentinel":
                Data("synthetic research prompt boundary".utf8)
        ]
        for (key, value) in protectedSentinels {
            defaults.set(value, forKey: key)
        }

        for preference in BlueMinutesAppearancePreference.allCases {
            defaults.set(
                preference.rawValue,
                forKey: BlueMinutesUIPreferenceKeys.appearance
            )
            #expect(
                BlueMinutesAppearancePreference.resolve(
                    defaults.string(
                        forKey: BlueMinutesUIPreferenceKeys.appearance
                    )
                ) == preference
            )
        }
        for preference in BlueMinutesInterfaceDensityPreference.allCases {
            defaults.set(
                preference.rawValue,
                forKey: BlueMinutesUIPreferenceKeys.interfaceDensity
            )
            #expect(
                BlueMinutesInterfaceDensityPreference.resolve(
                    defaults.string(
                        forKey:
                            BlueMinutesUIPreferenceKeys.interfaceDensity
                    )
                ) == preference
            )
        }
        for preference in BlueMinutesReadingWidthPreference.allCases {
            defaults.set(
                preference.rawValue,
                forKey: BlueMinutesUIPreferenceKeys.readingWidth
            )
            #expect(
                BlueMinutesReadingWidthPreference.resolve(
                    defaults.string(
                        forKey: BlueMinutesUIPreferenceKeys.readingWidth
                    )
                ) == preference
            )
        }

        BlueMinutesUIPreferenceKeys.reset(in: defaults)

        for key in BlueMinutesUIPreferenceKeys.all {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(
            BlueMinutesAppearancePreference.resolve(
                defaults.string(
                    forKey: BlueMinutesUIPreferenceKeys.appearance
                )
            ) == .compiledDefault
        )
        #expect(
            BlueMinutesInterfaceDensityPreference.resolve(
                defaults.string(
                    forKey: BlueMinutesUIPreferenceKeys.interfaceDensity
                )
            ) == .compiledDefault
        )
        #expect(
            BlueMinutesReadingWidthPreference.resolve(
                defaults.string(
                    forKey: BlueMinutesUIPreferenceKeys.readingWidth
                )
            ) == .compiledDefault
        )
        for (key, value) in protectedSentinels {
            #expect(defaults.data(forKey: key) == value)
        }
        let persistentKeys: Set<String>
        if let domain = defaults.persistentDomain(forName: suiteName) {
            persistentKeys = Set(domain.keys)
        } else {
            persistentKeys = []
        }
        #expect(persistentKeys == Set(protectedSentinels.keys))
    }

    @Test @MainActor
    func appPreferencesRemainSharedAndIndependentFromSceneState() throws {
        let suiteName =
            "BlueMinutesSceneIsolationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            BlueMinutesAppearancePreference.dark.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.appearance
        )
        defaults.set(
            BlueMinutesInterfaceDensityPreference.compact.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.interfaceDensity
        )
        defaults.set(
            BlueMinutesReadingWidthPreference.expanded.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.readingWidth
        )

        let first = MediaReviewSceneState()
        let second = MediaReviewSceneState()
        let mainRecorder = BlueMinutesPresentationRecorder()
        let settingsRecorder = BlueMinutesPresentationRecorder()

        let mainWindow = hostWindow(
            title: "BlueMinutes Main Preference Probe",
            size: CGSize(width: 80, height: 80)
        ) {
            BlueMinutesPresentationRoot(defaults: defaults) {
                BlueMinutesPresentationProbe(recorder: mainRecorder)
            }
        }
        let settingsWindow = hostWindow(
            title: "BlueMinutes Settings Preference Probe",
            size: CGSize(width: 560, height: 360)
        ) {
            BlueMinutesPresentationRoot(defaults: defaults) {
                ZStack {
                    BlueMinutesSettingsView(
                        defaults: defaults,
                        initialTab: .general
                    )
                    BlueMinutesPresentationProbe(
                        recorder: settingsRecorder
                    )
                }
            }
        }
        defer {
            closeWindow(mainWindow)
            closeWindow(settingsWindow)
        }

        let initialPreferences = BlueMinutesPresentationSnapshot(
            colorScheme: .dark,
            controlSize: .small,
            readingWidth: .expanded
        )
        #expect(
            waitUntil {
                mainRecorder.latest == initialPreferences
                    && settingsRecorder.latest == initialPreferences
            }
        )

        first.selectedSection = .briefing
        first.meetingTitle = "Synthetic first scene"
        first.manualTranscriptText = "Synthetic transient draft"
        first.recordingAcknowledged = true
        first.unWebTVURL =
            "https://webtv.un.org/en/asset/synthetic/synthetic-id"
        first.unWebTVNetworkAuthorized = true
        first.confirmPreferenceReset = true

        #expect(first !== second)
        #expect(second.selectedSection == .intake)
        #expect(second.meetingTitle.isEmpty)
        #expect(second.manualTranscriptText.isEmpty)
        #expect(!second.recordingAcknowledged)
        #expect(!second.unWebTVNetworkAuthorized)
        #expect(!second.confirmPreferenceReset)

        #expect(first.selectedSection == .briefing)
        #expect(first.meetingTitle == "Synthetic first scene")
        #expect(first.manualTranscriptText == "Synthetic transient draft")
        #expect(first.recordingAcknowledged)
        #expect(first.unWebTVNetworkAuthorized)
        #expect(first.confirmPreferenceReset)

        #expect(mainRecorder.latest == initialPreferences)
        #expect(settingsRecorder.latest == initialPreferences)
        #expect(
            defaults.string(
                forKey: BlueMinutesUIPreferenceKeys.appearance
            ) == BlueMinutesAppearancePreference.dark.rawValue
        )
        #expect(
            defaults.string(
                forKey: BlueMinutesUIPreferenceKeys.interfaceDensity
            ) == BlueMinutesInterfaceDensityPreference.compact.rawValue
        )
        #expect(
            defaults.string(
                forKey: BlueMinutesUIPreferenceKeys.readingWidth
            ) == BlueMinutesReadingWidthPreference.expanded.rawValue
        )

        defaults.set(
            BlueMinutesAppearancePreference.light.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.appearance
        )
        defaults.set(
            BlueMinutesInterfaceDensityPreference.comfortable.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.interfaceDensity
        )
        defaults.set(
            BlueMinutesReadingWidthPreference.focused.rawValue,
            forKey: BlueMinutesUIPreferenceKeys.readingWidth
        )

        let updatedPreferences = BlueMinutesPresentationSnapshot(
            colorScheme: .light,
            controlSize: .regular,
            readingWidth: .focused
        )
        #expect(
            waitUntil {
                mainRecorder.latest == updatedPreferences
                    && settingsRecorder.latest == updatedPreferences
            }
        )
        #expect(first.selectedSection == .briefing)
        #expect(first.manualTranscriptText == "Synthetic transient draft")
        #expect(second.selectedSection == .intake)
        #expect(second.manualTranscriptText.isEmpty)

        BlueMinutesUIPreferenceKeys.reset(in: defaults)

        #expect(
            waitUntil {
                guard let main = mainRecorder.latest,
                      let settings = settingsRecorder.latest
                else {
                    return false
                }
                return main == settings
                    && main.controlSize == .regular
                    && main.readingWidth == .comfortable
            }
        )
        for key in BlueMinutesUIPreferenceKeys.all {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(first.confirmPreferenceReset)
        #expect(!second.confirmPreferenceReset)
    }

    @Test @MainActor
    func completeSettingsLayoutSurvivesThemesAndLargerMacText() throws {
        let suiteName =
            "BlueMinutesSettingsRenderingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rolesByIdentifier = [
            "blueminutes.settings": kAXTabGroupRole,
            "blueminutes.settings.tab.general": kAXRadioButtonRole,
            "blueminutes.settings.tab.appearance": kAXRadioButtonRole,
            "blueminutes.settings.interface-density":
                kAXPopUpButtonRole,
            "blueminutes.settings.reading-width": kAXPopUpButtonRole,
            "blueminutes.settings.layout-explanation":
                kAXStaticTextRole,
            "blueminutes.settings.reset": kAXButtonRole,
            "blueminutes.settings.appearance-picker":
                kAXRadioGroupRole,
            "blueminutes.settings.appearance-explanation":
                kAXStaticTextRole
        ]
        let sharedIdentifiers = [
            "blueminutes.settings",
            "blueminutes.settings.tab.general",
            "blueminutes.settings.tab.appearance"
        ]
        let contentIdentifiersByTab = [
            BlueMinutesSettingsTab.general: [
                "blueminutes.settings.interface-density",
                "blueminutes.settings.reading-width",
                "blueminutes.settings.layout-explanation",
                "blueminutes.settings.reset"
            ],
            BlueMinutesSettingsTab.appearance: [
                "blueminutes.settings.appearance-picker",
                "blueminutes.settings.appearance-explanation"
            ]
        ]
        let standardFontSize = NSFont.systemFontSize
        let largerFontSize = standardFontSize + 5

        for appearance in [
            BlueMinutesAppearancePreference.light,
            .dark
        ] {
            defaults.set(
                appearance.rawValue,
                forKey: BlueMinutesUIPreferenceKeys.appearance
            )

            for tab in [
                BlueMinutesSettingsTab.general,
                .appearance
            ] {
                let tabName = tab == .general
                    ? "general"
                    : "appearance"
                let expectedIdentifiers =
                    sharedIdentifiers
                    + (contentIdentifiersByTab[tab] ?? [])
                var standardFrames: [String: CGRect] = [:]

                for fontSize in [
                    standardFontSize,
                    largerFontSize
                ] {
                    let title = [
                        "BlueMinutes Settings Layout Probe",
                        appearance.rawValue,
                        tabName,
                        String(describing: fontSize)
                    ].joined(separator: " ")
                    let snapshots = try withHostedWindow(
                        title: title,
                        size: CGSize(width: 560, height: 360),
                        content: {
                            BlueMinutesPresentationRoot(
                                defaults: defaults
                            ) {
                                BlueMinutesSettingsView(
                                    defaults: defaults,
                                    initialTab: tab
                                )
                            }
                            // Dynamic Type does not resize macOS text.
                            // An inherited larger system font provides a
                            // real native layout stress without fixtures.
                            .environment(
                                \.font,
                                Font.system(size: fontSize)
                            )
                        },
                        operation: { _ in
                            try accessibilitySnapshots(
                                windowTitle: title,
                                identifiers: Set(expectedIdentifiers)
                            )
                        }
                    )

                    for identifier in expectedIdentifiers {
                        #expect(snapshots[identifier] != nil)
                        guard let snapshot = snapshots[identifier] else {
                            continue
                        }
                        #expect(
                            snapshot.role
                                == rolesByIdentifier[identifier]
                        )
                        #expect(snapshot.frame.width > 0)
                        #expect(snapshot.frame.height > 0)
                        #expect(
                            NSContainsRect(
                                snapshots.containingFrame.insetBy(
                                    dx: -1,
                                    dy: -1
                                ),
                                snapshot.frame
                            )
                        )
                    }

                    let frames = snapshots.elements.mapValues {
                        $0.frame
                    }
                    if fontSize == standardFontSize {
                        standardFrames = frames
                    } else {
                        #expect(frames != standardFrames)
                    }
                }
            }
        }
    }

    @Test
    func appStorageAndSceneRestorationStayInsideTheUIOnlyBoundary() throws {
        #expect(
            try productionSourcePaths(containing: "@AppStorage") == [
                "Sources/MeetingBuddyFeatures/DesignSystem/Environment/BlueMinutesPresentationRoot.swift",
                "Sources/MeetingBuddyFeatures/Views/BlueMinutesSettingsView.swift"
            ]
        )
        #expect(try productionSourcePaths(containing: "@SceneStorage").isEmpty)
        #expect(try productionSourcePaths(containing: "SceneStorage(").isEmpty)
        #expect(try productionSourcePaths(containing: "NSUserActivity").isEmpty)
        #expect(
            try productionSourcePaths(containing: ".inspector(") == [
                "Sources/MeetingBuddyFeatures/Views/AnalysisReviewView.swift",
                "Sources/MeetingBuddyFeatures/Views/TranscriptReviewView.swift"
            ]
        )

        let transcriptReviewSource = try source(
            "Sources/MeetingBuddyFeatures/Views/TranscriptReviewView.swift"
        )
        #expect(
            transcriptReviewSource.contains(
                "@State private var inspectorIsPresented = false"
            )
        )
        #expect(!transcriptReviewSource.contains("@SceneStorage"))
        #expect(!transcriptReviewSource.contains("@AppStorage"))

        let analysisReviewSource = try source(
            "Sources/MeetingBuddyFeatures/Views/AnalysisReviewView.swift"
        )
        #expect(
            analysisReviewSource.contains(
                "@State private var inspectorIsPresented = false"
            )
        )
        #expect(!analysisReviewSource.contains("@SceneStorage"))
        #expect(!analysisReviewSource.contains("@AppStorage"))

        let preferenceSources = try [
            source(
                "Sources/MeetingBuddyFeatures/DesignSystem/Environment/BlueMinutesUIPreferences.swift"
            ),
            source(
                "Sources/MeetingBuddyFeatures/DesignSystem/Environment/BlueMinutesPresentationRoot.swift"
            ),
            source(
                "Sources/MeetingBuddyFeatures/Views/BlueMinutesSettingsView.swift"
            )
        ].joined(separator: "\n")

        #expect(
            preferenceSources.contains(
                ".preferredColorScheme(appearance.colorScheme)"
            )
        )
        #expect(
            preferenceSources.contains(
                ".controlSize(interfaceDensity.controlSize)"
            )
        )
        #expect(
            preferenceSources.contains(
                ".environment(\\.blueMinutesReadingWidth, readingWidth)"
            )
        )
        #expect(
            preferenceSources.contains(
                "BlueMinutesUIPreferenceKeys.reset(in: defaults)"
            )
        )

        let normalizedPreferenceSources = preferenceSources.lowercased()
        for forbidden in [
            "automationsettingsvalues",
            "versionedautomationsettings",
            "learnedpreference",
            "appcapabilities",
            "credential",
            "token",
            "oauth",
            "secret",
            "keychain",
            "workspace",
            "bookmark",
            "raw path",
            "file path",
            "filesystem path",
            "meetingid",
            "meeting id",
            "meetingcontent",
            "meeting content",
            "meetingtitle",
            "meeting title",
            "draft",
            "classification",
            "accesspolicy",
            "access policy",
            "provider",
            "externalroute",
            "external route",
            "route authority",
            "retention",
            "evidence",
            "citation",
            "recording",
            "consent",
            "humanconfirmation",
            "human confirmation",
            "confirmation authority",
            "research",
            "prompt",
            "inspector",
            "removepersistentdomain"
        ] {
            #expect(!normalizedPreferenceSources.contains(forbidden))
        }
        #expect(!preferenceSources.contains("MeetingBuddyPersistence"))
    }

    @MainActor
    private func hostWindow<Content: View>(
        title: String,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        let application = NSApplication.shared
        if !application.isRunning {
            application.finishLaunching()
        }

        let contentRect = CGRect(origin: .zero, size: size)
        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = contentRect

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(
            until: Date(timeIntervalSinceNow: 0.05)
        )
        return window
    }

    @MainActor
    private func closeWindow(_ window: NSWindow) {
        window.contentView = nil
        window.close()
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(
                until: Date(timeIntervalSinceNow: 0.02)
            )
        }
        return condition()
    }

    @MainActor
    private func withHostedWindow<Content: View, Result>(
        title: String,
        size: CGSize,
        @ViewBuilder content: () -> Content,
        operation: (NSWindow) throws -> Result
    ) rethrows -> Result {
        let window = hostWindow(
            title: title,
            size: size,
            content: content
        )
        defer { closeWindow(window) }
        return try operation(window)
    }

    @MainActor
    private func accessibilitySnapshots(
        windowTitle: String,
        identifiers: Set<String>
    ) throws -> BlueMinutesAXSnapshots {
        let application = AXUIElementCreateApplication(getpid())
        let deadline = Date(timeIntervalSinceNow: 1)
        var matchingWindow: AXUIElement?

        repeat {
            matchingWindow = axElements(
                application,
                attribute: kAXWindowsAttribute
            ).first {
                axString($0, attribute: kAXTitleAttribute)
                    == windowTitle
            }
            if matchingWindow == nil {
                RunLoop.main.run(
                    until: Date(timeIntervalSinceNow: 0.02)
                )
            }
        } while matchingWindow == nil && Date() < deadline

        guard let matchingWindow else {
            throw BlueMinutesSettingsTestError
                .accessibilityWindowUnavailable(windowTitle)
        }
        guard let containingFrame = axFrame(matchingWindow) else {
            throw BlueMinutesSettingsTestError
                .accessibilityFrameUnavailable(windowTitle)
        }

        var elements: [String: BlueMinutesAXElementSnapshot] = [:]
        collectAccessibilitySnapshots(
            from: matchingWindow,
            identifiers: identifiers,
            depth: 0,
            into: &elements
        )
        return BlueMinutesAXSnapshots(
            containingFrame: containingFrame,
            elements: elements
        )
    }

    @MainActor
    private func collectAccessibilitySnapshots(
        from element: AXUIElement,
        identifiers: Set<String>,
        depth: Int,
        into snapshots: inout [String: BlueMinutesAXElementSnapshot]
    ) {
        guard depth < 20 else { return }

        if let identifier = axString(
            element,
            attribute: kAXIdentifierAttribute
        ), identifiers.contains(identifier),
           let role = axString(element, attribute: kAXRoleAttribute),
           let frame = axFrame(element)
        {
            snapshots[identifier] = BlueMinutesAXElementSnapshot(
                role: role,
                frame: frame
            )
        }

        for child in axElements(
            element,
            attribute: kAXChildrenAttribute
        ) {
            collectAccessibilitySnapshots(
                from: child,
                identifiers: identifiers,
                depth: depth + 1,
                into: &snapshots
            )
        }
    }

    @MainActor
    private func axElements(
        _ element: AXUIElement,
        attribute: String
    ) -> [AXUIElement] {
        axValue(element, attribute: attribute) as? [AXUIElement] ?? []
    }

    @MainActor
    private func axString(
        _ element: AXUIElement,
        attribute: String
    ) -> String? {
        axValue(element, attribute: attribute) as? String
    }

    @MainActor
    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(
            element,
            attribute: kAXPositionAttribute
        ), let sizeValue = axValue(
            element,
            attribute: kAXSizeAttribute
        ), CFGetTypeID(positionValue) == AXValueGetTypeID(),
           CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            positionValue as! AXValue,
            .cgPoint,
            &position
        ), AXValueGetValue(
            sizeValue as! AXValue,
            .cgSize,
            &size
        ) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    @MainActor
    private func axValue(
        _ element: AXUIElement,
        attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
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

    private func productionSourcePaths(
        containing token: String
    ) throws -> [String] {
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator
            where fileURL.pathExtension == "swift"
        {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            guard contents.contains(token) else { continue }
            paths.append(
                fileURL.path.replacingOccurrences(
                    of: repositoryRoot.path + "/",
                    with: ""
                )
            )
        }
        return paths.sorted()
    }
}

private struct BlueMinutesPresentationSnapshot: Equatable {
    let colorScheme: ColorScheme
    let controlSize: ControlSize
    let readingWidth: BlueMinutesReadingWidthPreference
}

@MainActor
private final class BlueMinutesPresentationRecorder {
    private(set) var latest: BlueMinutesPresentationSnapshot?

    func record(_ snapshot: BlueMinutesPresentationSnapshot) {
        latest = snapshot
    }
}

@MainActor
private struct BlueMinutesPresentationProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlSize) private var controlSize
    @Environment(\.blueMinutesReadingWidth) private var readingWidth

    let recorder: BlueMinutesPresentationRecorder

    private var snapshot: BlueMinutesPresentationSnapshot {
        BlueMinutesPresentationSnapshot(
            colorScheme: colorScheme,
            controlSize: controlSize,
            readingWidth: readingWidth
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                recorder.record(snapshot)
            }
            .onChange(of: snapshot) { _, newValue in
                recorder.record(newValue)
            }
    }
}

private struct BlueMinutesAXElementSnapshot {
    let role: String
    let frame: CGRect
}

private struct BlueMinutesAXSnapshots {
    let containingFrame: CGRect
    let elements: [String: BlueMinutesAXElementSnapshot]

    subscript(_ identifier: String) -> BlueMinutesAXElementSnapshot? {
        elements[identifier]
    }
}

private enum BlueMinutesSettingsTestError: Error {
    case accessibilityWindowUnavailable(String)
    case accessibilityFrameUnavailable(String)
}
