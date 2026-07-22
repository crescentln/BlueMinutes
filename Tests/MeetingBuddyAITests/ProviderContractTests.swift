@preconcurrency import AVFAudio
import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite(.serialized)
struct ProviderContractTests {
    @Test
    func policyRouterPrefersLocalFailsClosedAndLimitsTestProvider() throws {
        let router = ModelPolicyRouter()
        let local = try router.decide(
            request(localModelAvailable: true, environment: .production)
        )
        #expect(local.route == .appleOnDevice)
        #expect(local.route.privacyRoute == .localOnly)
        #expect(local.providerIdentifier == "apple-speech")

        let localTranslation = try router.decide(
            ModelRouteRequest(
                capability: .translation,
                dataClassification: .sensitive,
                offlineMode: true,
                organizationAllowsExternalProcessing: false,
                deploymentEnvironment: .production,
                destination: .localDevice,
                retentionPolicy: .localWorkspaceOnly,
                dataCategories: [.transcriptText],
                visibleUserAuthorization: false,
                localModelAvailable: true
            )
        )
        #expect(localTranslation.providerIdentifier == "apple-translation")

        let unavailable = try router.decide(
            request(localModelAvailable: false, environment: .production)
        )
        #expect(unavailable.route == .manualFallback)
        #expect(unavailable.providerIdentifier == nil)

        let test = try router.decide(
            request(localModelAvailable: true, environment: .test)
        )
        #expect(test.route == .deterministicTest)

        let externalCandidate = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(identifier: "synthetic-approved"),
            retentionPolicy: .noProviderRetention,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: true,
            localModelAvailable: false,
            securityPolicy: try externalSecurityPolicy()
        )
        #expect(throws: AIProviderContractError.self) {
            _ = try router.decide(externalCandidate)
        }

        let missingAuthorization = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(identifier: "synthetic-approved"),
            retentionPolicy: .noProviderRetention,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: false,
            localModelAvailable: false,
            securityPolicy: try externalSecurityPolicy()
        )
        #expect(try router.decide(missingAuthorization).route == .manualFallback)

        let deniedDestination = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: true,
            localModelAvailable: false,
            securityPolicy: try externalSecurityPolicy()
        )
        #expect(try router.decide(deniedDestination).route == .manualFallback)

        let deniedRetention = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(identifier: "synthetic-approved"),
            retentionPolicy: .localWorkspaceOnly,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: true,
            localModelAvailable: false,
            securityPolicy: try externalSecurityPolicy()
        )
        #expect(try router.decide(deniedRetention).route == .manualFallback)

        let noOutbound = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(identifier: "synthetic-approved"),
            retentionPolicy: .noProviderRetention,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: true,
            localModelAvailable: false,
            securityPolicy: try localOnlySecurityPolicy()
        )
        #expect(try router.decide(noOutbound).reasonCode == "no_outbound_mode")

        let localDenied = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .localWorkspaceOnly,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: false,
            localModelAvailable: true,
            securityPolicy: try localOnlySecurityPolicy(localProcessingAllowed: false)
        )
        #expect(try router.decide(localDenied).reasonCode == "local_processing_denied")
    }

    @Test
    func routePolicyMatrixKeepsEveryClassificationLocalAndRejectsPolicyDrift() throws {
        let router = ModelPolicyRouter()
        for (index, classification) in [
            DataClassification.public,
            .internal,
            .sensitive,
            .restricted
        ].enumerated() {
            let policy = try localOnlySecurityPolicy(
                classification: classification,
                identifierOffset: 920 + index * 4
            )
            let local = try ModelRouteRequest(
                capability: .analysis,
                dataClassification: classification,
                offlineMode: false,
                organizationAllowsExternalProcessing: true,
                deploymentEnvironment: .production,
                destination: .approvedProvider(identifier: "ignored-ui-selection"),
                retentionPolicy: .approvedProviderRetention,
                dataCategories: [
                    .transcriptText,
                    .speakerContext,
                    .evidenceIdentifiers
                ],
                visibleUserAuthorization: true,
                localModelAvailable: true,
                securityPolicy: policy
            )
            let decision = try router.decide(local)
            #expect(decision.route == .appleOnDevice)
            #expect(decision.route.privacyRoute == .localOnly)
        }

        let legacyExternal = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(identifier: "synthetic-approved"),
            retentionPolicy: .noProviderRetention,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: true,
            localModelAvailable: false
        )
        #expect(try router.decide(legacyExternal).reasonCode == "legacy_policy_is_local_only")

        #expect(throws: AIProviderContractError.self) {
            _ = try ModelRouteRequest(
                capability: .transcription,
                dataClassification: .sensitive,
                offlineMode: false,
                organizationAllowsExternalProcessing: true,
                deploymentEnvironment: .production,
                destination: .approvedProvider(identifier: "synthetic-approved"),
                retentionPolicy: .noProviderRetention,
                dataCategories: [.canonicalAudio],
                visibleUserAuthorization: true,
                localModelAvailable: false,
                securityPolicy: externalSecurityPolicy()
            )
        }
        #expect(throws: AIProviderContractError.self) {
            _ = try ModelSecurityPolicySnapshot(
                sensitivityLabelRevision: SemanticRevisionReference(
                    logicalID: aiID(940, SensitivityLabelID.self),
                    revisionID: aiID(941, RevisionID.self)
                ),
                accessPolicyRevision: SemanticRevisionReference(
                    logicalID: aiID(942, AccessPolicyID.self),
                    revisionID: aiID(943, RevisionID.self)
                ),
                effectiveClassification: .restricted,
                noOutboundMode: false,
                localProcessingAllowed: true,
                manualLocalReviewAllowed: true,
                externalProcessingAllowed: true,
                approvedExternalProviderIdentifiers: ["synthetic-approved"],
                approvedDeploymentEnvironments: [.production],
                approvedRetentionPolicies: [.noProviderRetention]
            )
        }
    }

    @Test
    func structuredProviderOutputRejectsOverlapAndEmptySpeech() throws {
        let confidence = try ConfidenceScore(millionths: 900_000)
        let first = try TranscriptionSpan(
            startMilliseconds: 0,
            endMilliseconds: 500,
            text: "first",
            confidence: confidence
        )
        let overlap = try TranscriptionSpan(
            startMilliseconds: 400,
            endMilliseconds: 800,
            text: "overlap",
            confidence: confidence
        )
        #expect(throws: AIProviderContractError.self) {
            _ = try TranscriptionChunkResult(validatingSpans: [first, overlap])
        }
        #expect(throws: AIProviderContractError.self) {
            _ = try TranscriptionChunkResult(validatingSpans: [])
        }
        #expect(try TranscriptionChunkResult(validatingSpans: [first]) == .speech(spans: [first]))
    }

    @Test
    func coverageDistinguishesNoSpeechFailureAndMissingAndFailsClosed() throws {
        let route = try ModelPolicyRouter().decide(
            request(localModelAvailable: true, environment: .test)
        )
        let source = try SemanticRevisionReference(
            logicalID: aiID(1, SourceAssetID.self),
            revisionID: aiID(2, RevisionID.self)
        )
        let plan = try CanonicalChunkPlanner.plan(totalFrameCount: 600_000)
        let noSpeech = try TranscriptChunkCoverage(
            index: plan[0].index,
            coreRange: plan[0].coreRange,
            physicalRange: plan[0].physicalRange,
            disposition: .noSpeech,
            attemptCount: 1,
            provider: try providerMetadata()
        )
        let failed = try TranscriptChunkCoverage(
            index: plan[1].index,
            coreRange: plan[1].coreRange,
            physicalRange: plan[1].physicalRange,
            disposition: .failed,
            attemptCount: 2,
            provider: try providerMetadata(),
            safeFailureCode: "provider_output_invalid"
        )
        let incomplete = try TranscriptCoverageManifest(
            transcriptSetID: TranscriptSetID(UUID()),
            meetingID: aiID(3, MeetingID.self),
            canonicalSourceRevision: source,
            canonicalFrameCount: 600_000,
            transcriptionRoute: route,
            status: .incomplete,
            chunks: [noSpeech, failed],
            createdAt: aiInstant(1_900_000_000_000)
        )
        #expect(incomplete.chunks[0].disposition == .noSpeech)
        #expect(incomplete.chunks[1].disposition == .failed)

        #expect(throws: TranscriptCoverageError.self) {
            _ = try TranscriptCoverageManifest(
                transcriptSetID: TranscriptSetID(UUID()),
                meetingID: aiID(3, MeetingID.self),
                canonicalSourceRevision: source,
                canonicalFrameCount: 600_000,
                transcriptionRoute: route,
                status: .published,
                chunks: [noSpeech, failed],
                createdAt: aiInstant(1_900_000_000_001)
            )
        }

        let missing = try TranscriptChunkCoverage(
            index: plan[1].index,
            coreRange: plan[1].coreRange,
            physicalRange: plan[1].physicalRange,
            disposition: .missing,
            attemptCount: 0
        )
        #expect(missing.disposition != noSpeech.disposition)
    }

    @Test
    func productionNoSpeechVerifierAcceptsOnlyExactDigitalSilence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meetingbuddy-no-speech-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let silentURL = directory.appendingPathComponent("silent.caf")
        let nonSilentURL = directory.appendingPathComponent("non-silent.caf")
        try writePCMFixture(to: silentURL, nonzeroSample: false)
        try writePCMFixture(to: nonSilentURL, nonzeroSample: true)
        let plan = try #require(CanonicalChunkPlanner.plan(totalFrameCount: 16_000).first)
        let verifier = DigitalSilenceNoSpeechVerifier()

        let silence = await verifier.confirmation(
            for: try TaskOwnedAudioChunk(fileURL: silentURL, plan: plan)
        )
        let speech = await verifier.confirmation(
            for: try TaskOwnedAudioChunk(fileURL: nonSilentURL, plan: plan)
        )

        #expect(silence?.verifiedCoreRange == plan.coreRange)
        #expect(speech == nil)
    }

    @Test
    func nonSubstantiveVerifierBindsOnlyClosedMarkersToExactText() throws {
        let workspace = try AIWorkspace()
        defer { workspace.cleanup() }
        let source = try prepareAnalysisSource(workspace)
        let original = try #require(
            AnalysisPipelineJobPlan.requestPackages(from: source).first?.request
        )
        let translationRevision = try SemanticRevisionReference(
            logicalID: aiID(70, TranslationSegmentID.self),
            revisionID: aiID(71, RevisionID.self)
        )
        let marker: AnalysisRequest
        do {
            marker = try AnalysisRequest(
                packageIdentifier: original.packageIdentifier,
                transcriptRevision: original.transcriptRevision,
                translationRevision: translationRevision,
                speakerAssignmentRevision: original.speakerAssignmentRevision,
                transcriptText: "[applause]",
                translatedText: "[applause]",
                speakerContext: original.speakerContext,
                evidenceKeys: original.evidenceKeys,
                dataClassification: original.dataClassification,
                localeIdentifier: original.localeIdentifier
            )
        } catch {
            Issue.record("Marker fixture construction failed: \(error)")
            return
        }

        let markerConfirmation = try AnalysisNonSubstantiveVerifier.confirmation(for: marker)
        let confirmation = try #require(markerConfirmation)
        let markerDigest = try ContentDigest.sha256(ofUTF8Text: marker.transcriptText)
        let translationDigest = try ContentDigest.sha256(ofUTF8Text: "[applause]")
        let meaningfulConfirmation = try AnalysisNonSubstantiveVerifier.confirmation(
            for: original
        )
        let mismatchedTranslation: AnalysisRequest
        do {
            mismatchedTranslation = try AnalysisRequest(
                packageIdentifier: original.packageIdentifier,
                transcriptRevision: original.transcriptRevision,
                translationRevision: translationRevision,
                speakerAssignmentRevision: original.speakerAssignmentRevision,
                transcriptText: "[applause]",
                translatedText: "The delegation supports the draft.",
                speakerContext: original.speakerContext,
                evidenceKeys: original.evidenceKeys,
                dataClassification: original.dataClassification,
                localeIdentifier: original.localeIdentifier
            )
        } catch {
            Issue.record("Mismatched-translation fixture construction failed: \(error)")
            return
        }
        #expect(confirmation.segmentRevision == marker.transcriptRevision)
        #expect(confirmation.sourceTextDigest == markerDigest)
        #expect(confirmation.translationRevision == marker.translationRevision)
        #expect(confirmation.translationTextDigest == translationDigest)
        #expect(meaningfulConfirmation == nil)
        #expect(try AnalysisNonSubstantiveVerifier.confirmation(
            for: mismatchedTranslation
        ) == nil)
    }

    @Test
    func keychainRoundTripsOpaqueSecretWithoutFilesystemStorage() throws {
        let store = MacOSKeychainSecretStore()
        #expect(throws: AIProviderContractError.self) {
            _ = try SecretIdentifier(service: "com.meetingbuddy/tests", account: "ephemeral")
        }
        #expect(throws: AIProviderContractError.self) {
            _ = try SecretIdentifier(service: "com.meetingbuddy.tests", account: "")
        }
        let identifier = try SecretIdentifier(
            service: "com.meetingbuddy.tests.\(UUID().uuidString.lowercased())",
            account: "ephemeral"
        )
        defer { try? store.remove(identifier) }
        let value = Data("synthetic-secret-not-a-credential".utf8)
        #expect(throws: KeychainSecretStoreError.valueTooLarge) {
            try store.write(Data(), for: identifier)
        }
        #expect(throws: KeychainSecretStoreError.valueTooLarge) {
            try store.write(
                Data(repeating: 0x5a, count: MacOSKeychainSecretStore.maximumValueBytes + 1),
                for: identifier
            )
        }
        try store.write(value, for: identifier)
        #expect(try store.read(identifier) == value)
        try store.remove(identifier)
        #expect(try store.read(identifier) == nil)
    }

    @Test
    func telemetryIsDefaultOffBoundedAndContentFreeByConstruction() async throws {
        let event = try ContentFreeTelemetryEvent(
            name: .taskStateChanged,
            counters: [TelemetryCounter(key: .successful, value: 1)]
        )
        let disabled = LocalTelemetryBuffer(policy: try TelemetryPolicy())
        #expect(await disabled.record(event) == .suppressedDisabled)
        #expect(await disabled.bufferedEvents().isEmpty)

        let local = LocalTelemetryBuffer(
            policy: try TelemetryPolicy(
                mode: .localDiagnostics,
                noOutboundMode: true,
                maximumBufferedEvents: 2
            )
        )
        #expect(await local.record(event) == .recordedInMemory)
        #expect(await local.bufferedEvents() == [event])

        let encoded = try JSONEncoder().encode(event)
        let text = String(decoding: encoded, as: UTF8.self)
        let forbiddenFixtures = [
            "Synthetic Secret Meeting",
            "transcript sentence",
            "sk-test-credential",
            "recording.wav",
            "/Users/example/private",
            "60000000-0000-0000-0000-000000000001"
        ]
        #expect(forbiddenFixtures.allSatisfy { !text.contains($0) })
        #expect(!text.contains("title"))
        #expect(!text.contains("filename"))
        #expect(!text.contains("path"))
        #expect(!text.contains("meeting_id"))
    }
}

