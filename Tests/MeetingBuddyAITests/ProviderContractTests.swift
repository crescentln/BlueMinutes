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
            localModelAvailable: false
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
            localModelAvailable: false
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
            localModelAvailable: false
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
            localModelAvailable: false
        )
        #expect(try router.decide(deniedRetention).route == .manualFallback)
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
    func keychainRoundTripsOpaqueSecretWithoutFilesystemStorage() throws {
        let store = MacOSKeychainSecretStore()
        let identifier = try SecretIdentifier(
            service: "com.meetingbuddy.tests.\(UUID().uuidString.lowercased())",
            account: "ephemeral"
        )
        defer { try? store.remove(identifier) }
        let value = Data("synthetic-secret-not-a-credential".utf8)
        try store.write(value, for: identifier)
        #expect(try store.read(identifier) == value)
        try store.remove(identifier)
        #expect(try store.read(identifier) == nil)
    }
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
