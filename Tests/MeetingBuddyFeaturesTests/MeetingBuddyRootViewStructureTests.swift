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
            #expect(rootView.contains("Label(\"\(label)\""))
        }
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
        #expect(rootView.contains("public init(store: MediaReviewStore)"))
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
