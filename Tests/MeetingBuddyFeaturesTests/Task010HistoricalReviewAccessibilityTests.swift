import Foundation
import Testing

@Suite
struct Task010HistoricalReviewAccessibilityTests {
    @Test
    func historyAndPreferenceControlsKeepQualificationsAndAssistiveLabelsVisible() throws {
        let root = try source("MeetingBuddyRootView.swift")
        #expect(root.contains("Label(\"Meeting History\""))
        #expect(root.contains("case .history: \"Meeting History\""))

        let history = try source("HistoricalReviewView.swift")
        #expect(history.contains("GroupBox(\"Historical Context Search\")"))
        #expect(history.contains("GroupBox(\"Learned Preferences\")"))
        #expect(history.contains("Unauthorized records are not included in content, counts, or facets."))
        #expect(history.contains("Wording differences, silence, and group membership never establish a policy change."))
        #expect(history.contains("Confirm Possible Change…"))
        #expect(history.contains("superseding user-confirmed comparison"))
        #expect(history.contains("Button(\"Reset All…\", role: .destructive)"))
        #expect(history.contains("Disabled preferences remain visible and editable"))
        #expect(history.contains("DisclosureGroup(\"Recent Preference Audit\")"))
        #expect(history.contains("never deleted raw preference values"))
        #expect(history.contains(".accessibilityLabel(\"Meeting History local index\")"))
        #expect(history.contains(".accessibilityLabel(\"Learned preference value\")"))
        #expect(history.contains("Position effective time:"))
    }

    private func source(_ fileName: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository
                .appendingPathComponent("Sources/MeetingBuddyFeatures/Views")
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }
}
