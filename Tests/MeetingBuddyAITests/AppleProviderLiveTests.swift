import CryptoKit
import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite(.serialized)
struct AppleProviderLiveTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["MEETINGBUDDY_RUN_LIVE_APPLE_MODELS"] == "1",
            "Live installed-model validation is opt-in."
        )
    )
    func installedAppleProvidersProcessOnlySyntheticData() async throws {
        guard #available(macOS 26.0, *) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meetingbuddy-live-provider-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("synthetic.aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [
            "-v", "Samantha", "-o", audioURL.path,
            "Meeting Buddy preserves every source segment."
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let speech = AppleOnDeviceTranscriptionProvider()
        let english = try LanguageTag("en")
        guard await speech.isModelInstalled(for: english) else { return }
        let speechDecision = try ModelPolicyRouter().decide(
            localDecisionRequest(capability: .transcription, categories: [.canonicalAudio])
        )
        #expect(speechDecision.providerIdentifier == speech.metadata.providerIdentifier)
        let chunk = try CanonicalChunkPlanner.plan(totalFrameCount: 480_000)[0]
        let source = try SemanticRevisionReference(
            logicalID: aiID(90, SourceAssetID.self),
            revisionID: aiID(91, RevisionID.self)
        )
        let result = try await speech.transcribe(
            TranscriptionRequest(
                audio: TaskOwnedAudioChunk(fileURL: audioURL, plan: chunk),
                canonicalSourceRevision: source,
                language: english,
                dataClassification: .internal
            )
        )
        guard case let .speech(spans) = result else {
            Issue.record("Synthetic speech was unexpectedly classified as no-speech.")
            return
        }
        #expect(!spans.map(\.text).joined().isEmpty)

        let translation = AppleOnDeviceTranslationProvider()
        let chinese = try LanguageTag("zh-hans")
        guard await translation.isModelInstalled(source: english, target: chinese) else { return }
        let translationDecision = try ModelPolicyRouter().decide(
            localDecisionRequest(capability: .translation, categories: [.transcriptText])
        )
        #expect(translationDecision.providerIdentifier == translation.metadata.providerIdentifier)
        let response = try await translation.translate(
            TranslationRequest(
                sourceText: "MeetingBuddy preserves every source segment.",
                sourceLanguage: english,
                targetLanguage: chinese,
                dataClassification: .internal
            )
        )
        #expect(!response.translatedText.isEmpty)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["MEETINGBUDDY_RUN_LIVE_APPLE_ANALYSIS"] == "1",
            "Live Apple Foundation Models analysis validation is opt-in."
        )
    )
    func installedAppleFoundationModelAnalyzesOnlyVersionedSyntheticText() async throws {
        guard #available(macOS 26.0, *) else { return }
        let fixtureIdentifier = "task006a-live-synthetic-diplomatic-001"
        let fixtureVersion = "1"
        let fixtureText = "The delegation supports the voluntary reporting proposal on the condition that participation remains optional, while reserving its position on the proposal's annual review requirement."
        let fixtureHash = SHA256.hash(data: Data(fixtureText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(fixtureIdentifier == "task006a-live-synthetic-diplomatic-001")
        #expect(fixtureVersion == "1")
        #expect(fixtureHash == "d220ba7046fb638853b24cc0eaf31b477576f1a4b0b4be6ab297a5f19ed49898")

        let provider = AppleFoundationModelsAnalysisProvider()
        guard await provider.isModelAvailable(localeIdentifier: "en") else { return }
        let routeRequest = try ModelRouteRequest(
            capability: .analysis,
            dataClassification: .internal,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: [.transcriptText, .speakerContext, .evidenceIdentifiers],
            visibleUserAuthorization: true,
            localModelAvailable: true
        )
        let decision = try ModelPolicyRouter().decide(routeRequest)
        #expect(decision.route == .appleOnDevice)
        #expect(decision.providerIdentifier == provider.metadata.providerIdentifier)
        #expect(decision.request.destination == .localDevice)
        #expect(decision.request.retentionPolicy == .noProviderRetention)

        let result = try await provider.analyze(
            AnalysisRequest(
                packageIdentifier: fixtureIdentifier + "@" + fixtureVersion,
                transcriptRevision: SemanticRevisionReference(
                    logicalID: aiID(92, TranscriptSegmentID.self),
                    revisionID: aiID(93, RevisionID.self)
                ),
                speakerAssignmentRevision: SemanticRevisionReference(
                    logicalID: aiID(94, SpeakerAssignmentID.self),
                    revisionID: aiID(95, RevisionID.self)
                ),
                transcriptText: fixtureText,
                speakerContext: AnalysisSpeakerContext(
                    actorLabel: "Synthetic Delegate",
                    capacityLabel: "delegate",
                    representedEntityLabel: "Synthetic Delegation",
                    assignmentIsConfirmed: true
                ),
                evidenceKeys: ["evidence_task006a_live_001"],
                dataClassification: .internal,
                localeIdentifier: "en"
            )
        )
        #expect(result.substantive)
        #expect(result.positionType?.isKnown == true)
        #expect(result.positionType != .noStatedPosition)
        #expect(result.positionStatement?.isEmpty == false)
        #expect(result.conditions.contains { $0.contains("participation remains optional") })
        #expect(result.reservations.contains { $0.contains("annual review") })
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["MEETINGBUDDY_RUN_LIVE_APPLE_BRIEFING"] == "1",
            "Live Apple Foundation Models briefing validation is opt-in."
        )
    )
    func installedAppleFoundationModelGeneratesOnlyEvidenceKeyedSyntheticBriefing() async throws {
        guard #available(macOS 26.0, *) else { return }
        let provider = AppleFoundationModelsBriefingProvider()
        guard await provider.isModelAvailable(localeIdentifier: "en") else { return }
        let routeRequest = try ModelRouteRequest(
            capability: .analysis,
            dataClassification: .internal,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: [.validatedIntelligenceClaims, .evidenceIdentifiers],
            visibleUserAuthorization: true,
            localModelAvailable: true
        )
        let decision = try ModelPolicyRouter().decide(routeRequest)
        #expect(decision.route == .appleOnDevice)
        #expect(decision.providerIdentifier == provider.metadata.providerIdentifier)

        let evidence = try SemanticRevisionReference(
            logicalID: aiID(96, EvidenceID.self),
            revisionID: aiID(97, RevisionID.self)
        )
        let request = try BriefingSectionRequest(
            packageIdentifier: "task006b-live-synthetic-briefing-001@1",
            templateRevision: SemanticRevisionReference(
                logicalID: aiID(98, BriefingTemplateID.self),
                revisionID: aiID(99, RevisionID.self)
            ),
            graphRevision: SemanticRevisionReference(
                logicalID: aiID(100, IssuePositionGraphID.self),
                revisionID: aiID(101, RevisionID.self)
            ),
            sectionDefinition: TemplateSectionDefinition(
                key: "major-issues",
                sectionType: .majorIssues,
                order: 2,
                title: "Major Issues",
                targetLengthUTF8Bytes: 8_192,
                requiredInputObjectTypes: [.issuePositionGraph, .issue],
                promptModules: [
                    VersionedComponent(
                        identifier: "briefing-major-issues-generator",
                        version: "1.0.0"
                    )
                ]
            ),
            outputLanguage: LanguageTag("en"),
            sourceClaims: [
                BriefingSourceClaim(
                    sourceKey: "issue_synthetic_001",
                    sourceRevision: SemanticRevisionReference(
                        logicalID: aiID(102, IssueID.self),
                        revisionID: aiID(103, RevisionID.self)
                    ),
                    claim: EvidenceLinkedClaim(
                        text: "The synthetic issue concerns a voluntary reporting proposal.",
                        taxonomy: .meetingBuddyExtraction,
                        supportStatus: .supported,
                        evidenceRevisions: [evidence],
                        confidence: ConfidenceScore(millionths: 900_000)
                    )
                )
            ],
            dataClassification: .internal,
            localeIdentifier: "en"
        )
        let result = try await provider.generateSection(request)
        #expect(result.sectionType == .majorIssues)
        #expect(!result.items.isEmpty)
        #expect(Set(result.items.flatMap(\.sourceKeys)) == Set(["issue_synthetic_001"]))
        #expect(result.items.allSatisfy { !$0.text.isEmpty })
    }
}

private func localDecisionRequest(
    capability: AIProcessingCapability,
    categories: [ProviderDataCategory]
) throws -> ModelRouteRequest {
    try ModelRouteRequest(
        capability: capability,
        dataClassification: .internal,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: .production,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: categories,
        visibleUserAuthorization: false,
        localModelAvailable: true
    )
}
