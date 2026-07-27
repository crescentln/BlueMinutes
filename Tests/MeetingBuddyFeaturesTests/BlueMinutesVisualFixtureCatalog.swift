enum BlueMinutesVisualFixtureSurface:
    String,
    CaseIterable,
    Codable,
    Sendable
{
    case shell
    case onboarding
    case localMedia = "local-media"
    case recording
    case unWebTV = "un-web-tv"
    case transcript
    case analysis
    case briefing
    case history
    case storage
    case settings
}

struct BlueMinutesVisualNativeActionContract:
    Equatable,
    Sendable
{
    let fixtureID: String
    let accessibilityIdentifier:
        String
    let accessibilityLabel: String
    let region:
        BlueMinutesVisualPixelRegion

    static let all: [
        BlueMinutesVisualNativeActionContract
    ] = [
        contract(
            fixtureID:
                "local-media-ready-light",
            identifier:
                "BlueMinutes.LocalMedia.ChooseSource",
            label:
                "Choose Audio or Video…",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 24,
                    y: 205,
                    width: 175,
                    height: 32
                )
        ),
        contract(
            fixtureID:
                "local-media-ready-light",
            identifier:
                "BlueMinutes.LocalMedia.ImportAndProcess",
            label:
                "Import and Process",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 24,
                    y: 525,
                    width: 150,
                    height: 36
                )
        ),
        contract(
            fixtureID:
                "local-media-ready-dark",
            identifier:
                "BlueMinutes.LocalMedia.ChooseSource",
            label:
                "Choose Audio or Video…",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 24,
                    y: 205,
                    width: 175,
                    height: 32
                )
        ),
        contract(
            fixtureID:
                "local-media-ready-dark",
            identifier:
                "BlueMinutes.LocalMedia.ImportAndProcess",
            label:
                "Import and Process",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 24,
                    y: 525,
                    width: 150,
                    height: 36
                )
        ),
        contract(
            fixtureID:
                "recording-ready-light",
            identifier:
                "BlueMinutes.Recording.StartVisible",
            label:
                "Start Visible Recording",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 560,
                    y: 553,
                    width: 180,
                    height: 34
                )
        ),
        contract(
            fixtureID:
                "recording-ready-dark",
            identifier:
                "BlueMinutes.Recording.StartVisible",
            label:
                "Start Visible Recording",
            region:
                BlueMinutesVisualPixelRegion(
                    x: 560,
                    y: 553,
                    width: 180,
                    height: 34
                )
        )
    ]

    static func matching(
        fixtureID: String
    ) -> [
        BlueMinutesVisualNativeActionContract
    ] {
        all.filter {
            $0.fixtureID == fixtureID
        }
    }

    private static func contract(
        fixtureID: String,
        identifier: String,
        label: String,
        region:
            BlueMinutesVisualPixelRegion
    ) -> BlueMinutesVisualNativeActionContract {
        BlueMinutesVisualNativeActionContract(
            fixtureID: fixtureID,
            accessibilityIdentifier:
                identifier,
            accessibilityLabel: label,
            region: region
        )
    }
}

