import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct IntelligenceConfigurationStoreTests {
    @Test @MainActor
    func remoteProvidersKeepSecretsSeparateAndRouteOnlyEligibleTasks()
        async throws
    {
        let repository =
            try IntelligenceConfigurationRepositoryProbe()
        let secrets = IntelligenceSecretStoreProbe()
        let tester = IntelligenceConnectionTesterProbe(
            result: .ready
        )
        let modelManager = LocalSpeechModelManagerProbe(
            snapshot: LocalSpeechModelSnapshot(
                languageTag: "en",
                resolvedLocaleIdentifier: "en-US",
                phase: .supported
            )
        )
        let store = IntelligenceConfigurationStore(
            repository: repository,
            secretStore: secrets,
            connectionTester: tester,
            localModelManager: modelManager,
            now: {
                try UTCInstant(
                    millisecondsSinceUnixEpoch: 1_722_188_800_000
                )
            }
        )
        await store.refreshLocalSpeechModel()

        let speechKey = "speech-test-key-0001"
        let speechConfigured =
            await store.configureOpenAISpeechProvider(
                modelIdentifier:
                    "gpt-4o-transcribe-diarize",
                apiKey: speechKey
            )
        #expect(speechConfigured)
        await store.testProvider(identifier: "openai-stt")

        let speech = try #require(
            store.state?.providers.first {
                $0.identifier == "openai-stt"
            }
        )
        #expect(speech.connectionState == .ready)
        #expect(
            secrets.value(for: try speech.secretIdentifier)
                == Data(speechKey.utf8)
        )
        #expect(
            try JSONEncoder().encode(
                #require(store.state)
            ).contains(Data(speechKey.utf8)) == false
        )

        let textKey = "text-test-key-000002"
        let textConfigured =
            await store.configureOpenAITextProvider(
                modelIdentifier: "gpt-5.6-terra",
                apiKey: textKey
            )
        #expect(textConfigured)
        await store.testProvider(identifier: "openai-text")
        let text = try #require(
            store.state?.providers.first {
                $0.identifier == "openai-text"
            }
        )
        #expect(
            speech.credentialAccount
                == text.credentialAccount
        )
        #expect(
            secrets.value(for: try text.secretIdentifier)
                == Data(textKey.utf8)
        )

        await store.useRecommendedRouting(
            codexConnected: false
        )
        #expect(
            store.state?.route(for: .speechToTextBatch)
                .selection?.providerIdentifier
                == "openai-stt"
        )
        #expect(
            store.state?.route(for: .summaryAndMinutes)
                .selection?.providerIdentifier
                == "openai-text"
        )
        let speechOptions = store.routeOptions(
            for: .speechToTextBatch,
            codexConnected: true
        )
        #expect(
            speechOptions.allSatisfy {
                $0.selection?.providerIdentifier
                    != "codex-subscription"
            }
        )
        #expect(
            speechOptions.allSatisfy {
                !$0.label.localizedCaseInsensitiveContains(
                    "Codex"
                )
            }
        )

        await store.removeProvider(
            identifier: "openai-stt"
        )
        #expect(
            secrets.value(for: try text.secretIdentifier)
                == Data(textKey.utf8)
        )
        #expect(
            store.state?.route(for: .speechToTextBatch)
                .selection == nil
        )
        await store.removeProvider(
            identifier: "openai-text"
        )
        #expect(
            secrets.value(for: try text.secretIdentifier)
                == nil
        )
        #expect(
            store.state?.route(for: .summaryAndMinutes)
                .selection == nil
        )
    }

    @Test @MainActor
    func installedLocalSpeechModelTakesRecommendedBatchPriority()
        async throws
    {
        let testedAt = try UTCInstant(
            millisecondsSinceUnixEpoch: 1_722_188_800_000
        )
        let remote = try
            RemoteProviderConfiguration
            .openAISpeechToText(
                modelIdentifier: "whisper-1"
            )
            .recordingConnectionResult(
                .ready,
                testedAt: testedAt
            )
        let initial = try IntelligenceConfigurationState
            .compiledDefault()
            .replacing(providers: [remote])
        let repository =
            try IntelligenceConfigurationRepositoryProbe(
                state: initial
            )
        let store = IntelligenceConfigurationStore(
            repository: repository,
            secretStore: IntelligenceSecretStoreProbe(),
            connectionTester:
                IntelligenceConnectionTesterProbe(
                    result: .ready
                ),
            localModelManager:
                LocalSpeechModelManagerProbe(
                    snapshot: LocalSpeechModelSnapshot(
                        languageTag: "en",
                        resolvedLocaleIdentifier: "en-US",
                        phase: .installed,
                        completedUnitCount: 1,
                        totalUnitCount: 1,
                        isReserved: true
                    )
                )
        )
        await store.refreshLocalSpeechModel()

        await store.useRecommendedRouting(
            codexConnected: false
        )

        #expect(
            store.state?.route(for: .speechToTextBatch)
                .selection
                == ProviderModelSelectionRecord(
                    providerIdentifier: "apple-speech",
                    modelIdentifier:
                        "speech-analyzer-installed"
                )
        )
        #expect(
            store.state?.route(for: .speechToTextRealtime)
                .selection == nil
        )
    }

    @Test @MainActor
    func failedMetadataSaveRestoresThePreviousKeychainValue()
        async throws
    {
        let repository =
            try IntelligenceConfigurationRepositoryProbe()
        let secrets = IntelligenceSecretStoreProbe()
        let configuration =
            try RemoteProviderConfiguration.openAIText(
                modelIdentifier: "gpt-5.6-sol"
            )
        let identifier = try configuration.secretIdentifier
        let previous = Data("previous-test-key-01".utf8)
        try secrets.write(previous, for: identifier)
        repository.failNextSave()
        let store = IntelligenceConfigurationStore(
            repository: repository,
            secretStore: secrets,
            connectionTester:
                IntelligenceConnectionTesterProbe(
                    result: .ready
                ),
            localModelManager:
                LocalSpeechModelManagerProbe(
                    snapshot: LocalSpeechModelSnapshot(
                        languageTag: "en",
                        resolvedLocaleIdentifier: "en-US",
                        phase: .supported
                    )
                )
        )

        let configured =
            await store.configureOpenAITextProvider(
                modelIdentifier: "gpt-5.6-sol",
                apiKey: "replacement-test-key"
            )

        #expect(configured == false)
        #expect(secrets.value(for: identifier) == previous)
        #expect(store.state?.providers.isEmpty == true)
        #expect(store.safeErrorMessage != nil)
    }

    @Test @MainActor
    func codexCannotBePersistedAsASpeechToTextRoute()
        async throws
    {
        let store = IntelligenceConfigurationStore(
            repository:
                try IntelligenceConfigurationRepositoryProbe(),
            secretStore: IntelligenceSecretStoreProbe(),
            connectionTester:
                IntelligenceConnectionTesterProbe(
                    result: .ready
                ),
            localModelManager:
                LocalSpeechModelManagerProbe(
                    snapshot: LocalSpeechModelSnapshot(
                        languageTag: "en",
                        resolvedLocaleIdentifier: "en-US",
                        phase: .supported
                    )
                )
        )

        await store.setRoute(
            task: .speechToTextBatch,
            optionID:
                "codex-subscription:codex-default"
        )

        #expect(
            store.state?.route(for: .speechToTextBatch)
                .selection == nil
        )
        #expect(
            store.safeErrorMessage
                == "The selected provider does not support this task."
        )
    }
}