private func writePCMFixture(to url: URL, nonzeroSample: Bool) throws {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    ))
    var file: AVAudioFile? = try AVAudioFile(
        forWriting: url,
        settings: format.settings,
        commonFormat: .pcmFormatInt16,
        interleaved: true
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    buffer.frameLength = 16_000
    let samples = try #require(buffer.int16ChannelData?[0])
    samples.initialize(repeating: 0, count: 16_000)
    if nonzeroSample { samples[8_000] = 1 }
    try file?.write(from: buffer)
    file = nil
}

private func externalSecurityPolicy() throws -> ModelSecurityPolicySnapshot {
    try ModelSecurityPolicySnapshot(
        sensitivityLabelRevision: SemanticRevisionReference(
            logicalID: aiID(901, SensitivityLabelID.self),
            revisionID: aiID(902, RevisionID.self)
        ),
        accessPolicyRevision: SemanticRevisionReference(
            logicalID: aiID(903, AccessPolicyID.self),
            revisionID: aiID(904, RevisionID.self)
        ),
        effectiveClassification: .internal,
        noOutboundMode: false,
        localProcessingAllowed: true,
        manualLocalReviewAllowed: true,
        externalProcessingAllowed: true,
        approvedExternalProviderIdentifiers: ["synthetic-approved"],
        approvedDeploymentEnvironments: [.production],
        approvedRetentionPolicies: [.noProviderRetention]
    )
}

