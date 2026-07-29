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
                "let workflow = AppMediaReviewWorkflow("
            )
        )
        #expect(
            app.contains(
                "capabilities: capabilities,"
            )
        )

        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        #expect(workflow.contains("let capabilities: AppCapabilities"))
        #expect(workflow.contains("private let capabilities: AppCapabilities"))
        #expect(
            workflow.contains(
                "init(\n        capabilities: AppCapabilities,"
            )
        )
        #expect(
            workflow.components(
                separatedBy: "capabilities: capabilities"
            ).count == 3
        )
        for capability in [
            "research",
            "transcriptSourceResolution",
            "sharedObjectStore",
            "conversationPersistence",
        ] {
            #expect(
                !workflow.contains(
                    "capabilities.\(capability)"
                )
            )
        }

        #expect(
            try productionSourceReferences(to: "AppCapabilities") == [
                "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift",
                "Sources/MeetingBuddyApp/MeetingBuddyApp.swift",
                "Sources/MeetingBuddyApplication/AppCapabilities.swift"
            ]
        )
    }

    @Test
    func mediaImportCompletesFalliblePreflightBeforePersistentWrites() throws {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        let importStart = try #require(
            workflow.range(
                of:
                    "func importAndProcess(_ submission: MediaImportSubmission)"
            )
        )
        let importEnd = try #require(
            workflow.range(
                of: "func jobReview(jobID: JobID)",
                range: importStart.upperBound..<workflow.endIndex
            )
        )
        let importBody = String(
            workflow[importStart.lowerBound..<importEnd.lowerBound]
        )
        let falliblePreflightMarkers = [
            "let createdAt = try currentInstant()",
            "let meeting = try meetingProfile(",
            "let meetingUUID = try requiredUUID(",
            "let securityPolicy = try LocalSecurityPolicyFactory().makeDefault(",
            "let selectedTrack = try inspection.requireTrack(",
            "let expectedSourceByteSize = try sourceByteSize(",
            "let intakePlan = try LocalMediaIntakeJobPlan(",
            "let intakeRequest = try LocalMediaIntakeJobFactory().request(",
            "try runtime.transientSources.register(sourceURL, for: intakeJobID)",
        ]
        let preflightRanges = try falliblePreflightMarkers.map { marker in
            try #require(importBody.range(of: marker))
        }
        for (earlier, later) in zip(preflightRanges, preflightRanges.dropFirst()) {
            #expect(earlier.lowerBound < later.lowerBound)
        }

        let persistentSinkMarkers = [
            "runtime.store.",
            "runtime.manager.enqueue(",
        ]
        let persistentSinkRanges = try persistentSinkMarkers.map { marker in
            try #require(importBody.range(of: marker))
        }
        let firstPersistentWrite = try #require(
            persistentSinkRanges.min {
                $0.lowerBound < $1.lowerBound
            }
        )
        let completedPreflight = try #require(preflightRanges.last)

        #expect(completedPreflight.lowerBound < firstPersistentWrite.lowerBound)
    }

    @Test
    func appWorkflowRecoversEveryPersistedIntakeBoundary()
        throws
    {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        let restoreStart = try #require(
            workflow.range(
                of:
                    "func restoredMediaReview() async throws"
            )
        )
        let restoreEnd = try #require(
            workflow.range(
                of:
                    "func openOrCreateWorkspace",
                range:
                    restoreStart.upperBound
                        ..< workflow.endIndex
            )
        )
        let restoreBody = String(
            workflow[
                restoreStart.lowerBound
                    ..< restoreEnd.lowerBound
            ]
        )

        for required in [
            "MediaJobTypes.localIntake",
            ".manager.cancel(",
            "intakeRecord.state",
            "== .succeeded",
            "CanonicalAudioJobFactory()",
            "sourceReselectionJob:",
            "canonicalJob: nil"
        ] {
            #expect(
                restoreBody.contains(required)
            )
        }
    }

    @Test
    func startupRecoveryDoesNotReplayOrStrandPersistedQueuedJobs()
        throws
    {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        for required in [
            "cancelPersistedQueuedJobs()",
            "A queued record proves persistence completed",
            "visible outbound authorization"
        ] {
            #expect(
                workflow.contains(required)
            )
        }
    }

    @Test
    func workspaceFolderFailuresRemainSafeAndActionable()
        throws
    {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        #expect(
            workflow.contains(
                "case workspaceFolderContainsOtherFiles"
            )
        )
        #expect(
            workflow.contains(
                "This folder contains other files, so BlueMinutes left it unchanged."
            )
        )
        #expect(
            workflow.contains(
                "error as?"
            )
        )
        #expect(
            workflow.contains(
                ".workspaceRootNotEmpty"
            )
        )
        #expect(
            workflow.contains(
                ".workspaceFolderContainsOtherFiles"
            )
        )
    }

    @Test
    func codexAssistantEnforcesThePersistedMeetingChatRoute()
        throws
    {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        let turnStart = try #require(
            workflow.range(
                of:
                    "func codexTurnRequest("
            )
        )
        let turnEnd = try #require(
            workflow.range(
                of:
                    "private func recordingReview(",
                range:
                    turnStart.upperBound
                        ..< workflow.endIndex
            )
        )
        let body = String(
            workflow[
                turnStart.lowerBound
                    ..< turnEnd.lowerBound
            ]
        )

        for required in [
            "try intelligenceRepository.load()",
            ".route(for: .meetingChat)",
            "== configuredSelection",
            "intelligenceState",
            ".routingProfile()",
            "registry: try intelligenceState.registry()"
        ] {
            #expect(body.contains(required))
        }
        #expect(
            !body.contains(
                "identifier: \"v4-codex-text\""
            )
        )
    }

    @Test
    func workspaceSwitchChecksRecordingAndEveryTaskManagerJob()
        throws
    {
        let workflow = try source(
            "Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift"
        )
        let switchStart = try #require(
            workflow.range(
                of:
                    "func openOrCreateWorkspace(at selectedDirectory: URL)"
            )
        )
        let switchEnd = try #require(
            workflow.range(
                of:
                    "func inspectSelectedMedia",
                range:
                    switchStart.upperBound
                        ..< workflow.endIndex
            )
        )
        let switchBody = String(
            workflow[
                switchStart.lowerBound
                    ..< switchEnd.lowerBound
            ]
        )
        #expect(
            switchBody.contains(
                "nonterminalSessions()"
            )
        )
        #expect(
            switchBody.contains(
                "runtime.manager"
            )
        )
        #expect(
            switchBody.contains(
                ".allSatisfy(\\.state.isTerminal)"
            )
        )
        let prepare = try #require(
            switchBody.range(
                of:
                    ".prepare(selectedDirectory)"
            )
        )
        let recover = try #require(
            switchBody.range(
                of:
                    "try await nextRuntime.recover()"
            )
        )
        let commit = try #require(
            switchBody.range(
                of:
                    ".commit(candidateScope)"
            )
        )
        #expect(
            prepare.lowerBound
                < recover.lowerBound
        )
        #expect(
            recover.lowerBound
                < commit.lowerBound
        )
        #expect(
            switchBody.components(
                separatedBy:
                    ".discard(candidateScope)"
            ).count == 3
        )
        #expect(
            !switchBody.contains(
                "workspaceSecurityScope.forget()"
            )
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
