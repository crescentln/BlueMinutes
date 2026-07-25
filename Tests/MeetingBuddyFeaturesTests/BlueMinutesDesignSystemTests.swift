import AppKit
import SwiftUI
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct BlueMinutesDesignSystemTests {
    @Test @MainActor
    func consumedIconRolesResolvePreferredFallbackAndLastResortSymbols() {
        for role in BlueMinutesIconRole.allCases {
            #expect(
                role.resolvedSystemName { $0 == role.preferredSystemName }
                    == role.preferredSystemName
            )
            #expect(
                role.resolvedSystemName { $0 == role.fallbackSystemName }
                    == role.fallbackSystemName
            )
            #expect(role.resolvedSystemName { _ in false } == "circle")
        }
    }

    @Test @MainActor
    func canvasSurfaceResolvesForLightDarkAndHighContrastAppearances() throws {
        let light = try rgba(
            BlueMinutesColors.canvasNSColor,
            appearance: try #require(NSAppearance(named: .aqua))
        )
        let dark = try rgba(
            BlueMinutesColors.canvasNSColor,
            appearance: try #require(NSAppearance(named: .darkAqua))
        )
        let highContrastLight = try rgba(
            BlueMinutesColors.canvasNSColor,
            appearance: try #require(
                NSAppearance(named: .accessibilityHighContrastAqua)
            )
        )
        let highContrastDark = try rgba(
            BlueMinutesColors.canvasNSColor,
            appearance: try #require(
                NSAppearance(named: .accessibilityHighContrastDarkAqua)
            )
        )

        #expect(luminance(light) > luminance(dark))
        #expect(luminance(highContrastLight) > luminance(highContrastDark))
        #expect(light.alpha > 0)
        #expect(dark.alpha > 0)
        #expect(highContrastLight.alpha > 0)
        #expect(highContrastDark.alpha > 0)
    }

    @Test @MainActor
    func sidebarRowRendersAcrossAppearanceAndAccessibilityFallbacks() throws {
        let configurations: [(ColorScheme, Bool)] = [
            (.light, false),
            (.dark, false),
            (.light, true),
            (.dark, true)
        ]

        for configuration in configurations {
            let row = WorkspaceSidebarRow(
                title: "Transcript Review",
                icon: .transcript,
                enabledHint: "Open Transcript Review.",
                availability: configuration.1
                    ? .prerequisiteUnavailable(
                        reason:
                            "Available after local media processing succeeds."
                    )
                    : .enabled
            )
            .disabled(configuration.1)
            .environment(\.colorScheme, configuration.0)
            .frame(width: 260, height: 44, alignment: .leading)

            let renderer = ImageRenderer(content: row)
            renderer.scale = 2
            let image = try #require(renderer.nsImage)

            #expect(image.size.width == 260)
            #expect(image.size.height == 44)
        }
    }

    @Test
    func sidebarAvailabilityKeepsEveryReasonExplicit() {
        let enabledHint = "Open Transcript Review."
        let prerequisiteReason =
            "Available after local media processing succeeds."
        let interactionLockReason =
            "Temporarily unavailable while BlueMinutes completes a save or workspace change."
        let storeWorkReason =
            "Temporarily unavailable while BlueMinutes completes the current operation."

        let enabled = WorkspaceSidebarRowAvailability.resolve(
            prerequisiteReason: nil,
            temporaryReason: nil
        )
        #expect(enabled == .enabled)
        #expect(enabled.resolvedHint(enabledHint: enabledHint) == enabledHint)

        let prerequisiteOnly =
            WorkspaceSidebarRowAvailability.resolve(
                prerequisiteReason: prerequisiteReason,
                temporaryReason: nil
            )
        #expect(
            prerequisiteOnly
                == .prerequisiteUnavailable(reason: prerequisiteReason)
        )
        #expect(
            prerequisiteOnly.resolvedHint(enabledHint: enabledHint)
                == prerequisiteReason
        )

        let prerequisiteAndTemporary =
            WorkspaceSidebarRowAvailability.resolve(
                prerequisiteReason: prerequisiteReason,
                temporaryReason: interactionLockReason
            )
        #expect(
            prerequisiteAndTemporary
                == .prerequisiteUnavailable(reason: prerequisiteReason)
        )
        #expect(
            prerequisiteAndTemporary.resolvedHint(enabledHint: enabledHint)
                == prerequisiteReason
        )

        for temporaryReason in [interactionLockReason, storeWorkReason] {
            let temporarilyUnavailable =
                WorkspaceSidebarRowAvailability.resolve(
                    prerequisiteReason: nil,
                    temporaryReason: temporaryReason
                )
            #expect(
                temporarilyUnavailable
                    == .temporarilyUnavailable(reason: temporaryReason)
            )
            #expect(
                temporarilyUnavailable.resolvedHint(enabledHint: enabledHint)
                    == temporaryReason
            )
        }
    }

    @Test
    func sidebarRowKeepsTextAndAccessibilityIndependentOfColor() throws {
        let component = try source(
            "Sources/MeetingBuddyFeatures/DesignSystem/Components/WorkspaceSidebarRow.swift"
        )

        #expect(component.contains("Text(title)"))
        #expect(component.contains(".accessibilityHidden(true)"))
        #expect(component.contains(".accessibilityLabel(title)"))
        #expect(
            component.contains(
                ".accessibilityHint(availability.resolvedHint(enabledHint: enabledHint))"
            )
        )
        #expect(
            component.contains(
                ".help(availability.resolvedHint(enabledHint: enabledHint))"
            )
        )
        #expect(!component.contains("@Environment(\\.isEnabled)"))
        #expect(!component.contains(".foregroundStyle(BlueMinutesColors"))
    }

    @Test
    func designSystemContainsOnlyTheValuesConsumedByTheCurrentShell() {
        #expect(BlueMinutesLayout.sidebarRowSpacing == 8)
        #expect(BlueMinutesLayout.sidebarIconWidth == 16)
    }

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    @MainActor
    private func rgba(
        _ color: NSColor,
        appearance: NSAppearance
    ) throws -> RGBA {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB)
        }
        let resolvedColor = try #require(resolved)
        return RGBA(
            red: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent,
            alpha: resolvedColor.alphaComponent
        )
    }

    private func luminance(_ color: RGBA) -> CGFloat {
        (0.2126 * color.red)
            + (0.7152 * color.green)
            + (0.0722 * color.blue)
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
