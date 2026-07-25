import Foundation
import SwiftUI

public struct BlueMinutesPresentationRoot<Content: View>: View {
    @AppStorage private var appearanceRawValue: String
    @AppStorage private var interfaceDensityRawValue: String
    @AppStorage private var readingWidthRawValue: String

    private let content: Content

    public init(
        defaults: UserDefaults = .standard,
        @ViewBuilder content: () -> Content
    ) {
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
        self.content = content()
    }

    public var body: some View {
        let appearance = BlueMinutesAppearancePreference.resolve(
            appearanceRawValue
        )
        let interfaceDensity =
            BlueMinutesInterfaceDensityPreference.resolve(
                interfaceDensityRawValue
            )
        let readingWidth = BlueMinutesReadingWidthPreference.resolve(
            readingWidthRawValue
        )

        content
            .preferredColorScheme(appearance.colorScheme)
            .controlSize(interfaceDensity.controlSize)
            .environment(\.blueMinutesReadingWidth, readingWidth)
    }
}
