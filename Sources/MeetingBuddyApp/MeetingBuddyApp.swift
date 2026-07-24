import AppKit
import MeetingBuddyApplication
import MeetingBuddyFeatures
import SwiftUI

@main
@MainActor
struct MeetingBuddyDesktopApp: App {
    @NSApplicationDelegateAdaptor(MeetingBuddyApplicationDelegate.self)
    private var applicationDelegate
    @State private var store: MediaReviewStore

    init() {
        let capabilities = AppCapabilities()
        let workflow = AppMediaReviewWorkflow(capabilities: capabilities)
        _store = State(initialValue: MediaReviewStore(workflow: workflow))
    }

    var body: some Scene {
        Window("BlueMinutes", id: "main") {
            MeetingBuddyRootView(
                store: store,
                onSceneStateAvailable: { sceneState in
                    applicationDelegate.store = store
                    applicationDelegate.terminationSceneState = sceneState
                }
            )
            .background(
                MainWindowResolver { window in
                    applicationDelegate.installCloseGuard(on: window)
                }
            )
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            SidebarCommands()
        }
    }
}

@MainActor
private final class MeetingBuddyApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: MediaReviewStore?
    // Retain the singleton Window's scene-local state in this lifecycle bridge
    // so last-window termination cannot erase a draft before negotiation.
    var terminationSceneState: MediaReviewSceneState?
    private var terminationTask: Task<Void, Never>?
    private var windowCloseTask: Task<Void, Never>?
    private var windowDelegateProxy: MainWindowDelegateProxy?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        guard let store else { return .terminateNow }

        if store.recordingIndicatorIsVisible {
            return beginRecordingTermination(sender, store: store)
        }
        return beginEditorTerminationIfNeeded(sender, store: store)
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
    }

    private func shouldCloseMainWindow(_ window: NSWindow) -> Bool {
        guard windowCloseTask == nil else { return false }
        guard let store else { return true }
        if store.recordingIndicatorIsVisible {
            NSApp.terminate(nil)
            return false
        }
        guard let sceneState = terminationSceneState else { return true }

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
            return false
        case .discard:
            sceneState.discardAllEditorChanges()
            return true
        case .cancel:
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
                finishTermination(sender, permitted: false)
                return
            }

            let mayTerminate = await resolveDirtyDraftsAfterRecording(
                store: store,
                sceneState: sceneState
            )
            finishTermination(sender, permitted: mayTerminate)
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
                finishTermination(sender, permitted: saved)
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

    private func finishTermination(
        _ sender: NSApplication?,
        permitted: Bool
    ) {
        terminationTask = nil
        sender?.reply(toApplicationShouldTerminate: permitted)
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
