import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyAI

@Suite
struct OpenAIRemoteTranscriptionProviderTests {
    @Test
    func authorizedProviderMapsBoundedTimestampedSegments()
        async throws
    {
        let configuration =
            try readySpeechConfiguration(
                model: "whisper-1"
            )
        let transport = OpenAITranscriptionTransportProbe(
            response: OpenAITranscriptionResponse(
                text: "First. Second.",
                segments: [
                    .init(
                        startSeconds: 0.1,
                        endSeconds: 0.7,
                        text: "First.",
                        averageLogProbability: -0.1
                    ),
                    .init(
                        startSeconds: 0.8,
                        endSeconds: 1.4,
                        text: "Second.",
                        averageLogProbability: -0.2
                    )
                ],
                tokenLogProbabilities: []
            )
        )
        let provider = try
            OpenAIRemoteTranscriptionProvider(
                configuration: configuration,
                apiKey:
                    Data("test-api-key-0001".utf8),
                authorization:
                    remoteAudioAuthorization(),
                transport: transport
            )

        let result = try await provider.transcribe(
            transcriptionRequest(
                classification: .internal
            )
        )

        guard case let .speech(spans) = result else {
            Issue.record(
                "Expected timestamped speech."
            )
            return
        }
        #expect(spans.count == 2)
        #expect(spans.map(\.text) == ["First.", "Second."])
        #expect(spans[0].startMilliseconds == 100)
        #expect(spans[1].endMilliseconds == 1_000)
        #expect(
            provider.metadata.providerIdentifier
                == "openai-stt"
        )
        #expect(
            provider.metadata.modelIdentifier
                == "whisper-1"
        )
        #expect(provider.route == .approvedExternal)
        #expect(await transport.callCount() == 1)
    }

    @Test
    func unTimestampedResponseUsesOneBoundedChunkSpan()
        throws
    {
        let response = OpenAITranscriptionResponse(
            text: "Coarse bounded transcript",
            segments: [],
            tokenLogProbabilities: [-0.2, -0.3]
        )

        let result = try response.result(
            maximumDurationMilliseconds: 30_000
        )

        guard case let .speech(spans) = result else {
            Issue.record("Expected one coarse speech span.")
            return
        }
        #expect(spans.count == 1)
        #expect(spans[0].startMilliseconds == 0)
        #expect(spans[0].endMilliseconds == 30_000)
    }

    @Test
    func hugeFiniteTimestampsFailAsTypedInvalidResponses()
        throws
    {
        let response = OpenAITranscriptionResponse(
            text: "Must not overflow.",
            segments: [
                .init(
                    startSeconds: 1e308,
                    endSeconds: 1.1e308,
                    text: "Must not overflow.",
                    averageLogProbability: nil
                )
            ],
            tokenLogProbabilities: []
        )

        #expect(
            throws: AIProviderContractError.self
        ) {
            _ = try response.result(
                maximumDurationMilliseconds: 30_000
            )
        }
    }

    @Test
    func roundedInt64BoundaryCannotTrapTimestampConversion()
        throws
    {
        let response = OpenAITranscriptionResponse(
            text: "Must remain typed.",
            segments: [
                .init(
                    startSeconds: 0,
                    endSeconds:
                        Double(Int64.max)
                            / 1_000,
                    text: "Must remain typed.",
                    averageLogProbability: nil
                )
            ],
            tokenLogProbabilities: []
        )

        #expect(
            throws: AIProviderContractError.self
        ) {
            _ = try response.result(
                maximumDurationMilliseconds: 30_000
            )
        }
    }

    @Test
    func classificationDriftFailsBeforeTheTransport()
        async throws
    {
        let transport = OpenAITranscriptionTransportProbe(
            response: OpenAITranscriptionResponse(
                text: "Must not be used",
                segments: [],
                tokenLogProbabilities: []
            )
        )
        let provider = try
            OpenAIRemoteTranscriptionProvider(
                configuration:
                    try readySpeechConfiguration(
                        model: "whisper-1"
                    ),
                apiKey:
                    Data("test-api-key-0001".utf8),
                authorization:
                    remoteAudioAuthorization(),
                transport: transport
            )

        await #expect(
            throws: AIProviderContractError.self
        ) {
            _ = try await provider.transcribe(
                transcriptionRequest(
                    classification: .public
                )
            )
        }
        #expect(await transport.callCount() == 0)
    }

    @Test
    func remoteAudioRequiresFreshVisibleAuthorization()
        throws
    {
        let request = try remoteAudioRouteRequest(
            visibleUserAuthorization: false
        )
        let router = ModelPolicyRouter()

        #expect(
            try router.decide(request).route
                == .manualFallback
        )
        #expect(throws: AIProviderContractError.self) {
            _ = try router.authorizeExternal(
                request,
                expectedProviderIdentifier:
                    "openai-stt"
            )
        }
    }

    @Test
    func policyRouterRejectsSensitiveAudioBeforeJobConstruction()
        throws
    {
        let request =
            try remoteAudioRouteRequest(
                classification: .sensitive,
                visibleUserAuthorization: true
            )

        #expect(throws: AIProviderContractError.self) {
            _ = try ModelPolicyRouter()
                .authorizeExternal(
                    request,
                    expectedProviderIdentifier:
                        "openai-stt"
                )
        }
        #expect(
            try ModelPolicyRouter()
                .decide(request)
                .reasonCode
                == "external_route_denied"
        )
    }

    @Test
    func transcriptPlanStillRejectsForgedSensitiveExternalDecision()
        throws
    {
        let request =
            try remoteAudioRouteRequest(
                classification: .sensitive,
                visibleUserAuthorization: true
            )
        let forgedDecision = try ModelRouteDecision(
            route: .approvedExternal,
            providerIdentifier: "openai-stt",
            reasonCode: "forged_test_authorization",
            request: request
        )
        let configuration =
            try readySpeechConfiguration(
                model: "whisper-1"
            )

        #expect(throws: AIProviderContractError.self) {
            _ = try TranscriptPipelineJobPlan(
                meetingID: MeetingID(UUID()),
                canonicalSourceRevision:
                    SemanticRevisionReference(
                        logicalID:
                            SourceAssetID(UUID()),
                        revisionID:
                            RevisionID(UUID())
                    ),
                canonicalFrameCount: 16_000,
                speechSourceKind:
                    .originalSpeakerAudio,
                sourceLanguage:
                    LanguageTag("en"),
                targetLanguage: nil,
                dataClassification: .sensitive,
                createdAt: UTCInstant(
                    millisecondsSinceUnixEpoch:
                        1_722_188_800_000
                ),
                transcriptionRoute:
                    forgedDecision,
                transcriptionSelection:
                    ProviderModelSelectionRecord(
                        providerIdentifier:
                            configuration.identifier,
                        modelIdentifier:
                            configuration.modelIdentifier
                    ),
                remoteProviderConfiguration:
                    configuration,
                intelligenceConfigurationRevision:
                    9,
                translationRoute: nil
            )
        }
    }

    @Test
    func secureMultipartRequestPinsEndpointAndModelShape()
        throws
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "blueminutes-openai-request-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let audioURL = root.appendingPathComponent(
            "chunk.wav"
        )
        let syntheticWAV = Data(
            "RIFFsynthetic-bounded-wave".utf8
        )
        try syntheticWAV.write(to: audioURL)
        let apiKey = Data("test-api-key-0001".utf8)
        let input =
            OpenAITranscriptionTransportRequest(
                configuration:
                    try readySpeechConfiguration(
                        model:
                            "gpt-4o-transcribe-diarize"
                    ),
                apiKey: apiKey,
                audioURL: audioURL,
                language: try LanguageTag("en")
            )

        let request =
            try SecureOpenAITranscriptionTransport()
            .urlRequest(input)
        let body = try #require(
            request.httpBody.flatMap {
                String(
                    data: $0,
                    encoding: .isoLatin1
                )
            }
        )

        #expect(
            request.url?.absoluteString
                == "https://api.openai.com/v1/audio/transcriptions"
        )
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(
                forHTTPHeaderField:
                    "Authorization"
            ) == "Bearer test-api-key-0001"
        )
        #expect(
            body.contains(
                "gpt-4o-transcribe-diarize"
            )
        )
        #expect(body.contains("diarized_json"))
        #expect(body.contains("chunking_strategy"))
        #expect(body.contains("audio/wav"))
        #expect(!body.contains("test-api-key-0001"))
    }

    @Test
    func bundledConnectionSampleIsBoundedAndRequiresTheExpectedTranscript()
        throws
    {
        let sample = try
            BundledSTTConnectionSample.wavData()
        #expect(sample.count == 23_276)
        #expect(
            String(
                data: sample.prefix(4),
                encoding: .ascii
            ) == "RIFF"
        )
        #expect(
            OpenAIProviderConnectionTester
                .containsExpectedSampleTranscript(
                    Data(
                        #"{"text":"Blue Minutes test."}"#
                            .utf8
                    )
                )
        )
        #expect(
            OpenAIProviderConnectionTester
                .containsExpectedSampleTranscript(
                    Data(
                        #"{"text":"unrelated meeting content"}"#
                            .utf8
                    )
                ) == false
        )
        #expect(
            OpenAIProviderConnectionTester
                .containsExpectedSampleTranscript(
                    Data(
                        #"{"unexpected":"Blue Minutes test"}"#
                            .utf8
                    )
                ) == false
        )
    }

    @Test
    func remoteJobSnapshotPinsProviderModelAndCloudRoute()
        throws
    {
        let configuration =
            try readySpeechConfiguration(
                model: "whisper-1"
            )
        let authorization =
            try remoteAudioAuthorization()
        let selection =
            ProviderModelSelectionRecord(
                providerIdentifier:
                    configuration.identifier,
                modelIdentifier:
                    configuration.modelIdentifier
            )
        let plan = try TranscriptPipelineJobPlan(
            meetingID: MeetingID(UUID()),
            canonicalSourceRevision:
                SemanticRevisionReference(
                    logicalID:
                        SourceAssetID(UUID()),
                    revisionID: RevisionID(UUID())
                ),
            canonicalFrameCount: 32_000,
            speechSourceKind:
                .originalSpeakerAudio,
            sourceLanguage: LanguageTag("en"),
            targetLanguage: nil,
            dataClassification: .internal,
            createdAt: UTCInstant(
                millisecondsSinceUnixEpoch:
                    1_722_188_800_000
            ),
            transcriptionRoute:
                authorization.decision,
            transcriptionSelection: selection,
            remoteProviderConfiguration:
                configuration,
            intelligenceConfigurationRevision: 9,
            translationRoute: nil
        )

        let request =
            try TranscriptPipelineJobFactory()
            .request(
                plan: plan,
                requestedBy:
                    JobRequester("test-suite")
            )

        #expect(
            request.privacyRoute
                == .approvedCloud
        )
        #expect(
            request.inputPayload?.formatVersion
                == 2
        )
        #expect(
            try TranscriptPipelineJobPlan.decode(
                from: request.inputPayload
            ) == plan
        )
    }

    @Test
    func legacyVersionOneLocalPlanRemainsReadable()
        throws
    {
        let routeRequest = try ModelRouteRequest(
            capability: .transcription,
            dataClassification: .internal,
            offlineMode: true,
            organizationAllowsExternalProcessing:
                false,
            deploymentEnvironment: .test,
            destination: .localDevice,
            retentionPolicy: .localWorkspaceOnly,
            dataCategories: [.canonicalAudio],
            visibleUserAuthorization: false,
            localModelAvailable: true
        )
        let plan = try TranscriptPipelineJobPlan(
            meetingID: MeetingID(UUID()),
            canonicalSourceRevision:
                SemanticRevisionReference(
                    logicalID:
                        SourceAssetID(UUID()),
                    revisionID: RevisionID(UUID())
                ),
            canonicalFrameCount: 16_000,
            speechSourceKind:
                .originalSpeakerAudio,
            sourceLanguage: LanguageTag("en"),
            targetLanguage: nil,
            dataClassification: .internal,
            createdAt: UTCInstant(
                millisecondsSinceUnixEpoch:
                    1_722_188_800_000
            ),
            transcriptionRoute:
                ModelPolicyRouter().decide(
                    routeRequest
                ),
            translationRoute: nil
        )
        let encoded = try JSONEncoder().encode(plan)
        var object = try #require(
            JSONSerialization.jsonObject(
                with: encoded
            ) as? [String: Any]
        )
        object.removeValue(
            forKey: "transcriptionSelection"
        )
        object.removeValue(
            forKey:
                "remoteProviderConfiguration"
        )
        object.removeValue(
            forKey:
                "intelligenceConfigurationRevision"
        )
        let legacyData =
            try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        let legacyPayload = try JobInputPayload(
            formatIdentifier:
                TranscriptPipelineJobPlan
                .inputFormatIdentifier,
            formatVersion: 1,
            payload: legacyData
        )

        let decoded =
            try TranscriptPipelineJobPlan.decode(
                from: legacyPayload
            )

        #expect(
            decoded.transcriptionSelection
                == ProviderModelSelectionRecord(
                    providerIdentifier:
                        "meetingbuddy-deterministic-transcription",
                    modelIdentifier: "fixture-v1"
                )
        )
        #expect(
            decoded.chunkIdentities
                == plan.chunkIdentities
        )
        #expect(
            decoded.remoteProviderConfiguration
                == nil
        )
    }
}

