import MeetingBuddyFeatures
import SwiftUI

@main
@MainActor
struct MeetingBuddyDesktopApp: App {
    @State private var store: MediaReviewStore

    init() {
        let workflow = AppMediaReviewWorkflow()
        _store = State(initialValue: MediaReviewStore(workflow: workflow))
    }

    var body: some Scene {
        WindowGroup {
            MeetingBuddyRootView(store: store)
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            SidebarCommands()
        }
    }
}
