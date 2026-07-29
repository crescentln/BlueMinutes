import AppKit
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyFeatures
import MeetingBuddyPersistence
import SwiftUI

private let windowingDiagnostics =
    BlueMinutesUnifiedDiagnosticLogger(
        category: .windowing
    )

@main
@MainActor
struct MeetingBuddyDesktopApp: App {
    @NSApplicationDelegateAdaptor(MeetingBuddyApplicationDelegate.self)
    private var applicationDelegate
    @State private var store: MediaReviewStore
    @State private var codexStore: CodexConnectionStore
    @State private var intelligenceStore:
        IntelligenceConfigurationStore
    @State private var selectedSettingsTab:
        BlueMinutesSettingsTab = .general

    init() {
        windowingDiagnostics.record(
            .applicationStarted
        )
        let capabilities = AppCapabilities()
        let intelligenceFile =
            FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/BlueMinutes/Intelligence/configuration-v1.json",
                isDirectory: false
            )
        let intelligenceRepository:
            any IntelligenceConfigurationRepository =
            (try? LocalIntelligenceConfigurationRepository(
                fileURL: intelligenceFile
            ))
                ?? UnavailableIntelligenceRepository()
        let secretStore = MacOSKeychainSecretStore()
        let workflow = AppMediaReviewWorkflow(
            capabilities: capabilities,
            intelligenceRepository:
                intelligenceRepository,
            secretStore: secretStore
        )
        _store = State(
            initialValue:
                MediaReviewStore(workflow: workflow)
        )
        let codexService = CodexMeetingSessionService(
            storageRootURL:
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(
                        "Library/Application Support/BlueMinutes/CodexRuntime",
                        isDirectory: true
                    )
        )
        _codexStore = State(
            initialValue: CodexConnectionStore(
                service: codexService
            )
        )
        let localSpeechModelManager:
            any LocalSpeechModelManaging
        if #available(macOS 26.0, *) {
            localSpeechModelManager =
                AppleLocalSpeechModelManager()
        } else {
            localSpeechModelManager =
                UnavailableLocalSpeechModelManager()
        }
        _intelligenceStore = State(
            initialValue: IntelligenceConfigurationStore(
                repository: intelligenceRepository,
                secretStore: secretStore,
                connectionTester:
                    OpenAIProviderConnectionTester(),
                localModelManager:
                    localSpeechModelManager
            )
        )
    }

    var body: some Scene {
        Window("BlueMinutes", id: "main") {
            BlueMinutesPresentationRoot {
                MeetingBuddyRootView(
                    store: store,
                    codexStore: codexStore,
                    intelligenceStore:
                        intelligenceStore,
                    selectedSettingsTab:
                        $selectedSettingsTab,
                    onSceneStateAvailable: { sceneState in
                        applicationDelegate.store = store
                        applicationDelegate.codexStore =
                            codexStore
                        applicationDelegate.terminationSceneState = sceneState
                    }
                )
            }
            .background(
                MainWindowResolver { window in
                    applicationDelegate.installCloseGuard(on: window)
                }
            )
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            SidebarCommands()
            BlueMinutesShellCommands()
            BlueMinutesTranscriptCommands()
            BlueMinutesAboutCommands()
        }

        Settings {
            BlueMinutesPresentationRoot {
                BlueMinutesSettingsView(
                    store: store,
                    codexStore: codexStore,
                    intelligenceStore:
                        intelligenceStore,
                    selectedTab:
                        $selectedSettingsTab
                )
            }
        }

        Window(
            "About BlueMinutes",
            id: "about"
        ) {
            BlueMinutesPresentationRoot {
                BlueMinutesAboutView()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            BlueMinutesMenuBarView(
                store: store
            )
        } label: {
            Label(
                store.recordingIndicatorIsVisible
                    ? "BlueMinutes Recording"
                    : "BlueMinutes",
                systemImage:
                    store.recordingIndicatorIsVisible
                    ? "record.circle.fill"
                    : "b.circle"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct BlueMinutesMenuBarView:
    View
{
    @Bindable var store:
        MediaReviewStore
    @Environment(\.openWindow)
    private var openWindow

    var body: some View {
        if let recording =
                store.recordingSession,
           store.recordingIndicatorIsVisible
        {
            Text(
                recording.state
                    == .recording
                ? "Recording"
                : recording.state
                    .rawValue
            )
            Text(
                "Inputs: "
                    + recording
                    .activeTrackKinds
                    .map(trackLabel)
                    .joined(
                        separator: ", "
                    )
            )
            if let duration =
                    recording
                    .durableThroughNanoseconds
            {
                Text(
                    "Durable audio: "
                        + durationLabel(
                            duration
                        )
                )
            } else {
                Text(
                    "Durable audio: waiting for the first sealed interval"
                )
            }
            Divider()
            Button(
                "Open Current Meeting"
            ) {
                openMainWindow()
            }
            Button("About BlueMinutes") {
                openAboutWindow()
            }
            Button(
                "Stop and Finalize"
            ) {
                Task {
                    await store
                        .stopRecording()
                }
            }
            .disabled(
                store
                    .isStoppingRecording
                    || !recording.canStop
            )
        } else {
            Text(
                "No active recording"
            )
            Button("Open BlueMinutes") {
                openMainWindow()
            }
            Button("About BlueMinutes") {
                openAboutWindow()
            }
        }
        Divider()
        Button("Quit BlueMinutes") {
            windowingDiagnostics.record(
                .applicationQuitRequested
            )
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMainWindow() {
        windowingDiagnostics.record(
            .mainWindowOpenRequested
        )
        openWindow(id: "main")
        NSApp.activate(
            ignoringOtherApps: true
        )
    }

    private func openAboutWindow() {
        windowingDiagnostics.record(
            .aboutWindowOpenRequested
        )
        openWindow(id: "about")
        NSApp.activate(
            ignoringOtherApps: true
        )
    }

    private func trackLabel(
        _ kind: CaptureTrackKind
    ) -> String {
        switch kind {
        case .microphone:
            "Microphone"
        case .applicationAudio:
            "Application"
        }
    }

    private func durationLabel(
        _ nanoseconds: UInt64
    ) -> String {
        let totalSeconds =
            nanoseconds
            / 1_000_000_000
        let hours =
            totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600)
            / 60
        let seconds =
            totalSeconds % 60
        if hours > 0 {
            return String(
                format:
                    "%02llu:%02llu:%02llu",
                hours,
                minutes,
                seconds
            )
        }
        return String(
            format:
                "%02llu:%02llu",
            minutes,
            seconds
        )
    }
}

private struct BlueMinutesAboutCommands:
    Commands
{
    @Environment(\.openWindow)
    private var openWindow

    var body: some Commands {
        CommandGroup(
            replacing: .appInfo
        ) {
            Button("About BlueMinutes") {
                windowingDiagnostics.record(
                    .aboutWindowOpenRequested
                )
                openWindow(id: "about")
                NSApp.activate(
                    ignoringOtherApps:
                        true
                )
            }
        }
    }
}

private struct BlueMinutesAboutView:
    View
{
    @State private var diagnosticsCopied =
        false
    private let release =
        ReleaseIntegrationConfiguration
        .publicBeta

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            HStack(spacing: 18) {
                Image(
                    nsImage:
                        NSApp
                        .applicationIconImage
                )
                .resizable()
                .frame(
                    width: 88,
                    height: 88
                )
                .accessibilityLabel(
                    "BlueMinutes app icon"
                )
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text("BlueMinutes")
                        .font(.title.bold())
                    Text(versionLabel)
                        .foregroundStyle(
                            .secondary
                        )
                    Text(
                        "Local-first meeting audio, transcript review, and evidence-linked intelligence."
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }
            Divider()
            Grid(
                alignment: .leading,
                horizontalSpacing: 18,
                verticalSpacing: 8
            ) {
                GridRow {
                    Text("Product access")
                    Text(
                        release.billing
                            .keepsProductFeaturesUnlocked
                        ? "Unlocked · billing disabled"
                        : "Build configuration required"
                    )
                }
                GridRow {
                    Text("Website")
                    Text(
                        release.website.mode
                            == .disconnected
                        ? "Disconnected · typed handoff reserved"
                        : release.website.mode
                            .rawValue
                    )
                }
                GridRow {
                    Text("Updates")
                    Text(
                        release.update.mode
                            == .unconfigured
                        ? "Not configured for this development build"
                        : release.update.mode
                            .rawValue
                    )
                }
            }
            Text(
                "BlueMinutes does not contact the separate website, billing, licensing, or update service from this build. Connecting those interfaces requires a separately approved release configuration."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            HStack {
                Button(
                    "Copy Sanitized Diagnostics"
                ) {
                    copySanitizedDiagnostics()
                }
                .disabled(
                    diagnosticsReport == nil
                )
                .accessibilityIdentifier(
                    "BlueMinutes.About.CopyDiagnostics"
                )
                if diagnosticsCopied {
                    Label(
                        "Copied",
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private var versionLabel: String {
        "Version \(appVersion) (\(buildVersion))"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String
            ?? "Development"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?[
            "CFBundleVersion"
        ] as? String
            ?? "local"
    }

    private var diagnosticsReport:
        SanitizedDiagnosticsReport?
    {
        try? SanitizedDiagnosticsReport(
            productName: "BlueMinutes",
            appVersion: appVersion,
            buildVersion: buildVersion,
            operatingSystem:
                ProcessInfo.processInfo
                .operatingSystemVersionString,
            architecture:
                architectureLabel,
            releaseConfiguration: release,
            telemetryMode: .disabled
        )
    }

    private var architectureLabel: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private func copySanitizedDiagnostics() {
        guard let diagnosticsReport else {
            diagnosticsCopied = false
            return
        }
        let pasteboard =
            NSPasteboard.general
        pasteboard.clearContents()
        diagnosticsCopied =
            pasteboard.setString(
                diagnosticsReport
                    .renderedText,
                forType: .string
            )
        if diagnosticsCopied {
            windowingDiagnostics.record(
                .sanitizedDiagnosticsCopied
            )
        }
    }
}

private struct UnavailableIntelligenceRepository:
    IntelligenceConfigurationRepository
{
    func load() throws -> IntelligenceConfigurationState {
        throw IntelligenceConfigurationError
            .persistenceUnavailable
    }

    func save(
        _ state: IntelligenceConfigurationState,
        expectedRevision: UInt64
    ) throws {
        throw IntelligenceConfigurationError
            .persistenceUnavailable
    }
}

@MainActor
private final class MeetingBuddyApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: MediaReviewStore?
    weak var codexStore: CodexConnectionStore?
    // Retain the singleton Window's scene-local state in this lifecycle bridge
    // so last-window termination cannot erase a draft before negotiation.
    var terminationSceneState: MediaReviewSceneState?
    private var terminationTask: Task<Void, Never>?
    private var windowCloseTask: Task<Void, Never>?
    private var windowDelegateProxy: MainWindowDelegateProxy?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowingDiagnostics.record(
            .applicationTerminationRequested
        )
        guard terminationTask == nil else {
            windowingDiagnostics.record(
                .applicationTerminationDeferred
            )
            return .terminateLater
        }
        let reply: NSApplication.TerminateReply
        if let store,
           store.recordingIndicatorIsVisible
        {
            reply =
                beginRecordingTermination(
                    sender,
                    store: store
                )
        } else if let store {
            reply =
                beginEditorTerminationIfNeeded(
                    sender,
                    store: store
                )
        } else {
            reply = .terminateNow
        }

        let finalReply =
            deferForCodexCleanupIfNeeded(
                sender,
                after: reply
            )
        recordTerminationReply(finalReply)
        return finalReply
    }

    func installCloseGuard(on window: NSWindow) {
        if let windowDelegateProxy,
           windowDelegateProxy.window === window
        {
            if window.delegate !== windowDelegateProxy {
                windowDelegateProxy.downstream = window.delegate
                window.delegate = windowDelegateProxy
            }
            return
        }

        let proxy = MainWindowDelegateProxy(
            window: window,
            downstream: window.delegate,
            shouldClose: { [weak self] window in
                self?.shouldCloseMainWindow(window) ?? true
            }
        )
        windowDelegateProxy = proxy
        window.delegate = proxy
        windowingDiagnostics.record(
            .mainWindowResolved
        )
    }

    private func shouldCloseMainWindow(_ window: NSWindow) -> Bool {
        windowingDiagnostics.record(
            .mainWindowCloseRequested
        )
        guard windowCloseTask == nil else {
            windowingDiagnostics.record(
                .mainWindowCloseBlocked
            )
            return false
        }
        guard let store else {
            windowingDiagnostics.record(
                .mainWindowCloseAllowed
            )
            return true
        }
        guard let sceneState = terminationSceneState else {
            windowingDiagnostics.record(
                .mainWindowCloseAllowed
            )
            return true
        }

        switch sceneState.applicationTerminationRequirement {
        case .operationInFlight:
            showEditorOperationInFlightAlert()
            windowingDiagnostics.record(
                .mainWindowCloseBlocked
            )
            return false
        case .none:
            windowingDiagnostics.record(
                .mainWindowCloseAllowed
            )
            return true
        case .unsavedEditorChanges:
            break
        }

        switch editorTerminationChoice() {
        case .save:
            windowCloseTask = Task {
                @MainActor [weak self, weak window] in
                guard let self else { return }
                let saved = await store.saveAllEditorDrafts(in: sceneState)
                if !saved {
                    showEditorSaveFailureAlert()
                }
                windowCloseTask = nil
                if saved {
                    window?.performClose(nil)
                }
            }
            windowingDiagnostics.record(
                .mainWindowCloseBlocked
            )
            return false
        case .discard:
            sceneState.discardAllEditorChanges()
            windowingDiagnostics.record(
                .mainWindowCloseAllowed
            )
            return true
        case .cancel:
            windowingDiagnostics.record(
                .mainWindowCloseBlocked
            )
            return false
        }
    }

    private func beginRecordingTermination(
        _ sender: NSApplication,
        store: MediaReviewStore
    ) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Finish the visible recording before quitting?"
        alert.informativeText = "BlueMinutes will stop packet admission, seal verified local audio, and finish or retain an explicit incomplete result before it quits. Force-quitting may leave the session for restart recovery."
        alert.addButton(withTitle: "Stop, Finalize, and Quit")
        alert.addButton(withTitle: "Keep Recording")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        let sceneState = terminationSceneState
        terminationTask = Task {
            @MainActor [weak self, weak sender] in
            guard let self else { return }
            if store.recordingSession?.canStop == true {
                await store.stopRecording()
            }
            for _ in 0..<200 where store.recordingIndicatorIsVisible {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !store.recordingIndicatorIsVisible else {
                let failure = NSAlert()
                failure.alertStyle = .critical
                failure.messageText = "Recording finalization is not finished"
                failure.informativeText = "BlueMinutes remains open so retained local audio is not silently abandoned. Stop or finish the recording from the visible recording controls, then quit again."
                failure.runModal()
                await finishTermination(
                    sender,
                    permitted: false
                )
                return
            }

            let mayTerminate = await resolveDirtyDraftsAfterRecording(
                store: store,
                sceneState: sceneState
            )
            await finishTermination(
                sender,
                permitted: mayTerminate
            )
        }
        return .terminateLater
    }

    private func beginEditorTerminationIfNeeded(
        _ sender: NSApplication,
        store: MediaReviewStore
    ) -> NSApplication.TerminateReply {
        guard let sceneState = terminationSceneState else {
            return .terminateNow
        }
        switch sceneState.applicationTerminationRequirement {
        case .operationInFlight:
            showEditorOperationInFlightAlert()
            return .terminateCancel
        case .none:
            return .terminateNow
        case .unsavedEditorChanges:
            break
        }

        switch editorTerminationChoice() {
        case .save:
            terminationTask = Task {
                @MainActor [weak self, weak sender] in
                guard let self else { return }
                let saved = await store.saveAllEditorDrafts(in: sceneState)
                if !saved {
                    showEditorSaveFailureAlert()
                }
                await finishTermination(
                    sender,
                    permitted: saved
                )
            }
            return .terminateLater
        case .discard:
            sceneState.discardAllEditorChanges()
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    private func resolveDirtyDraftsAfterRecording(
        store: MediaReviewStore,
        sceneState: MediaReviewSceneState?
    ) async -> Bool {
        guard let sceneState else {
            return true
        }
        switch sceneState.applicationTerminationRequirement {
        case .operationInFlight:
            showEditorOperationInFlightAlert()
            return false
        case .none:
            return true
        case .unsavedEditorChanges:
            break
        }

        switch editorTerminationChoice() {
        case .save:
            let saved = await store.saveAllEditorDrafts(in: sceneState)
            if !saved {
                showEditorSaveFailureAlert()
            }
            return saved
        case .discard:
            sceneState.discardAllEditorChanges()
            return true
        case .cancel:
            return false
        }
    }

    private func editorTerminationChoice() -> EditorTerminationChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save editor changes before quitting?"
        alert.informativeText = "Transcript, Analysis, or Briefing drafts are still unpublished. Save them through their existing local actions, discard them, or keep editing."
        alert.addButton(withTitle: "Save and Quit")
        alert.addButton(withTitle: "Discard and Quit")
        alert.addButton(withTitle: "Keep Editing")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func showEditorOperationInFlightAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "An editor operation is still in progress"
        alert.informativeText = "BlueMinutes remains open until the current save or workspace change finishes. Quit again after the visible operation completes."
        alert.runModal()
    }

    private func showEditorSaveFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Editor changes were not saved"
        alert.informativeText = "BlueMinutes remains open with the draft retained. Review the visible error and source revision, then save or discard the draft before quitting."
        alert.runModal()
    }

    private func deferForCodexCleanupIfNeeded(
        _ sender: NSApplication,
        after reply:
            NSApplication.TerminateReply
    ) -> NSApplication.TerminateReply {
        guard reply == .terminateNow,
              codexStore?
                .requiresTerminationCleanup
                == true
        else {
            return reply
        }
        terminationTask = Task {
            @MainActor [weak self, weak sender] in
            guard let self else { return }
            await finishTermination(
                sender,
                permitted: true
            )
        }
        return .terminateLater
    }

    private func finishTermination(
        _ sender: NSApplication?,
        permitted: Bool
    ) async {
        var finalPermission = permitted
        if permitted,
           let codexStore,
           codexStore.requiresTerminationCleanup
        {
            finalPermission =
                await codexStore
                .shutdownForApplicationTermination()
            if !finalPermission {
                showCodexShutdownFailureAlert()
            }
        }
        terminationTask = nil
        windowingDiagnostics.record(
            finalPermission
                ? .applicationTerminationAllowed
                : .applicationTerminationCancelled
        )
        sender?.reply(
            toApplicationShouldTerminate:
                finalPermission
        )
    }

    private func showCodexShutdownFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText =
            "Codex is still shutting down"
        alert.informativeText =
            "BlueMinutes remains open because the isolated Codex process did not confirm its exit. Disconnect Codex and try quitting again."
        alert.runModal()
    }

    private func recordTerminationReply(
        _ reply:
            NSApplication.TerminateReply
    ) {
        switch reply {
        case .terminateNow:
            windowingDiagnostics.record(
                .applicationTerminationAllowed
            )
        case .terminateCancel:
            windowingDiagnostics.record(
                .applicationTerminationCancelled
            )
        case .terminateLater:
            windowingDiagnostics.record(
                .applicationTerminationDeferred
            )
        @unknown default:
            windowingDiagnostics.record(
                .applicationTerminationCancelled
            )
        }
    }
}

private enum EditorTerminationChoice {
    case save
    case discard
    case cancel
}

@MainActor
private final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    // AppKit dispatches window-delegate messages on the main thread, while
    // NSObject's Objective-C forwarding overrides are nonisolated in Swift.
    nonisolated(unsafe) weak var downstream: (any NSWindowDelegate)?
    private let shouldClose: @MainActor (NSWindow) -> Bool

    init(
        window: NSWindow,
        downstream: (any NSWindowDelegate)?,
        shouldClose: @escaping @MainActor (NSWindow) -> Bool
    ) {
        self.window = window
        self.downstream = downstream
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose(sender) else {
            return false
        }
        return downstream?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        selector == #selector(NSWindowDelegate.windowShouldClose(_:))
            || super.responds(to: selector)
            || downstream?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if downstream?.responds(to: selector) == true {
            return downstream
        }
        return super.forwardingTarget(for: selector)
    }
}

private struct MainWindowResolver: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    init(onResolve: @escaping @MainActor (NSWindow) -> Void) {
        self.onResolve = onResolve
    }

    func makeNSView(context _: Context) -> MainWindowResolverView {
        MainWindowResolverView(onResolve: onResolve)
    }

    func updateNSView(
        _ view: MainWindowResolverView,
        context _: Context
    ) {
        view.onResolve = onResolve
        view.resolveWindow()
    }
}

@MainActor
private final class MainWindowResolverView: NSView {
    var onResolve: @MainActor (NSWindow) -> Void

    init(onResolve: @escaping @MainActor (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindow()
    }

    func resolveWindow() {
        if let window {
            onResolve(window)
        }
    }
}
