import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

public struct IntelligenceRouteOption:
    Identifiable,
    Hashable,
    Sendable
{
    public let selection: ProviderModelSelectionRecord?
    public let label: String
    public let detail: String
    public let isReady: Bool

    public var id: String {
        guard let selection else { return "disabled" }
        return [
            selection.providerIdentifier,
            selection.modelIdentifier
        ].joined(separator: ":")
    }
}

@MainActor
@Observable
public final class IntelligenceConfigurationStore {
    public private(set) var state:
        IntelligenceConfigurationState?
    public private(set) var localSpeechModel =
        LocalSpeechModelSnapshot(
            languageTag: "en",
            resolvedLocaleIdentifier: nil,
            phase: .supported
        )
    public private(set) var isWorking = false
    public private(set) var safeErrorMessage: String?

    @ObservationIgnored
    private let repository:
        any IntelligenceConfigurationRepository
    @ObservationIgnored
    private let secretStore: any SecretStore
    @ObservationIgnored
    private let connectionTester:
        any RemoteProviderConnectionTesting
    @ObservationIgnored
    private let localModelManager:
        any LocalSpeechModelManaging
    @ObservationIgnored
    private let now: @Sendable () throws -> UTCInstant
    @ObservationIgnored
    private var modelObservationTask: Task<Void, Never>?

    public init(
        repository:
            any IntelligenceConfigurationRepository,
        secretStore: any SecretStore,
        connectionTester:
            any RemoteProviderConnectionTesting,
        localModelManager:
            any LocalSpeechModelManaging,
        now:
            @escaping @Sendable () throws -> UTCInstant = {
                try UTCInstant(
                    millisecondsSinceUnixEpoch:
                        Int64(
                            (
                                Date().timeIntervalSince1970
                                    * 1_000
                            ).rounded(.down)
                        )
                )
            }
    ) {
        self.repository = repository
        self.secretStore = secretStore
        self.connectionTester = connectionTester
        self.localModelManager = localModelManager
        self.now = now
        do {
            state = try repository.load()
        } catch {
            state = nil
            safeErrorMessage = safeMessage(for: error)
        }
        let events = localModelManager.events
        modelObservationTask =
            Task { @MainActor [weak self] in
                for await snapshot in events {
                    guard !Task.isCancelled,
                          let self
                    else { return }
                    localSpeechModel = snapshot
                }
            }
        Task { [weak self] in
            await self?.refreshLocalSpeechModel()
        }
    }

    deinit {
        modelObservationTask?.cancel()
    }

    public var remoteSpeechProviders:
        [RemoteProviderConfiguration]
    {
        state?.providers.filter {
            $0.purpose == .speechToText
        } ?? []
    }

    public var remoteTextProviders:
        [RemoteProviderConfiguration]
    {
        state?.providers.filter {
            $0.purpose == .textIntelligence
        } ?? []
    }

    public func reload() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            state = try repository.load()
            safeErrorMessage = nil
            await refreshLocalSpeechModel()
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func refreshLocalSpeechModel() async {
        let language = state?.defaultSpeechLanguageTag
            ?? localSpeechModel.languageTag
        localSpeechModel = await localModelManager.snapshot(
            languageTag: language
        )
    }

    public func setDefaultSpeechLanguage(
        _ languageTag: String
    ) async {
        await mutate { current in
            try current.replacing(
                defaultSpeechLanguageTag: languageTag
            )
        }
        await refreshLocalSpeechModel()
    }

