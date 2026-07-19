import Foundation
import Testing

@Suite
struct Task007ViewAccessibilityTests {
    @Test
    func implementedVerticalSliceKeepsKeyboardAndAssistiveLabelsVisibleInSource() throws {
        let root = try source("MeetingBuddyRootView.swift")
        #expect(root.contains(".keyboardShortcut(\"o\", modifiers: .command)"))
        #expect(root.contains(".keyboardShortcut(\"i\", modifiers: .command)"))
        #expect(root.contains(".keyboardShortcut(.return, modifiers: .command)"))
        #expect(root.contains(".accessibilityLabel(\"Canonical audio progress\")"))
        #expect(root.contains(".accessibilityValue("))
        #expect(root.contains(".confirmationDialog("))
        #expect(root.contains("role: .destructive"))

        let storage = try source("StorageDashboardView.swift")
        #expect(storage.contains(".keyboardShortcut(\"r\", modifiers: [.command, .shift])"))
        #expect(storage.contains(".accessibilityLabel(\"Workspace storage usage by category\")"))
        #expect(storage.contains("Requires visible confirmation"))
        #expect(storage.contains("does not guarantee forensic erasure"))

        let briefing = try source("BriefingReviewView.swift")
        #expect(briefing.contains("This briefing is stale after an upstream correction"))
        #expect(briefing.contains(".accessibilityLabel(\"Stale briefing warning\")"))
        let analysis = try source("AnalysisReviewView.swift")
        #expect(analysis.contains("Stale after correction"))
        #expect(analysis.contains("No-outbound mode"))
        let transcript = try source("TranscriptReviewView.swift")
        #expect(transcript.contains("No-outbound mode"))
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
