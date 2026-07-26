import Foundation
import Testing

@Suite
struct Task007ViewAccessibilityTests {
    @Test
    func implementedVerticalSliceKeepsKeyboardAndAssistiveLabelsVisibleInSource() throws {
        let root = try source("MeetingBuddyRootView.swift")
        let localMedia = try source("LocalMediaIntakeView.swift")
        let shell = try source("BlueMinutesMainWindowShell.swift")
        #expect(
            shell.contains(
                ".keyboardShortcut(\"o\", modifiers: .command)"
            )
        )
        #expect(
            shell.contains(
                "@FocusedValue(\\.blueMinutesShellCommandActions)"
            )
        )
        #expect(
            !root.contains(
                ".keyboardShortcut(\"o\", modifiers: .command)"
            )
        )
        #expect(localMedia.contains(".keyboardShortcut(\"i\", modifiers: .command)"))
        #expect(localMedia.contains(".keyboardShortcut(.return, modifiers: .command)"))
        #expect(localMedia.contains(".accessibilityLabel(\"Canonical audio progress\")"))
        #expect(localMedia.contains(".accessibilityValue("))
        #expect(root.contains(".confirmationDialog("))
        #expect(root.contains("role: .destructive"))

        let storage = try source("StorageDashboardView.swift")
        #expect(storage.contains(".keyboardShortcut(\"r\", modifiers: [.command, .shift])"))
        #expect(storage.contains(".accessibilityLabel(\"Workspace storage usage by category\")"))
        #expect(storage.contains("Requires visible confirmation"))
        #expect(storage.contains("does not guarantee forensic erasure"))

        let briefing = try source("BriefingReviewView.swift")
        let briefingSources = try [
            briefing,
            source("BriefingEditorialCanvas.swift"),
            source("BriefingSectionEditor.swift"),
            source("BriefingPublicationProofView.swift"),
            featureSource(
                "Models/BriefingReviewPresentation.swift"
            )
        ].joined(separator: "\n")
        #expect(briefingSources.contains("This briefing is stale after an upstream correction"))
        #expect(briefingSources.contains(".accessibilityLabel(\"Stale briefing warning\")"))
        #expect(
            briefingSources.contains(
                "BlueMinutes.Briefing.EditorialCanvas"
            )
        )
        #expect(briefingSources.contains("Editorial Briefing Canvas"))
        #expect(briefingSources.contains(".meetingOverview"))
        #expect(briefingSources.contains(".majorIssues"))
        #expect(briefingSources.contains(".majorDelegations"))
        #expect(
            briefingSources.contains(
                "Exact EvidenceRef revisions"
            )
        )
        #expect(
            briefingSources.contains(
                "No Briefing evidence inspector is shown"
            )
        )
        #expect(
            briefingSources.contains(
                "Published section provenance"
            )
        )
        #expect(
            briefingSources.contains(
                ".accessibilityLabel(editorLabel)"
            )
        )
        #expect(
            briefingSources.contains(
                ".accessibilityValue(text)"
            )
        )
        #expect(
            briefingSources.contains(
                "Saving creates an immutable user-confirmed revision"
            )
        )
        #expect(
            briefingSources.contains(
                "Commitment and Decision references are document evidence only"
            )
        )
        #expect(
            briefingSources.contains(
                "sceneState.beginDirectBriefingSave"
            )
        )
        #expect(
            briefingSources.contains(
                ".regenerateBriefingSection("
            )
        )
        #expect(!briefingSources.contains(".inspector("))
        #expect(!briefingSources.contains("@AppStorage"))
        #expect(!briefingSources.contains("@SceneStorage"))
        let analysis = try source("AnalysisReviewView.swift")
        #expect(analysis.contains("Stale after correction"))
        #expect(analysis.contains("No-outbound mode"))
        #expect(
            analysis.contains(
                "AnalysisEvidenceInspectorPanel"
            )
        )
        #expect(analysis.contains("Unresolved exact evidence"))
        let analysisInspector = try source(
            "AnalysisEvidenceInspectorPanel.swift"
        )
        #expect(
            analysisInspector.contains(
                "BlueMinutes.Analysis.EvidenceInspector"
            )
        )
        #expect(
            analysisInspector.contains(
                "Whole-ledger human confirmation"
            )
        )
        #expect(
            analysisInspector.contains(
                ".textSelection(.enabled)"
            )
        )
        let transcript = try source("TranscriptReviewView.swift")
        #expect(transcript.contains("No-outbound mode"))
    }

    private func source(_ fileName: String) throws -> String {
        try featureSource("Views/\(fileName)")
    }

    private func featureSource(
        _ relativePath: String
    ) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository
                .appendingPathComponent(
                    "Sources/MeetingBuddyFeatures"
                )
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
