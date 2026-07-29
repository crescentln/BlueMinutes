import Foundation
@testable import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

struct ProviderRoutingContractTests {
    @Test
    func builtInRegistryKeepsCodexOutOfSpeechToText() throws {
        let registry =
            try BlueMinutesBuiltInProviders.registry()
        let speechOptions = registry.eligibleModels(for: .speechToTextBatch)
        let realtimeSpeechOptions = registry.eligibleModels(
            for: .speechToTextRealtime
        )
        let textOptions = registry.eligibleModels(for: .meetingChat)
        let analysisOptions = registry.eligibleModels(for: .textAnalysis)
        let researchOptions = registry.eligibleModels(
            for: .externalResearch
        )

        #expect(
            speechOptions
                == [
                    try ProviderModelSelection(
                        providerIdentifier: "apple-speech",
                        modelIdentifier: "speech-analyzer-installed"
                    )
                ]
        )
        #expect(realtimeSpeechOptions.isEmpty)
        #expect(
            textOptions.contains(
                try ProviderModelSelection(
                    providerIdentifier: "codex-subscription",
                    modelIdentifier: "codex-default"
                )
            )
        )
        #expect(
            analysisOptions.contains(
                try ProviderModelSelection(
                    providerIdentifier: "codex-subscription",
                    modelIdentifier: "codex-default"
                )
            )
        )
        #expect(
            researchOptions.allSatisfy {
                $0.providerIdentifier
                    != "codex-subscription"
            }
        )
    }

    @Test
    func providerProfilesRejectCodexOrTextAPIWithSpeechCapabilities() throws {
        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderProfile(
                identifier: "invalid-codex",
                displayName: "Invalid Codex",
                kind: .codexSubscription,
                dataRoute: .codexSubscriptionText,
                costOwner: .codexSubscription,
                models: [
                    ProviderModelProfile(
                        identifier: "invalid",
                        displayName: "Invalid",
                        capabilities: [.speechToTextBatch]
                    )
                ],
                requiresCredential: false
            )
        }

        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderProfile(
                identifier: "text-only-api",
                displayName: "Text Only API",
                kind: .remoteAPI,
                dataRoute: .userAPIText,
                costOwner: .userAPIAccount,
                models: [
                    ProviderModelProfile(
                        identifier: "misdeclared",
                        displayName: "Misdeclared",
                        capabilities: [.speechToTextRealtime]
                    )
                ],
                requiresCredential: true
            )
        }

        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderProfile(
                identifier: "mixed-audio-api",
                displayName: "Mixed Audio API",
                kind: .remoteAPI,
                dataRoute: .userAPIAudio,
                costOwner: .userAPIAccount,
                models: [
                    ProviderModelProfile(
                        identifier: "mixed",
                        displayName: "Mixed",
                        capabilities: [.speechToTextBatch, .meetingChat]
                    )
                ],
                requiresCredential: true
            )
        }
    }

    @Test
    func selectionsAndFallbacksRejectUnboundedOrAmbiguousIdentity() throws {
        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderModelSelection(
                providerIdentifier: "../provider",
                modelIdentifier: "model"
            )
        }
        #expect(throws: ProviderRoutingError.self) {
            let selection = try ProviderModelSelection(
                providerIdentifier: "codex-subscription",
                modelIdentifier: "codex-default"
            )
            _ = try TaskRoutePreference(
                task: .meetingChat,
                routeOverride: .selection(
                    primary: selection,
                    fallback: selection
                )
            )
        }

        let registry =
            try BlueMinutesBuiltInProviders.registry()
        let speechProvider = try #require(
            registry.provider(identifier: "apple-speech")
        )
        let speech = try #require(speechProvider.models.first)
        #expect(
            speech.capabilities
                == Set<ProviderCapability>([.speechToTextBatch])
        )
    }

    @Test
    func routingContextBindsOneExactMeetingWorkspaceAndPolicyGraph() throws {
        let securityPolicy = try routingSecurityPolicy(
            externalProviderIdentifiers: ["codex-subscription"]
        )
        let graph = try routingSecurityGraph(securityPolicy: securityPolicy)
        let context = try TaskRoutingSecurityContext(
            meeting: graph.meeting,
            sensitivityLabel: graph.sensitivityLabel,
            accessPolicy: graph.accessPolicy,
            securityPolicy: securityPolicy
        )
        #expect(context.workspaceID == routingWorkspaceID)
        #expect(context.meetingID == routingMeetingID)
        #expect(
            context.meetingRevision.logicalID.canonicalString
                == routingMeetingID.canonicalString
        )
        let widerSnapshot = try ModelSecurityPolicySnapshot(
            sensitivityLabelRevision:
                securityPolicy.sensitivityLabelRevision,
            accessPolicyRevision: securityPolicy.accessPolicyRevision,
            effectiveClassification:
                securityPolicy.effectiveClassification,
            noOutboundMode: false,
            localProcessingAllowed: true,
            manualLocalReviewAllowed: true,
            externalProcessingAllowed: true,
            approvedExternalProviderIdentifiers: [
                "codex-subscription",
                "unexpected-provider"
            ],
            approvedDeploymentEnvironments: [.production],
            approvedRetentionPolicies: [.noProviderRetention]
        )
        #expect(throws: ProviderRoutingError.self) {
            _ = try TaskRoutingSecurityContext(
                meeting: graph.meeting,
                sensitivityLabel: graph.sensitivityLabel,
                accessPolicy: graph.accessPolicy,
                securityPolicy: widerSnapshot
            )
        }

        let otherMeeting = try routingMeetingProfile(
            workspaceID: routingWorkspaceID,
            meetingID: MeetingID(
                UUID(
                    uuidString: "00000000-0000-0000-0000-000000000699"
                )!
            ),
            classification: .internal,
            externalProcessingAllowed: true
        )
        #expect(throws: DomainValidationError.self) {
            _ = try TaskRoutingSecurityContext(
                meeting: otherMeeting,
                sensitivityLabel: graph.sensitivityLabel,
                accessPolicy: graph.accessPolicy,
                securityPolicy: securityPolicy
            )
        }

        let unscopedGraph = try routingSecurityGraph(
            securityPolicy: securityPolicy,
            workspaceID: nil
        )
        #expect(throws: ProviderRoutingError.self) {
            _ = try TaskRoutingSecurityContext(
                meeting: unscopedGraph.meeting,
                sensitivityLabel: unscopedGraph.sensitivityLabel,
                accessPolicy: unscopedGraph.accessPolicy,
                securityPolicy: securityPolicy
            )
        }
    }

    @Test
    func defaultExternalPolicyRetainsUserConfirmationProvenance() throws {
        let meeting = try routingMeetingProfile(
            workspaceID: routingWorkspaceID,
            meetingID: routingMeetingID,
            classification: .internal,
            externalProcessingAllowed: true
        )
        let bundle = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: routingSensitivityLabelID,
            sensitivityLabelRevisionID:
                routingSensitivityLabelRevisionID,
            accessPolicyID: routingAccessPolicyID,
            accessPolicyRevisionID:
                routingAccessPolicyRevisionID,
            createdAt: routingCreatedAt,
            approvedExternalProviderIdentifiers: [
                CodexTextExecutionAuthorization
                    .providerIdentifier
            ]
        )

        #expect(bundle.accessPolicy.userConfirmed)
        #expect(bundle.accessPolicy.reviewStatus == .confirmed)
        #expect(bundle.accessPolicy.revision.createdBy == .user)
        #expect(
            bundle.accessPolicy
                .approvedExternalProviderIdentifiers
                == [
                    CodexTextExecutionAuthorization
                        .providerIdentifier
                ]
        )
        try SecurityPolicyGraphValidator.validate(
            meeting: meeting,
            sensitivityLabel: bundle.sensitivityLabel,
            accessPolicy: bundle.accessPolicy
        )
    }

    @Test
    func routingRequiresReadinessAndNeverSilentlyUsesFallback() throws {
        let registry = try BlueMinutesBuiltInProviders.registry()
        let route = try TaskRoutePreference(
            task: .summaryAndMinutes,
            routeOverride: .selection(
                primary: try ProviderModelSelection(
                    providerIdentifier: "codex-subscription",
                    modelIdentifier: "codex-default"
                ),
                fallback: try ProviderModelSelection(
                    providerIdentifier: "apple-foundation-models",
                    modelIdentifier: "system-language-model"
                )
            )
        )
        let profile = try TaskRoutingProfile(
            identifier: "recommended",
            displayName: "Recommended",
            scope: .global,
            routes: [route]
        )
        let securityPolicy = try routingSecurityPolicy(
            externalProviderIdentifiers: ["codex-subscription"]
        )
        let resolution = TaskRoutingResolver().resolve(
            task: .summaryAndMinutes,
            scopeStack: try routingScopeStack(
                global: profile,
                securityPolicy: securityPolicy
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "codex-subscription",
                        modelIdentifier: "codex-default",
                        state: .quotaUnavailable
                    ),
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "apple-foundation-models",
                        modelIdentifier: "system-language-model",
                        state: .ready
                    )
                ]
            )
        )

        #expect(
            resolution
                == .unavailable(
                    reasonCode: "provider_quota_unavailable",
                    repairSelection: try ProviderModelSelection(
                        providerIdentifier: "apple-foundation-models",
                        modelIdentifier: "system-language-model"
                    ),
                    origin: .global(profileIdentifier: "recommended")
                )
        )
    }

    @Test
    func repairCandidatesAreCapabilityAndSensitivePolicyFiltered() throws {
        let registry = try BlueMinutesBuiltInProviders.registry()
        let speechProfile = try TaskRoutingProfile(
            identifier: "speech-repair-filter",
            displayName: "Speech Repair Filter",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .speechToTextBatch,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier: "apple-speech",
                            modelIdentifier: "speech-analyzer-installed"
                        ),
                        fallback: ProviderModelSelection(
                            providerIdentifier: "codex-subscription",
                            modelIdentifier: "codex-default"
                        )
                    )
                )
            ]
        )
        let speechResult = TaskRoutingResolver().resolve(
            task: .speechToTextBatch,
            scopeStack: try routingScopeStack(
                global: speechProfile,
                securityPolicy: routingSecurityPolicy(
                    externalProviderIdentifiers: ["codex-subscription"]
                )
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "apple-speech",
                        modelIdentifier: "speech-analyzer-installed",
                        state: .notInstalled
                    )
                ]
            )
        )
        #expect(
            speechResult
                == .unavailable(
                    reasonCode: "provider_not_installed",
                    repairSelection: nil,
                    origin: .global(
                        profileIdentifier: "speech-repair-filter"
                    )
                )
        )

        let summaryProfile = try TaskRoutingProfile(
            identifier: "sensitive-repair-filter",
            displayName: "Sensitive Repair Filter",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .summaryAndMinutes,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier: "apple-foundation-models",
                            modelIdentifier: "system-language-model"
                        ),
                        fallback: ProviderModelSelection(
                            providerIdentifier: "codex-subscription",
                            modelIdentifier: "codex-default"
                        )
                    )
                )
            ]
        )
        let summaryResult = TaskRoutingResolver().resolve(
            task: .summaryAndMinutes,
            scopeStack: try routingScopeStack(
                global: summaryProfile,
                securityPolicy: routingSecurityPolicy(
                    classification: .sensitive,
                    noOutboundMode: true
                )
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "apple-foundation-models",
                        modelIdentifier: "system-language-model",
                        state: .notInstalled
                    )
                ]
            )
        )
        #expect(
            summaryResult
                == .unavailable(
                    reasonCode: "provider_not_installed",
                    repairSelection: nil,
                    origin: .global(
                        profileIdentifier: "sensitive-repair-filter"
                    )
                )
        )
    }

    @Test
    func recordOnlyAndSensitiveProfilesFailClosed() throws {
        let registry = try BlueMinutesBuiltInProviders.registry()
        let globalSpeech = try TaskRoutingProfile(
            identifier: "global-speech",
            displayName: "Global Speech",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .speechToTextBatch,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier: "apple-speech",
                            modelIdentifier: "speech-analyzer-installed"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        let recordOnlyMeeting = try TaskRoutingProfile(
            identifier: "meeting-record-only",
            displayName: "Meeting Record Only",
            scope: .meeting(meetingRevision: routingMeetingRevision),
            routes: [
                TaskRoutePreference(
                    task: .speechToTextBatch,
                    routeOverride: .disabled
                )
            ]
        )
        #expect(
            TaskRoutingResolver().resolve(
                task: .speechToTextBatch,
                scopeStack: try routingScopeStack(
                    global: globalSpeech,
                    meeting: recordOnlyMeeting,
                    securityPolicy: routingSecurityPolicy(noOutboundMode: true)
                ),
                registry: registry,
                runtime: try ProviderRuntimeRegistry(snapshots: [])
            )
                == .recordOnly(
                    origin: .meeting(
                        meetingID: routingMeetingID,
                        profileIdentifier: "meeting-record-only"
                    )
                )
        )
        let inheritingMeeting = try TaskRoutingProfile(
            identifier: "meeting-inherit",
            displayName: "Meeting Inherit",
            scope: .meeting(meetingRevision: routingMeetingRevision),
            routes: [
                TaskRoutePreference(
                    task: .speechToTextBatch,
                    routeOverride: .inherit
                )
            ]
        )
        let localSecurityPolicy = try routingSecurityPolicy(noOutboundMode: true)
        let inheritedResolution = TaskRoutingResolver().resolve(
            task: .speechToTextBatch,
            scopeStack: try routingScopeStack(
                global: globalSpeech,
                meeting: inheritingMeeting,
                securityPolicy: localSecurityPolicy
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "apple-speech",
                        modelIdentifier: "speech-analyzer-installed",
                        state: .ready
                    )
                ]
            )
        )
        guard case let .ready(inheritedRoute) = inheritedResolution else {
            Issue.record("An inherited STT route should resolve the global selection.")
            return
        }
        #expect(
            inheritedRoute.accessPolicyRevision
                == localSecurityPolicy.accessPolicyRevision
        )
        #expect(inheritedRoute.effectiveClassification == .internal)
        #expect(inheritedRoute.noOutboundMode)
        #expect(inheritedRoute.workspaceID == routingWorkspaceID)
        #expect(inheritedRoute.meetingID == routingMeetingID)
        #expect(
            inheritedRoute.meetingRevision.logicalID.canonicalString
                == routingMeetingID.canonicalString
        )
        #expect(
            inheritedRoute.routeOrigin
                == .global(profileIdentifier: "global-speech")
        )

        let sensitive = try TaskRoutingProfile(
            identifier: "sensitive",
            displayName: "Sensitive Meeting",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .meetingChat,
                    routeOverride: .selection(
                        primary: try ProviderModelSelection(
                            providerIdentifier: "codex-subscription",
                            modelIdentifier: "codex-default"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        #expect(
            TaskRoutingResolver().resolve(
                task: .meetingChat,
                scopeStack: try routingScopeStack(
                    global: sensitive,
                    securityPolicy: routingSecurityPolicy(
                        classification: .sensitive,
                        noOutboundMode: true
                    )
                ),
                registry: registry,
                runtime: try ProviderRuntimeRegistry(
                    snapshots: [
                        ProviderRuntimeSnapshot(
                            providerIdentifier: "codex-subscription",
                            modelIdentifier: "codex-default",
                            state: .ready
                        )
                    ]
                )
            )
                == .unavailable(
                    reasonCode: "sensitive_meeting_requires_local_provider",
                    repairSelection: nil,
                    origin: .global(profileIdentifier: "sensitive")
                )
        )
    }

    @Test
    func exactRuntimeReadinessRejectsDuplicatesAndModelAmbiguity() throws {
        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "provider",
                        modelIdentifier: "model-a",
                        state: .ready
                    ),
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "provider",
                        modelIdentifier: "model-a",
                        state: .invalidCredential
                    )
                ]
            )
        }

        let registry = try ProviderRegistry(
            providers: [
                ProviderProfile(
                    identifier: "multi-model",
                    displayName: "Multi Model",
                    kind: .localText,
                    dataRoute: .localOnly,
                    costOwner: .localDevice,
                    models: [
                        ProviderModelProfile(
                            identifier: "model-a",
                            displayName: "Model A",
                            capabilities: [.summaryAndMinutes]
                        ),
                        ProviderModelProfile(
                            identifier: "model-b",
                            displayName: "Model B",
                            capabilities: [.summaryAndMinutes]
                        )
                    ],
                    requiresCredential: false
                )
            ]
        )
        let profile = try TaskRoutingProfile(
            identifier: "exact-model",
            displayName: "Exact Model",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .summaryAndMinutes,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier: "multi-model",
                            modelIdentifier: "model-b"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        let localSecurityPolicy = try routingSecurityPolicy(noOutboundMode: true)
        let result = TaskRoutingResolver().resolve(
            task: .summaryAndMinutes,
            scopeStack: try routingScopeStack(
                global: profile,
                securityPolicy: localSecurityPolicy
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "multi-model",
                        modelIdentifier: "model-a",
                        state: .ready
                    ),
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "multi-model",
                        modelIdentifier: "model-b",
                        state: .notInstalled
                    )
                ]
            )
        )
        #expect(
            result
                == .unavailable(
                    reasonCode: "provider_not_installed",
                    repairSelection: nil,
                    origin: .global(profileIdentifier: "exact-model")
                )
        )
    }

    @Test
    func sensitiveMeetingDisablesResearchAndRejectsLocalResearchMetadata() throws {
        #expect(throws: ProviderRoutingError.self) {
            _ = try ProviderProfile(
                identifier: "invalid-local-research",
                displayName: "Invalid Local Research",
                kind: .localText,
                dataRoute: .localOnly,
                costOwner: .localDevice,
                models: [
                    ProviderModelProfile(
                        identifier: "invalid",
                        displayName: "Invalid",
                        capabilities: [.externalResearch]
                    )
                ],
                requiresCredential: false
            )
        }

        let builtIn =
            try BlueMinutesBuiltInProviders.registry()
        let registry = try ProviderRegistry(
            providers:
                builtIn.providers
                + [
                    ProviderProfile(
                        identifier: "research-api",
                        displayName: "Research API",
                        kind: .remoteAPI,
                        dataRoute: .userAPIText,
                        costOwner: .userAPIAccount,
                        models: [
                            ProviderModelProfile(
                                identifier:
                                    "research-model",
                                displayName:
                                    "Research Model",
                                capabilities:
                                    [.externalResearch]
                            )
                        ],
                        requiresCredential: true
                    )
                ]
        )
        let profile = try TaskRoutingProfile(
            identifier: "sensitive-research",
            displayName: "Sensitive Research",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .externalResearch,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier:
                                "research-api",
                            modelIdentifier:
                                "research-model"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        #expect(
            TaskRoutingResolver().resolve(
                task: .externalResearch,
                scopeStack: try routingScopeStack(
                    global: profile,
                    securityPolicy: routingSecurityPolicy(
                        classification: .sensitive,
                        noOutboundMode: true
                    )
                ),
                registry: registry,
                runtime: try ProviderRuntimeRegistry(
                    snapshots: [
                        ProviderRuntimeSnapshot(
                            providerIdentifier:
                                "research-api",
                            modelIdentifier:
                                "research-model",
                            state: .ready
                        )
                    ]
                )
            )
                == .unavailable(
                    reasonCode: "sensitive_meeting_disables_external_research",
                    repairSelection: nil,
                    origin: .global(profileIdentifier: "sensitive-research")
                )
        )
    }

    @Test
    func externalRouteRequiresExactProviderApprovalFromSecuritySnapshot() throws {
        let registry = try BlueMinutesBuiltInProviders.registry()
        let profile = try TaskRoutingProfile(
            identifier: "external-policy",
            displayName: "External Policy",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .meetingChat,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier: "codex-subscription",
                            modelIdentifier: "codex-default"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        let result = TaskRoutingResolver().resolve(
            task: .meetingChat,
            scopeStack: try routingScopeStack(
                global: profile,
                securityPolicy: routingSecurityPolicy(
                    externalProviderIdentifiers: ["different-provider"]
                )
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "codex-subscription",
                        modelIdentifier: "codex-default",
                        state: .ready
                    )
                ]
            )
        )
        #expect(
            result
                == .unavailable(
                    reasonCode: "security_policy_denies_external_provider",
                    repairSelection: nil,
                    origin: .global(profileIdentifier: "external-policy")
                )
        )

        let approvedCandidate = TaskRoutingResolver().resolve(
            task: .meetingChat,
            scopeStack: try routingScopeStack(
                global: profile,
                securityPolicy: routingSecurityPolicy(
                    externalProviderIdentifiers: ["codex-subscription"]
                )
            ),
            registry: registry,
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier: "codex-subscription",
                        modelIdentifier: "codex-default",
                        state: .ready
                    )
                ]
            )
        )
        guard case let .requiresExecutionAuthorization(candidate) = approvedCandidate
        else {
            Issue.record(
                "An external candidate must not become ready before a complete ModelRouteRequest authorization."
            )
            return
        }
        #expect(candidate.providerIdentifier == "codex-subscription")
        #expect(candidate.dataRoute == .codexSubscriptionText)
        #expect(
            candidate.routeOrigin
                == .global(profileIdentifier: "external-policy")
        )
    }

    @Test
    func codexAuthorizationBindsExactRouteAndBoundedSelectedTranscriptText() throws {
        let securityPolicy = try routingSecurityPolicy(
            externalProviderIdentifiers: [
                CodexTextExecutionAuthorization.providerIdentifier
            ]
        )
        let profile = try TaskRoutingProfile(
            identifier: "codex-chat",
            displayName: "Codex Chat",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .meetingChat,
                    routeOverride: .selection(
                        primary: ProviderModelSelection(
                            providerIdentifier:
                                CodexTextExecutionAuthorization
                                .providerIdentifier,
                            modelIdentifier: "codex-default"
                        ),
                        fallback: nil
                    )
                )
            ]
        )
        let resolution = TaskRoutingResolver().resolve(
            task: .meetingChat,
            scopeStack: try routingScopeStack(
                global: profile,
                securityPolicy: securityPolicy
            ),
            registry: try BlueMinutesBuiltInProviders.registry(),
            runtime: try ProviderRuntimeRegistry(
                snapshots: [
                    ProviderRuntimeSnapshot(
                        providerIdentifier:
                            CodexTextExecutionAuthorization
                            .providerIdentifier,
                        modelIdentifier: "codex-default",
                        state: .ready
                    )
                ]
            )
        )
        guard case let .requiresExecutionAuthorization(candidate) = resolution
        else {
            Issue.record("The exact Codex route did not require authorization.")
            return
        }

        let request = try ModelRouteRequest(
            capability: .analysis,
            dataClassification: .internal,
            offlineMode: false,
            organizationAllowsExternalProcessing: true,
            deploymentEnvironment: .production,
            destination: .approvedProvider(
                identifier:
                    CodexTextExecutionAuthorization.providerIdentifier
            ),
            retentionPolicy: .noProviderRetention,
            dataCategories: [.userPromptText, .transcriptText],
            visibleUserAuthorization: true,
            localModelAvailable: false,
            securityPolicy: securityPolicy
        )
        let authorization = try CodexTextExecutionAuthorizationFactory()
            .authorize(candidate: candidate, request: request)
        let researchCandidate = ResolvedTaskRoute(
            task: .externalResearch,
            providerIdentifier:
                candidate.providerIdentifier,
            modelIdentifier:
                candidate.modelIdentifier,
            capability: .externalResearch,
            dataRoute: candidate.dataRoute,
            costOwner: candidate.costOwner,
            meetingRevision:
                candidate.meetingRevision,
            sensitivityLabelRevision:
                candidate.sensitivityLabelRevision,
            accessPolicyRevision:
                candidate.accessPolicyRevision,
            effectiveClassification:
                candidate.effectiveClassification,
            noOutboundMode:
                candidate.noOutboundMode,
            workspaceID: candidate.workspaceID,
            meetingID: candidate.meetingID,
            routeOrigin: candidate.routeOrigin
        )
        #expect(
            throws:
                CodexIntegrationContractError
                .self
        ) {
            _ = try
                CodexTextExecutionAuthorizationFactory()
                .authorize(
                    candidate: researchCandidate,
                    request: ModelRouteRequest(
                        capability: .analysis,
                        dataClassification:
                            .internal,
                        offlineMode: false,
                        organizationAllowsExternalProcessing:
                            true,
                        deploymentEnvironment:
                            .production,
                        destination:
                            .approvedProvider(
                                identifier:
                                    CodexTextExecutionAuthorization
                                    .providerIdentifier
                            ),
                        retentionPolicy:
                            .noProviderRetention,
                        dataCategories:
                            [.userPromptText],
                        visibleUserAuthorization:
                            true,
                        localModelAvailable: false,
                        securityPolicy:
                            securityPolicy
                    )
                )
        }
        let later = try routingTranscriptSegment(
            index: 2,
            startMilliseconds: 2_000,
            text: "second synthetic segment"
        )
        let earlier = try routingTranscriptSegment(
            index: 1,
            startMilliseconds: 500,
            text: "first synthetic segment"
        )
        let context = try CodexMeetingTextContextFactory().make(
            authorization: authorization,
            selectedSegments: [later, earlier]
        )
        #expect(context.workspaceID == routingWorkspaceID)
        #expect(context.meetingID == routingMeetingID)
        #expect(context.meetingRevision == routingMeetingRevision)
        #expect(
            context.segments.map(\.text)
                == [
                    "first synthetic segment",
                    "second synthetic segment"
                ]
        )
        #expect(
            context.totalUTF8Bytes
                == "first synthetic segment".utf8.count
                    + "second synthetic segment".utf8.count
        )
        let turn = try CodexMeetingTurnRequest(
            authorization: authorization,
            context: context,
            prompt: "Summarize the selected synthetic text."
        )
        #expect(turn.prompt == "Summarize the selected synthetic text.")

        #expect(throws: CodexIntegrationContractError.self) {
            _ = try CodexMeetingTextContextFactory().make(
                authorization: authorization,
                selectedSegments: [earlier, earlier]
            )
        }
        #expect(throws: CodexIntegrationContractError.self) {
            _ = try CodexMeetingTextContextFactory().make(
                authorization: authorization,
                selectedSegments: [
                    routingTranscriptSegment(
                        index: 3,
                        startMilliseconds: 3_000,
                        text: String(
                            repeating: "x",
                            count:
                                CodexMeetingTextContext
                                .maximumSegmentUTF8Bytes + 1
                        )
                    )
                ]
            )
        }
        #expect(throws: CodexIntegrationContractError.self) {
            _ = try CodexMeetingTextContextFactory().make(
                authorization: authorization,
                selectedSegments: [
                    routingTranscriptSegment(
                        index: 4,
                        startMilliseconds: 4_000,
                        text: "other meeting",
                        meetingID: MeetingID(
                            UUID(
                                uuidString:
                                    "00000000-0000-0000-0000-000000000699"
                            )!
                        )
                    )
                ]
            )
        }
        #expect(throws: CodexIntegrationContractError.self) {
            _ = try CodexMeetingTurnRequest(
                authorization: authorization,
                context: context,
                prompt: "invalid\u{0000}prompt"
            )
        }
        #expect(throws: CodexIntegrationContractError.self) {
            _ = try CodexTextExecutionAuthorizationFactory().authorize(
                candidate: candidate,
                request: ModelRouteRequest(
                    capability: .analysis,
                    dataClassification: .internal,
                    offlineMode: false,
                    organizationAllowsExternalProcessing: true,
                    deploymentEnvironment: .production,
                    destination: .approvedProvider(
                        identifier:
                            CodexTextExecutionAuthorization
                            .providerIdentifier
                    ),
                    retentionPolicy: .noProviderRetention,
                    dataCategories: [
                        .transcriptText,
                        .speakerContext,
                        .evidenceIdentifiers
                    ],
                    visibleUserAuthorization: true,
                    localModelAvailable: false,
                    securityPolicy: securityPolicy
                )
            )
        }
    }

    @Test
    func scopeStackRejectsProfilesFromOtherOwnersOrMeetingRevisions() throws {
        let securityPolicy = try routingSecurityPolicy(noOutboundMode: true)
        let context = try routingSecurityContext(
            securityPolicy: securityPolicy
        )
        let global = try TaskRoutingProfile(
            identifier: "scope-global",
            displayName: "Scope Global",
            scope: .global,
            routes: []
        )
        let validWorkspace = try TaskRoutingProfile(
            identifier: "scope-workspace",
            displayName: "Scope Workspace",
            scope: .workspace(workspaceID: routingWorkspaceID),
            routes: []
        )
        let validMeeting = try TaskRoutingProfile(
            identifier: "scope-meeting",
            displayName: "Scope Meeting",
            scope: .meeting(meetingRevision: routingMeetingRevision),
            routes: []
        )
        _ = try TaskRoutingScopeStack(
            securityContext: context,
            global: global,
            workspace: validWorkspace,
            meeting: validMeeting
        )

        let otherWorkspace = try TaskRoutingProfile(
            identifier: "other-workspace",
            displayName: "Other Workspace",
            scope: .workspace(
                workspaceID: WorkspaceID(
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000000699"
                    )!
                )
            ),
            routes: []
        )
        #expect(throws: ProviderRoutingError.self) {
            _ = try TaskRoutingScopeStack(
                securityContext: context,
                global: global,
                workspace: otherWorkspace
            )
        }

        let otherMeetingRevision = try TaskRoutingProfile(
            identifier: "other-meeting-revision",
            displayName: "Other Meeting Revision",
            scope: .meeting(
                meetingRevision: SemanticRevisionReference(
                    logicalID: routingMeetingID,
                    revisionID: RevisionID(
                        UUID(
                            uuidString:
                                "00000000-0000-0000-0000-000000000698"
                        )!
                    )
                )
            ),
            routes: []
        )
        #expect(throws: ProviderRoutingError.self) {
            _ = try TaskRoutingScopeStack(
                securityContext: context,
                global: global,
                meeting: otherMeetingRevision
            )
        }

        let workspaceUsedAsMeeting = try TaskRoutingProfile(
            identifier: "wrong-scope-kind",
            displayName: "Wrong Scope Kind",
            scope: .workspace(workspaceID: routingWorkspaceID),
            routes: []
        )
        #expect(throws: ProviderRoutingError.self) {
            _ = try TaskRoutingScopeStack(
                securityContext: context,
                global: global,
                meeting: workspaceUsedAsMeeting
            )
        }
    }

    @Test
    func disabledReleaseIntegrationsCannotGateFeaturesOrReachServices() throws {
        let configuration = ReleaseIntegrationConfiguration.publicBeta
        let billing = configuration.billing
        let website = configuration.website

        #expect(billing.mode == .disabled)
        #expect(billing.keepsProductFeaturesUnlocked)
        #expect(!billing.permitsLicensingNetworkRequests)
        #expect(!billing.displaysTrialOrPaywall)
        #expect(website.mode == .disconnected)
        #expect(!website.permitsServiceRequests)
        #expect(website.updateFeedURL == nil)
        #expect(website.billingAPIBaseURL == nil)

        let updatePolicy = configuration.update
        #expect(updatePolicy.mode == .unconfigured)
        #expect(
            UpdateSafetyGate().decide(
                .check,
                configuration: configuration,
                activeMeeting: false
            ) == .blocked(reasonCode: "update_service_unconfigured")
        )
        let publicLinks = try WebsiteIntegrationConfiguration.publicLinks(
            supportURL: URL(string: "https://support.example.test/help")
        )
        #expect(!publicLinks.permitsServiceRequests)
        #expect(publicLinks.supportURL?.host == "support.example.test")
    }

    @Test
    func releaseServicesRequireOneUnforgeableMatchingBuildApproval() throws {
        let sandboxApproval = ReleaseIntegrationApproval.testOnly(
            environment: .sandbox,
            updaterApproved: true,
            allowedServiceEndpoints: [
                URL(string: "https://billing.sandbox.example.test/v1")!,
                URL(string: "https://updates.sandbox.example.test/feed.xml")!,
                URL(string: "https://updates2.sandbox.example.test/feed.xml")!
            ],
            allowedUpdateFeedURLs: [
                URL(string: "https://updates.sandbox.example.test/feed.xml")!,
                URL(string: "https://updates2.sandbox.example.test/feed.xml")!
            ]
        )
        let productionApproval = ReleaseIntegrationApproval.testOnly(
            environment: .production,
            updaterApproved: true,
            allowedServiceEndpoints: [
                URL(string: "https://billing.example.test/v1")!,
                URL(string: "https://updates.example.test/feed.xml")!
            ],
            allowedUpdateFeedURLs: [
                URL(string: "https://updates.example.test/feed.xml")!
            ]
        )
        let sandboxBilling = try BillingFeatureGate.internalSandbox(
            approval: sandboxApproval
        )
        let sandboxWebsite = try WebsiteIntegrationConfiguration.approvedServices(
            environment: .sandbox,
            updateFeedURL: URL(
                string: "https://updates.sandbox.example.test/feed.xml"
            ),
            billingAPIBaseURL: URL(
                string: "https://billing.sandbox.example.test/v1"
            ),
            approval: sandboxApproval
        )
        let sandboxUpdate = try UpdatePolicy.approved(
            mode: .manual,
            environment: .sandbox,
            feedURL: URL(
                string: "https://updates.sandbox.example.test/feed.xml"
            )!,
            approval: sandboxApproval
        )
        let configuration = try ReleaseIntegrationConfiguration.approvedInternal(
            billing: sandboxBilling,
            website: sandboxWebsite,
            update: sandboxUpdate,
            approval: sandboxApproval
        )
        #expect(configuration.billing.mode == .sandbox)
        #expect(configuration.website.serviceEnvironment == .sandbox)
        #expect(configuration.update.serviceEnvironment == .sandbox)
        #expect(
            UpdateSafetyGate().decide(
                .download,
                configuration: configuration,
                activeMeeting: true
            ) == .blocked(reasonCode: "active_meeting_protects_runtime")
        )
        #expect(
            UpdateSafetyGate().decide(
                .check,
                configuration: configuration,
                activeMeeting: false
            ) == .allowed
        )

        let productionWebsite = try WebsiteIntegrationConfiguration.approvedServices(
            environment: .production,
            billingAPIBaseURL: URL(
                string: "https://billing.example.test/v1"
            ),
            approval: productionApproval
        )
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try ReleaseIntegrationConfiguration.approvedInternal(
                billing: sandboxBilling,
                website: productionWebsite,
                update: sandboxUpdate,
                approval: sandboxApproval
            )
        }
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try UpdatePolicy.approved(
                mode: .automatic,
                environment: .sandbox,
                feedURL: URL(
                    string: "https://updates.not-allowlisted.example.test/feed.xml"
                )!,
                approval: sandboxApproval
            )
        }
        let standaloneFeedApproval = ReleaseIntegrationApproval.testOnly(
            environment: .sandbox,
            updaterApproved: true,
            allowedServiceEndpoints: [],
            allowedUpdateFeedURLs: [
                URL(
                    string:
                        "https://updates.standalone.example.test/feed.xml"
                )!
            ]
        )
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try UpdatePolicy.approved(
                mode: .manual,
                environment: .sandbox,
                feedURL: URL(
                    string:
                        "https://updates.standalone.example.test/feed.xml"
                )!,
                approval: standaloneFeedApproval
            )
        }
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try WebsiteIntegrationConfiguration.approvedServices(
                environment: .sandbox,
                billingAPIBaseURL: URL(
                    string: "https://billing.not-allowlisted.example.test/v1"
                ),
                approval: sandboxApproval
            )
        }
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try ReleaseIntegrationConfiguration.approvedInternal(
                billing: sandboxBilling,
                website: sandboxWebsite,
                update: .publicBeta,
                approval: sandboxApproval
            )
        }

        let secondSandboxWebsite =
            try WebsiteIntegrationConfiguration.approvedServices(
                environment: .sandbox,
                updateFeedURL: URL(
                    string: "https://updates2.sandbox.example.test/feed.xml"
                ),
                approval: sandboxApproval
            )
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try ReleaseIntegrationConfiguration.approvedInternal(
                billing: .publicBeta,
                website: secondSandboxWebsite,
                update: sandboxUpdate,
                approval: sandboxApproval
            )
        }

        let updaterDeniedApproval = ReleaseIntegrationApproval.testOnly(
            environment: .sandbox,
            updaterApproved: false,
            allowedServiceEndpoints: [
                URL(string: "https://updates.sandbox.example.test/feed.xml")!
            ],
            allowedUpdateFeedURLs: [
                URL(string: "https://updates.sandbox.example.test/feed.xml")!
            ]
        )
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try WebsiteIntegrationConfiguration.approvedServices(
                environment: .sandbox,
                updateFeedURL: URL(
                    string: "https://updates.sandbox.example.test/feed.xml"
                ),
                approval: updaterDeniedApproval
            )
        }
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try UpdatePolicy.approved(
                mode: .manual,
                environment: .sandbox,
                feedURL: URL(
                    string: "https://updates.sandbox.example.test/feed.xml"
                )!,
                approval: updaterDeniedApproval
            )
        }
        #expect(throws: ReleaseIntegrationError.self) {
            _ = try ReleaseIntegrationConfiguration.approvedInternal(
                billing: .publicBeta,
                website: sandboxWebsite,
                update: sandboxUpdate,
                approval: updaterDeniedApproval
            )
        }
    }
}

