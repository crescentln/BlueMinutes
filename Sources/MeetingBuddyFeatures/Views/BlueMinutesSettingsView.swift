import Foundation
import SwiftUI

enum BlueMinutesSettingsTab: Hashable {
    case general
    case appearance
    case intelligence
    case learnedPreferences
}

public struct BlueMinutesSettingsView: View {
    @AppStorage private var appearanceRawValue: String
    @AppStorage private var interfaceDensityRawValue: String
    @AppStorage private var readingWidthRawValue: String
    @State private var selectedTab: BlueMinutesSettingsTab
    @State private var preferenceEditor:
        LearnedPreferenceEditorState

    private let defaults: UserDefaults
    private let store: MediaReviewStore?
    private let codexStore: CodexConnectionStore?
    private let intelligenceStore:
        IntelligenceConfigurationStore?

    public init(defaults: UserDefaults = .standard) {
        self.init(
            store: nil,
            codexStore: nil,
            intelligenceStore: nil,
            defaults: defaults,
            initialTab: .general
        )
    }

    public init(
        store: MediaReviewStore,
        codexStore: CodexConnectionStore? = nil,
        intelligenceStore:
            IntelligenceConfigurationStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            store: store,
            codexStore: codexStore,
            intelligenceStore: intelligenceStore,
            defaults: defaults,
            initialTab: .general
        )
    }

    init(
        defaults: UserDefaults,
        initialTab: BlueMinutesSettingsTab
    ) {
        self.init(
            store: nil,
            codexStore: nil,
            intelligenceStore: nil,
            defaults: defaults,
            initialTab: initialTab
        )
    }

    init(
        store: MediaReviewStore?,
        codexStore: CodexConnectionStore? = nil,
        intelligenceStore:
            IntelligenceConfigurationStore? = nil,
        defaults: UserDefaults,
        initialTab: BlueMinutesSettingsTab
    ) {
        self.defaults = defaults
        self.store = store
        self.codexStore = codexStore
        self.intelligenceStore = intelligenceStore
        _selectedTab = State(initialValue: initialTab)
        _preferenceEditor = State(
            initialValue:
                LearnedPreferenceEditorState()
        )
        _appearanceRawValue = AppStorage(
            wrappedValue:
                BlueMinutesAppearancePreference.compiledDefault.rawValue,
            BlueMinutesUIPreferenceKeys.appearance,
            store: defaults
        )
        _interfaceDensityRawValue = AppStorage(
            wrappedValue:
                BlueMinutesInterfaceDensityPreference.compiledDefault.rawValue,
            BlueMinutesUIPreferenceKeys.interfaceDensity,
            store: defaults
        )
        _readingWidthRawValue = AppStorage(
            wrappedValue:
                BlueMinutesReadingWidthPreference.compiledDefault.rawValue,
            BlueMinutesUIPreferenceKeys.readingWidth,
            store: defaults
        )
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            BlueMinutesGeneralSettingsPane(
                interfaceDensity: interfaceDensity,
                readingWidth: readingWidth,
                resetUIPreferences: {
                    BlueMinutesUIPreferenceKeys.reset(in: defaults)
                }
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
                    .accessibilityIdentifier(
                        "blueminutes.settings.tab.general"
                    )
            }
            .tag(BlueMinutesSettingsTab.general)

            BlueMinutesAppearanceSettingsPane(appearance: appearance)
            .tabItem {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                    .accessibilityIdentifier(
                        "blueminutes.settings.tab.appearance"
                    )
            }
            .tag(BlueMinutesSettingsTab.appearance)

            if let codexStore,
               let intelligenceStore
            {
                CodexIntelligenceSettingsPane(
                    codexStore: codexStore,
                    intelligenceStore:
                        intelligenceStore
                )
                .tabItem {
                    Label(
                        "Intelligence",
                        systemImage: "sparkles"
                    )
                    .accessibilityIdentifier(
                        "blueminutes.settings.tab.intelligence"
                    )
                }
                .tag(BlueMinutesSettingsTab.intelligence)
            }

            if let store {
                LearnedPreferencesSettingsPane(
                    store: store,
                    editorState: preferenceEditor
                )
                .tabItem {
                    Label(
                        "Learned Preferences",
                        systemImage:
                            "text.badge.checkmark"
                    )
                    .accessibilityIdentifier(
                        "blueminutes.settings.tab.learned-preferences"
                    )
                }
                .tag(
                    BlueMinutesSettingsTab
                        .learnedPreferences
                )
            }
        }
        .frame(width: 520, height: 320)
        .scenePadding()
        .accessibilityIdentifier("blueminutes.settings")
    }

    private var appearance:
        Binding<BlueMinutesAppearancePreference>
    {
        Binding(
            get: {
                BlueMinutesAppearancePreference.resolve(
                    appearanceRawValue
                )
            },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var interfaceDensity:
        Binding<BlueMinutesInterfaceDensityPreference>
    {
        Binding(
            get: {
                BlueMinutesInterfaceDensityPreference.resolve(
                    interfaceDensityRawValue
                )
            },
            set: { interfaceDensityRawValue = $0.rawValue }
        )
    }

    private var readingWidth:
        Binding<BlueMinutesReadingWidthPreference>
    {
        Binding(
            get: {
                BlueMinutesReadingWidthPreference.resolve(
                    readingWidthRawValue
                )
            },
            set: { readingWidthRawValue = $0.rawValue }
        )
    }
}

struct BlueMinutesGeneralSettingsPane: View {
    @Binding var interfaceDensity: BlueMinutesInterfaceDensityPreference
    @Binding var readingWidth: BlueMinutesReadingWidthPreference
    let resetUIPreferences: () -> Void

    var body: some View {
        Form {
            Section("Layout") {
                Picker(
                    "Interface density",
                    selection: $interfaceDensity
                ) {
                    ForEach(
                        BlueMinutesInterfaceDensityPreference.allCases
                    ) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .accessibilityIdentifier(
                    "blueminutes.settings.interface-density"
                )

                Picker("Reading width", selection: $readingWidth) {
                    ForEach(
                        BlueMinutesReadingWidthPreference.allCases
                    ) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .accessibilityIdentifier(
                    "blueminutes.settings.reading-width"
                )

                Text(
                    "Density uses native macOS control sizing. Reading width adjusts the current Local Media editorial setup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "blueminutes.settings.layout-explanation"
                )
            }

            Section {
                Button("Reset UI Preferences") {
                    resetUIPreferences()
                }
                .accessibilityIdentifier(
                    "blueminutes.settings.reset"
                )
                .accessibilityHint(
                    "Restore only appearance, interface density, and reading width to their compiled defaults."
                )
            }
        }
    }
}

struct BlueMinutesAppearanceSettingsPane: View {
    @Binding var appearance: BlueMinutesAppearancePreference

    var body: some View {
        Form {
            Section("Application Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(
                        BlueMinutesAppearancePreference.allCases
                    ) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier(
                    "blueminutes.settings.appearance-picker"
                )

                Text(
                    "System follows the current macOS appearance. Light and Dark use native adaptive surfaces."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "blueminutes.settings.appearance-explanation"
                )
            }
        }
    }
}