private actor OpenAITranscriptionTransportProbe:
    OpenAITranscriptionTransport
{
    private let response:
        OpenAITranscriptionResponse
    private var calls = 0

    init(response: OpenAITranscriptionResponse) {
        self.response = response
    }

    func transcribe(
        _ request:
            OpenAITranscriptionTransportRequest
    ) -> OpenAITranscriptionResponse {
        calls += 1
        return response
    }

    func callCount() -> Int { calls }
}

private func readySpeechConfiguration(
    model: String
) throws -> RemoteProviderConfiguration {
    try RemoteProviderConfiguration
        .openAISpeechToText(
            modelIdentifier: model
        )
        .recordingConnectionResult(
            .ready,
            testedAt: try UTCInstant(
                millisecondsSinceUnixEpoch:
                    1_722_188_800_000
            )
        )
}

private func remoteAudioAuthorization()
    throws -> ExternalModelExecutionAuthorization
{
    try remoteAudioAuthorization(
        classification: .internal
    )
}

private func remoteAudioAuthorization(
    classification: DataClassification
) throws -> ExternalModelExecutionAuthorization {
    let request = try remoteAudioRouteRequest(
        classification: classification,
        visibleUserAuthorization: true
    )
    return try ModelPolicyRouter()
        .authorizeExternal(
            request,
            expectedProviderIdentifier:
                "openai-stt"
        )
}

