import MeetingBuddyAI
import MeetingBuddyApplication
import SwiftUI

struct CodexIntelligenceSettingsPane: View {
    @Bindable var codexStore: CodexConnectionStore
    @Bindable var intelligenceStore:
        IntelligenceConfigurationStore
    @State private var speechModelIdentifier =
        OpenAIModelCapabilityCatalog.speechModels[0]
            .identifier
    @State private var textModelIdentifier =
        OpenAIModelCapabilityCatalog.textModels[0]
            .identifier
    @State private var speechAPIKey = ""
    @State private var textAPIKey = ""
    @State private var confirmLocalModelRelease = false

    var body: some View {
        Form {
            Section("Codex with ChatGPT Subscription") {
                LabeledContent("Status", value: statusLabel)
                if let version = codexStore.snapshot.runtimeVersion {
                    LabeledContent(
                        "Runtime",
                        value: "Codex \(version)"
                    )
                }
                if let source = codexStore.snapshot.runtimeSource {
                    LabeledContent(
                        "Source",
                        value: source.displayName
                    )
                }
                if let account = codexStore.snapshot.account {
                    LabeledContent(
                        "Account",
                        value: accountLabel(account)
                    )
                }
                if let quota = codexStore.snapshot.quota {
                    LabeledContent(
                        "Quota",
                        value: quotaLabel(quota)
                    )
                }

                HStack {
                    Button(connectButtonLabel) {
                        Task {
                            if codexStore.snapshot.phase == .disconnected
                                || codexStore.snapshot.phase == .runtimeMissing
                                || codexStore.snapshot.phase == .runtimeUntrusted
                                || codexStore.snapshot.phase
                                    == .runtimeIncompatible
                            {
                                await codexStore.connect()
                            } else {
                                await codexStore.reconnect()
                            }
                        }
                    }
                    .disabled(codexStore.isWorking)
                    .accessibilityIdentifier(
                        "blueminutes.settings.codex.connect"
                    )

                    Button("Test Connection") {
                        Task { await codexStore.testConnection() }
                    }
                    .disabled(codexStore.isWorking)
                    .accessibilityIdentifier(
                        "blueminutes.settings.codex.test"
                    )

                    if codexStore.snapshot.phase == .connected
                        || codexStore.snapshot.phase == .signedOut
                    {
                        Button("Disconnect") {
                            Task { await codexStore.disconnect() }
                        }
                        .disabled(codexStore.isWorking)
                    }

                    if codexStore.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if codexStore.isSignedOut {
                    HStack {
                        Button("Sign In in Browser") {
                            Task {
                                await codexStore.startBrowserLogin()
                            }
                        }
                        .disabled(codexStore.isWorking)

                        Button("Use Device Code") {
                            Task {
                                await codexStore.startDeviceCodeLogin()
                            }
                        }
                        .disabled(codexStore.isWorking)
                    }
                }

                if let challenge = codexStore.loginChallenge {
                    VStack(alignment: .leading, spacing: 6) {
                        Link(
                            challenge.kind == .browser
                                ? "Continue Official Sign-In"
                                : "Open Device Verification",
                            destination: challenge.verificationURL
                        )
                        if let code = challenge.userCode {
                            LabeledContent(
                                "Device code",
                                value: code
                            )
                            .textSelection(.enabled)
                        }
                        Button("Cancel Sign-In", role: .cancel) {
                            Task { await codexStore.cancelLogin() }
                        }
                        .disabled(codexStore.isWorking)
                    }
                }

                if codexStore.isConnected {
                    Button("Sign Out", role: .destructive) {
                        Task { await codexStore.logout() }
                    }
                    .disabled(codexStore.isWorking)
                }

                Text(
                    "Codex is used for text analysis, chat, research, and structured outputs. Speech-to-text must be configured separately with a local model or a remote STT API."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                LabeledContent(
                    "Speech-to-text",
                    value: "Configure separately"
                )
                LabeledContent("Audio access", value: "Never")
                LabeledContent(
                    "Billing",
                    value: "Uses the user's Codex subscription"
                )
            }

            Section("Speech-to-Text Setup") {
                LabeledContent(
                    "Current route",
                    value: routeLabel(
                        task: .speechToTextBatch
                    )
                )
                LabeledContent(
                    "Codex",
                    value: "Not used for speech-to-text"
                )
                Text(
                    "Recording and imported transcripts remain available. Codex is never offered as a speech-to-text provider."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Local STT Models") {
                    Picker(
                        "Language",
                        selection: Binding(
                            get: {
                                intelligenceStore.state?
                                    .defaultSpeechLanguageTag
                                    ?? "en"
                            },
                            set: { language in
                                Task {
                                    await intelligenceStore
                                        .setDefaultSpeechLanguage(
                                            language
                                        )
                                }
                            }
                        )
                    ) {
                        ForEach(
                            [
                                ("en", "English"),
                                ("es", "Spanish"),
                                ("fr", "French"),
                                ("de", "German"),
                                ("zh", "Chinese"),
                                ("ar", "Arabic"),
                                ("ru", "Russian"),
                                ("ja", "Japanese")
                            ],
                            id: \.0
                        ) {
                            Text($0.1).tag($0.0)
                        }
                    }

                    LabeledContent(
                        "Recommended model",
                        value:
                            "Apple On-Device Speech"
                    )
                    LabeledContent(
                        "Status",
                        value: localModelStatus
                    )
                    LabeledContent(
                        "Backend",
                        value: "macOS SpeechAnalyzer"
                    )
                    LabeledContent(
                        "Data route",
                        value: "Local on this Mac"
                    )
                    LabeledContent(
                        "Source and verification",
                        value:
                            "Apple system-managed signed asset"
                    )
                    LabeledContent(
                        "Storage",
                        value:
                            "Managed by macOS; custom location unavailable"
                    )
                    if let fraction =
                        intelligenceStore.localSpeechModel
                        .fractionCompleted
                    {
                        ProgressView(value: fraction)
                    }
                    HStack {
                        switch intelligenceStore
                            .localSpeechModel.phase
                        {
                        case .supported, .failed:
                            Button("Download") {
                                Task {
                                    await intelligenceStore
                                        .installLocalSpeechModel()
                                }
                            }
                        case .downloading:
                            Button("Pause") {
                                Task {
                                    await intelligenceStore
                                        .pauseLocalSpeechDownload()
                                }
                            }
                            Button("Cancel", role: .cancel) {
                                Task {
                                    await intelligenceStore
                                        .cancelLocalSpeechDownload()
                                }
                            }
                        case .paused:
                            Button("Resume") {
                                Task {
                                    await intelligenceStore
                                        .resumeLocalSpeechDownload()
                                }
                            }
                            Button("Cancel", role: .cancel) {
                                Task {
                                    await intelligenceStore
                                        .cancelLocalSpeechDownload()
                                }
                            }
                        case .installed:
                            Button(
                                "Release Model Reservation",
                                role: .destructive
                            ) {
                                confirmLocalModelRelease = true
                            }
                        case .unsupported:
                            Text(
                                "Requires macOS 26 and a supported Apple Speech locale."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(intelligenceStore.isWorking)
                    Text(
                        "Installing this model keeps audio on this Mac and does not use Codex quota. macOS controls download size, cache location, updates, and final asset reclamation."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                DisclosureGroup("Remote STT API") {
                    Picker(
                        "OpenAI speech model",
                        selection: $speechModelIdentifier
                    ) {
                        ForEach(
                            OpenAIModelCapabilityCatalog
                                .speechModels,
                            id: \.identifier
                        ) { model in
                            Text(model.displayName)
                                .tag(model.identifier)
                        }
                    }
                    SecureField(
                        "OpenAI API key",
                        text: $speechAPIKey
                    )
                    .textContentType(.password)
                    Button(
                        intelligenceStore
                            .remoteSpeechProviders.isEmpty
                            ? "Configure Remote STT API"
                            : "Replace Remote STT API"
                    ) {
                        let submittedKey = speechAPIKey
                        Task {
                            if await intelligenceStore
                                .configureOpenAISpeechProvider(
                                    modelIdentifier:
                                        speechModelIdentifier,
                                    apiKey: submittedKey
                                )
                            {
                                speechAPIKey = ""
                            }
                        }
                    }
                    .disabled(
                        intelligenceStore.isWorking
                            || speechAPIKey.isEmpty
                    )
                    ForEach(
                        intelligenceStore
                            .remoteSpeechProviders,
                        id: \.identifier
                    ) { provider in
                        providerControls(provider)
                    }
                    Text(
                        "Remote STT uploads audio to api.openai.com and is billed to the user's OpenAI API account. The API key is stored only in macOS Keychain. No connection test includes meeting content."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Bring Your Own API Key") {
                Picker(
                    "OpenAI text model",
                    selection: $textModelIdentifier
                ) {
                    ForEach(
                        OpenAIModelCapabilityCatalog
                            .textModels,
                        id: \.identifier
                    ) { model in
                        Text(model.displayName)
                            .tag(model.identifier)
                    }
                }
                SecureField(
                    "OpenAI API key",
                    text: $textAPIKey
                )
                .textContentType(.password)
                Button(
                    intelligenceStore.remoteTextProviders
                        .isEmpty
                        ? "Add Text API Provider"
                        : "Replace Text API Provider"
                ) {
                    let submittedKey = textAPIKey
                    Task {
                        if await intelligenceStore
                            .configureOpenAITextProvider(
                                modelIdentifier:
                                    textModelIdentifier,
                                apiKey: submittedKey
                            )
                        {
                            textAPIKey = ""
                        }
                    }
                }
                .disabled(
                    intelligenceStore.isWorking
                        || textAPIKey.isEmpty
                )
                ForEach(
                    intelligenceStore.remoteTextProviders,
                    id: \.identifier
                ) { provider in
                    providerControls(provider)
                }
                Text(
                    "Provider keys are stored only in macOS Keychain. The OpenAI speech and text entries share one Keychain credential without copying it into the routing configuration."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Task Routing") {
                Button("Use Recommended Routing") {
                    Task {
                        await intelligenceStore
                            .useRecommendedRouting(
                                codexConnected:
                                    codexStore.isConnected
                            )
                    }
                }
                .disabled(intelligenceStore.isWorking)

                ForEach(
                    RoutedTask.allCases,
                    id: \.rawValue
                ) { task in
                    Picker(
                        taskLabel(task),
                        selection: Binding(
                            get: {
                                intelligenceStore
                                    .selectedOptionID(
                                        for: task
                                    )
                            },
                            set: { optionID in
                                Task {
                                    await intelligenceStore
                                        .setRoute(
                                            task: task,
                                            optionID: optionID
                                        )
                                }
                            }
                        )
                    ) {
                        ForEach(
                            intelligenceStore.routeOptions(
                                for: task,
                                codexConnected:
                                    codexStore.isConnected
                            )
                        ) { option in
                            Text(
                                "\(option.label) — \(option.detail)"
                            )
                            .tag(option.id)
                            .disabled(!option.isReady)
                        }
                    }
                }
                Text(
                    "Every route stores one exact provider/model. Fallback remains off; unavailable tasks fail independently. Sensitive meetings re-check the local-only policy before execution."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .alert(
            "Codex",
            isPresented: Binding(
                get: { codexStore.safeErrorMessage != nil },
                set: { if !$0 { codexStore.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                codexStore.clearError()
            }
        } message: {
            Text(codexStore.safeErrorMessage ?? "")
        }
        .alert(
            "Intelligence Settings",
            isPresented: Binding(
                get: {
                    intelligenceStore.safeErrorMessage
                        != nil
                },
                set: {
                    if !$0 {
                        intelligenceStore.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                intelligenceStore.clearError()
            }
        } message: {
            Text(
                intelligenceStore.safeErrorMessage
                    ?? ""
            )
        }
        .confirmationDialog(
            "Release the local Speech model reservation?",
            isPresented: $confirmLocalModelRelease,
            titleVisibility: .visible
        ) {
            Button(
                "Release Reservation",
                role: .destructive
            ) {
                Task {
                    await intelligenceStore
                        .releaseLocalSpeechModel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "BlueMinutes will stop reserving this language model. macOS decides when the system-managed cached asset is physically reclaimed."
            )
        }
        .accessibilityIdentifier(
            "blueminutes.settings.intelligence"
        )
    }

    @ViewBuilder
    private func providerControls(
        _ provider: RemoteProviderConfiguration
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
                provider.displayName,
                value:
                    "\(provider.modelDisplayName) · \(provider.connectionState == .ready ? "Ready" : "Needs test")"
            )
            HStack {
                Button(
                    provider.purpose == .speechToText
                        ? "Test STT Sample"
                        : "Test Connection"
                ) {
                    Task {
                        await intelligenceStore
                            .testProvider(
                                identifier:
                                    provider.identifier
                            )
                    }
                }
                .disabled(intelligenceStore.isWorking)
                Button("Remove", role: .destructive) {
                    Task {
                        await intelligenceStore
                            .removeProvider(
                                identifier:
                                    provider.identifier
                            )
                    }
                }
                .disabled(intelligenceStore.isWorking)
            }
            if provider.purpose == .speechToText {
                Text(
                    "Testing sends only BlueMinutes' bundled synthetic “Blue Minutes test” WAV to this provider. It uses the user's API account and may incur a small provider charge; no meeting audio is used."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var localModelStatus: String {
        switch intelligenceStore.localSpeechModel.phase {
        case .unsupported:
            "Unsupported"
        case .supported:
            "Available to download"
        case .downloading:
            "Downloading"
        case .paused:
            "Paused"
        case .installed:
            intelligenceStore.localSpeechModel.isReserved
                ? "Installed and reserved"
                : "Installed"
        case .failed:
            "Download failed"
        }
    }

    private func routeLabel(task: RoutedTask) -> String {
        let id = intelligenceStore.selectedOptionID(
            for: task
        )
        return intelligenceStore.routeOptions(
            for: task,
            codexConnected: codexStore.isConnected
        ).first { $0.id == id }?.label
            ?? (task.isSpeechToText
                ? "Not configured / Record only"
                : "Not configured")
    }

    private func taskLabel(_ task: RoutedTask) -> String {
        switch task {
        case .speechToTextBatch:
            "Speech-to-Text · Batch"
        case .speechToTextRealtime:
            "Speech-to-Text · Realtime"
        case .speakerProcessing:
            "Speaker Processing"
        case .translation:
            "Translation"
        case .textAnalysis:
            "Text Analysis"
        case .summaryAndMinutes:
            "Summary & Minutes"
        case .meetingChat:
            "Meeting Chat"
        case .documentQuery:
            "Document Query"
        case .externalResearch:
            "External Research"
        }
    }

    private var statusLabel: String {
        switch codexStore.snapshot.phase {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .runtimeMissing:
            "Compatible runtime not found"
        case .runtimeUntrusted:
            "Runtime failed signature verification"
        case .runtimeIncompatible:
            "Runtime version is not supported"
        case .signedOut:
            "Runtime connected; sign-in required"
        case .connected:
            "Connected"
        case .failed:
            "Connection failed"
        }
    }

    private var connectButtonLabel: String {
        switch codexStore.snapshot.phase {
        case .disconnected,
             .runtimeMissing,
             .runtimeUntrusted,
             .runtimeIncompatible:
            "Connect"
        case .connecting,
             .signedOut,
             .connected,
             .failed:
            "Reconnect"
        }
    }

    private func accountLabel(
        _ account: CodexAccountState
    ) -> String {
        switch account {
        case .signedOut:
            "Signed out"
        case let .connected(plan):
            "\(planLabel(plan)) plan"
        }
    }

    private func quotaLabel(
        _ quota: CodexQuotaState
    ) -> String {
        if quota.isUnavailable {
            return "Unavailable"
        }
        if let primary = quota.primary {
            return "\(primary.usedPercent)% used"
        }
        if quota.creditsUnlimited == true {
            return "Unlimited"
        }
        return "Available"
    }

    private func planLabel(_ plan: CodexPlanType) -> String {
        switch plan {
        case .free:
            "Free"
        case .go:
            "Go"
        case .plus:
            "Plus"
        case .pro:
            "Pro"
        case .prolite:
            "Pro Lite"
        case .team:
            "Team"
        case .business:
            "Business"
        case .enterprise:
            "Enterprise"
        case .education:
            "Education"
        case .unknown:
            "Unknown"
        }
    }
}