    public func installLocalSpeechModel() async {
        guard let state, !isWorking else { return }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            try await localModelManager.install(
                languageTag:
                    state.defaultSpeechLanguageTag
            )
            await refreshLocalSpeechModel()
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func pauseLocalSpeechDownload() async {
        await localModelManager.pauseDownload()
    }

    public func resumeLocalSpeechDownload() async {
        await localModelManager.resumeDownload()
    }

    public func cancelLocalSpeechDownload() async {
        await localModelManager.cancelDownload()
        await refreshLocalSpeechModel()
    }

    public func releaseLocalSpeechModel() async {
        guard let state, !isWorking else { return }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            try await localModelManager.release(
                languageTag:
                    state.defaultSpeechLanguageTag
            )
            await refreshLocalSpeechModel()
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func configureOpenAISpeechProvider(
        modelIdentifier: String,
        apiKey: String
    ) async -> Bool {
        await configure(
            try? RemoteProviderConfiguration
                .openAISpeechToText(
                    modelIdentifier: modelIdentifier
                ),
            apiKey: apiKey
        )
    }

    public func configureOpenAITextProvider(
        modelIdentifier: String,
        apiKey: String
    ) async -> Bool {
        await configure(
            try? RemoteProviderConfiguration.openAIText(
                modelIdentifier: modelIdentifier
            ),
            apiKey: apiKey
        )
    }

    public func testProvider(
        identifier: String
    ) async {
        guard let state,
              let configuration = state.providers.first(
                  where: { $0.identifier == identifier }
              ),
              !isWorking
        else { return }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            let secretID = try configuration.secretIdentifier
            guard let key = try secretStore.read(secretID)
            else {
                throw IntelligenceConfigurationError
                    .credentialUnavailable
            }
            let result = await connectionTester.test(
                configuration: configuration,
                apiKey: key
            )
            let tested = try configuration
                .recordingConnectionResult(
                    result,
                    testedAt: try now()
                )
            var providers = state.providers
            guard let index = providers.firstIndex(
                where: {
                    $0.identifier == identifier
                }
            ) else { return }
            providers[index] = tested
            let next = try state.replacing(
                providers: providers
            )
            try repository.save(
                next,
                expectedRevision: state.revision
            )
            self.state = next
            if result != .ready {
                safeErrorMessage =
                    IntelligenceConfigurationError
                    .connectionFailed(result)
                    .errorDescription
            }
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    public func removeProvider(
        identifier: String
    ) async {
        guard let state,
              let removed = state.providers.first(
                  where: { $0.identifier == identifier }
              )
        else { return }
        let providers = state.providers.filter {
            $0.identifier != identifier
        }
        let routes = state.routes.map { route in
            guard route.selection?.providerIdentifier
                    == identifier
            else { return route }
            return IntelligenceTaskRouteSetting(
                task: route.task,
                selection: nil
            )
        }
        await mutate { current in
            guard current.revision == state.revision else {
                throw IntelligenceConfigurationError
                    .revisionConflict
            }
            return try current.replacing(
                providers: providers,
                routes: routes
            )
        }
        guard self.state?.revision == state.revision + 1,
              !providers.contains(where: {
                  $0.credentialAccount
                      == removed.credentialAccount
              })
        else { return }
        do {
            try secretStore.remove(
                removed.secretIdentifier
            )
        } catch {
            safeErrorMessage =
                "The provider was removed, but BlueMinutes could not remove its orphaned Keychain item."
        }
    }

    public func setRoute(
        task: RoutedTask,
        optionID: String
    ) async {
        guard let current = state else { return }
        let option = routeOptions(
            for: task,
            codexConnected: true
        ).first { $0.id == optionID }
        guard let option else {
            safeErrorMessage =
                "The selected provider does not support this task."
            return
        }
        let routes = current.routes.map {
            $0.task == task
                ? IntelligenceTaskRouteSetting(
                    task: task,
                    selection: option.selection
                )
                : $0
        }
        await mutate { state in
            try state.replacing(routes: routes)
        }
    }

    public func useRecommendedRouting(
        codexConnected: Bool
    ) async {
        guard let current = state else { return }
        let readySpeech = current.providers.first {
            $0.purpose == .speechToText
                && $0.connectionState == .ready
        }
        let readyText = current.providers.first {
            $0.purpose == .textIntelligence
                && $0.connectionState == .ready
        }
        let speechSelection:
            ProviderModelSelectionRecord? =
            localSpeechModel.phase == .installed
            ? ProviderModelSelectionRecord(
                providerIdentifier: "apple-speech",
                modelIdentifier:
                    "speech-analyzer-installed"
            )
            : readySpeech.map {
                ProviderModelSelectionRecord(
                    providerIdentifier: $0.identifier,
                    modelIdentifier: $0.modelIdentifier
                )
            }
        let textSelection:
            ProviderModelSelectionRecord? =
            codexConnected
            ? ProviderModelSelectionRecord(
                providerIdentifier:
                    "codex-subscription",
                modelIdentifier: "codex-default"
            )
            : readyText.map {
                ProviderModelSelectionRecord(
                    providerIdentifier: $0.identifier,
                    modelIdentifier: $0.modelIdentifier
                )
            }

        let routes = RoutedTask.allCases.map { task in
            let selection:
                ProviderModelSelectionRecord?
            switch task {
            case .speechToTextBatch:
                selection = speechSelection
            case .speechToTextRealtime:
                selection = readySpeech.flatMap {
                    $0.capabilities.contains(
                        .speechToTextRealtime
                    )
                    ? ProviderModelSelectionRecord(
                        providerIdentifier: $0.identifier,
                        modelIdentifier:
                            $0.modelIdentifier
                    )
                    : nil
                }
            case .speakerProcessing:
                selection = readySpeech.flatMap {
                    $0.capabilities.contains(
                        .speakerProcessing
                    )
                    ? ProviderModelSelectionRecord(
                        providerIdentifier: $0.identifier,
                        modelIdentifier:
                            $0.modelIdentifier
                    )
                    : nil
                }
            case .translation,
                 .textAnalysis,
                 .summaryAndMinutes,
                 .meetingChat,
                 .documentQuery,
                 .externalResearch:
                selection = textSelection
            }
            return IntelligenceTaskRouteSetting(
                task: task,
                selection: selection
            )
        }
        await mutate { state in
            try state.replacing(routes: routes)
        }
    }

    public func routeOptions(
        for task: RoutedTask,
        codexConnected: Bool
    ) -> [IntelligenceRouteOption] {
        var options = [
            IntelligenceRouteOption(
                selection: nil,
                label: task.isSpeechToText
                    ? "None / Record only"
                    : "None",
                detail: "No fallback",
                isReady: true
            )
        ]
        if task == .speechToTextBatch {
            options.append(
                IntelligenceRouteOption(
                    selection:
                        ProviderModelSelectionRecord(
                            providerIdentifier:
                                "apple-speech",
                            modelIdentifier:
                                "speech-analyzer-installed"
                        ),
                    label: "Apple On-Device Speech",
                    detail:
                        "Local · no API billing · \(localSpeechModel.phase == .installed ? "Ready" : "Model missing")",
                    isReady:
                        localSpeechModel.phase == .installed
                )
            )
        }
        if !task.isSpeechToText,
           task != .speakerProcessing
        {
            options.append(
                IntelligenceRouteOption(
                    selection:
                        ProviderModelSelectionRecord(
                            providerIdentifier:
                                "codex-subscription",
                            modelIdentifier:
                                "codex-default"
                        ),
                    label:
                        "Codex with ChatGPT Subscription",
                    detail:
                        "Selected text · subscription · \(codexConnected ? "Ready" : "Not connected")",
                    isReady: codexConnected
                )
            )
        }
        for provider in state?.providers ?? [] {
            guard let profile = try? provider
                    .providerProfile(),
                  profile.model(
                      identifier:
                        provider.modelIdentifier
                  )?.capabilities.isDisjoint(
                      with: task.acceptedCapabilities
                  ) == false
            else { continue }
            options.append(
                IntelligenceRouteOption(
                    selection:
                        ProviderModelSelectionRecord(
                            providerIdentifier:
                                provider.identifier,
                            modelIdentifier:
                                provider.modelIdentifier
                        ),
                    label:
                        "\(provider.displayName) · \(provider.modelDisplayName)",
                    detail:
                        "\(provider.purpose == .speechToText ? "Audio upload" : "Text upload") · user API billing · \(provider.connectionState == .ready ? "Ready" : "Needs test")",
                    isReady:
                        provider.connectionState == .ready
                )
            )
        }
        return options
    }

    public func selectedOptionID(
        for task: RoutedTask
    ) -> String {
        guard let selection = state?.route(
            for: task
        ).selection else {
            return "disabled"
        }
        return [
            selection.providerIdentifier,
            selection.modelIdentifier
        ].joined(separator: ":")
    }

    public func clearError() {
        safeErrorMessage = nil
    }

    private func configure(
        _ configuration: RemoteProviderConfiguration?,
        apiKey: String
    ) async -> Bool {
        guard let configuration,
              let current = state,
              !isWorking
        else {
            safeErrorMessage =
                "Choose a capability-verified provider model."
            return false
        }
        let normalizedKey = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedKey == apiKey,
              (16...1_024).contains(
                  normalizedKey.utf8.count
              ),
              !normalizedKey.unicodeScalars.contains(
                  where: CharacterSet.controlCharacters
                      .contains
              )
        else {
            safeErrorMessage =
                "Enter a bounded API key without surrounding whitespace."
            return false
        }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            let identifier = try configuration
                .secretIdentifier
            let previous = try secretStore.read(identifier)
            try secretStore.write(
                Data(normalizedKey.utf8),
                for: identifier
            )
            var providers = current.providers.filter {
                $0.identifier != configuration.identifier
            }
            providers.append(configuration)
            let next = try current.replacing(
                providers: providers
            )
            do {
                try repository.save(
                    next,
                    expectedRevision:
                        current.revision
                )
            } catch {
                if let previous {
                    try? secretStore.write(
                        previous,
                        for: identifier
                    )
                } else {
                    try? secretStore.remove(identifier)
                }
                throw error
            }
            state = next
            return true
        } catch {
            safeErrorMessage = safeMessage(for: error)
            return false
        }
    }

    private func mutate(
        _ change:
            (IntelligenceConfigurationState) throws
                -> IntelligenceConfigurationState
    ) async {
        guard let current = state, !isWorking else {
            return
        }
        isWorking = true
        safeErrorMessage = nil
        defer { isWorking = false }
        do {
            let next = try change(current)
            try repository.save(
                next,
                expectedRevision: current.revision
            )
            state = next
        } catch {
            safeErrorMessage = safeMessage(for: error)
        }
    }

    private func safeMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription
        {
            return description
        }
        return "BlueMinutes could not safely update Intelligence settings."
    }
}