private enum IntelligenceConfigurationProbeError: Error {
    case forcedSaveFailure
}

private final class IntelligenceConfigurationRepositoryProbe:
    IntelligenceConfigurationRepository,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var state: IntelligenceConfigurationState
    private var shouldFailNextSave = false

    init(
        state: IntelligenceConfigurationState? = nil
    ) throws {
        if let state {
            self.state = state
        } else {
            self.state =
                try IntelligenceConfigurationState
                .compiledDefault()
        }
    }

    func load() throws -> IntelligenceConfigurationState {
        lock.withLock { state }
    }

    func save(
        _ state: IntelligenceConfigurationState,
        expectedRevision: UInt64
    ) throws {
        try lock.withLock {
            if shouldFailNextSave {
                shouldFailNextSave = false
                throw IntelligenceConfigurationProbeError
                    .forcedSaveFailure
            }
            guard self.state.revision == expectedRevision
            else {
                throw IntelligenceConfigurationError
                    .revisionConflict
            }
            self.state = state
        }
    }

    func failNextSave() {
        lock.withLock {
            shouldFailNextSave = true
        }
    }
}

private final class IntelligenceSecretStoreProbe:
    SecretStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [SecretIdentifier: Data] = [:]

    func read(
        _ identifier: SecretIdentifier
    ) throws -> Data? {
        value(for: identifier)
    }

    func write(
        _ value: Data,
        for identifier: SecretIdentifier
    ) throws {
        lock.withLock {
            values[identifier] = value
        }
    }

    func remove(
        _ identifier: SecretIdentifier
    ) throws {
        _ = lock.withLock {
            values.removeValue(forKey: identifier)
        }
    }

    func value(
        for identifier: SecretIdentifier
    ) -> Data? {
        lock.withLock { values[identifier] }
    }
}

private actor IntelligenceConnectionTesterProbe:
    RemoteProviderConnectionTesting
{
    private let result: RemoteProviderConnectionState

    init(result: RemoteProviderConnectionState) {
        self.result = result
    }

    func test(
        configuration: RemoteProviderConfiguration,
        apiKey: Data
    ) -> RemoteProviderConnectionState {
        result
    }
}

private actor LocalSpeechModelManagerProbe:
    LocalSpeechModelManaging
{
    nonisolated let events:
        AsyncStream<LocalSpeechModelSnapshot>
    private var current: LocalSpeechModelSnapshot

    init(snapshot: LocalSpeechModelSnapshot) {
        current = snapshot
        events = AsyncStream { _ in }
    }

    func snapshot(
        languageTag: String
    ) -> LocalSpeechModelSnapshot {
        LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier:
                current.resolvedLocaleIdentifier,
            phase: current.phase,
            completedUnitCount:
                current.completedUnitCount,
            totalUnitCount: current.totalUnitCount,
            isReserved: current.isReserved
        )
    }

    func install(languageTag: String) {
        current = LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier:
                current.resolvedLocaleIdentifier,
            phase: .installed,
            completedUnitCount: 1,
            totalUnitCount: 1,
            isReserved: true
        )
    }

    func pauseDownload() {}

    func resumeDownload() {}

    func cancelDownload() {}

    func release(languageTag: String) {
        current = LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier:
                current.resolvedLocaleIdentifier,
            phase: .supported
        )
    }
}