struct BlueMinutesVisualFixtureCase:
    Identifiable,
    Sendable
{
    let descriptor:
        BlueMinutesVisualCaptureDescriptor

    var id: String {
        descriptor.id
    }

    var surface:
        BlueMinutesVisualFixtureSurface
    {
        BlueMinutesVisualFixtureSurface(
            rawValue:
                descriptor.surface
        )!
    }

    static let all:
        [BlueMinutesVisualFixtureCase] =
        shellCases + surfaceCases

    static let manualSystemCases:
        [BlueMinutesVisualCaptureDescriptor] = [
            descriptor(
                id:
                    "transcript-incomplete-reduce-transparency",
                surface: .transcript,
                state: "incomplete",
                appearance: .dark,
                accessibility:
                    BlueMinutesVisualAccessibility(
                        increaseContrast: false,
                        reduceTransparency: true,
                        differentiateWithoutColor:
                            false,
                        reduceMotion: false,
                        largerText: false
                    ),
                inspectorPresented: false
            ),
            descriptor(
                id:
                    "analysis-stale-differentiate-without-color",
                surface: .analysis,
                state: "stale",
                appearance: .light,
                accessibility:
                    BlueMinutesVisualAccessibility(
                        increaseContrast: false,
                        reduceTransparency: false,
                        differentiateWithoutColor:
                            true,
                        reduceMotion: false,
                        largerText: false
                    ),
                inspectorPresented: true
            ),
            descriptor(
                id:
                    "recording-active-reduce-motion",
                surface: .recording,
                state: "active",
                appearance: .dark,
                accessibility:
                    BlueMinutesVisualAccessibility(
                        increaseContrast: false,
                        reduceTransparency: false,
                        differentiateWithoutColor:
                            false,
                        reduceMotion: true,
                        largerText: false
                    ),
                inspectorPresented: false
            )
        ]

    private static let shellCases:
        [BlueMinutesVisualFixtureCase] =
        [
            BlueMinutesVisualViewport(
                width: 860,
                height: 600
            ),
            BlueMinutesVisualViewport(
                width: 1_080,
                height: 720
            ),
            BlueMinutesVisualViewport(
                width: 1_440,
                height: 1_024
            ),
            BlueMinutesVisualViewport(
                width: 1_728,
                height: 1_024
            )
        ]
        .flatMap { viewport in
            BlueMinutesVisualAppearance
                .allCases.map {
                    appearance in
                    fixture(
                        descriptor(
                            id:
                                "shell-\(viewport.width)x\(viewport.height)-\(appearance.rawValue)",
                            surface: .shell,
                            state:
                                "workspace-ready",
                            viewport:
                                viewport,
                            appearance:
                                appearance,
                            accessibility:
                                .standard,
                            inspectorPresented:
                                false
                        )
                    )
                }
        }

    private static let surfaceCases:
        [BlueMinutesVisualFixtureCase] =
        ([
            (.onboarding, "empty", false),
            (.localMedia, "ready", false),
            (.localMedia, "working", false),
            (.recording, "ready", false),
            (.recording, "loading", false),
            (.recording, "active", false),
            (.unWebTV, "blocked", false),
            (.unWebTV, "candidate", false),
            (.transcript, "selected", true),
            (.transcript, "incomplete", false),
            (.analysis, "selected", true),
            (.analysis, "stale", true),
            (.briefing, "selected", false),
            (
                .briefing,
                "export-blocked",
                false
            ),
            (.history, "empty", false),
            (.history, "results", false),
            (.storage, "healthy", false),
            (
                .storage,
                "destructive-disabled",
                false
            ),
            (.storage, "failure", false),
            (.settings, "general", false),
            (.settings, "appearance", false)
        ] as [
            (
                BlueMinutesVisualFixtureSurface,
                String,
                Bool
            )
        ])
        .flatMap {
            surface,
            state,
            inspectorPresented in
            BlueMinutesVisualAppearance
                .allCases.map {
                    appearance in
                    fixture(
                        descriptor(
                            id:
                                "\(surface.rawValue)-\(state)-\(appearance.rawValue)",
                            surface: surface,
                            state: state,
                            appearance:
                                appearance,
                            accessibility:
                                accessibility(
                                    surface:
                                        surface,
                                    state: state,
                                    appearance:
                                        appearance
                                ),
                            inspectorPresented:
                                inspectorPresented
                        )
                    )
                }
        }

    private static func fixture(
        _ descriptor:
            BlueMinutesVisualCaptureDescriptor
    ) -> BlueMinutesVisualFixtureCase {
        BlueMinutesVisualFixtureCase(
            descriptor: descriptor
        )
    }

    private static func descriptor(
        id: String,
        surface:
            BlueMinutesVisualFixtureSurface,
        state: String,
        viewport:
            BlueMinutesVisualViewport =
            BlueMinutesVisualViewport(
                width: 1_440,
                height: 1_024
            ),
        appearance:
            BlueMinutesVisualAppearance,
        accessibility:
            BlueMinutesVisualAccessibility,
        inspectorPresented: Bool
    ) -> BlueMinutesVisualCaptureDescriptor {
        BlueMinutesVisualCaptureDescriptor(
            id: id,
            surface: surface.rawValue,
            state: state,
            viewport: viewport,
            appearance: appearance,
            accessibility:
                accessibility,
            locale: "en_US_POSIX",
            timeZone: "UTC",
            accent: "systemBlue",
            textSize:
                accessibility.largerText
                ? "accessibility2"
                : "large",
            inspectorPresented:
                inspectorPresented
        )
    }

    private static func accessibility(
        surface:
            BlueMinutesVisualFixtureSurface,
        state: String,
        appearance:
            BlueMinutesVisualAppearance
    ) -> BlueMinutesVisualAccessibility {
        if surface == .transcript,
           state == "selected",
           appearance == .dark
        {
            return BlueMinutesVisualAccessibility(
                increaseContrast: true,
                reduceTransparency: false,
                differentiateWithoutColor:
                    false,
                reduceMotion: false,
                largerText: false
            )
        }
        if surface == .history,
           state == "results",
           appearance == .light
        {
            return BlueMinutesVisualAccessibility(
                increaseContrast: false,
                reduceTransparency: false,
                differentiateWithoutColor:
                    false,
                reduceMotion: false,
                largerText: true
            )
        }
        if surface == .storage,
           state == "destructive-disabled",
           appearance == .dark
        {
            return BlueMinutesVisualAccessibility(
                increaseContrast: true,
                reduceTransparency: false,
                differentiateWithoutColor:
                    false,
                reduceMotion: false,
                largerText: true
            )
        }
        return .standard
    }
}

extension BlueMinutesVisualAppearance {
    static let allCases:
        [BlueMinutesVisualAppearance] = [
            .light,
            .dark
        ]
}