private let routingWorkspaceID = WorkspaceID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000611")!
)
private let routingMeetingID = MeetingID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000612")!
)
private let routingMeetingRevisionID = RevisionID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000613")!
)
private let routingMeetingRevision = try! SemanticRevisionReference(
    logicalID: routingMeetingID,
    revisionID: routingMeetingRevisionID
)
private let routingSensitivityLabelID = SensitivityLabelID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
)
private let routingSensitivityLabelRevisionID = RevisionID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
)
private let routingAccessPolicyID = AccessPolicyID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
)
private let routingAccessPolicyRevisionID = RevisionID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000604")!
)
private let routingCreatedAt = try! UTCInstant(
    millisecondsSinceUnixEpoch: 1_900_000_000_000
)

private func routingTranscriptSegment(
    index: Int,
    startMilliseconds: Int64,
    text: String,
    meetingID: MeetingID = routingMeetingID,
    classification: DataClassification = .internal
) throws -> TranscriptSegmentV1 {
    let source = try SemanticRevisionReference(
        logicalID: SourceAssetID(
            UUID(
                uuidString: String(
                    format:
                        "00000000-0000-0000-0001-%012d",
                    index
                )
            )!
        ),
        revisionID: RevisionID(
            UUID(
                uuidString: String(
                    format:
                        "00000000-0000-0000-0002-%012d",
                    index
                )
            )!
        )
    )
    let revision = try RevisionEnvelope(
        logicalID: TranscriptSegmentID(
            UUID(
                uuidString: String(
                    format:
                        "00000000-0000-0000-0003-%012d",
                    index
                )
            )!
        ),
        revisionID: RevisionID(
            UUID(
                uuidString: String(
                    format:
                        "00000000-0000-0000-0004-%012d",
                    index
                )
            )!
        ),
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: routingCreatedAt,
        createdBy: .application,
        inputRevisions: [source],
        sourceAssetRevisions: [source],
        dataClassification: classification
    )
    return try TranscriptSegmentV1(
        revision: revision,
        meetingID: meetingID,
        sourceProvenance: .originalSpeakerAudio(
            sourceAssetRevision: source
        ),
        timeRange: MediaTimeRange(
            startMilliseconds: startMilliseconds,
            endMilliseconds: startMilliseconds + 1_000
        ),
        detectedLanguage: LanguageTag("en"),
        text: text,
        confidence: ConfidenceScore(millionths: 900_000),
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}

private func routingScopeStack(
    global: TaskRoutingProfile,
    workspace: TaskRoutingProfile? = nil,
    meeting: TaskRoutingProfile? = nil,
    securityPolicy: ModelSecurityPolicySnapshot
) throws -> TaskRoutingScopeStack {
    try TaskRoutingScopeStack(
        securityContext: routingSecurityContext(
            securityPolicy: securityPolicy
        ),
        global: global,
        workspace: workspace,
        meeting: meeting
    )
}

private func routingSecurityPolicy(
    classification: DataClassification = .internal,
    noOutboundMode: Bool = false,
    externalProviderIdentifiers: [String] = []
) throws -> ModelSecurityPolicySnapshot {
    let externalProcessingAllowed = !noOutboundMode
        && !externalProviderIdentifiers.isEmpty
    return try ModelSecurityPolicySnapshot(
        sensitivityLabelRevision: SemanticRevisionReference(
            logicalID: routingSensitivityLabelID,
            revisionID: routingSensitivityLabelRevisionID
        ),
        accessPolicyRevision: SemanticRevisionReference(
            logicalID: routingAccessPolicyID,
            revisionID: routingAccessPolicyRevisionID
        ),
        effectiveClassification: classification,
        noOutboundMode: noOutboundMode,
        localProcessingAllowed: true,
        manualLocalReviewAllowed: true,
        externalProcessingAllowed: externalProcessingAllowed,
        approvedExternalProviderIdentifiers: externalProviderIdentifiers,
        approvedDeploymentEnvironments: externalProcessingAllowed ? [.production] : [],
        approvedRetentionPolicies: externalProcessingAllowed ? [.noProviderRetention] : []
    )
}

private struct RoutingSecurityGraph {
    let meeting: MeetingProfileV1
    let sensitivityLabel: SensitivityLabelV1
    let accessPolicy: AccessPolicyV1
}

private func routingSecurityContext(
    securityPolicy: ModelSecurityPolicySnapshot
) throws -> TaskRoutingSecurityContext {
    let graph = try routingSecurityGraph(securityPolicy: securityPolicy)
    return try TaskRoutingSecurityContext(
        meeting: graph.meeting,
        sensitivityLabel: graph.sensitivityLabel,
        accessPolicy: graph.accessPolicy,
        securityPolicy: securityPolicy
    )
}

private func routingSecurityGraph(
    securityPolicy: ModelSecurityPolicySnapshot,
    workspaceID: WorkspaceID? = routingWorkspaceID
) throws -> RoutingSecurityGraph {
    let externalProcessingAllowed = securityPolicy.externalProcessingAllowed
    let meeting = try routingMeetingProfile(
        workspaceID: workspaceID,
        meetingID: routingMeetingID,
        classification: securityPolicy.effectiveClassification,
        externalProcessingAllowed: externalProcessingAllowed
    )
    let meetingReference = try SemanticRevisionReference(
        logicalID: meeting.meetingID,
        revisionID: meeting.revision.revisionID
    )
    let labelEnvelope = try RevisionEnvelope(
        logicalID: routingSensitivityLabelID,
        revisionID: routingSensitivityLabelRevisionID,
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: routingCreatedAt,
        createdBy: .application,
        inputRevisions: [meetingReference],
        dataClassification: securityPolicy.effectiveClassification
    )
    let sensitivityLabel = try SensitivityLabelV1(
        revision: labelEnvelope,
        meetingID: meeting.meetingID,
        meetingRevision: meetingReference,
        inheritedClassifications: [securityPolicy.effectiveClassification],
        effectiveClassification: securityPolicy.effectiveClassification,
        rationale: .inheritedMostRestrictive,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
    let labelReference = try SemanticRevisionReference(
        logicalID: sensitivityLabel.labelID,
        revisionID: sensitivityLabel.revision.revisionID
    )
    let accessEnvelope = try RevisionEnvelope(
        logicalID: routingAccessPolicyID,
        revisionID: routingAccessPolicyRevisionID,
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: routingCreatedAt,
        createdBy: .application,
        inputRevisions: [labelReference],
        dataClassification: securityPolicy.effectiveClassification
    )
    let accessPolicy = try AccessPolicyV1(
        revision: accessEnvelope,
        meetingID: meeting.meetingID,
        sensitivityLabelRevision: labelReference,
        effectiveClassification: securityPolicy.effectiveClassification,
        localProcessingAllowed: securityPolicy.localProcessingAllowed,
        manualLocalReviewAllowed: securityPolicy.manualLocalReviewAllowed,
        externalProcessingAllowed: externalProcessingAllowed,
        organizationAllowsExternalProcessing: externalProcessingAllowed,
        deploymentAllowsExternalProcessing: externalProcessingAllowed,
        destinationAllowsExternalProcessing: externalProcessingAllowed,
        retentionAllowsExternalProcessing: externalProcessingAllowed,
        requiresVisibleUserAuthorization: true,
        approvedExternalProviderIdentifiers: securityPolicy
            .approvedExternalProviderIdentifiers,
        noOutboundMode: securityPolicy.noOutboundMode,
        telemetryMode: .disabled,
        localExportAllowed: true,
        trashAllowed: true,
        minimumTrashRetentionDays: 30,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
    return RoutingSecurityGraph(
        meeting: meeting,
        sensitivityLabel: sensitivityLabel,
        accessPolicy: accessPolicy
    )
}

private func routingMeetingProfile(
    workspaceID: WorkspaceID?,
    meetingID: MeetingID,
    classification: DataClassification,
    externalProcessingAllowed: Bool
) throws -> MeetingProfileV1 {
    let envelope = try RevisionEnvelope(
        logicalID: meetingID,
        revisionID: routingMeetingRevisionID,
        schemaVersion: .v1,
        lifecycleStatus: .draft,
        validationState: .notValidated,
        createdAt: routingCreatedAt,
        createdBy: .application,
        dataClassification: classification
    )
    return try MeetingProfileV1(
        revision: envelope,
        title: "Routing security fixture",
        sourceLanguages: [LanguageTag("en")],
        outputLanguage: LanguageTag("en"),
        cloudProcessingPolicy: externalProcessingAllowed
            ? .approvedCloudAllowed
            : .localOnly,
        workspaceID: workspaceID,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}
