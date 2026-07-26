import Foundation
import Testing

@Suite
struct Task010HistoricalReviewAccessibilityTests {
    @Test
    func historyAndPreferenceControlsKeepQualificationsAndAssistiveLabelsVisible() throws {
        let root = try source("MeetingBuddyRootView.swift")
        #expect(root.contains("title: \"Meeting History\""))
        #expect(root.contains("case .history: \"Meeting History\""))

        let history = try [
            source("HistoricalReviewView.swift"),
            source("HistoricalIndexSearchView.swift"),
            source("HistoricalResultsView.swift"),
            source("HistoricalComparisonView.swift")
        ].joined(separator: "\n")
        let preferences = try source(
            "LearnedPreferencesSettingsPane.swift"
        )

        #expect(history.contains("GroupBox(\"Historical Context Search\")"))
        #expect(history.contains("Unauthorized records are not included in content, counts, or facets."))
        #expect(history.contains("Wording differences, silence, and group membership never establish a policy change."))
        #expect(history.contains("Confirm Possible Change…"))
        #expect(history.contains("superseding user-confirmed comparison"))
        #expect(
            history.contains(
                "\"Meeting History local index\""
            )
        )
        #expect(history.contains("\"Position effective time\""))
        #expect(
            history.contains(
                "No history search has run"
            )
        )
        #expect(
            history.contains(
                "No Authorized History Results"
            )
        )
        #expect(
            history.contains(
                "Last successful results are not current"
            )
        )
        #expect(
            history.contains(
                "Run a successful search for the current filters"
            )
        )

        #expect(
            preferences.contains(
                "GroupBox(\"Learned Preferences\")"
            )
        )
        #expect(
            preferences.contains(
                "Button(\n                        \"Reset All…\""
            )
        )
        #expect(preferences.contains("Disabled preferences remain visible and editable"))
        #expect(preferences.contains("Recent Preference Audit"))
        #expect(preferences.contains("never deleted raw preference values"))
        #expect(preferences.contains(".accessibilityLabel(\n                    \"Learned preference value\""))
        #expect(preferences.contains("Presentation guidance only"))
        #expect(!preferences.contains("@AppStorage"))
        #expect(!history.contains("Learned Preferences"))
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
