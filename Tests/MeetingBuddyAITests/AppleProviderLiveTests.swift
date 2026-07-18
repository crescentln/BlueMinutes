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
