import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite
struct IntelligenceConfigurationContractTests {
    @Test
    func compiledDefaultDisablesEveryTaskExplicitly()
        throws
    {
        let state = try IntelligenceConfigurationState
            .compiledDefault()

        #expect(state.schemaVersion == 1)
        #expect(state.revision == 0)
        #expect(
            state.routes.map(\.task)
                == RoutedTask.allCases.sorted {
                    $0.rawValue < $1.rawValue
                }
        )
        #expect(
            state.routes.allSatisfy {
                $0.selection == nil
            }
        )
    }

    @Test
    func verifiedRemoteSpeechModelsNeverGrantTextCapabilities()
        throws
    {
        for descriptor in
            OpenAIModelCapabilityCatalog.speechModels
        {
            let configuration = try
                RemoteProviderConfiguration
                .openAISpeechToText(
                    modelIdentifier:
                        descriptor.identifier
                )
            let profile = try configuration
                .providerProfile()
            #expect(profile.kind == .remoteAPI)
            #expect(profile.dataRoute == .userAPIAudio)
            #expect(
                profile.capabilities.isDisjoint(
                    with: [
                        .textAnalysis,
                        .meetingChat,
                        .externalResearch
                    ]
                )
            )
            #expect(
                !profile.capabilities.contains(
                    .structuredOutput
                )
            )
        }
    }

    @Test
    func speechRoutingRejectsCodexAndTextOnlyAPI()
        throws
    {
        let textProvider = try
            RemoteProviderConfiguration.openAIText(
                modelIdentifier: "gpt-5.6-terra"
            )
        let defaultState = try
            IntelligenceConfigurationState
            .compiledDefault()
        #expect(throws: (any Error).self) {
            _ = try defaultState.replacing(
                providers: [textProvider],
                routes: defaultState.routes.map {
                    $0.task == .speechToTextBatch
                        ? IntelligenceTaskRouteSetting(
                            task: .speechToTextBatch,
                            selection:
                                ProviderModelSelectionRecord(
                                    providerIdentifier:
                                        "openai-text",
                                    modelIdentifier:
                                        "gpt-5.6-terra"
                                )
                        )
                        : $0
                }
            )
        }
        #expect(
            try defaultState.registry()
                .eligibleModels(
                    for: .speechToTextBatch
                )
                .contains(
                    ProviderModelSelection(
                        providerIdentifier:
                            "codex-subscription",
                        modelIdentifier:
                            "codex-default"
                    )
                ) == false
        )
    }

    @Test
    func remoteSpeechConfigurationRoundTripsWithoutASecret()
        throws
    {
        let provider = try
            RemoteProviderConfiguration
            .openAISpeechToText(
                modelIdentifier: "whisper-1"
            )
            .recordingConnectionResult(
                .ready,
                testedAt: try UTCInstant(
                    millisecondsSinceUnixEpoch: 1_000
                )
            )
        let original = try
            IntelligenceConfigurationState(
                revision: 7,
                defaultSpeechLanguageTag: "en",
                providers: [provider],
                routes: RoutedTask.allCases.map {
                    IntelligenceTaskRouteSetting(
                        task: $0,
                        selection:
                            $0 == .speechToTextBatch
                            ? ProviderModelSelectionRecord(
                                providerIdentifier:
                                    provider.identifier,
                                modelIdentifier:
                                    provider.modelIdentifier
                            )
                            : nil
                    )
                }
            )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let text = try #require(
            String(data: data, encoding: .utf8)
        )

        #expect(!text.lowercased().contains("api_key"))
        #expect(!text.contains("sk-"))
        #expect(
            try JSONDecoder().decode(
                IntelligenceConfigurationState.self,
                from: data
            ) == original
        )
    }

    @Test
    func unverifiedModelIdentifiersCannotManufactureCapabilities()
    {
        #expect(throws: (any Error).self) {
            _ = try RemoteProviderConfiguration
                .openAISpeechToText(
                    modelIdentifier:
                        "codex-default"
                )
        }
        #expect(throws: (any Error).self) {
            _ = try RemoteProviderConfiguration
                .openAIText(
                    modelIdentifier:
                        "whisper-1"
                )
        }
    }
}
