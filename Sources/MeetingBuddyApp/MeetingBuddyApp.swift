import AppKit
import MeetingBuddyFeatures
import SwiftUI

@main
@MainActor
struct MeetingBuddyDesktopApp: App {
    @NSApplicationDelegateAdaptor(MeetingBuddyApplicationDelegate.self)
    private var applicationDelegate
    @State private var store: MediaReviewStore

    init() {
        let workflow = AppMediaReviewWorkflow()
        _store = State(initialValue: MediaReviewStore(workflow: workflow))
    }

    var body: some Scene {
        WindowGroup {
            MeetingBuddyRootView(store: store)
                .onAppear {
                    applicationDelegate.store = store
                }
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
    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.recordingIndicatorIsVisible else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Finish the visible recording before quitting?"
        alert.informativeText = "MeetingBuddy will stop packet admission, seal verified local audio, and finish or retain an explicit incomplete result before it quits. Force-quitting may leave the session for restart recovery."
        alert.addButton(withTitle: "Stop, Finalize, and Quit")
        alert.addButton(withTitle: "Keep Recording")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        terminationTask = Task { @MainActor [weak self, weak sender] in
            if store.recordingSession?.canStop == true {
                await store.stopRecording()
            }
            for _ in 0..<200 where store.recordingIndicatorIsVisible {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let mayTerminate = !store.recordingIndicatorIsVisible
            if !mayTerminate {
                let failure = NSAlert()
                failure.alertStyle = .critical
                failure.messageText = "Recording finalization is not finished"
                failure.informativeText = "MeetingBuddy remains open so retained local audio is not silently abandoned. Stop or finish the recording from the visible recording controls, then quit again."
                failure.runModal()
            }
            self?.terminationTask = nil
            sender?.reply(toApplicationShouldTerminate: mayTerminate)
        }
        return .terminateLater
    }
}