private func localOnlySecurityPolicy(
    localProcessingAllowed: Bool = true,
    classification: DataClassification = .internal,
    identifierOffset: Int = 905
) throws -> ModelSecurityPolicySnapshot {
    try ModelSecurityPolicySnapshot(
        sensitivityLabelRevision: SemanticRevisionReference(
            logicalID: aiID(identifierOffset, SensitivityLabelID.self),
            revisionID: aiID(identifierOffset + 1, RevisionID.self)
        ),
        accessPolicyRevision: SemanticRevisionReference(
            logicalID: aiID(identifierOffset + 2, AccessPolicyID.self),
            revisionID: aiID(identifierOffset + 3, RevisionID.self)
        ),
        effectiveClassification: classification,
        noOutboundMode: true,
        localProcessingAllowed: localProcessingAllowed,
        manualLocalReviewAllowed: true,
        externalProcessingAllowed: false,
        approvedExternalProviderIdentifiers: []
    )
}

private func request(
    localModelAvailable: Bool,
    environment: ModelDeploymentEnvironment
) throws -> ModelRouteRequest {
    try ModelRouteRequest(
        capability: .transcription,
        dataClassification: .restricted,
        offlineMode: true,
        organizationAllowsExternalProcessing: false,
        deploymentEnvironment: environment,
        destination: .localDevice,
        retentionPolicy: .localWorkspaceOnly,
        dataCategories: [.canonicalAudio],
        visibleUserAuthorization: false,
        localModelAvailable: localModelAvailable
    )
}

func providerMetadata() throws -> ProviderMetadata {
    try ProviderMetadata(
        providerIdentifier: "meetingbuddy-deterministic-transcription",
        modelIdentifier: "fixture-v1"
    )
}

func aiID<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
    StableID<Tag>(UUID(uuidString: String(format: "60000000-0000-0000-0000-%012d", suffix))!)
}

func aiInstant(_ milliseconds: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
}
