import Foundation
import SwiftUI

enum BlueMinutesUIPreferenceKeys {
    static let appearance = "meetingbuddy.ui.appearance.v1"
    static let interfaceDensity = "meetingbuddy.ui.interface-density.v1"
    static let readingWidth = "meetingbuddy.ui.reading-width.v1"

    static let all = [
        appearance,
        interfaceDensity,
        readingWidth
    ]

    static func reset(in defaults: UserDefaults) {
        for key in all {
            defaults.removeObject(forKey: key)
        }
    }
}

enum BlueMinutesAppearancePreference:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case system
    case light
    case dark

    static let compiledDefault = Self.system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    static func resolve(_ storedRawValue: String?) -> Self {
        storedRawValue.flatMap(Self.init(rawValue:)) ?? compiledDefault
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum BlueMinutesInterfaceDensityPreference:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case comfortable
    case compact

    static let compiledDefault = Self.comfortable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .comfortable:
            "Comfortable"
        case .compact:
            "Compact"
        }
    }

    static func resolve(_ storedRawValue: String?) -> Self {
        storedRawValue.flatMap(Self.init(rawValue:)) ?? compiledDefault
    }

    var controlSize: ControlSize {
        switch self {
        case .comfortable:
            .regular
        case .compact:
            .small
        }
    }
}

enum BlueMinutesReadingWidthPreference:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case focused
    case comfortable
    case expanded

    static let compiledDefault = Self.comfortable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focused:
            "Focused"
        case .comfortable:
            "Comfortable"
        case .expanded:
            "Expanded"
        }
    }

    var points: CGFloat {
        switch self {
        case .focused:
            640
        case .comfortable:
            760
        case .expanded:
            880
        }
    }

    static func resolve(_ storedRawValue: String?) -> Self {
        storedRawValue.flatMap(Self.init(rawValue:)) ?? compiledDefault
    }
}

private struct BlueMinutesReadingWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue =
        BlueMinutesReadingWidthPreference.compiledDefault
}

extension EnvironmentValues {
    var blueMinutesReadingWidth: BlueMinutesReadingWidthPreference {
        get { self[BlueMinutesReadingWidthEnvironmentKey.self] }
        set { self[BlueMinutesReadingWidthEnvironmentKey.self] = newValue }
    }
}
