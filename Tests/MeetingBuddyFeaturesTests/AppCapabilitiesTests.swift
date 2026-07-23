import Foundation
import MeetingBuddyApplication
import Testing

@Suite
struct AppCapabilitiesTests {
    @Test
    func defaultSnapshotDisablesEveryResearchIntegration() {
        let capabilities = AppCapabilities()

        #expect(capabilities.research == false)
        #expect(capabilities.transcriptSourceResolution == false)
        #expect(capabilities.sharedObjectStore == false)
        #expect(capabilities.conversationPersistence == false)
        #expect(
            capabilities.canonicalDescription
                == "research=false,transcript_source_resolution=false,"
                    + "shared_object_store=false,conversation_persistence=false"
        )
    }

    @Test
    func explicitCompositionValuesHaveStableValueSemanticsAndDescription() {
        let capabilities = AppCapabilities(
            research: true,
            transcriptSourceResolution: false,
            sharedObjectStore: true,
            conversationPersistence: false
        )
        let sameCapabilities = AppCapabilities(
            research: true,
            transcriptSourceResolution: false,
            sharedObjectStore: true,
            conversationPersistence: false
        )

        #expect(capabilities == sameCapabilities)
        #expect(
            capabilities.canonicalDescription
                == "research=true,transcript_source_resolution=false,"
                    + "shared_object_store=true,conversation_persistence=false"
        )
    }

    @Test
    func productionCompositionOwnsOneInertSnapshot() throws {
        let app = try source("Sources/MeetingBuddyApp/MeetingBuddyApp.swift")
        #expect(app.contains("let capabilities = AppCapabilities()"))
        #expect(
            app.contains(
                "AppMediaReviewWorkflow(capabilities: capabilities)"
            )
        )

        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        #expect(workflow.contains("let capabilities: AppCapabilities"))
        #expect(workflow.contains("private let capabilities: AppCapabilities"))
        #expect(workflow.contains("init(capabilities: AppCapabilities)"))
        #expect(
            workflow.components(
                separatedBy: "capabilities: capabilities"
            ).count == 3
        )
        #expect(!workflow.contains("capabilities."))

        #expect(
            try productionSourceReferences(to: "AppCapabilities") == [
                "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift",
                "Sources/MeetingBuddyApp/MeetingBuddyApp.swift",
                "Sources/MeetingBuddyApplication/AppCapabilities.swift"
            ]
        )
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

    private func productionSourceReferences(to token: String) throws -> [String] {
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var references: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            guard contents.contains(token) else { continue }
            references.append(
                fileURL.path.replacingOccurrences(
                    of: repositoryRoot.path + "/",
                    with: ""
                )
            )
        }
        return references.sorted()
    }
}
