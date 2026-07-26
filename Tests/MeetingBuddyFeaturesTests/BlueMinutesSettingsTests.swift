import AppKit
import ApplicationServices
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
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

    @Test @MainActor
    func learnedPreferencesTabHostsRepositoryBackedControlsInsideSettings()
        async throws
    {
        let suiteName =
            "BlueMinutesLearnedSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let store =
            try makeFeatureStoreForHostedSettingsTests()
        let sceneState = MediaReviewSceneState()
        await store.openOrCreateWorkspace(
            at: URL(
                fileURLWithPath:
                    "/synthetic-hosted-settings-workspace"
            ),
            using: sceneState
        )
        await store.loadLearnedPreferences()

        let title =
            "BlueMinutes Learned Preferences AX Probe"
        let identifiers: Set<String> = [
            "blueminutes.settings",
            "blueminutes.settings.tab.learned-preferences",
            "blueminutes.settings.learned-preferences",
            "blueminutes.settings.learned-preferences.global-toggle",
            "blueminutes.settings.learned-preferences.kind",
            "blueminutes.settings.learned-preferences.value",
            "blueminutes.settings.learned-preferences.save",
            "blueminutes.settings.learned-preferences.reset"
        ]
        let snapshots = try withHostedWindow(
            title: title,
            size: CGSize(width: 560, height: 360),
            content: {
                BlueMinutesPresentationRoot(
                    defaults: defaults
                ) {
                    BlueMinutesSettingsView(
                        store: store,
                        defaults: defaults,
                        initialTab:
                            .learnedPreferences
                    )
                }
            },
            operation: { _ in
                try accessibilitySnapshots(
                    windowTitle: title,
                    identifiers: identifiers
                )
            }
        )

        for identifier in identifiers {
            #expect(snapshots[identifier] != nil)
            guard let snapshot =
                snapshots[identifier]
            else { continue }
            #expect(snapshot.frame.width > 0)
            #expect(snapshot.frame.height > 0)
            #expect(
                snapshot.frame.width
                    <= snapshots.containingFrame.width
                        + 2
            )
        }
        #expect(
            snapshots[
                "blueminutes.settings.tab.learned-preferences"
            ]?.role == kAXRadioButtonRole
        )
        #expect(
            snapshots[
                "blueminutes.settings.learned-preferences.kind"
            ]?.role == kAXPopUpButtonRole
        )
        #expect(
            snapshots[
                "blueminutes.settings.learned-preferences.value"
            ]?.role == kAXTextFieldRole
        )
        #expect(
            snapshots[
                "blueminutes.settings.learned-preferences.save"
            ]?.role == kAXButtonRole
        )
        #expect(
            snapshots[
                "blueminutes.settings.learned-preferences.reset"
            ]?.role == kAXButtonRole
        )
    }

    @Test @MainActor
    func historyStatesAndCommandsExposeNativeRuntimeAccessibility()
        throws
    {
        let indexTitle =
            "BlueMinutes History Index AX Probe"
        let indexIdentifiers: Set<String> = [
            "blueminutes.history.index-search",
            "blueminutes.history.reload-index",
            "blueminutes.history.rebuild-index",
            "blueminutes.history.search"
        ]
        let indexSnapshots = try withHostedWindow(
            title: indexTitle,
            size: CGSize(width: 860, height: 600),
            content: {
                HostedHistoryIndexAccessibilityProbe()
                    .padding()
            },
            operation: { _ in
                try accessibilitySnapshots(
                    windowTitle: indexTitle,
                    identifiers: indexIdentifiers
                )
            }
        )
        for identifier in indexIdentifiers {
            #expect(
                indexSnapshots[identifier] != nil
            )
            #expect(
                indexSnapshots[identifier]?.frame
                    .width ?? 0 > 0
            )
            #expect(
                indexSnapshots[identifier]?.frame
                    .height ?? 0 > 0
            )
        }
        for identifier in [
            "blueminutes.history.reload-index",
            "blueminutes.history.rebuild-index",
            "blueminutes.history.search"
        ] {
            #expect(
                indexSnapshots.roleOccurrenceCount(
                    identifier,
                    role: kAXButtonRole
                ) == 1
            )
        }

        let reviewTitle =
            "BlueMinutes History Review AX Probe"
        let reviewFixture =
            try HostedHistoryReviewAccessibilityFixture()
        let reviewIdentifiers: Set<String> = [
            "blueminutes.history.results",
            reviewFixture.currentSelectionIdentifier,
            reviewFixture.previousSelectionIdentifier
        ]
        let reviewSnapshots = try withHostedWindow(
            title: reviewTitle,
            size: CGSize(width: 860, height: 600),
            content: {
                HostedHistoryResultsAccessibilityProbe(
                    fixture: reviewFixture
                )
                    .padding()
            },
            operation: { _ in
                try accessibilitySnapshots(
                    windowTitle: reviewTitle,
                    identifiers: reviewIdentifiers
                )
            }
        )
        for identifier in reviewIdentifiers {
            #expect(
                reviewSnapshots[identifier] != nil
            )
            #expect(
                reviewSnapshots[identifier]?.frame
                    .width ?? 0 > 0
            )
            #expect(
                reviewSnapshots[identifier]?.frame
                    .height ?? 0 > 0
            )
        }
        for identifier in [
            reviewFixture.currentSelectionIdentifier,
            reviewFixture.previousSelectionIdentifier
        ] {
            #expect(
                reviewSnapshots.roleOccurrenceCount(
                    identifier,
                    role: kAXButtonRole
                ) == 1
            )
        }

        let comparisonTitle =
            "BlueMinutes History Comparison AX Probe"
        let comparisonIdentifiers: Set<String> = [
            "blueminutes.history.comparison",
            "blueminutes.history.compare",
            "blueminutes.history.confirm-change"
        ]
        let comparisonSnapshots = try withHostedWindow(
            title: comparisonTitle,
            size: CGSize(width: 860, height: 600),
            content: {
                HostedHistoryComparisonAccessibilityProbe(
                    fixture: reviewFixture
                )
                    .padding()
            },
            operation: { _ in
                try accessibilitySnapshots(
                    windowTitle: comparisonTitle,
                    identifiers: comparisonIdentifiers
                )
            }
        )
        for identifier in comparisonIdentifiers {
            #expect(
                comparisonSnapshots[identifier] != nil
            )
            #expect(
                comparisonSnapshots[identifier]?.frame
                    .width ?? 0 > 0
            )
            #expect(
                comparisonSnapshots[identifier]?.frame
                    .height ?? 0 > 0
            )
        }
        for identifier in [
            "blueminutes.history.compare",
            "blueminutes.history.confirm-change"
        ] {
            #expect(
                comparisonSnapshots.roleOccurrenceCount(
                    identifier,
                    role: kAXButtonRole
                ) == 1
            )
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

        let uiPreferenceSources = try [
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
            uiPreferenceSources.contains(
                ".preferredColorScheme(appearance.colorScheme)"
            )
        )
        #expect(
            uiPreferenceSources.contains(
                ".controlSize(interfaceDensity.controlSize)"
            )
        )
        #expect(
            uiPreferenceSources.contains(
                ".environment(\\.blueMinutesReadingWidth, readingWidth)"
            )
        )
        #expect(
            uiPreferenceSources.contains(
                "BlueMinutesUIPreferenceKeys.reset(in: defaults)"
            )
        )

        let normalizedPreferenceSources =
            uiPreferenceSources.lowercased()
        for forbidden in [
            "automationsettingsvalues",
            "versionedautomationsettings",
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
        #expect(
            !uiPreferenceSources.contains(
                "MeetingBuddyPersistence"
            )
        )

        let learnedPreferences = try source(
            "Sources/MeetingBuddyFeatures/Views/LearnedPreferencesSettingsPane.swift"
        )
        #expect(!learnedPreferences.contains("@AppStorage"))
        #expect(!learnedPreferences.contains("@SceneStorage"))
        #expect(
            learnedPreferences.contains(
                "store.loadLearnedPreferences()"
            )
        )
        #expect(
            learnedPreferences.contains(
                "Presentation guidance only"
            )
        )
        let settingsView = try source(
            "Sources/MeetingBuddyFeatures/Views/BlueMinutesSettingsView.swift"
        )
        #expect(
            !settingsView.contains(
                "safeErrorMessage"
            )
        )
        #expect(
            normalizedPreferenceSources.contains(
                "learnedpreferences"
            )
        )
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
        var matches:
            [String: [BlueMinutesAXElementSnapshot]] = [:]
        collectAccessibilitySnapshots(
            from: matchingWindow,
            identifiers: identifiers,
            depth: 0,
            into: &elements,
            matches: &matches
        )
        return BlueMinutesAXSnapshots(
            containingFrame: containingFrame,
            elements: elements,
            matches: matches
        )
    }

    @MainActor
    private func collectAccessibilitySnapshots(
        from element: AXUIElement,
        identifiers: Set<String>,
        depth: Int,
        into snapshots: inout [String: BlueMinutesAXElementSnapshot],
        matches:
            inout [String: [BlueMinutesAXElementSnapshot]]
    ) {
        guard depth < 20 else { return }

        if let identifier = axString(
            element,
            attribute: kAXIdentifierAttribute
        ), identifiers.contains(identifier),
           let role = axString(element, attribute: kAXRoleAttribute),
           let frame = axFrame(element)
        {
            let snapshot = BlueMinutesAXElementSnapshot(
                role: role,
                frame: frame
            )
            matches[identifier, default: []].append(
                snapshot
            )
            snapshots[identifier] = snapshot
        }

        for child in axElements(
            element,
            attribute: kAXChildrenAttribute
        ) {
            collectAccessibilitySnapshots(
                from: child,
                identifiers: identifiers,
                depth: depth + 1,
                into: &snapshots,
                matches: &matches
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

@MainActor
private struct HostedHistoryIndexAccessibilityProbe:
    View
{
    @State private var actorOrCountry = ""
    @State private var topic = ""
    @State private var organizationOrBody = ""
    @State private var meetingType = ""
    @State private var startDate = ""
    @State private var endDate = ""

    var body: some View {
        HistoricalIndexSearchView(
            status: HistoricalIndexStatus(
                availability: .ready,
                generation: 7,
                normalizerVersion: 1,
                indexedPositionCount: 0,
                rebuiltAt: nil,
                sourceFingerprint: nil
            ),
            job: nil,
            isLoading: false,
            failureMessage: nil,
            isWorking: false,
            actorOrCountry: $actorOrCountry,
            topic: $topic,
            organizationOrBody:
                $organizationOrBody,
            meetingType: $meetingType,
            startDate: $startDate,
            endDate: $endDate,
            reloadStatus: {},
            rebuildIndex: {},
            search: {}
        )
    }
}

@MainActor
private struct HostedHistoryResultsAccessibilityProbe:
    View
{
    let fixture: HostedHistoryReviewAccessibilityFixture

    var body: some View {
        HistoricalResultsView(
            page: HistoricalSearchPage(
                results: [fixture.result],
                nextCursor: nil,
                indexGeneration: 7
            ),
            isLoading: false,
            failureMessage: nil,
            lastSuccessfulFilter: fixture.filter,
            currentFilter: fixture.filter,
            selectedCurrentRevisionID:
                fixture.currentRevisionID,
            selectedPreviousRevisionID:
                fixture.previousRevisionID,
            selectCurrent: { _ in },
            selectPrevious: { _ in }
        )
    }
}

@MainActor
private struct HostedHistoryComparisonAccessibilityProbe:
    View
{
    let fixture: HostedHistoryReviewAccessibilityFixture

    var body: some View {
        HistoricalComparisonView(
            comparison: fixture.comparison,
            currentRevisionID:
                fixture.currentRevisionID,
            previousRevisionID:
                fixture.previousRevisionID,
            isWorking: false,
            resultsAreCurrent: true,
            compare: {},
            requestConfirmation: {}
        )
    }
}

private struct HostedHistoryReviewAccessibilityFixture {
    let result: HistoricalPositionResult
    let comparison: HistoricalComparisonV1
    let currentRevisionID: RevisionID
    let previousRevisionID: RevisionID
    let filter = HistoricalSearchFilterSnapshot(
        actorOrCountry: "",
        topic: "",
        organizationOrBody: "",
        meetingType: "",
        startDate: "",
        endDate: ""
    )

    var currentSelectionIdentifier: String {
        selectionIdentifier(role: "current")
    }

    var previousSelectionIdentifier: String {
        selectionIdentifier(role: "previous")
    }

    init() throws {
        let createdAt = try UTCInstant(
            millisecondsSinceUnixEpoch:
                1_950_000_000_000
        )
        let currentDate = try CalendarDate(
            year: 2026,
            month: 7,
            day: 26
        )
        let previousDate = try CalendarDate(
            year: 2025,
            month: 7,
            day: 26
        )

        let meetingID = historyAXID(
            1,
            MeetingID.self
        )
        let meetingRevisionID = historyAXID(
            2,
            RevisionID.self
        )
        let meetingReference = try historyAXReference(
            meetingID,
            meetingRevisionID
        )
        let meeting = try MeetingProfileV1(
            revision: historyAXEnvelope(
                logicalID: meetingID,
                revisionID: meetingRevisionID,
                createdAt: createdAt
            ),
            title: "Synthetic accessibility meeting",
            meetingDate: currentDate,
            outputLanguage: LanguageTag("en"),
            cloudProcessingPolicy: .localOnly,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )

        let actorID = historyAXID(3, ActorID.self)
        let actorRevisionID = historyAXID(
            4,
            RevisionID.self
        )
        let actorReference = try historyAXReference(
            actorID,
            actorRevisionID
        )
        let actor = try ActorV1(
            revision: historyAXEnvelope(
                logicalID: actorID,
                revisionID: actorRevisionID,
                createdAt: createdAt
            ),
            identity: .other(
                displayName:
                    "Synthetic Accessibility Delegation"
            ),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )

        let issueID = historyAXID(5, IssueID.self)
        let issueRevisionID = historyAXID(
            6,
            RevisionID.self
        )
        let issueReference = try historyAXReference(
            issueID,
            issueRevisionID
        )
        let issue = try IssueV1(
            revision: historyAXEnvelope(
                logicalID: issueID,
                revisionID: issueRevisionID,
                inputs: [meetingReference],
                createdAt: createdAt
            ),
            meetingID: meetingID,
            title: EvidenceLinkedClaim(
                text:
                    "Synthetic accessibility issue",
                taxonomy: .meetingBuddyExtraction,
                supportStatus: .unsupported,
                evidenceRevisions: [],
                confidence:
                    ConfidenceScore(
                        millionths: 500_000
                    )
            ),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )

        let organizationReference =
            try historyAXReference(
                historyAXID(
                    7,
                    OrganizationID.self
                ),
                historyAXID(
                    8,
                    RevisionID.self
                )
            )
        let capacityReference =
            try historyAXReference(
                historyAXID(
                    9,
                    SpeakingCapacityID.self
                ),
                historyAXID(
                    10,
                    RevisionID.self
                )
            )
        let positionID = historyAXID(
            11,
            PositionID.self
        )
        let positionRevisionID = historyAXID(
            12,
            RevisionID.self
        )
        let position = try PositionV1(
            revision: historyAXEnvelope(
                logicalID: positionID,
                revisionID: positionRevisionID,
                inputs: [
                    meetingReference,
                    actorReference,
                    organizationReference,
                    capacityReference,
                    issueReference
                ],
                createdAt: createdAt
            ),
            meetingID: meetingID,
            actorRevision: actorReference,
            representedEntityRevision:
                organizationReference,
            speakingCapacityRevision:
                capacityReference,
            issueRevision: issueReference,
            positionType: .supports,
            statement: EvidenceLinkedClaim(
                text:
                    "Synthetic accessibility position",
                taxonomy: .meetingBuddyExtraction,
                supportStatus: .unsupported,
                evidenceRevisions: [],
                confidence:
                    ConfidenceScore(
                        millionths: 500_000
                    )
            ),
            comparisonState: .unknown,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )

        let sensitivityReference =
            try historyAXReference(
                historyAXID(
                    13,
                    SensitivityLabelID.self
                ),
                historyAXID(
                    14,
                    RevisionID.self
                )
            )
        let policyReference =
            try historyAXReference(
                historyAXID(
                    15,
                    AccessPolicyID.self
                ),
                historyAXID(
                    16,
                    RevisionID.self
                )
            )
        result = HistoricalPositionResult(
            position: position,
            meeting: meeting,
            actor: actor,
            issue: issue,
            evidence: [],
            sensitivityLabelRevision:
                sensitivityReference,
            accessPolicyRevision: policyReference,
            organizationLabel:
                "Synthetic Organization",
            meetingType: nil,
            effectiveClassification: .internal
        )

        currentRevisionID = positionRevisionID
        previousRevisionID = historyAXID(
            17,
            RevisionID.self
        )
        let currentPositionReference =
            try historyAXReference(
                positionID,
                positionRevisionID
            )
        let previousPositionReference =
            try historyAXReference(
                historyAXID(
                    18,
                    PositionID.self
                ),
                previousRevisionID
            )
        let previousMeetingReference =
            try historyAXReference(
                historyAXID(
                    19,
                    MeetingID.self
                ),
                historyAXID(
                    20,
                    RevisionID.self
                )
            )
        let previousActorReference =
            try historyAXReference(
                historyAXID(
                    21,
                    ActorID.self
                ),
                historyAXID(
                    22,
                    RevisionID.self
                )
            )
        let previousIssueReference =
            try historyAXReference(
                historyAXID(
                    23,
                    IssueID.self
                ),
                historyAXID(
                    24,
                    RevisionID.self
                )
            )
        let previousSensitivityReference =
            try historyAXReference(
                historyAXID(
                    25,
                    SensitivityLabelID.self
                ),
                historyAXID(
                    26,
                    RevisionID.self
                )
            )
        let previousPolicyReference =
            try historyAXReference(
                historyAXID(
                    27,
                    AccessPolicyID.self
                ),
                historyAXID(
                    28,
                    RevisionID.self
                )
            )
        let currentEvidenceReference =
            try historyAXReference(
                historyAXID(
                    29,
                    EvidenceID.self
                ),
                historyAXID(
                    30,
                    RevisionID.self
                )
            )
        let previousEvidenceReference =
            try historyAXReference(
                historyAXID(
                    31,
                    EvidenceID.self
                ),
                historyAXID(
                    32,
                    RevisionID.self
                )
            )
        let comparisonInputs = [
            currentPositionReference,
            previousPositionReference,
            meetingReference,
            previousMeetingReference,
            actorReference,
            previousActorReference,
            issueReference,
            previousIssueReference,
            sensitivityReference,
            previousSensitivityReference,
            policyReference,
            previousPolicyReference
        ]
        comparison = try HistoricalComparisonV1(
            revision: historyAXEnvelope(
                logicalID: historyAXID(
                    33,
                    HistoricalComparisonID.self
                ),
                revisionID: historyAXID(
                    34,
                    RevisionID.self
                ),
                inputs: comparisonInputs,
                evidence: [
                    currentEvidenceReference,
                    previousEvidenceReference
                ],
                createdAt: createdAt
            ),
            currentPositionRevision:
                currentPositionReference,
            historicalPositionRevision:
                previousPositionReference,
            currentMeetingRevision:
                meetingReference,
            historicalMeetingRevision:
                previousMeetingReference,
            currentActorRevision: actorReference,
            historicalActorRevision:
                previousActorReference,
            currentIssueRevision: issueReference,
            historicalIssueRevision:
                previousIssueReference,
            currentSensitivityLabelRevision:
                sensitivityReference,
            historicalSensitivityLabelRevision:
                previousSensitivityReference,
            currentAccessPolicyRevision:
                policyReference,
            historicalAccessPolicyRevision:
                previousPolicyReference,
            currentEffectiveDate: currentDate,
            historicalEffectiveDate: previousDate,
            currentEffectiveTimeRange: nil,
            historicalEffectiveTimeRange: nil,
            currentConfidence:
                ConfidenceScore(
                    millionths: 800_000
                ),
            historicalConfidence:
                ConfidenceScore(
                    millionths: 700_000
                ),
            currentEvidenceRevisions: [
                currentEvidenceReference
            ],
            historicalEvidenceRevisions: [
                previousEvidenceReference
            ],
            differenceState:
                .possibleDifference,
            finding: .possibleChange,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
    }

    private func selectionIdentifier(
        role: String
    ) -> String {
        "blueminutes.history.result."
            + currentRevisionID.canonicalString
            + ".use-"
            + role
    }
}

private func historyAXID<Tag>(
    _ suffix: Int,
    _: StableID<Tag>.Type
) -> StableID<Tag> {
    StableID<Tag>(
        UUID(
            uuidString: String(
                format:
                    "52000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    )
}

private func historyAXReference<
    Tag: LogicalObjectIDScope
>(
    _ logicalID: StableID<Tag>,
    _ revisionID: RevisionID
) throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: logicalID,
        revisionID: revisionID
    )
}

private func historyAXEnvelope<
    Tag: LogicalObjectIDScope
>(
    logicalID: StableID<Tag>,
    revisionID: RevisionID,
    inputs: [SemanticRevisionReference] = [],
    evidence: [SemanticRevisionReference] = [],
    createdAt: UTCInstant
) throws -> RevisionEnvelope<Tag> {
    try RevisionEnvelope(
        logicalID: logicalID,
        revisionID: revisionID,
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: createdAt,
        createdBy: .application,
        inputRevisions: inputs,
        evidenceRevisions: evidence,
        dataClassification: .internal
    )
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
    let matches:
        [String: [BlueMinutesAXElementSnapshot]]

    subscript(_ identifier: String) -> BlueMinutesAXElementSnapshot? {
        elements[identifier]
    }

    func roleOccurrenceCount(
        _ identifier: String,
        role: String
    ) -> Int {
        matches[identifier, default: []]
            .count { $0.role == role }
    }
}

private enum BlueMinutesSettingsTestError: Error {
    case accessibilityWindowUnavailable(String)
    case accessibilityFrameUnavailable(String)
}