private func remoteAudioRouteRequest(
    classification:
        DataClassification = .internal,
    visibleUserAuthorization: Bool
) throws -> ModelRouteRequest {
    let policy = try ModelSecurityPolicySnapshot(
        sensitivityLabelRevision:
            SemanticRevisionReference(
                logicalID:
                    SensitivityLabelID(UUID()),
                revisionID: RevisionID(UUID())
            ),
        accessPolicyRevision:
            SemanticRevisionReference(
                logicalID:
                    AccessPolicyID(UUID()),
                revisionID: RevisionID(UUID())
            ),
        effectiveClassification: classification,
        noOutboundMode: false,
        localProcessingAllowed: true,
        manualLocalReviewAllowed: true,
        externalProcessingAllowed: true,
        approvedExternalProviderIdentifiers: [
            "openai-stt"
        ],
        approvedDeploymentEnvironments: [
            .production
        ],
        approvedRetentionPolicies: [
            .approvedProviderRetention
        ]
    )
    let request = try ModelRouteRequest(
        capability: .transcription,
        dataClassification: classification,
        offlineMode: false,
        organizationAllowsExternalProcessing: true,
        deploymentEnvironment: .production,
        destination: .approvedProvider(
            identifier: "openai-stt"
        ),
        retentionPolicy:
            .approvedProviderRetention,
        dataCategories: [.canonicalAudio],
        visibleUserAuthorization:
            visibleUserAuthorization,
        localModelAvailable: false,
        securityPolicy: policy
    )
    return request
}

private func transcriptionRequest(
    classification: DataClassification
) throws -> TranscriptionRequest {
    let chunk = try #require(
        CanonicalChunkPlanner.plan(
            totalFrameCount: 16_000
        ).first
    )
    return try TranscriptionRequest(
        audio: TaskOwnedAudioChunk(
            fileURL: URL(
                fileURLWithPath:
                    "/tmp/blueminutes-probe.wav"
            ),
            plan: chunk
        ),
        canonicalSourceRevision:
            SemanticRevisionReference(
                logicalID: SourceAssetID(UUID()),
                revisionID: RevisionID(UUID())
            ),
        language: LanguageTag("en"),
        dataClassification: classification
    )
}
