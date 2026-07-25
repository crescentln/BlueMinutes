import Foundation
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct MeetingBuddyRootViewStructureTests {
    @Test
    func mediaReviewSectionsRemainTheAcceptedEightCases() {
        let sections: [MediaReviewSection] = [
            .intake,
            .recording,
            .webMetadata,
            .transcript,
            .analysis,
            .briefing,
            .history,
            .storage
        ]

        #expect(
            sections.map(sectionIdentifier) == [
                "intake",
                "recording",
                "web_metadata",
                "transcript",
                "analysis",
                "briefing",
                "history",
                "storage"
            ]
        )
    }

    @Test
    func defaultRootViewKeepsExistingNavigationAndNoResearchSurface() throws {
        let rootView = try source(
            "Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift"
        )

        #expect(
            taggedSections(in: rootView) == [
                "intake",
                "recording",
                "webMetadata",
                "transcript",
                "analysis",
                "briefing",
                "history",
                "storage"
            ]
        )
        for label in [
            "Local Media",
            "Record Audio",
            "UN Web TV Metadata",
            "Transcript Review",
            "Analysis Review",
            "Briefing",
            "Meeting History",
            "Storage"
        ] {
            #expect(rootView.contains("title: \"\(label)\""))
        }
        #expect(
            rootView.components(
                separatedBy: "WorkspaceSidebarRow("
            ).count - 1 == 9
        )
        for titleCase in [
            "case .recording: \"Record Audio\"",
            "case .webMetadata: \"UN Web TV Metadata\"",
            "case .transcript: \"Transcript Review\"",
            "case .analysis: \"Analysis Review\"",
            "case .briefing: \"Briefing\"",
            "case .history: \"Meeting History\"",
            "case .storage: \"Storage\"",
            "case .intake, nil: \"Local Media Intake\""
        ] {
            #expect(rootView.contains(titleCase))
        }
        #expect(rootView.contains("store: MediaReviewStore,"))
        #expect(!rootView.contains("AppCapabilities"))
        for forbiddenVisibleSurface in [
            "Label(\"Research",
            "Text(\"Research",
            "Button(\"Research",
            ".navigationTitle(\"Research",
            "Label(\"Conversation",
            "Text(\"Conversation",
            "Button(\"Conversation",
            ".navigationTitle(\"Conversation"
        ] {
            #expect(!rootView.contains(forbiddenVisibleSurface))
        }
    }

    @Test
    func singletonWindowKeepsServicesAppOwnedAndDraftsSceneOwned() throws {
        let app = try source(
            "Sources/MeetingBuddyApp/MeetingBuddyApp.swift"
        )
        let root = try source(
            "Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift"
        )
        let store = try source(
            "Sources/MeetingBuddyFeatures/Stores/MediaReviewStore.swift"
        )
        let sceneState = try source(
            "Sources/MeetingBuddyFeatures/Models/MediaReviewSceneState.swift"
        )

        #expect(app.contains("@State private var store: MediaReviewStore"))
        #expect(app.contains("Window(\"BlueMinutes\", id: \"main\")"))
        #expect(!app.contains("WindowGroup"))
        #expect(app.contains("MainWindowResolver { window in"))
        #expect(app.contains("installCloseGuard(on: window)"))
        #expect(app.contains("func windowShouldClose(_ sender: NSWindow)"))
        #expect(app.contains("guard shouldClose(sender) else"))
        #expect(app.contains("window?.performClose(nil)"))
        #expect(app.contains("forwardingTarget(for selector: Selector!)"))
        #expect(
            app.contains(
                "var terminationSceneState: MediaReviewSceneState?"
            )
        )
        #expect(app.contains("onSceneStateAvailable: { sceneState in"))
        #expect(root.contains("@Bindable private var store: MediaReviewStore"))
        #expect(!root.contains("@State private var store: MediaReviewStore"))
        #expect(root.contains("@State private var sceneState: MediaReviewSceneState"))
        #expect(
            root.contains(
                ".disabled(sceneState.isInteractionLocked || store.isWorking)"
            )
        )
        #expect(root.contains("List(selection: sectionSelection)"))
        #expect(
            root.components(
                separatedBy: "sceneState.isDestinationAvailable("
            ).count - 1 == 3
        )
        #expect(!root.contains("$store.selectedSection"))
        #expect(!store.contains("public var selectedSection"))
        #expect(sceneState.contains("public var selectedSection"))
        #expect(!sceneState.contains("@AppStorage"))
        #expect(!sceneState.contains("@SceneStorage"))
    }

    @Test
    func dirtyNavigationAndApplicationTerminationWireEveryResolution() throws {
        let app = try source(
            "Sources/MeetingBuddyApp/MeetingBuddyApp.swift"
        )
        let root = try source(
            "Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift"
        )

        for requiredRootAction in [
            "Button(\"Save and Continue\")",
            "sceneState.beginPendingNavigationSave()",
            "sceneState.resolvePendingNavigationSave(",
            "sceneState.requestMediaImport()",
            "case .importPendingMedia:",
            "Button(\"Discard Changes\", role: .destructive)",
            "sceneState.discardChangesAndResolvePending()",
            "Button(\"Keep Editing\", role: .cancel)",
            "sceneState.cancelPendingNavigation()"
        ] {
            #expect(root.contains(requiredRootAction))
        }
        for requiredTerminationAction in [
            "sceneState.applicationTerminationRequirement",
            "case .operationInFlight:",
            "case .unsavedEditorChanges:",
            "Save and Quit",
            "Discard and Quit",
            "Keep Editing",
            "store.saveAllEditorDrafts(in: sceneState)",
            "sceneState.discardAllEditorChanges()",
            "return .terminateCancel"
        ] {
            #expect(app.contains(requiredTerminationAction))
        }
    }

    private func sectionIdentifier(_ section: MediaReviewSection) -> String {
        switch section {
        case .intake:
            "intake"
        case .recording:
            "recording"
        case .webMetadata:
            "web_metadata"
        case .transcript:
            "transcript"
        case .analysis:
            "analysis"
        case .briefing:
            "briefing"
        case .history:
            "history"
        case .storage:
            "storage"
        }
    }

    private func taggedSections(in source: String) -> [String] {
        let prefix = ".tag(MediaReviewSection."
        return source.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(")") else {
                return nil
            }
            return String(trimmed.dropFirst(prefix.count).dropLast())
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
