import CryptoKit
import Foundation
import MeetingBuddyAI
import MeetingBuddyApplication
import MeetingBuddyDomain
import MeetingBuddyMedia
import MeetingBuddyPersistence
import MeetingBuddyTasks

enum AppWorkflowError: LocalizedError {
    case workspaceRequired
    case workspaceAuthorizationFailed
    case workspaceOpenFailed
    case workspaceHealthFailed
    case workspaceWorkInProgress
    case sourceAuthorizationFailed
    case sourceSelectionExpired
    case sourceInspectionFailed
    case importFailed
    case jobUnavailable
    case canonicalAudioRequired
    case onDeviceModelUnavailable
    case speechToTextNotConfigured
    case speechToTextConfigurationUnavailable
    case remoteAudioAuthorizationRequired
    case transcriptUnavailable
    case analysisUnavailable
    case briefingUnavailable
    case recordingInProgress
    case recordingUnavailable
    case recordingAuthorizationRequired
    case webMetadataUnavailable
    case historicalReviewUnavailable
    case externalTextAuthorizationUnavailable
    case codexContextUnavailable
    case reviewFailed

    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "Choose a local BlueMinutes workspace first."
        case .workspaceAuthorizationFailed:
            "BlueMinutes could not retain access to the selected workspace."
        case .workspaceOpenFailed:
            "The selected folder is not an empty folder or a valid BlueMinutes workspace."
        case .workspaceHealthFailed:
            "The workspace did not pass its local database and recovery health checks."
        case .workspaceWorkInProgress:
            "Finish or cancel the current background job before switching workspaces."
        case .sourceAuthorizationFailed:
            "BlueMinutes could not read the user-selected source file."
        case .sourceSelectionExpired:
            "Choose the local source file again before importing it."
        case .sourceInspectionFailed:
            "The selected file is unsupported or contains no readable audio track."
        case .importFailed:
            "The source could not be copied, verified, and registered in the workspace."
        case .jobUnavailable:
            "The processing job is no longer available."
        case .canonicalAudioRequired:
            "Finish canonical local audio processing before starting transcription."
        case .onDeviceModelUnavailable:
            "The requested on-device model is unavailable. Use the manual local fallback or install the model in system settings."
        case .speechToTextNotConfigured:
            "Speech-to-text is not configured. Keep the recording, import a transcript, or choose a verified STT route."
        case .speechToTextConfigurationUnavailable:
            "The selected speech-to-text provider/model is no longer ready. No audio was sent."
        case .remoteAudioAuthorizationRequired:
            "Remote speech-to-text requires a visible authorization for this meeting and again immediately before audio upload."
        case .transcriptUnavailable:
            "No published transcript review is available for this meeting."
        case .analysisUnavailable:
            "Analysis requires a complete reviewed transcript with exactly one resolved speaker and capacity for every segment."
        case .briefingUnavailable:
            "A current, fully validated analysis is required before creating or changing the briefing."
        case .recordingInProgress:
            "Finish or retain the current recording before switching workspaces."
        case .recordingUnavailable:
            "The recording session is unavailable or cannot be changed safely."
        case .recordingAuthorizationRequired:
            "Recording requires a direct visible acknowledgement and explicit source selection."
        case .webMetadataUnavailable:
            "The official UN Web TV page metadata could not be read safely. Open the page and enter metadata manually."
        case .historicalReviewUnavailable:
            "Meeting History is unavailable until its local index and exact policy graph are current."
        case .externalTextAuthorizationUnavailable:
            "Codex text processing requires a Public or Internal meeting with explicit visible authorization."
        case .codexContextUnavailable:
            "Select a current transcript segment from a meeting that explicitly allows Codex text processing."
        case .reviewFailed:
            "The review change failed without replacing accepted content."
        }
    }
}

private actor WorkspaceRemoteTranscriptionPolicyAuthority {
    private let workspaceID: WorkspaceID
    private let store: SQLitePersistenceStore
    private let intelligenceRepository:
        any IntelligenceConfigurationRepository

    init(
        workspaceID: WorkspaceID,
        store: SQLitePersistenceStore,
        intelligenceRepository:
            any IntelligenceConfigurationRepository
    ) {
        self.workspaceID = workspaceID
        self.store = store
        self.intelligenceRepository =
            intelligenceRepository
    }

    func authorize(
        plan: TranscriptPipelineJobPlan
    ) async throws
        -> ExternalModelExecutionAuthorization
    {
        guard let expectedConfiguration =
                plan.remoteProviderConfiguration,
              let expectedRevision =
                plan
                .intelligenceConfigurationRevision
        else {
            throw AIProviderContractError
                .routeDenied(
                    "Remote transcription authority is absent, stale, or belongs to another attempt."
                )
        }

        let configurationState =
            try intelligenceRepository.load()
        let expectedMeetingRoute =
            try MeetingSpeechToTextRouteV1(
                kind: .approvedRemote,
                providerIdentifier:
                    expectedConfiguration
                    .identifier,
                modelIdentifier:
                    expectedConfiguration
                    .modelIdentifier,
                intelligenceConfigurationRevision:
                    expectedRevision
            )
        guard configurationState.revision
                == expectedRevision,
              configurationState.providers
                .contains(
                    expectedConfiguration
                ),
              expectedConfiguration
                .connectionState == .ready,
              expectedConfiguration
                .capabilities.contains(
                    .speechToTextBatch
                ),
              let meeting =
                try activeMeeting(
                    plan.meetingID
                ),
              meeting.workspaceID
                == workspaceID,
              meeting.revision
                .dataClassification
                == plan.dataClassification,
              meeting.speechToTextRoute
                == expectedMeetingRoute,
              let securityPolicy =
                try activeSecurityPolicy(
                    meetingID:
                        plan.meetingID
                )
        else {
            throw AIProviderContractError
                .routeDenied(
                    "Current meeting policy or provider configuration no longer authorizes remote transcription."
                )
        }

        let persisted =
            plan.transcriptionRoute.request
        guard persisted.capability
                == .transcription,
              persisted.dataClassification
                == plan.dataClassification,
              persisted.deploymentEnvironment
                == .production,
              persisted.destination
                == .approvedProvider(
                    identifier:
                        expectedConfiguration
                        .identifier
                ),
              persisted.retentionPolicy
                == .approvedProviderRetention,
              persisted.dataCategories
                == [.canonicalAudio],
              persisted.visibleUserAuthorization,
              !persisted.offlineMode,
              !persisted.localModelAvailable
        else {
            throw AIProviderContractError
                .routeDenied(
                    "The persisted remote route does not match the exact bounded audio request."
                )
        }

        let currentRequest =
            try ModelRouteRequest(
                capability: .transcription,
                dataClassification:
                    plan.dataClassification,
                offlineMode: false,
                organizationAllowsExternalProcessing:
                    securityPolicy
                    .externalProcessingAllowed,
                deploymentEnvironment:
                    .production,
                destination:
                    .approvedProvider(
                        identifier:
                            expectedConfiguration
                            .identifier
                    ),
                retentionPolicy:
                    .approvedProviderRetention,
                dataCategories:
                    [.canonicalAudio],
                visibleUserAuthorization: true,
                localModelAvailable: false,
                securityPolicy:
                    securityPolicy
            )
        let authorization =
            try ModelPolicyRouter()
            .authorizeExternal(
                currentRequest,
                expectedProviderIdentifier:
                    expectedConfiguration
                    .identifier
            )
        return authorization
    }

    private func activeMeeting(
        _ meetingID: MeetingID
    ) throws -> MeetingProfileV1? {
        if let active =
            try store.activeRevisionState(
                MeetingProfileV1.self,
                logicalID: meetingID
            )?.revision
        {
            return active
        }
        let revisions = try store.revisions(
            MeetingProfileV1.self,
            logicalID: meetingID
        )
        guard revisions.count <= 1 else {
            throw AIProviderContractError
                .routeDenied(
                    "The meeting profile has no unambiguous active revision."
                )
        }
        return revisions.first
    }

    private func activeSecurityPolicy(
        meetingID: MeetingID
    ) throws -> ModelSecurityPolicySnapshot? {
        let labelID =
            try SensitivityLabelID(
                validating:
                    meetingID
                    .canonicalString
            )
        let policyID =
            try AccessPolicyID(
                validating:
                    meetingID
                    .canonicalString
            )
        guard let label =
                try store
                .activeRevisionState(
                    SensitivityLabelV1.self,
                    logicalID: labelID
                )?.revision,
              let policy =
                try store
                .activeRevisionState(
                    AccessPolicyV1.self,
                    logicalID: policyID
                )?.revision
        else { return nil }
        let labelReference =
            try SemanticRevisionReference(
                logicalID:
                    label.labelID,
                revisionID:
                    label.revision
                    .revisionID
            )
        guard label.meetingID == meetingID,
              policy.meetingID == meetingID,
              policy
                .sensitivityLabelRevision
                == labelReference,
              policy.effectiveClassification
                == label
                .effectiveClassification
        else {
            throw AIProviderContractError
                .routeDenied(
                    "The active meeting security policy is inconsistent."
                )
        }
        return try LocalSecurityPolicyBundle(
            sensitivityLabel: label,
            accessPolicy: policy
        ).modelSnapshot
    }

}

private final class WorkspaceRuntime: @unchecked Sendable {
    let descriptor: LocalWorkspaceDescriptor
    let capabilities: AppCapabilities
    let store: SQLitePersistenceStore
    let storage: LocalStorageService
    let coordinator: ManagedAssetCoordinator
    let fileAccess: LocalManagedMediaFileAccess
    let processor: AVFoundationMediaProcessor
    let intake: LocalMediaIntakeService
    let transientSources: TransientMediaSourceRegistry
    let manager: LocalTaskManager
    let telemetry: LocalTelemetryBuffer
    let storageReporter: LocalWorkspaceStorageReporter
    let recordingFileStore: LocalRecordingFileStore
    let recordingRecovery: LocalRecordingRecoveryService
    let captureProvider: MacOSAudioCaptureProvider
    let captureRegistry: TransientRecordingCaptureRegistry
    let metadataSource: URLSessionUNWebTVMetadataSource
    let remoteTranscriptionAuthorization:
        EphemeralExternalTranscriptionAuthorizationBroker
    let transcriptionProvider: (any TranscriptionProvider)?
    let translationProvider: (any TranslationProvider)?
    let analysisProvider: (any AnalysisProvider)?
    let briefingProvider: (any BriefingSectionProvider)?
    private(set) var mostRecentRecoveredRecordingSession: RecordingSessionSnapshot? = nil

    init(
        descriptor: LocalWorkspaceDescriptor,
        capabilities: AppCapabilities,
        intelligenceRepository:
            any IntelligenceConfigurationRepository,
        secretStore: any SecretStore
    ) throws {
        self.descriptor = descriptor
        self.capabilities = capabilities
        store = try SQLitePersistenceStore(workspace: descriptor)
        storage = LocalStorageService(workspace: descriptor)
        coordinator = ManagedAssetCoordinator(storage: storage, metadata: store)
        fileAccess = LocalManagedMediaFileAccess(storage: storage, metadata: store)
        processor = AVFoundationMediaProcessor()
        intake = LocalMediaIntakeService(
            processor: processor,
            storage: coordinator,
            catalog: store,
            fileAccess: fileAccess
        )
        transientSources = TransientMediaSourceRegistry()
        telemetry = LocalTelemetryBuffer(policy: try TelemetryPolicy())
        storageReporter = LocalWorkspaceStorageReporter(
            workspace: descriptor,
            store: store
        )
        recordingFileStore = LocalRecordingFileStore(workspace: descriptor)
        recordingRecovery = LocalRecordingRecoveryService(
            repository: store,
            fileStore: recordingFileStore
        )
        captureProvider = MacOSAudioCaptureProvider()
        captureRegistry = TransientRecordingCaptureRegistry()
        metadataSource = URLSessionUNWebTVMetadataSource()
        let remotePolicyAuthority =
            WorkspaceRemoteTranscriptionPolicyAuthority(
                workspaceID:
                    descriptor.manifest
                    .workspaceID,
                store: store,
                intelligenceRepository:
                    intelligenceRepository
            )
        remoteTranscriptionAuthorization =
            EphemeralExternalTranscriptionAuthorizationBroker {
                plan in
                try await remotePolicyAuthority
                    .authorize(plan: plan)
            }
        let intakeExecutor = LocalMediaIntakeJobExecutor(
            intake: intake,
            sources: transientSources
        )
        let canonicalExecutor = CanonicalAudioJobExecutor(
            processor: processor,
            storage: coordinator,
            catalog: store,
            fileAccess: fileAccess
        )
        let recordingExecutor = RecordingCaptureJobExecutor(
            repository: store,
            fileStore: recordingFileStore,
            assetStorage: coordinator,
            assetCatalog: store,
            assetFileAccess: fileAccess,
            registry: captureRegistry,
            recovery: recordingRecovery
        )
        var executors: [any TaskJobExecutor] = [
            intakeExecutor,
            canonicalExecutor,
            recordingExecutor,
            HistoricalIndexRebuildJobExecutor(repository: store)
        ]
        if #available(macOS 26.0, *) {
            let speech = AppleOnDeviceTranscriptionProvider()
            let translation = AppleOnDeviceTranslationProvider()
            let analysis = AppleFoundationModelsAnalysisProvider()
            let briefing = AppleFoundationModelsBriefingProvider()
            transcriptionProvider = speech
            translationProvider = translation
            analysisProvider = analysis
            briefingProvider = briefing
            executors.append(
                TranscriptPipelineJobExecutor(
                    transcriptionProvider: speech,
                    translationProvider: translation,
                    processor: processor,
                    catalog: store,
                    fileAccess: fileAccess,
                    repository: store,
                    externalProviderBuilder:
                        OpenAIRemoteTranscriptionProviderFactory(
                            secretStore: secretStore
                        ),
                    externalExecutionAuthorizer:
                        remoteTranscriptionAuthorization
                )
            )
            executors.append(
                AnalysisPipelineJobExecutor(
                    provider: analysis,
                    repository: store
                )
            )
            executors.append(
                BriefingPipelineJobExecutor(
                    provider: briefing,
                    repository: store
                )
            )
        } else {
            transcriptionProvider = nil
            translationProvider = nil
            analysisProvider = nil
            briefingProvider = nil
            executors.append(
                TranscriptPipelineJobExecutor(
                    transcriptionProvider:
                        UnavailableLocalTranscriptionProvider(),
                    translationProvider: nil,
                    processor: processor,
                    catalog: store,
                    fileAccess: fileAccess,
                    repository: store,
                    externalProviderBuilder:
                        OpenAIRemoteTranscriptionProviderFactory(
                            secretStore: secretStore
                        ),
                    externalExecutionAuthorizer:
                        remoteTranscriptionAuthorization
                )
            )
        }
        manager = try LocalTaskManager(
            repository: SQLiteJobRepository(store: store),
            temporaryStorage: LocalTaskTemporaryStorage(workspace: descriptor),
            logStore: RotatingTaskLogStore(
                workspace: descriptor,
                configuration: try TaskLogConfiguration()
            ),
            managedAssetRecovery: coordinator,
            maximumConcurrentJobs: 2,
            executors: executors
        )
    }

    deinit {
        try? store.close()
    }

    func recover() async throws {
        let recordingOutcomes = try await recordingRecovery.recoverNonterminalSessions()
        mostRecentRecoveredRecordingSession = recordingOutcomes.last?.snapshot
        let report = try await manager.recoverAtStartup(
            policy: StartupRecoveryPolicy()
        )
        guard report.databaseHealth.isHealthy,
              report.managedAssetRecovery.repairRequiredOperationCount == 0,
              !report.managedAssetRecovery.truncated,
              !report.orphanScan.truncated
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        // A queued record proves persistence completed, but not that the
        // pre-crash process still held its transient source, capture handle,
        // or visible outbound authorization. Move every such record to an
        // actionable terminal state instead of silently replaying it or
        // leaving the workspace permanently blocked.
        _ = try await manager
            .cancelPersistedQueuedJobs()
        _ = await telemetry.record(
            try ContentFreeTelemetryEvent(
                name: .workspaceHealthChecked,
                counters: [TelemetryCounter(key: .successful, value: 1)]
            )
        )
    }
}

@MainActor
final class AppMediaReviewWorkflow: MediaReviewWorkflow {
    private let capabilities: AppCapabilities
    private let intelligenceRepository:
        any IntelligenceConfigurationRepository
    private let secretStore: any SecretStore
    private let workspaceService = LocalWorkspaceService()
    private let workspaceSecurityScope = WorkspaceSecurityScope()

    private var runtime: WorkspaceRuntime?
    private var workspaceDisplayName = ""
    private var pendingSourceURL: URL?
    private var pendingSourceDidStartScope = false
    private var pendingInspection: MediaInspection?

    init(
        capabilities: AppCapabilities,
        intelligenceRepository:
            any IntelligenceConfigurationRepository,
        secretStore: any SecretStore
    ) {
        self.capabilities = capabilities
        self.intelligenceRepository =
            intelligenceRepository
        self.secretStore = secretStore
    }

    deinit {
        if pendingSourceDidStartScope {
            pendingSourceURL?.stopAccessingSecurityScopedResource()
        }
    }

    func restoreWorkspace() async throws -> WorkspaceReview? {
        guard let url = try workspaceSecurityScope.restore() else { return nil }
        do {
            let descriptor = try workspaceService.openWorkspace(at: url)
            let nextRuntime = try WorkspaceRuntime(
                descriptor: descriptor,
                capabilities: capabilities,
                intelligenceRepository:
                    intelligenceRepository,
                secretStore: secretStore
            )
            try await nextRuntime.recover()
            runtime = nextRuntime
            workspaceDisplayName = displayName(for: url)
            return WorkspaceReview(
                workspaceID: descriptor.manifest.workspaceID,
                displayName: workspaceDisplayName
            )
        } catch let error as AppWorkflowError {
            workspaceSecurityScope.forget()
            throw error
        } catch {
            workspaceSecurityScope.forget()
            throw AppWorkflowError.workspaceOpenFailed
        }
    }

    func restoredMediaReview() async throws
        -> RestoredMediaWorkflowReview?
    {
        guard let runtime else {
            throw AppWorkflowError.workspaceRequired
        }
        let records = try await runtime.manager.jobs()
        let pipelineTypes: Set<JobType> = [
            MediaJobTypes.canonicalAudio,
            TranscriptJobTypes.pipeline,
            AnalysisJobTypes.pipeline,
            BriefingJobTypes.pipeline,
        ]
        let pipelineRecords = records.filter {
            pipelineTypes.contains($0.jobType)
        }
        let activeRecords = pipelineRecords.filter {
            !$0.state.isTerminal
        }
        var activeMeetingIDs = Set<MeetingID>()
        for record in activeRecords {
            guard let meetingID = record.meetingID else {
                throw AppWorkflowError.workspaceHealthFailed
            }
            activeMeetingIDs.insert(meetingID)
        }
        guard activeMeetingIDs.count <= 1 else {
            throw AppWorkflowError.workspaceHealthFailed
        }

        let canonicalRecords = pipelineRecords.filter {
            $0.jobType == MediaJobTypes.canonicalAudio
        }
        guard canonicalRecords.allSatisfy({
            $0.meetingID != nil
        }) else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        let intakeRecords = records.filter {
            $0.jobType
                == MediaJobTypes.localIntake
        }
        guard intakeRecords.allSatisfy({
            $0.meetingID != nil
        }) else {
            throw AppWorkflowError
                .workspaceHealthFailed
        }
        let canonicalMeetingIDs =
            Set(
                canonicalRecords
                    .compactMap(\.meetingID)
            )
        let orphanIntake =
            newestRecord(
                in:
                    intakeRecords.filter {
                        guard let meetingID =
                                $0.meetingID
                        else { return false }
                        return !canonicalMeetingIDs
                            .contains(meetingID)
                    }
            )
        let latestCanonical =
            newestRecord(
                in: canonicalRecords
            )
        let orphanIntakeIsLatest: Bool
        if let orphanIntake {
            if let latestCanonical {
                orphanIntakeIsLatest =
                    orphanIntake.createdAt
                        > latestCanonical.createdAt
                    || (
                        orphanIntake.createdAt
                            == latestCanonical.createdAt
                            && orphanIntake.jobID
                                > latestCanonical.jobID
                    )
            } else {
                orphanIntakeIsLatest = true
            }
        } else {
            orphanIntakeIsLatest = false
        }
        if activeRecords.isEmpty,
           orphanIntakeIsLatest,
           var intakeRecord = orphanIntake
        {
            if !intakeRecord.state.isTerminal {
                intakeRecord = try await runtime
                    .manager.cancel(
                        jobID:
                            intakeRecord.jobID
                    )
            }
            let plan =
                try LocalMediaIntakeJobPlan
                .decode(
                    from:
                        intakeRecord
                        .inputPayload
                )
            guard intakeRecord.meetingID
                    == plan.meetingID,
                  intakeRecord
                    .dataClassification
                    == plan.dataClassification,
                  intakeRecord.privacyRoute
                    == .localOnly
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            let meeting =
                try restoredMeetingProfile(
                    meetingID:
                        plan.meetingID,
                    runtime: runtime
                )
            guard meeting.revision
                    .dataClassification
                    == plan.dataClassification
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            let securityPolicy =
                try securityPolicySnapshot(
                    meetingID:
                        plan.meetingID
                )
            let codexAllowed =
                securityPolicy?
                .approvedExternalProviderIdentifiers
                .contains(
                    CodexTextExecutionAuthorization
                        .providerIdentifier
                ) == true

            if intakeRecord.state
                == .succeeded
            {
                guard intakeRecord
                        .outputRevisionIDs
                        == [
                            try plan
                                .outputRevision
                        ],
                      let sourceAsset =
                        try runtime.store
                        .sourceAsset(
                            revisionID:
                                plan
                                .sourceRevisionID
                        )
                else {
                    throw AppWorkflowError
                        .workspaceHealthFailed
                }
                let selectedTrack =
                    try plan.initialInspection
                    .requireTrack(
                        plan.selectedTrack
                    )
                let sourceReference =
                    try SemanticRevisionReference(
                        logicalID:
                            sourceAsset.assetID,
                        revisionID:
                            sourceAsset.revision
                            .revisionID
                    )
                let canonicalPlan =
                    try CanonicalAudioJobPlan(
                        sourceRevision:
                            sourceReference,
                        selectedTrack:
                            plan.selectedTrack,
                        speechSourceKind:
                            plan.speechSourceKind,
                        meetingID:
                            plan.meetingID,
                        createdAt:
                            try currentInstant(),
                        dataClassification:
                            plan.dataClassification,
                        language:
                            plan.language
                                ?? selectedTrack
                                .language,
                        expectedDurationFrames:
                            plan.initialInspection
                            .durationFrameCount
                    )
                let canonicalRecord =
                    try await runtime.manager
                    .enqueue(
                        CanonicalAudioJobFactory()
                            .request(
                                plan:
                                    canonicalPlan,
                                requestedBy:
                                    JobRequester(
                                        "meetingbuddy-app"
                                    )
                            )
                    )
                return RestoredMediaWorkflowReview(
                    meetingTitle:
                        meeting.title,
                    dataClassification:
                        plan.dataClassification,
                    sourceLanguage:
                        plan.language,
                    codexTextProcessingAllowed:
                        codexAllowed,
                    speechToTextRoute:
                        meeting
                        .speechToTextRoute,
                    importedSource:
                        ImportedSourceReview(
                            assetID:
                                sourceAsset
                                .assetID,
                            revisionID:
                                sourceAsset
                                .revision
                                .revisionID,
                            sourceHash:
                                sourceAsset
                                .sourceContentHash,
                            byteSize:
                                sourceAsset
                                .byteSize,
                            format:
                                plan
                                .initialInspection
                                .format,
                            durationFrameCount:
                                plan
                                .initialInspection
                                .durationFrameCount,
                            selectedTrack:
                                plan
                                .selectedTrack,
                            speechSourceKind:
                                plan
                                .speechSourceKind
                        ),
                    canonicalJob:
                        MediaJobReview(
                            record:
                                canonicalRecord
                        )
                )
            }

            return RestoredMediaWorkflowReview(
                meetingTitle: meeting.title,
                dataClassification:
                    plan.dataClassification,
                sourceLanguage:
                    plan.language,
                codexTextProcessingAllowed:
                    codexAllowed,
                speechToTextRoute:
                    meeting.speechToTextRoute,
                importedSource: nil,
                sourceReselectionJob:
                    MediaJobReview(
                        record:
                            intakeRecord
                    ),
                canonicalJob: nil
            )
        }
        guard !canonicalRecords.isEmpty else {
            guard activeRecords.isEmpty else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            return nil
        }

        let selectedMeetingID: MeetingID
        if let activeMeetingID = activeMeetingIDs.first {
            selectedMeetingID = activeMeetingID
        } else {
            guard let latestCanonical =
                    newestRecord(in: canonicalRecords),
                  let meetingID = latestCanonical.meetingID
            else {
                throw AppWorkflowError.workspaceHealthFailed
            }
            selectedMeetingID = meetingID
        }
        let meetingCanonicalRecords = canonicalRecords.filter {
            $0.meetingID == selectedMeetingID
        }
        guard meetingCanonicalRecords.count == 1,
              let canonicalRecord =
                meetingCanonicalRecords.first
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        let meetingRecords = pipelineRecords.filter {
            $0.meetingID == selectedMeetingID
        }
        guard meetingRecords.filter({
            !$0.state.isTerminal
        }).count <= 1 else {
            throw AppWorkflowError.workspaceHealthFailed
        }

        let plan = try CanonicalAudioJobPlan.decode(
            from: canonicalRecord.inputPayload
        )
        let expectedCanonicalReference =
            try SemanticRevisionReference(
                logicalID: plan.outputAssetID,
                revisionID: plan.outputRevisionID
            )
        guard canonicalRecord.meetingID == plan.meetingID,
              canonicalRecord.inputRevisionIDs
                  == [plan.sourceRevision],
              canonicalRecord.dataClassification
                  == plan.dataClassification,
              canonicalRecord.privacyRoute == .localOnly,
              canonicalRecord.state != .succeeded
                  || canonicalRecord.outputRevisionIDs
                      == [expectedCanonicalReference]
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }

        let meeting = try restoredMeetingProfile(
            meetingID: selectedMeetingID,
            runtime: runtime
        )
        guard meeting.revision.dataClassification
                == plan.dataClassification
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        let importedSource = try restoredImportedSource(
            plan: plan,
            runtime: runtime
        )
        let transcriptRecord = newestRecord(
            in: meetingRecords.filter {
                $0.jobType == TranscriptJobTypes.pipeline
            }
        )
        let analysisRecord = newestRecord(
            in: meetingRecords.filter {
                $0.jobType == AnalysisJobTypes.pipeline
            }
        )
        let briefingRecord = newestRecord(
            in: meetingRecords.filter {
                $0.jobType == BriefingJobTypes.pipeline
            }
        )
        if transcriptRecord != nil
            || analysisRecord != nil
            || briefingRecord != nil
        {
            guard canonicalRecord.state == .succeeded else {
                throw AppWorkflowError.workspaceHealthFailed
            }
        }
        if let transcriptRecord {
            guard transcriptRecord.inputRevisionIDs
                    == canonicalRecord.outputRevisionIDs
            else {
                throw AppWorkflowError.workspaceHealthFailed
            }
        }

        let transcriptReview =
            canonicalRecord.state == .succeeded
            ? try runtime.store.activeTranscriptReview(
                meetingID: selectedMeetingID
            )
            : nil
        let analysisReview =
            canonicalRecord.state == .succeeded
            ? try runtime.store.activeAnalysisReview(
                meetingID: selectedMeetingID
            )
            : nil
        let briefingReview =
            canonicalRecord.state == .succeeded
            ? try runtime.store.activeBriefingReview(
                meetingID: selectedMeetingID
            )
            : nil
        guard transcriptRecord?.state != .succeeded
                || transcriptReview != nil,
              analysisRecord?.state != .succeeded
                || analysisReview != nil,
              briefingRecord?.state != .succeeded
                || briefingReview != nil,
              analysisReview == nil
                || transcriptReview != nil,
              briefingReview == nil
                || analysisReview != nil
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }

        let securityPolicy = try securityPolicySnapshot(
            meetingID: selectedMeetingID
        )
        return RestoredMediaWorkflowReview(
            meetingTitle: meeting.title,
            dataClassification:
                meeting.revision.dataClassification,
            sourceLanguage: plan.language,
            codexTextProcessingAllowed:
                securityPolicy?
                .approvedExternalProviderIdentifiers
                .contains(
                    CodexTextExecutionAuthorization
                        .providerIdentifier
                ) == true,
            speechToTextRoute:
                meeting.speechToTextRoute,
            importedSource: importedSource,
            canonicalJob:
                MediaJobReview(record: canonicalRecord),
            transcriptJob:
                transcriptRecord.map(MediaJobReview.init),
            transcriptReview: transcriptReview,
            analysisJob:
                analysisRecord.map(MediaJobReview.init),
            analysisReview: analysisReview,
            briefingJob:
                briefingRecord.map(MediaJobReview.init),
            briefingReview: briefingReview
        )
    }

    func openOrCreateWorkspace(at selectedDirectory: URL) async throws -> WorkspaceReview {
        if let runtime {
            guard (try await runtime.store
                .nonterminalSessions()).isEmpty
            else {
                throw AppWorkflowError
                    .recordingInProgress
            }
            guard try await runtime.manager
                .jobs()
                .allSatisfy(\.state.isTerminal)
            else {
                throw AppWorkflowError
                    .workspaceWorkInProgress
            }
        }
        let candidateScope =
            try workspaceSecurityScope
            .prepare(selectedDirectory)
        let authorizedURL =
            candidateScope.url
        do {
            let descriptor: LocalWorkspaceDescriptor
            do {
                descriptor = try workspaceService.openWorkspace(at: authorizedURL)
            } catch WorkspaceContractError.workspaceManifestMissing {
                descriptor = try workspaceService.createWorkspace(
                    at: authorizedURL,
                    workspaceID: WorkspaceID(UUID()),
                    createdAt: try currentInstant()
                )
            }
            let nextRuntime = try WorkspaceRuntime(
                descriptor: descriptor,
                capabilities: capabilities,
                intelligenceRepository:
                    intelligenceRepository,
                secretStore: secretStore
            )
            try await nextRuntime.recover()
            workspaceSecurityScope
                .commit(candidateScope)
            releasePendingSource()
            runtime = nextRuntime
            workspaceDisplayName = displayName(for: authorizedURL)
            return WorkspaceReview(
                workspaceID: descriptor.manifest.workspaceID,
                displayName: workspaceDisplayName
            )
        } catch let error as AppWorkflowError {
            workspaceSecurityScope
                .discard(candidateScope)
            throw error
        } catch {
            workspaceSecurityScope
                .discard(candidateScope)
            throw AppWorkflowError.workspaceOpenFailed
        }
    }

    func inspectSelectedMedia(at sourceURL: URL) async throws -> PendingMediaReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        releasePendingSource()
        let url = sourceURL.standardizedFileURL
        let didStart = url.startAccessingSecurityScopedResource()
        pendingSourceURL = url
        pendingSourceDidStartScope = didStart
        do {
            let inspection = try await runtime.intake.inspect(url)
            pendingInspection = inspection
            return PendingMediaReview(
                displayName: url.lastPathComponent,
                inspection: inspection
            )
        } catch {
            releasePendingSource()
            if error is MediaContractError {
                throw AppWorkflowError.sourceInspectionFailed
            }
            throw AppWorkflowError.sourceAuthorizationFailed
        }
    }

    func discardPendingMedia() {
        releasePendingSource()
    }

    func importAndProcess(_ submission: MediaImportSubmission) async throws
        -> (ImportedSourceReview, MediaJobReview)
    {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let sourceURL = pendingSourceURL,
              let inspection = pendingInspection
        else {
            throw AppWorkflowError.sourceSelectionExpired
        }
        defer { releasePendingSource() }
        do {
            let createdAt = try currentInstant()
            let approvals =
                try meetingProviderApprovals(
                    codexTextProcessingAllowed:
                        submission
                        .codexTextProcessingAllowed,
                    transcriptionSelection:
                        submission
                        .transcriptionSelection,
                    remoteSpeechToTextAllowed:
                        submission
                        .remoteSpeechToTextAllowed,
                    classification:
                        submission.dataClassification
                )
            let meeting = try meetingProfile(
                title: submission.meetingTitle,
                classification: submission.dataClassification,
                language: submission.language,
                workspaceID: runtime.descriptor.manifest.workspaceID,
                approvedExternalProviderIdentifiers:
                    approvals
                    .approvedExternalProviderIdentifiers,
                speechToTextRoute:
                    approvals.speechToTextRoute,
                createdAt: createdAt
            )
            let meetingUUID = try requiredUUID(meeting.meetingID.canonicalString)
            let securityPolicy = try LocalSecurityPolicyFactory().makeDefault(
                meeting: meeting,
                sensitivityLabelID: SensitivityLabelID(meetingUUID),
                sensitivityLabelRevisionID: RevisionID(UUID()),
                accessPolicyID: AccessPolicyID(meetingUUID),
                accessPolicyRevisionID: RevisionID(UUID()),
                createdAt: createdAt,
                approvedExternalProviderIdentifiers:
                    approvals
                    .approvedExternalProviderIdentifiers
            )
            let selectedTrack = try inspection.requireTrack(submission.selectedTrack)
            let expectedSourceByteSize = try sourceByteSize(sourceURL)
            let intakePlan = try LocalMediaIntakeJobPlan(
                meetingID: meeting.meetingID,
                initialInspection: inspection,
                selectedTrack: selectedTrack.trackIdentifier,
                speechSourceKind: submission.speechSourceKind,
                language: submission.language,
                createdAt: createdAt,
                dataClassification: submission.dataClassification,
                expectedSourceByteSize: expectedSourceByteSize
            )
            let intakeJobID = JobID(UUID())
            let intakeRequest = try LocalMediaIntakeJobFactory().request(
                plan: intakePlan,
                jobID: intakeJobID,
                requestedBy: JobRequester("meetingbuddy-app")
            )
            try runtime.transientSources.register(sourceURL, for: intakeJobID)
            defer { runtime.transientSources.discard(jobID: intakeJobID) }

            try runtime.store.insert(meeting)
            try runtime.store.insert(securityPolicy.sensitivityLabel)
            _ = try runtime.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: securityPolicy.sensitivityLabel.labelID,
                    revisionID: securityPolicy.sensitivityLabel.revision.revisionID
                ),
                as: SensitivityLabelV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: createdAt
            )
            try runtime.store.insert(securityPolicy.accessPolicy)
            _ = try runtime.store.activate(
                ActivePublishedRevisionSelection(
                    logicalID: securityPolicy.accessPolicy.policyID,
                    revisionID: securityPolicy.accessPolicy.revision.revisionID
                ),
                as: AccessPolicyV1.self,
                expectedCurrentRevisionID: nil,
                markedAt: createdAt
            )
            _ = try await runtime.manager.enqueue(intakeRequest)
            let completedIntake = try await terminalJob(
                intakeJobID,
                manager: runtime.manager
            )
            let intakeOutputRevision = try intakePlan.outputRevision
            guard completedIntake.state == .succeeded,
                  completedIntake.outputRevisionIDs == [intakeOutputRevision],
                  let sourceAsset = try runtime.store.sourceAsset(
                      revisionID: intakePlan.sourceRevisionID
                  )
            else {
                throw AppWorkflowError.importFailed
            }
            let sourceReference = try SemanticRevisionReference(
                logicalID: sourceAsset.assetID,
                revisionID: sourceAsset.revision.revisionID
            )
            let plan = try CanonicalAudioJobPlan(
                sourceRevision: sourceReference,
                selectedTrack: selectedTrack.trackIdentifier,
                speechSourceKind: submission.speechSourceKind,
                meetingID: meeting.meetingID,
                createdAt: try currentInstant(),
                dataClassification: submission.dataClassification,
                language: submission.language ?? selectedTrack.language,
                expectedDurationFrames: inspection.durationFrameCount
            )
            let record = try await runtime.manager.enqueue(
                CanonicalAudioJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
            return (
                ImportedSourceReview(
                    assetID: sourceAsset.assetID,
                    revisionID: sourceAsset.revision.revisionID,
                    sourceHash: sourceAsset.sourceContentHash,
                    byteSize: sourceAsset.byteSize,
                    format: inspection.format,
                    durationFrameCount: inspection.durationFrameCount,
                    selectedTrack: selectedTrack.trackIdentifier,
                    speechSourceKind: submission.speechSourceKind
                ),
                MediaJobReview(record: record)
            )
        } catch let error as AppWorkflowError {
            throw error
        } catch {
            throw AppWorkflowError.importFailed
        }
    }

    func jobReview(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let record = try await runtime.manager.job(id: jobID) else {
            throw AppWorkflowError.jobUnavailable
        }
        return MediaJobReview(record: record)
    }

    func cancel(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return MediaJobReview(record: try await runtime.manager.cancel(jobID: jobID))
    }

    func retry(jobID: JobID) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        if let record =
                try await runtime.manager
                .job(id: jobID),
           record.jobType
                == TranscriptJobTypes.pipeline,
           let plan =
                try? TranscriptPipelineJobPlan
                .decode(
                    from:
                        record.inputPayload
                ),
           plan.remoteProviderConfiguration
                != nil
        {
            throw AppWorkflowError
                .remoteAudioAuthorizationRequired
        }
        return MediaJobReview(
            record:
                try await runtime.manager
                .retry(jobID: jobID)
        )
    }

    func transcriptRoute(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> TranscriptRouteReview {
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let selection =
                submission.transcriptionSelection
        else {
            let decision = try ModelPolicyRouter()
                .decide(
                    routeRequest(
                        meetingID:
                            context.plan.meetingID,
                        capability: .transcription,
                        classification:
                            context.plan
                            .dataClassification,
                        categories: [.canonicalAudio],
                        localModelAvailable: false
                    )
                )
            return TranscriptRouteReview(
                transcription: decision,
                translation: nil,
                selection: nil
            )
        }
        let speechDecision: ModelRouteDecision
        let remoteConfiguration:
            RemoteProviderConfiguration?
        let intelligenceRevision: UInt64?
        if selection.providerIdentifier
            == "apple-speech"
        {
            guard selection.modelIdentifier
                    == "speech-analyzer-installed"
            else {
                throw AppWorkflowError
                    .speechToTextConfigurationUnavailable
            }
            let speechInstalled =
                await runtime?.transcriptionProvider?
                .isModelInstalled(
                    for: submission.sourceLanguage
                ) ?? false
            speechDecision = try ModelPolicyRouter()
                .decide(
                    routeRequest(
                        meetingID:
                            context.plan.meetingID,
                        capability: .transcription,
                        classification:
                            context.plan
                            .dataClassification,
                        categories: [.canonicalAudio],
                        localModelAvailable:
                            speechInstalled
                    )
                )
            remoteConfiguration = nil
            intelligenceRevision = nil
        } else {
            let resolved =
                try remoteSpeechConfiguration(
                    selection: selection
                )
            let securityPolicy =
                try securityPolicySnapshot(
                    meetingID:
                        context.plan.meetingID
                )
            guard let securityPolicy else {
                throw AppWorkflowError
                    .remoteAudioAuthorizationRequired
            }
            let request = try ModelRouteRequest(
                capability: .transcription,
                dataClassification:
                    context.plan.dataClassification,
                offlineMode: false,
                organizationAllowsExternalProcessing:
                    securityPolicy
                    .externalProcessingAllowed,
                deploymentEnvironment:
                    .production,
                destination: .approvedProvider(
                    identifier:
                        resolved.configuration
                        .identifier
                ),
                retentionPolicy:
                    .approvedProviderRetention,
                dataCategories: [.canonicalAudio],
                visibleUserAuthorization:
                    submission
                    .visibleRemoteAudioAuthorization,
                localModelAvailable: false,
                securityPolicy: securityPolicy
            )
            if submission
                .visibleRemoteAudioAuthorization
            {
                speechDecision = try ModelPolicyRouter()
                    .authorizeExternal(
                        request,
                        expectedProviderIdentifier:
                            resolved.configuration
                            .identifier
                    ).decision
            } else {
                speechDecision =
                    try ModelPolicyRouter()
                    .decide(request)
            }
            remoteConfiguration =
                resolved.configuration
            intelligenceRevision =
                resolved.revision
        }
        let translationDecision: ModelRouteDecision?
        if let target = submission.targetLanguage {
            let translationInstalled = await runtime?.translationProvider?.isModelInstalled(
                    source: submission.sourceLanguage,
                    target: target
                ) ?? false
            translationDecision = try ModelPolicyRouter().decide(
                routeRequest(
                    meetingID: context.plan.meetingID,
                    capability: .translation,
                    classification: context.plan.dataClassification,
                    categories: [.transcriptText],
                    localModelAvailable:
                        translationInstalled
                )
            )
        } else {
            translationDecision = nil
        }
        return TranscriptRouteReview(
            transcription: speechDecision,
            translation: translationDecision,
            selection: selection,
            intelligenceConfigurationRevision:
                intelligenceRevision,
            remoteProviderConfiguration:
                remoteConfiguration
        )
    }

    func meetingSpeechToTextRoute(
        canonicalJobID: JobID
    ) async throws -> MeetingSpeechToTextRouteV1? {
        guard let runtime else {
            throw AppWorkflowError.workspaceRequired
        }
        let context = try await canonicalContext(
            jobID: canonicalJobID
        )
        if let active = try runtime.store
            .activeRevisionState(
                MeetingProfileV1.self,
                logicalID: context.plan.meetingID
            )?.revision
        {
            return active.speechToTextRoute
        }
        let revisions = try runtime.store.revisions(
            MeetingProfileV1.self,
            logicalID: context.plan.meetingID
        )
        guard revisions.count == 1 else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        return revisions[0].speechToTextRoute
    }

    func startTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission
    ) async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        let route = try await transcriptRoute(
            canonicalJobID: canonicalJobID,
            submission: submission
        )
        guard route.isReady,
              let selection = route.selection,
              route.remoteProviderConfiguration != nil
                || runtime.transcriptionProvider != nil,
              submission.targetLanguage == nil || runtime.translationProvider != nil
        else {
            throw route.selection == nil
                ? AppWorkflowError
                    .speechToTextNotConfigured
                : AppWorkflowError
                    .onDeviceModelUnavailable
        }
        let plan = try TranscriptPipelineJobPlan(
            meetingID: context.plan.meetingID,
            canonicalSourceRevision: context.canonicalReference,
            canonicalFrameCount: context.plan.expectedDurationFrames,
            speechSourceKind: context.plan.speechSourceKind,
            sourceLanguage: submission.sourceLanguage,
            targetLanguage: submission.targetLanguage,
            dataClassification: context.plan.dataClassification,
            createdAt: try currentInstant(),
            transcriptionRoute: route.transcription,
            transcriptionSelection: selection,
            remoteProviderConfiguration:
                route.remoteProviderConfiguration,
            intelligenceConfigurationRevision:
                route.intelligenceConfigurationRevision,
            translationRoute: route.translation
        )
        let jobID = JobID(UUID())
        let request =
            try TranscriptPipelineJobFactory()
            .request(
                plan: plan,
                jobID: jobID,
                requestedBy:
                    JobRequester(
                        "meetingbuddy-app"
                    ),
                maximumRetryCount:
                    plan.remoteProviderConfiguration
                        == nil
                    ? 2
                    : 0
            )
        if plan.remoteProviderConfiguration
            != nil
        {
            try await runtime
                .remoteTranscriptionAuthorization
                .register(
                    jobID: jobID,
                    plan: plan
                )
        }
        do {
            let record =
                try await runtime.manager
                .enqueue(request)
            if record.jobID != jobID {
                await runtime
                    .remoteTranscriptionAuthorization
                    .finish(jobID: jobID)
            }
            return MediaJobReview(
                record: record
            )
        } catch {
            await runtime
                .remoteTranscriptionAuthorization
                .finish(jobID: jobID)
            throw error
        }
    }

    func publishManualTranscript(
        canonicalJobID: JobID,
        submission: TranscriptStartSubmission,
        transcriptText: String,
        translatedText: String?,
        confirmsCompleteCoverage: Bool
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard confirmsCompleteCoverage else { throw AppWorkflowError.reviewFailed }
        let context = try await canonicalContext(jobID: canonicalJobID)
        let speechRoute = try ModelPolicyRouter().decide(
            routeRequest(
                meetingID: context.plan.meetingID,
                capability: .transcription,
                classification: context.plan.dataClassification,
                categories: [.canonicalAudio],
                localModelAvailable: false
            )
        )
        let translationRoute = try submission.targetLanguage.map { _ in
            try ModelPolicyRouter().decide(
                routeRequest(
                    meetingID: context.plan.meetingID,
                    capability: .translation,
                    classification: context.plan.dataClassification,
                    categories: [.transcriptText],
                    localModelAvailable: false
                )
            )
        }
        let publication = try TranscriptSemanticFactory.manualPublication(
            meetingID: context.plan.meetingID,
            canonicalSource: context.canonicalReference,
            canonicalFrameCount: context.plan.expectedDurationFrames,
            speechSourceKind: context.plan.speechSourceKind,
            sourceLanguage: submission.sourceLanguage,
            transcriptText: transcriptText,
            targetLanguage: submission.targetLanguage,
            translatedText: translatedText,
            confirmsCompleteCoverage: confirmsCompleteCoverage,
            classification: context.plan.dataClassification,
            transcriptionRoute: speechRoute,
            translationRoute: translationRoute,
            createdAt: try currentInstant()
        )
        try runtime.store.publishTranscript(
            publication,
            validatingInputRevisions: [context.canonicalReference]
        )
        guard let review = try runtime.store.activeTranscriptReview(
            meetingID: context.plan.meetingID
        ) else { throw AppWorkflowError.transcriptUnavailable }
        return review
    }

    func transcriptReview(canonicalJobID: JobID) async throws -> TranscriptReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID)
    }

    func correctTranscript(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let prior = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == revisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let correction = try TranscriptSemanticFactory.correctedTranscript(
            prior: prior,
            text: text,
            changedAt: changedAt
        )
        let manifest = try TranscriptSemanticFactory.replacingTranscript(
            in: review.manifest,
            oldRevisionID: revisionID,
            with: correction,
            at: changedAt
        )
        try runtime.store.saveTranscriptCorrection(
            correction,
            replacing: revisionID,
            updatedManifest: manifest,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func correctTranslation(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        text: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let prior = review.translations.first(where: { $0.revision.revisionID == revisionID }),
              let transcript = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == prior.sourceSegmentRevision.revisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let correction = try TranscriptSemanticFactory.correctedTranslation(
            prior: prior,
            sourceTranscript: transcript,
            text: text,
            changedAt: changedAt
        )
        let manifest = try TranscriptSemanticFactory.replacingTranslation(
            in: review.manifest,
            oldRevisionID: revisionID,
            with: correction,
            at: changedAt
        )
        try runtime.store.saveTranslationCorrection(
            correction,
            replacing: revisionID,
            updatedManifest: manifest,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func confirmSpeaker(
        canonicalJobID: JobID,
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async throws -> TranscriptReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID),
              let transcript = review.transcriptSegments.first(where: {
                  $0.revision.revisionID == transcriptRevisionID
              })
        else { throw AppWorkflowError.transcriptUnavailable }
        let changedAt = try currentInstant()
        let confirmation = try TranscriptSemanticFactory.speakerConfirmation(
            transcript: transcript,
            displayName: displayName,
            changedAt: changedAt
        )
        try runtime.store.publishSpeakerConfirmation(
            actor: confirmation.0,
            capacity: confirmation.1,
            evidence: confirmation.2,
            assignment: confirmation.3,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeTranscriptReview(meetingID: context.plan.meetingID) else {
            throw AppWorkflowError.reviewFailed
        }
        return updated
    }

    func analysisRoute(canonicalJobID: JobID) async throws -> AnalysisRouteReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let source = try await analysisSource(canonicalJobID: canonicalJobID)
        let locale = source.meeting.outputLanguage.value
        let modelAvailable = await runtime.analysisProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let request = try analysisRouteRequest(
            source: source,
            modelAvailable: modelAvailable,
            visibleUserAuthorization: false
        )
        return AnalysisRouteReview(
            analysis: try ModelPolicyRouter().decide(request),
            runtimeEvidence: try analysisRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: modelAvailable
            )
        )
    }

    func startAnalysis(canonicalJobID: JobID) async throws -> MediaJobReview {
        guard let runtime,
              runtime.analysisProvider != nil
        else { throw AppWorkflowError.onDeviceModelUnavailable }
        let source = try await analysisSource(canonicalJobID: canonicalJobID)
        let locale = source.meeting.outputLanguage.value
        let modelAvailable = await runtime.analysisProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let decision = try ModelPolicyRouter().decide(
            analysisRouteRequest(
                source: source,
                modelAvailable: modelAvailable,
                visibleUserAuthorization: true
            )
        )
        guard decision.route == .appleOnDevice,
              decision.providerIdentifier == "apple-foundation-models",
              modelAvailable
        else { throw AppWorkflowError.onDeviceModelUnavailable }
        let plan = try AnalysisPipelineJobPlan(
            source: source,
            analysisRoute: decision,
            runtimeEvidence: analysisRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: true
            ),
            createdAt: try currentInstant()
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                AnalysisPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func analysisReview(canonicalJobID: JobID) async throws -> AnalysisReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeAnalysisReview(meetingID: context.plan.meetingID)
    }

    func confirmAnalysisReview(
        canonicalJobID: JobID,
        confirmsEveryClaim: Bool
    ) async throws -> AnalysisReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try AnalysisManualReviewService(repository: runtime.store).confirmCurrent(
            meetingID: context.plan.meetingID,
            confirmsEveryClaim: confirmsEveryClaim,
            confirmedAt: try currentInstant()
        )
    }

    func correctPosition(
        canonicalJobID: JobID,
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async throws -> AnalysisReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ),
            review.isHumanConfirmed,
            let prior = review.positions.first(where: {
                $0.revision.revisionID == revisionID
            })
        else { throw AppWorkflowError.analysisUnavailable }
        let changedAt = try currentInstant()
        let correction = try AnalysisSemanticFactory.correctedPosition(
            prior: prior,
            positionType: positionType,
            statement: statement,
            reservations: reservations,
            conditions: conditions,
            changedAt: changedAt
        )
        try runtime.store.savePositionCorrection(
            correction,
            replacing: revisionID,
            changedAt: changedAt
        )
        guard let updated = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ) else { throw AppWorkflowError.reviewFailed }
        return updated
    }

    func briefingRoute(canonicalJobID: JobID) async throws -> BriefingRouteReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let template = try BriefingSemanticFactory.builtInTemplate(
            createdAt: try currentInstant()
        )
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: template
        )
        let locale = source.meeting.outputLanguage.value
        let available = await runtime.briefingProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        return BriefingRouteReview(
            briefing: try ModelPolicyRouter().decide(
                briefingRouteRequest(
                    source: source,
                    modelAvailable: available,
                    visibleUserAuthorization: false
                )
            ),
            runtimeEvidence: try briefingRuntimeEvidence(
                localeIdentifier: locale,
                modelAvailable: available
            )
        )
    }

    func startBriefing(canonicalJobID: JobID) async throws -> MediaJobReview {
        guard let runtime, runtime.briefingProvider != nil else {
            throw AppWorkflowError.onDeviceModelUnavailable
        }
        let createdAt = try currentInstant()
        let template = try BriefingSemanticFactory.builtInTemplate(createdAt: createdAt)
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: template
        )
        guard try runtime.store.activeBriefingReview(meetingID: source.meeting.meetingID) == nil
        else { throw AppWorkflowError.reviewFailed }
        let decision = try await approvedBriefingRoute(
            source: source,
            visibleUserAuthorization: true
        )
        let plan = try BriefingPipelineJobPlan(
            source: source,
            sectionRoute: decision,
            createdAt: createdAt
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                BriefingPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func briefingReview(canonicalJobID: JobID) async throws -> BriefingReviewBundle? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try runtime.store.activeBriefingReview(meetingID: context.plan.meetingID)
    }

    func regenerateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType
    ) async throws -> MediaJobReview {
        guard let runtime, runtime.briefingProvider != nil else {
            throw AppWorkflowError.onDeviceModelUnavailable
        }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let active = try runtime.store.activeBriefingReview(
            meetingID: context.plan.meetingID
        ),
            active.isCurrent,
            let section = active.publication.sections.first(where: {
                $0.sectionType == sectionType
            }),
            !section.locked,
            section.manualEditStatus == .generated
        else { throw AppWorkflowError.briefingUnavailable }
        let source = try await briefingSource(
            canonicalJobID: canonicalJobID,
            template: active.publication.template
        )
        let createdAt = try currentInstant()
        let operation = BriefingJobOperation.regenerate(
            sectionType: sectionType,
            expectedSectionRevisionID: section.revision.revisionID,
            graphRevision: try semanticReference(active.publication.graph),
            sectionRevisions: try active.publication.sections.map(semanticReference),
            validationReportRevision: try semanticReference(
                active.publication.validationReport
            ),
            finalBriefingRevision: try semanticReference(
                active.publication.finalBriefing
            ),
            briefingLedgerID: active.publication.ledger.ledgerID
        )
        let plan = try BriefingPipelineJobPlan(
            source: source,
            sectionRoute: try await approvedBriefingRoute(
                source: source,
                visibleUserAuthorization: true
            ),
            operation: operation,
            createdAt: createdAt
        )
        return MediaJobReview(
            record: try await runtime.manager.enqueue(
                BriefingPipelineJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        )
    }

    func updateBriefingSection(
        canonicalJobID: JobID,
        sectionType: BriefingSectionType,
        expectedRevisionID: RevisionID,
        editedTextByItemID: [BriefingItemID: String],
        locked: Bool
    ) async throws -> BriefingReviewBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        return try BriefingManualReviewService(repository: runtime.store).updateSection(
            meetingID: context.plan.meetingID,
            sectionType: sectionType,
            expectedRevisionID: expectedRevisionID,
            editedTextByItemID: editedTextByItemID,
            locked: locked,
            changedAt: try currentInstant()
        )
    }

    func exportBriefingMarkdown(
        canonicalJobID: JobID,
        fileName: String,
        expectedClassification: DataClassification
    ) async throws -> BriefingExportRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let active = try runtime.store.activeBriefingReview(
            meetingID: context.plan.meetingID
        ), active.isCurrent else { throw AppWorkflowError.briefingUnavailable }
        return try LocalMarkdownExportService(store: runtime.store).exportMarkdown(
            BriefingMarkdownExportRequest(
                meetingID: context.plan.meetingID,
                finalBriefingRevision: try semanticReference(
                    active.publication.finalBriefing
                ),
                fileName: fileName,
                expectedClassification: expectedClassification,
                explicitUserAuthorization: true,
                requestedAt: try currentInstant()
            )
        )
    }

    func storageReport() async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.storageReporter.storageReport(
            calculatedAt: currentInstant(),
            maximumEntries: 100_000
        )
    }

    func historicalIndexStatus() async throws -> HistoricalIndexStatus {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.historicalIndexStatus()
    }

    func rebuildHistoricalIndex() async throws -> MediaJobReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let plan = try HistoricalIndexRebuildJobPlan(requestedAt: currentInstant())
        let record = try await runtime.manager.enqueue(
            HistoricalIndexRebuildJobFactory().request(
                plan: plan,
                requestedBy: JobRequester("meetingbuddy-app")
            )
        )
        return MediaJobReview(record: record)
    }

    func searchMeetingHistory(
        _ query: HistoricalSearchQuery
    ) async throws -> HistoricalSearchPage {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        do {
            return try runtime.store.searchHistory(query)
        } catch let error as HistoricalReviewError {
            throw error
        } catch {
            throw AppWorkflowError.historicalReviewUnavailable
        }
    }

    func compareHistoricalPositions(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) async throws -> HistoricalComparisonV1 {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let evaluation = HistoricalComparisonEvaluator.evaluate(
            current: current,
            historical: historical
        )
        let candidate = try HistoricalComparisonFactory.candidate(
            evaluation: evaluation,
            createdAt: currentInstant()
        )
        try runtime.store.publishHistoricalComparison(
            candidate,
            expectedCurrentRevisionID: nil,
            changedAt: candidate.revision.createdAt
        )
        return candidate
    }

    func confirmHistoricalChange(
        candidateRevisionID: RevisionID
    ) async throws -> HistoricalComparisonV1 {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let candidate = try runtime.store.fetch(
            HistoricalComparisonV1.self,
            revisionID: candidateRevisionID
        ) else { throw HistoricalReviewError.sourceUnavailable(candidateRevisionID) }
        let confirmed = try HistoricalComparisonFactory.confirmedChange(
            candidate: candidate,
            confirmedAt: currentInstant()
        )
        try runtime.store.publishHistoricalComparison(
            confirmed,
            expectedCurrentRevisionID: candidate.revision.revisionID,
            changedAt: confirmed.revision.createdAt
        )
        return confirmed
    }

    func learnedPreferenceState() async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.learnedPreferenceState(maximumEvents: 100)
    }

    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?
    ) async throws -> LearnedPreferenceRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.saveLearnedPreference(
            preferenceID: preferenceID,
            value: value,
            enabled: enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceRecord {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.setLearnedPreferenceEnabled(
            preferenceID: preferenceID,
            enabled: enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        try runtime.store.removeLearnedPreference(
            preferenceID: preferenceID,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.setLearnedPreferencesGloballyEnabled(
            enabled,
            sourceAction: sourceAction,
            expectedVersion: expectedVersion,
            changedAt: currentInstant()
        )
    }

    func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64
    ) async throws -> LearnedPreferenceState {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        return try runtime.store.resetLearnedPreferences(
            sourceAction: sourceAction,
            expectedSettingsVersion: expectedSettingsVersion,
            changedAt: currentInstant()
        )
    }

    func restoreTrashItem(
        storageObjectID: StorageObjectID
    ) async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        _ = try runtime.coordinator.restoreFromTrash(
            storageObjectID: storageObjectID,
            at: currentInstant()
        )
        return try await storageReport()
    }

    func permanentlyDeleteTrashItem(
        storageObjectID: StorageObjectID,
        confirmsPermanentDeletion: Bool,
        acknowledgesUnlinkIsNotSecureErasure: Bool
    ) async throws -> WorkspaceStorageReport {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let timestamp = try currentInstant()
        let method: ManagedAssetDeletionMethod = .filesystemUnlinkNoErasureGuarantee
        guard acknowledgesUnlinkIsNotSecureErasure else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Permanent deletion requires acknowledgment of filesystem unlink semantics."
            )
        }
        let authorization = try ManagedAssetPurgeAuthorization(
            purgeID: UUID(),
            storageObjectID: storageObjectID,
            confirmedAt: timestamp,
            visibleUserConfirmation: confirmsPermanentDeletion,
            acknowledgedDeletionMethod: method
        )
        _ = try runtime.coordinator.permanentlyDeleteFromTrash(
            storageObjectID: storageObjectID,
            authorization: authorization
        )
        return try await storageReport()
    }

    func recordingSetup() async throws -> RecordingSetupReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let sessions = try await runtime.store.nonterminalSessions()
        guard sessions.count <= 1 else { throw AppWorkflowError.workspaceHealthFailed }
        let recoveredSession: RecordingSessionSnapshot?
        if let recovered = runtime.mostRecentRecoveredRecordingSession {
            recoveredSession = try await runtime.store.session(recovered.intent.sessionID)
        } else {
            recoveredSession = nil
        }
        let completedAwaitingProcessing:
            RecordingSessionSnapshot?
        if sessions.first == nil,
           recoveredSession == nil
        {
            completedAwaitingProcessing =
                try await latestCompletedRecordingAwaitingProcessing(
                    runtime: runtime
                )
        } else {
            completedAwaitingProcessing =
                nil
        }
        let visibleSession =
            sessions.first
            ?? recoveredSession
            ?? completedAwaitingProcessing
        let recoverable: RecordingSessionReview?
        if let session = visibleSession {
            recoverable = try await recordingReview(snapshot: session, runtime: runtime)
        } else {
            recoverable = nil
        }
        return RecordingSetupReview(
            capability: await runtime.captureProvider.snapshot(),
            microphones: try await runtime.captureProvider.microphones(),
            recoverableSession: recoverable
        )
    }

    private func latestCompletedRecordingAwaitingProcessing(
        runtime: WorkspaceRuntime
    ) async throws -> RecordingSessionSnapshot? {
        let records =
            try await runtime.manager.jobs()
        let canonicalMeetingIDs =
            Set(
                records.compactMap {
                    $0.jobType
                        == MediaJobTypes
                        .canonicalAudio
                        ? $0.meetingID
                        : nil
                }
            )
        let completedRecordingJobs =
            records.filter {
                $0.jobType
                    == MediaJobTypes
                    .recordingCapture
                    && $0.state == .succeeded
                    && !$0.outputRevisionIDs
                        .isEmpty
                    && $0.meetingID.map {
                        !canonicalMeetingIDs
                            .contains($0)
                    } == true
            }
        var candidates:
            [(JobRecord, RecordingSessionSnapshot)] = []
        candidates.reserveCapacity(
            completedRecordingJobs.count
        )
        for record in completedRecordingJobs {
            let plan =
                try RecordingCaptureJobPlan
                .decode(
                    from: record.inputPayload
                )
            guard
                record.jobID
                    == plan.intent.jobID,
                record.meetingID
                    == plan.intent.meetingID,
                record.outputRevisionIDs
                    == (try plan
                        .completedOutputRevisions),
                let snapshot =
                    try await runtime.store
                    .session(
                        plan.intent.sessionID
                    ),
                snapshot.intent == plan.intent,
                snapshot.state == .completed
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            candidates.append(
                (record, snapshot)
            )
        }
        return candidates.max {
            if $0.0.createdAt
                != $1.0.createdAt
            {
                return $0.0.createdAt
                    < $1.0.createdAt
            }
            return $0.0.jobID
                < $1.0.jobID
        }?.1
    }

    func startRecording(
        _ submission: RecordingStartSubmission
    ) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard submission.directUserAcknowledgement else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }
        guard try await runtime.store.nonterminalSessions().isEmpty else {
            throw AppWorkflowError.recordingInProgress
        }
        let title = submission.meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 2_048 else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }

        let capability = await runtime.captureProvider.snapshot()
        if submission.mode.requestedTrackKinds.contains(.applicationAudio) {
            guard capability.applicationAudioAvailable, capability.systemPickerAvailable else {
                throw AppWorkflowError.recordingUnavailable
            }
        }
        let microphone: CaptureMicrophoneChoice?
        if submission.mode.requestedTrackKinds.contains(.microphone) {
            guard let microphoneID = submission.microphoneDeviceID,
                  let selected = try await runtime.captureProvider.microphones().first(where: {
                      $0.id == microphoneID
                  })
            else { throw AppWorkflowError.recordingAuthorizationRequired }
            microphone = selected
        } else {
            guard submission.microphoneDeviceID == nil else {
                throw AppWorkflowError.recordingAuthorizationRequired
            }
            microphone = nil
        }

        let sessionID = RecordingSessionID(UUID())
        let jobID = JobID(UUID())
        let epochID = RecordingEpochID(UUID())
        var trackRequests: [RecordingTrackRequest] = []
        if submission.mode.requestedTrackKinds.contains(.microphone) {
            trackRequests.append(
                try RecordingTrackRequest(
                    kind: .microphone,
                    speechSourceKind: submission.microphoneSpeechSourceKind,
                    language: submission.language
                )
            )
        }
        if submission.mode.requestedTrackKinds.contains(.applicationAudio) {
            trackRequests.append(
                try RecordingTrackRequest(
                    kind: .applicationAudio,
                    speechSourceKind: submission.applicationSpeechSourceKind,
                    language: submission.language
                )
            )
        }

        let selection = try await runtime.captureProvider.requestSelection(
            CaptureSelectionRequest(
                sessionID: sessionID,
                epochID: epochID,
                mode: submission.mode,
                microphoneDeviceID: microphone?.id
            )
        )
        let applicationFormat = try CaptureAudioFormat(
            sampleRateHertz: 48_000,
            channelCount: 2,
            channelLayout: "interleaved-pcm-s16le",
            formatRevision: 1
        )
        let epochSources = try trackRequests.map { request -> RecordingEpochSource in
            switch request.kind {
            case .microphone:
                guard let microphone else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: sessionScopedSourceToken(
                        sessionID: sessionID,
                        sourceClass: "microphone",
                        platformIdentifier: microphone.id,
                        selectedAt: selection.selectedAt,
                        format: microphone.audioFormat
                    ),
                    audioFormat: microphone.audioFormat
                )
            case .applicationAudio:
                guard let token = selection.applicationSourceToken else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: token,
                    audioFormat: applicationFormat
                )
            }
        }
        let epoch = try RecordingEpoch(
            epochID: epochID,
            sessionID: sessionID,
            sequence: 1,
            selectedAt: selection.selectedAt,
            sources: epochSources,
            sourceSetDigest: try sourceSetDigest(epochSources),
            startHostNanoseconds: DispatchTime.now().uptimeNanoseconds
        )

        let createdAt = try currentInstant()
        let approvals =
            try meetingProviderApprovals(
                codexTextProcessingAllowed:
                    submission
                    .codexTextProcessingAllowed,
                transcriptionSelection:
                    submission
                    .transcriptionSelection,
                remoteSpeechToTextAllowed:
                    submission
                    .remoteSpeechToTextAllowed,
                classification:
                    submission.dataClassification
            )
        let meeting = try meetingProfile(
            title: title,
            classification: submission.dataClassification,
            language: submission.language,
            workspaceID: runtime.descriptor.manifest.workspaceID,
            approvedExternalProviderIdentifiers:
                approvals
                .approvedExternalProviderIdentifiers,
            speechToTextRoute:
                approvals.speechToTextRoute,
            createdAt: createdAt
        )
        let policy = try persistMeetingAndDefaultPolicy(
            meeting,
            createdAt: createdAt,
            runtime: runtime,
            approvedExternalProviderIdentifiers:
                approvals
                .approvedExternalProviderIdentifiers
        )
        let policySnapshot = try RecordingPolicySnapshot(
            sensitivityLabelRevision: semanticReference(policy.sensitivityLabel),
            accessPolicyRevision: semanticReference(policy.accessPolicy),
            dataClassification: policy.accessPolicy.effectiveClassification,
            localProcessingAllowed: policy.accessPolicy.localProcessingAllowed,
            noOutboundMode: policy.accessPolicy.noOutboundMode
        )
        let intent = try RecordingIntent(
            sessionID: sessionID,
            jobID: jobID,
            meetingID: meeting.meetingID,
            mode: submission.mode,
            requestedTracks: trackRequests,
            policy: policySnapshot,
            authorization: RecordingAuthorizationEvent(
                occurredAt: selection.selectedAt,
                directUserAction: true,
                visibleRecordingAcknowledged: true,
                participantAndPolicyResponsibilityAcknowledged: true
            ),
            diskBudgetBytes: 8 * 1_024 * 1_024 * 1_024,
            createdAt: createdAt
        )
        let plan = try RecordingCaptureJobPlan(intent: intent, initialEpoch: epoch)
        let initial = try await runtime.store.createIntent(intent)
        try await runtime.store.registerEpoch(epoch)

        let prepared: PreparedCapture
        do {
            prepared = try await runtime.captureProvider.prepare(
                PreparedCaptureRequest(
                    authorization: selection,
                    tracks: trackRequests
                )
            )
        } catch {
            let failureReason: RecordingTransitionReason
            if case CaptureProviderError.permissionDenied = error {
                failureReason = .permissionDenied
            } else {
                failureReason = .sourceUnavailable
            }
            _ = try? await runtime.store.transition(
                RecordingTransition(
                    sessionID: sessionID,
                    expectedStateVersion: initial.stateVersion,
                    from: .preparing,
                    to: .failed,
                    reason: failureReason,
                    actor: .captureProvider,
                    occurredAt: try currentInstant()
                )
            )
            throw error
        }

        try await runtime.captureRegistry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: prepared,
                epoch: epoch,
                provider: runtime.captureProvider
            ),
            for: jobID
        )
        do {
            _ = try await runtime.manager.enqueue(
                RecordingCaptureJobFactory().request(
                    plan: plan,
                    requestedBy: JobRequester("meetingbuddy-app")
                )
            )
        } catch {
            await runtime.captureRegistry.discard(jobID: jobID)
            if let snapshot = try? await runtime.store.session(sessionID), snapshot.state == .preparing {
                _ = try? await runtime.store.transition(
                    RecordingTransition(
                        sessionID: sessionID,
                        expectedStateVersion: snapshot.stateVersion,
                        from: .preparing,
                        to: .failed,
                        reason: .sourceUnavailable,
                        actor: .taskManager,
                        occurredAt: try currentInstant()
                    )
                )
            }
            throw error
        }
        return try await recordingReview(jobID: jobID)
    }

    func recordingReview(jobID: JobID) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let snapshot = try await runtime.store.session(jobID: jobID) else {
            throw AppWorkflowError.recordingUnavailable
        }
        return try await recordingReview(snapshot: snapshot, runtime: runtime)
    }

    func resumeRecording(
        jobID: JobID,
        submission: RecordingResumeSubmission
    ) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard submission.directUserAcknowledgement else {
            throw AppWorkflowError.recordingAuthorizationRequired
        }
        guard let snapshot = try await runtime.store.session(jobID: jobID),
              snapshot.state == .interrupted || snapshot.state == .recovering,
              let job = try await runtime.manager.job(id: jobID),
              job.state == .failed || job.state == .interrupted
        else {
            throw AppWorkflowError.recordingUnavailable
        }

        let mode = snapshot.intent.mode
        let capability = await runtime.captureProvider.snapshot()
        if mode.requestedTrackKinds.contains(.applicationAudio) {
            guard capability.applicationAudioAvailable, capability.systemPickerAvailable else {
                throw AppWorkflowError.recordingUnavailable
            }
        }
        let microphone: CaptureMicrophoneChoice?
        if mode.requestedTrackKinds.contains(.microphone) {
            guard let microphoneID = submission.microphoneDeviceID,
                  let selected = try await runtime.captureProvider.microphones().first(where: {
                      $0.id == microphoneID
                  })
            else { throw AppWorkflowError.recordingAuthorizationRequired }
            microphone = selected
        } else {
            guard submission.microphoneDeviceID == nil else {
                throw AppWorkflowError.recordingAuthorizationRequired
            }
            microphone = nil
        }

        let priorEpochs = try await runtime.store.epochs(sessionID: snapshot.intent.sessionID)
        guard let priorSequence = priorEpochs.map(\.sequence).max(),
              priorSequence < UInt32.max
        else { throw AppWorkflowError.recordingUnavailable }
        let epochID = RecordingEpochID(UUID())
        let selection = try await runtime.captureProvider.requestSelection(
            CaptureSelectionRequest(
                sessionID: snapshot.intent.sessionID,
                epochID: epochID,
                mode: mode,
                microphoneDeviceID: microphone?.id
            )
        )
        let applicationFormat = try CaptureAudioFormat(
            sampleRateHertz: 48_000,
            channelCount: 2,
            channelLayout: "interleaved-pcm-s16le",
            formatRevision: 1
        )
        let epochSources = try snapshot.intent.requestedTracks.map {
            request -> RecordingEpochSource in
            switch request.kind {
            case .microphone:
                guard let microphone else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: sessionScopedSourceToken(
                        sessionID: snapshot.intent.sessionID,
                        sourceClass: "microphone",
                        platformIdentifier: microphone.id,
                        selectedAt: selection.selectedAt,
                        format: microphone.audioFormat
                    ),
                    audioFormat: microphone.audioFormat
                )
            case .applicationAudio:
                guard let token = selection.applicationSourceToken else {
                    throw AppWorkflowError.recordingAuthorizationRequired
                }
                return try RecordingEpochSource(
                    trackID: request.trackID,
                    kind: request.kind,
                    sessionScopedDeviceToken: token,
                    audioFormat: applicationFormat
                )
            }
        }
        let epoch = try RecordingEpoch(
            epochID: epochID,
            sessionID: snapshot.intent.sessionID,
            sequence: priorSequence + 1,
            selectedAt: selection.selectedAt,
            sources: epochSources,
            sourceSetDigest: try sourceSetDigest(epochSources),
            startHostNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        let prepared = try await runtime.captureProvider.prepare(
            PreparedCaptureRequest(
                authorization: selection,
                tracks: snapshot.intent.requestedTracks
            )
        )

        if snapshot.state == .interrupted {
            _ = try await runtime.recordingRecovery.recover(snapshot.intent.sessionID)
        }
        try await runtime.captureRegistry.register(
            RecordingCaptureExecutionAuthority(
                preparedCapture: prepared,
                epoch: epoch,
                provider: runtime.captureProvider
            ),
            for: jobID
        )
        do {
            _ = try await runtime.manager.retry(jobID: jobID)
        } catch {
            await runtime.captureRegistry.discard(jobID: jobID)
            throw error
        }
        return try await recordingReview(jobID: jobID)
    }

    func stopRecording(jobID: JobID) async throws -> RecordingSessionReview {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let snapshot = try await runtime.store.session(jobID: jobID) else {
            throw AppWorkflowError.recordingUnavailable
        }
        if snapshot.state.isTerminal {
            return try await recordingReview(snapshot: snapshot, runtime: runtime)
        }

        let job = try await runtime.manager.job(id: jobID)
        if let job, job.state.isActiveExecution || job.state == .queued {
            _ = try await runtime.manager.cancel(jobID: jobID)
        } else {
            let outcome = try await runtime.recordingRecovery.recover(snapshot.intent.sessionID)
            let coordinator = RecordingPersistenceCoordinator(
                repository: runtime.store,
                fileStore: runtime.recordingFileStore,
                assetStorage: runtime.coordinator,
                assetCatalog: runtime.store,
                assetFileAccess: runtime.fileAccess
            )
            _ = try await coordinator.restore(
                outcome: outcome,
                epochs: try await runtime.store.epochs(sessionID: snapshot.intent.sessionID)
            )
            _ = try await coordinator.stop(reason: .recoveredWithoutResume)
        }

        for _ in 0..<100 {
            if let current = try await runtime.store.session(jobID: jobID), current.state.isTerminal {
                return try await recordingReview(snapshot: current, runtime: runtime)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AppWorkflowError.recordingUnavailable
    }

    func processCompletedRecording(
        jobID: JobID,
        trackID: RecordingTrackID
    ) async throws -> MediaJobReview {
        guard let runtime else {
            throw AppWorkflowError.workspaceRequired
        }
        guard let snapshot =
                try await runtime.store.session(
                    jobID: jobID
                ),
              snapshot.state == .completed
        else {
            throw AppWorkflowError
                .recordingUnavailable
        }
        let tracks =
            try await completedRecordingTracks(
                snapshot: snapshot,
                runtime: runtime
            )
        guard let selected =
                tracks.first(where: {
                    $0.trackID == trackID
                })
        else {
            throw AppWorkflowError
                .recordingUnavailable
        }

        let existing = try await runtime
            .manager.jobs()
            .filter {
                $0.jobType
                    == MediaJobTypes
                    .canonicalAudio
                    && $0.meetingID
                        == snapshot
                        .intent.meetingID
            }
        guard existing.count <= 1 else {
            throw AppWorkflowError
                .workspaceHealthFailed
        }
        if let record = existing.first {
            let plan =
                try CanonicalAudioJobPlan.decode(
                    from: record.inputPayload
                )
            guard
                plan.meetingID
                    == snapshot.intent.meetingID,
                plan.sourceRevision
                    == selected.sourceRevision,
                plan.selectedTrack
                    == selected
                    .mediaTrackIdentifier,
                plan.speechSourceKind
                    == selected
                    .speechSourceKind,
                plan.expectedDurationFrames
                    == selected
                    .durationFrameCount,
                plan.dataClassification
                    == snapshot.intent.policy
                    .dataClassification
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            return MediaJobReview(
                record: record
            )
        }

        let plan = try CanonicalAudioJobPlan(
            sourceRevision:
                selected.sourceRevision,
            selectedTrack:
                selected.mediaTrackIdentifier,
            speechSourceKind:
                selected.speechSourceKind,
            meetingID:
                snapshot.intent.meetingID,
            createdAt: try currentInstant(),
            dataClassification:
                snapshot.intent.policy
                .dataClassification,
            language: selected.language,
            expectedDurationFrames:
                selected.durationFrameCount
        )
        return MediaJobReview(
            record:
                try await runtime.manager.enqueue(
                    CanonicalAudioJobFactory()
                        .request(
                            plan: plan,
                            requestedBy:
                                JobRequester(
                                    "meetingbuddy-app"
                                )
                        )
                )
        )
    }

    func fetchUNWebTVMetadata(
        url: String,
        explicitNetworkAuthorization: Bool
    ) async throws -> UNWebTVMetadataCandidate {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        do {
            return try await runtime.metadataSource.metadataCandidate(
                for: ValidatedUNWebTVAssetURL(url),
                policy: UNWebTVMetadataRequestPolicy(
                    directUserAction: explicitNetworkAuthorization,
                    outboundEnabled: explicitNetworkAuthorization
                )
            )
        } catch {
            throw AppWorkflowError.webMetadataUnavailable
        }
    }

    func codexTurnRequest(
        canonicalJobID: JobID,
        selectedSegmentIDs: [TranscriptSegmentID],
        prompt: String,
        visibleUserAuthorization: Bool
    ) async throws -> CodexMeetingTurnRequest {
        guard let runtime else {
            throw AppWorkflowError.workspaceRequired
        }
        let canonical = try await canonicalContext(
            jobID: canonicalJobID
        )
        let meetingID = canonical.plan.meetingID
        guard let transcript = try runtime.store
            .activeTranscriptReview(meetingID: meetingID),
              transcript.manifest.status == .published,
              !selectedSegmentIDs.isEmpty,
              Set(selectedSegmentIDs).count
                  == selectedSegmentIDs.count
        else {
            throw AppWorkflowError.codexContextUnavailable
        }
        let selected = transcript.transcriptSegments.filter {
            selectedSegmentIDs.contains($0.segmentID)
        }
        guard selected.count == selectedSegmentIDs.count else {
            throw AppWorkflowError.codexContextUnavailable
        }

        let meetingState = try runtime.store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: meetingID
        )
        let meeting: MeetingProfileV1
        if let meetingState {
            meeting = meetingState.revision
        } else {
            let revisions = try runtime.store.revisions(
                MeetingProfileV1.self,
                logicalID: meetingID
            )
            guard revisions.count == 1,
                  let only = revisions.first
            else {
                throw AppWorkflowError.codexContextUnavailable
            }
            meeting = only
        }
        let labelID = try SensitivityLabelID(
            validating: meetingID.canonicalString
        )
        let policyID = try AccessPolicyID(
            validating: meetingID.canonicalString
        )
        guard let sensitivityLabel = try runtime.store
            .activeRevisionState(
                SensitivityLabelV1.self,
                logicalID: labelID
            )?.revision,
              let accessPolicy = try runtime.store
                .activeRevisionState(
                    AccessPolicyV1.self,
                    logicalID: policyID
                )?.revision,
              let securityPolicy = try securityPolicySnapshot(
                meetingID: meetingID
              )
        else {
            throw AppWorkflowError.codexContextUnavailable
        }
        let routingContext = try TaskRoutingSecurityContext(
            meeting: meeting,
            sensitivityLabel: sensitivityLabel,
            accessPolicy: accessPolicy,
            securityPolicy: securityPolicy
        )
        let selection = try ProviderModelSelection(
            providerIdentifier:
                CodexTextExecutionAuthorization
                .providerIdentifier,
            modelIdentifier: "codex-default"
        )
        let profile = try TaskRoutingProfile(
            identifier: "v4-codex-text",
            displayName: "Codex Text",
            scope: .global,
            routes: [
                TaskRoutePreference(
                    task: .meetingChat,
                    routeOverride: .selection(
                        primary: selection,
                        fallback: nil
                    )
                )
            ]
        )
        let resolution = TaskRoutingResolver().resolve(
            task: .meetingChat,
            scopeStack: try TaskRoutingScopeStack(
                securityContext: routingContext,
                global: profile
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
        guard case let .requiresExecutionAuthorization(candidate) =
            resolution
        else {
            throw AppWorkflowError.codexContextUnavailable
        }
        let routeRequest = try ModelRouteRequest(
            capability: .analysis,
            dataClassification:
                securityPolicy.effectiveClassification,
            offlineMode: false,
            organizationAllowsExternalProcessing:
                accessPolicy
                .organizationAllowsExternalProcessing,
            deploymentEnvironment: .production,
            destination: .approvedProvider(
                identifier:
                    CodexTextExecutionAuthorization
                    .providerIdentifier
            ),
            retentionPolicy: .noProviderRetention,
            dataCategories: [
                .userPromptText,
                .transcriptText,
                .evidenceIdentifiers
            ],
            visibleUserAuthorization:
                visibleUserAuthorization,
            localModelAvailable: false,
            securityPolicy: securityPolicy
        )
        let authorization =
            try CodexTextExecutionAuthorizationFactory()
            .authorize(
                candidate: candidate,
                request: routeRequest
            )
        let context = try CodexMeetingTextContextFactory().make(
            authorization: authorization,
            selectedSegments: selected
        )
        return try CodexMeetingTurnRequest(
            authorization: authorization,
            context: context,
            prompt: prompt
        )
    }

    private func recordingReview(
        snapshot: RecordingSessionSnapshot,
        runtime: WorkspaceRuntime
    ) async throws -> RecordingSessionReview {
        let checkpoint = try? await runtime.store.latestCheckpoint(
            sessionID: snapshot.intent.sessionID
        )
        let gaps = try await runtime.store.gaps(sessionID: snapshot.intent.sessionID)
        guard let gapCount = UInt32(exactly: gaps.count) else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        let safeReason: String?
        if let reason = snapshot.terminalReason {
            safeReason = reason.rawValue
        } else if snapshot.state == .recovering {
            safeReason = "Recovered sealed audio is retained. Finish to verify an incomplete result."
        } else if snapshot.state == .interrupted {
            safeReason = "Capture continuity was interrupted; no source was substituted."
        } else {
            safeReason = nil
        }
        let completedTracks =
            snapshot.state == .completed
            ? try await completedRecordingTracks(
                snapshot: snapshot,
                runtime: runtime
            )
            : []
        return RecordingSessionReview(
            sessionID: snapshot.intent.sessionID,
            jobID: snapshot.intent.jobID,
            state: snapshot.state,
            stateVersion: snapshot.stateVersion,
            activeTrackKinds: snapshot.intent.requestedTracks.map(\.kind).sorted {
                $0.rawValue < $1.rawValue
            },
            durableThroughNanoseconds: checkpoint?.tracks
                .map(\.lastCoveredMediaRange.endNanoseconds).max(),
            knownGapCount: gapCount,
            safeReason: safeReason,
            completedTracks:
                completedTracks
        )
    }

    private func completedRecordingTracks(
        snapshot: RecordingSessionSnapshot,
        runtime: WorkspaceRuntime
    ) async throws
        -> [CompletedRecordingTrackReview]
    {
        guard snapshot.state == .completed
        else {
            return []
        }
        let publication =
            snapshot.intent.publicationPlan
        let manifestReference =
            try publication.manifest
            .revisionReference
        guard
            let manifestSource =
                try runtime.store.sourceAsset(
                    revisionID:
                        publication.manifest
                        .revisionID
                ),
            manifestSource.assetID
                == publication.manifest
                .assetID,
            manifestSource.meetingID
                == snapshot.intent.meetingID,
            manifestSource.assetType
                == .document,
            manifestSource.originType
                == .generated,
            manifestSource.revision
                .lifecycleStatus
                == .published,
            manifestSource.revision
                .validationState
                == .valid,
            manifestSource.byteSize
                <= 16 * 1_024 * 1_024,
            let manifestStorage =
                manifestSource
                .managedStorageReference
        else {
            throw AppWorkflowError
                .workspaceHealthFailed
        }
        let manifestURL =
            try runtime.fileAccess
            .verifiedFileURL(
                for: manifestStorage
            )
        let manifestPayload =
            try Data(
                contentsOf: manifestURL,
                options: .mappedIfSafe
            )
        let manifest =
            try JSONDecoder().decode(
                CaptureManifestV1.self,
                from: manifestPayload
            )
        guard
            manifestPayload
                == (try manifest
                    .canonicalPayload()),
            manifest.sessionID
                == snapshot.intent.sessionID,
            manifest.meetingID
                == snapshot.intent.meetingID,
            manifest.terminalState
                == .completed,
            manifest.captureMode
                == snapshot.intent.mode,
            manifest.tracks.count
                == snapshot.intent
                .requestedTracks.count
        else {
            throw AppWorkflowError
                .workspaceHealthFailed
        }

        var reviews:
            [CompletedRecordingTrackReview] = []
        reviews.reserveCapacity(
            manifest.tracks.count
        )
        for request in
            snapshot.intent.requestedTracks
        {
            guard
                let trackPlan =
                    publication.tracks
                    .first(where: {
                        $0.trackID
                            == request.trackID
                    }),
                let manifestTrack =
                    manifest.tracks
                    .first(where: {
                        $0.trackID
                            == request.trackID
                    }),
                manifestTrack.kind
                    == request.kind,
                manifestTrack
                    .speechSourceKind
                    == request
                    .speechSourceKind,
                manifestTrack.language
                    == request.language,
                manifestTrack
                    .finalFrameCount > 0,
                let source =
                    try runtime.store
                    .sourceAsset(
                        revisionID:
                            trackPlan.asset
                            .revisionID
                    ),
                source.assetID
                    == trackPlan.asset
                    .assetID,
                source.meetingID
                    == snapshot.intent
                    .meetingID,
                source.assetType == .audio,
                source.originType
                    == .authorizedCapture,
                source.revision
                    .lifecycleStatus
                    == .published,
                source.revision
                    .validationState
                    == .valid,
                source.revision
                    .sourceAssetRevisions
                    == [manifestReference],
                source.sourceContentHash
                    == manifestTrack
                    .finalContentHash,
                source.byteSize
                    == manifestTrack
                    .finalByteSize,
                source.media?
                    .speechSourceKind
                    == request
                    .speechSourceKind,
                source.media?
                    .languageTrack
                    == request.language,
                let storage =
                    source
                    .managedStorageReference
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            let sourceURL =
                try runtime.fileAccess
                .verifiedFileURL(
                    for: storage
                )
            let mediaTracks =
                try await runtime.processor
                .audioTracks(in: sourceURL)
            guard mediaTracks.count == 1,
                  let mediaTrack =
                    mediaTracks.first,
                  mediaTrack
                    .durationFrameCount > 0,
                  mediaTrack
                    .sourceSampleRateHertz
                    .map({
                        $0
                            == manifestTrack
                            .format
                            .sampleRateHertz
                    }) ?? true,
                  mediaTrack
                    .sourceChannelCount
                    .map({
                        $0
                            == manifestTrack
                            .format
                            .channelCount
                    }) ?? true
            else {
                throw AppWorkflowError
                    .workspaceHealthFailed
            }
            reviews.append(
                CompletedRecordingTrackReview(
                    trackID:
                        request.trackID,
                    kind: request.kind,
                    sourceRevision:
                        try trackPlan.asset
                        .revisionReference,
                    mediaTrackIdentifier:
                        mediaTrack
                        .trackIdentifier,
                    durationFrameCount:
                        mediaTrack
                        .durationFrameCount,
                    speechSourceKind:
                        request
                        .speechSourceKind,
                    language:
                        request.language
                )
            )
        }
        guard Set(reviews.map(\.trackID))
                == Set(
                    snapshot.intent
                        .requestedTracks
                        .map(\.trackID)
                )
        else {
            throw AppWorkflowError
                .workspaceHealthFailed
        }
        return reviews.sorted {
            $0.trackID < $1.trackID
        }
    }

    private func persistMeetingAndDefaultPolicy(
        _ meeting: MeetingProfileV1,
        createdAt: UTCInstant,
        runtime: WorkspaceRuntime,
        approvedExternalProviderIdentifiers:
            [String]
    ) throws -> LocalSecurityPolicyBundle {
        try runtime.store.insert(meeting)
        let meetingUUID = try requiredUUID(meeting.meetingID.canonicalString)
        let policy = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: SensitivityLabelID(meetingUUID),
            sensitivityLabelRevisionID: RevisionID(UUID()),
            accessPolicyID: AccessPolicyID(meetingUUID),
            accessPolicyRevisionID: RevisionID(UUID()),
            createdAt: createdAt,
            approvedExternalProviderIdentifiers:
                approvedExternalProviderIdentifiers
        )
        try runtime.store.insert(policy.sensitivityLabel)
        _ = try runtime.store.activate(
            ActivePublishedRevisionSelection(
                logicalID: policy.sensitivityLabel.labelID,
                revisionID: policy.sensitivityLabel.revision.revisionID
            ),
            as: SensitivityLabelV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: createdAt
        )
        try runtime.store.insert(policy.accessPolicy)
        _ = try runtime.store.activate(
            ActivePublishedRevisionSelection(
                logicalID: policy.accessPolicy.policyID,
                revisionID: policy.accessPolicy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: createdAt
        )
        return policy
    }

    private func sessionScopedSourceToken(
        sessionID: RecordingSessionID,
        sourceClass: String,
        platformIdentifier: String,
        selectedAt: UTCInstant,
        format: CaptureAudioFormat
    ) throws -> ContentDigest {
        let material = [
            sessionID.canonicalString,
            sourceClass,
            platformIdentifier,
            String(selectedAt.millisecondsSinceUnixEpoch),
            String(format.sampleRateHertz),
            String(format.channelCount),
            format.channelLayout,
            String(format.formatRevision)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func sourceSetDigest(
        _ sources: [RecordingEpochSource]
    ) throws -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(sources.sorted { $0.trackID < $1.trackID })
        let digest = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func releasePendingSource() {
        if pendingSourceDidStartScope {
            pendingSourceURL?.stopAccessingSecurityScopedResource()
        }
        pendingSourceURL = nil
        pendingSourceDidStartScope = false
        pendingInspection = nil
    }

    private func newestRecord(
        in records: [JobRecord]
    ) -> JobRecord? {
        records.max { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.jobID < rhs.jobID
        }
    }

    private func restoredMeetingProfile(
        meetingID: MeetingID,
        runtime: WorkspaceRuntime
    ) throws -> MeetingProfileV1 {
        if let active = try runtime.store
            .activeRevisionState(
                MeetingProfileV1.self,
                logicalID: meetingID
            )?
            .revision
        {
            return active
        }
        let revisions = try runtime.store.revisions(
            MeetingProfileV1.self,
            logicalID: meetingID
        )
        guard revisions.count == 1,
              let only = revisions.first
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        return only
    }

    private func restoredImportedSource(
        plan: CanonicalAudioJobPlan,
        runtime: WorkspaceRuntime
    ) throws -> ImportedSourceReview? {
        guard let sourceAsset = try runtime.store
            .sourceAsset(
                revisionID:
                    plan.sourceRevision.revisionID
            ),
              sourceAsset.assetID
                .canonicalString
                == plan.sourceRevision.logicalID
                .canonicalString,
              sourceAsset.revision.revisionID
                == plan.sourceRevision.revisionID,
              sourceAsset.meetingID == plan.meetingID,
              let media = sourceAsset.media,
              media.speechSourceKind
                == plan.speechSourceKind
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        guard sourceAsset.originType == .localImport else {
            return nil
        }
        guard let formatIdentifier =
                media.containerFormat,
              let format = ApprovedMediaFormat(
                  rawValue: formatIdentifier
              ),
              format.assetType == sourceAsset.assetType
        else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        return ImportedSourceReview(
            assetID: sourceAsset.assetID,
            revisionID:
                sourceAsset.revision.revisionID,
            sourceHash: sourceAsset.sourceContentHash,
            byteSize: sourceAsset.byteSize,
            format: format,
            durationFrameCount:
                plan.expectedDurationFrames,
            selectedTrack: plan.selectedTrack,
            speechSourceKind:
                plan.speechSourceKind
        )
    }

    private func currentInstant() throws -> UTCInstant {
        try UTCInstant(
            millisecondsSinceUnixEpoch: Int64(
                max(Date().timeIntervalSince1970 * 1_000, 0).rounded(.down)
            )
        )
    }

    private func canonicalContext(jobID: JobID) async throws -> (
        plan: CanonicalAudioJobPlan,
        canonicalReference: SemanticRevisionReference
    ) {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        guard let record = try await runtime.manager.job(id: jobID),
              record.jobType == MediaJobTypes.canonicalAudio,
              record.state == .succeeded,
              record.outputRevisionIDs.count == 1,
              let reference = record.outputRevisionIDs.first
        else { throw AppWorkflowError.canonicalAudioRequired }
        return (try CanonicalAudioJobPlan.decode(from: record.inputPayload), reference)
    }

    private func analysisSource(
        canonicalJobID: JobID
    ) async throws -> AnalysisSourceBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let review = try runtime.store.activeTranscriptReview(
            meetingID: context.plan.meetingID
        ),
            review.manifest.status == .published
        else { throw AppWorkflowError.transcriptUnavailable }
        let activeMeeting = try runtime.store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: context.plan.meetingID
        )?.revision
        let meeting: MeetingProfileV1
        if let activeMeeting {
            meeting = activeMeeting
        } else {
            let revisions = try runtime.store.revisions(
                MeetingProfileV1.self,
                logicalID: context.plan.meetingID
            )
            guard revisions.count == 1, let only = revisions.first else {
                throw AppWorkflowError.analysisUnavailable
            }
            meeting = only
        }
        let meetingReference = try SemanticRevisionReference(
            logicalID: meeting.meetingID,
            revisionID: meeting.revision.revisionID
        )
        do {
            return try runtime.store.analysisSourceBundle(
                meetingRevision: meetingReference,
                transcriptManifestID: review.manifest.manifestID
            )
        } catch {
            throw AppWorkflowError.analysisUnavailable
        }
    }

    private func briefingSource(
        canonicalJobID: JobID,
        template: MeetingTemplateV1
    ) async throws -> BriefingSourceBundle {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let context = try await canonicalContext(jobID: canonicalJobID)
        guard let analysis = try runtime.store.activeAnalysisReview(
            meetingID: context.plan.meetingID
        ), analysis.ledger.status == .published else {
            throw AppWorkflowError.briefingUnavailable
        }
        let meetingState = try runtime.store.activeRevisionState(
            MeetingProfileV1.self,
            logicalID: context.plan.meetingID
        )
        let meeting: MeetingProfileV1
        if let meetingState {
            meeting = meetingState.revision
        } else {
            let revisions = try runtime.store.revisions(
                MeetingProfileV1.self,
                logicalID: context.plan.meetingID
            )
            guard revisions.count == 1, let only = revisions.first else {
                throw AppWorkflowError.briefingUnavailable
            }
            meeting = only
        }
        do {
            return try runtime.store.briefingSourceBundle(
                meetingRevision: try semanticReference(meeting),
                template: template,
                analysisLedgerID: analysis.ledger.ledgerID
            )
        } catch {
            throw AppWorkflowError.briefingUnavailable
        }
    }

    private func approvedBriefingRoute(
        source: BriefingSourceBundle,
        visibleUserAuthorization: Bool
    ) async throws -> ModelRouteDecision {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let locale = source.meeting.outputLanguage.value
        let available = await runtime.briefingProvider?.isModelAvailable(
            localeIdentifier: locale
        ) ?? false
        let decision = try ModelPolicyRouter().decide(
            briefingRouteRequest(
                source: source,
                modelAvailable: available,
                visibleUserAuthorization: visibleUserAuthorization
            )
        )
        guard decision.route == .appleOnDevice,
              decision.providerIdentifier == "apple-foundation-models",
              available else { throw AppWorkflowError.onDeviceModelUnavailable }
        return decision
    }

    private func briefingRouteRequest(
        source: BriefingSourceBundle,
        modelAvailable: Bool,
        visibleUserAuthorization: Bool
    ) throws -> ModelRouteRequest {
        let classification = DataClassification.mostRestrictive(
            [source.meeting.revision.dataClassification]
                + source.analysis.evidence.map(\.revision.dataClassification)
                + source.analysis.positions.map(\.revision.dataClassification)
                + source.analysis.interventionCards.map(\.revision.dataClassification)
                + source.analysis.delegationPositionCards.map(\.revision.dataClassification)
        ) ?? .restricted
        return try ModelRouteRequest(
            capability: .analysis,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: [.validatedIntelligenceClaims, .evidenceIdentifiers],
            visibleUserAuthorization: visibleUserAuthorization,
            localModelAvailable: modelAvailable,
            securityPolicy: try securityPolicySnapshot(
                meetingID: source.meeting.meetingID
            )
        )
    }

    private func briefingRuntimeEvidence(
        localeIdentifier: String,
        modelAvailable: Bool
    ) throws -> AnalysisRuntimeEvidence {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return try AnalysisRuntimeEvidence(
            operatingSystemVersion: "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            frameworkIdentifier: "com.apple.FoundationModels",
            adapterVersion: "meetingbuddy-task006b-v1",
            localeIdentifier: localeIdentifier,
            modelAvailable: modelAvailable,
            noOutboundMode: true
        )
    }

    private func semanticReference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    private func analysisRouteRequest(
        source: AnalysisSourceBundle,
        modelAvailable: Bool,
        visibleUserAuthorization: Bool
    ) throws -> ModelRouteRequest {
        let packages = try AnalysisPipelineJobPlan.requestPackages(from: source)
        let classification = DataClassification.mostRestrictive(
            packages.map(\.request.dataClassification)
                + [source.meeting.revision.dataClassification]
        ) ?? .restricted
        var categories: [ProviderDataCategory] = [
            .transcriptText,
            .speakerContext,
            .evidenceIdentifiers
        ]
        if !source.transcriptReview.translations.isEmpty {
            categories.append(.translationText)
        }
        return try ModelRouteRequest(
            capability: .analysis,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .noProviderRetention,
            dataCategories: categories,
            visibleUserAuthorization: visibleUserAuthorization,
            localModelAvailable: modelAvailable,
            securityPolicy: try securityPolicySnapshot(
                meetingID: source.meeting.meetingID
            )
        )
    }

    private func analysisRuntimeEvidence(
        localeIdentifier: String,
        modelAvailable: Bool
    ) throws -> AnalysisRuntimeEvidence {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return try AnalysisRuntimeEvidence(
            operatingSystemVersion: "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            frameworkIdentifier: "com.apple.FoundationModels",
            adapterVersion: "meetingbuddy-task006a-v1",
            localeIdentifier: localeIdentifier,
            modelAvailable: modelAvailable,
            noOutboundMode: true
        )
    }

    private func routeRequest(
        meetingID: MeetingID,
        capability: AIProcessingCapability,
        classification: DataClassification,
        categories: [ProviderDataCategory],
        localModelAvailable: Bool
    ) throws -> ModelRouteRequest {
        try ModelRouteRequest(
            capability: capability,
            dataClassification: classification,
            offlineMode: true,
            organizationAllowsExternalProcessing: false,
            deploymentEnvironment: .production,
            destination: .localDevice,
            retentionPolicy: .localWorkspaceOnly,
            dataCategories: categories,
            visibleUserAuthorization: false,
            localModelAvailable: localModelAvailable,
            securityPolicy: try securityPolicySnapshot(meetingID: meetingID)
        )
    }

    private func securityPolicySnapshot(
        meetingID: MeetingID
    ) throws -> ModelSecurityPolicySnapshot? {
        guard let runtime else { throw AppWorkflowError.workspaceRequired }
        let labelID = try SensitivityLabelID(validating: meetingID.canonicalString)
        let policyID = try AccessPolicyID(validating: meetingID.canonicalString)
        guard let label = try runtime.store.activeRevisionState(
            SensitivityLabelV1.self,
            logicalID: labelID
        )?.revision,
            let policy = try runtime.store.activeRevisionState(
                AccessPolicyV1.self,
                logicalID: policyID
            )?.revision
        else {
            // Accepted v5 jobs remain readable and local-only. Absence never
            // becomes external-processing authority.
            return nil
        }
        let labelReference = try semanticReference(label)
        guard policy.meetingID == meetingID,
              label.meetingID == meetingID,
              policy.sensitivityLabelRevision == labelReference,
              policy.effectiveClassification == label.effectiveClassification
        else { throw AppWorkflowError.workspaceHealthFailed }
        return try LocalSecurityPolicyBundle(
            sensitivityLabel: label,
            accessPolicy: policy
        ).modelSnapshot
    }

    private func requiredUUID(_ canonicalString: String) throws -> UUID {
        guard let value = UUID(uuidString: canonicalString) else {
            throw AppWorkflowError.workspaceHealthFailed
        }
        return value
    }

    private func sourceByteSize(_ sourceURL: URL) throws -> UInt64 {
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0
        else {
            throw AppWorkflowError.sourceAuthorizationFailed
        }
        return UInt64(fileSize)
    }

    private func terminalJob(
        _ jobID: JobID,
        manager: LocalTaskManager
    ) async throws -> JobRecord {
        while true {
            try Task.checkCancellation()
            guard let record = try await manager.job(id: jobID) else {
                throw AppWorkflowError.jobUnavailable
            }
            if record.state.isTerminal { return record }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func meetingProfile(
        title: String,
        classification: DataClassification,
        language: LanguageTag?,
        workspaceID: WorkspaceID,
        approvedExternalProviderIdentifiers:
            [String],
        speechToTextRoute:
            MeetingSpeechToTextRouteV1,
        createdAt: UTCInstant
    ) throws -> MeetingProfileV1 {
        let providers =
            approvedExternalProviderIdentifiers
            .sorted()
        guard Set(providers).count == providers.count,
              providers.isEmpty
                || classification.restrictionRank
                    < DataClassification.sensitive
                    .restrictionRank
        else {
            throw AppWorkflowError
                .externalTextAuthorizationUnavailable
        }
        return try MeetingProfileV1(
            revision: RevisionEnvelope(
                logicalID: MeetingID(UUID()),
                revisionID: RevisionID(UUID()),
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .user,
                dataClassification: classification
            ),
            title: title,
            sourceLanguages: language.map { [$0] } ?? [],
            outputLanguage: language ?? LanguageTag("en"),
            cloudProcessingPolicy:
                !providers.isEmpty
                ? .approvedCloudAllowed
                : .localOnly,
            speechToTextRoute:
                speechToTextRoute,
            workspaceID: workspaceID,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    private struct MeetingProviderApprovals {
        let approvedExternalProviderIdentifiers:
            [String]
        let speechToTextRoute:
            MeetingSpeechToTextRouteV1
    }

    private func meetingProviderApprovals(
        codexTextProcessingAllowed: Bool,
        transcriptionSelection:
            ProviderModelSelectionRecord?,
        remoteSpeechToTextAllowed: Bool,
        classification: DataClassification
    ) throws -> MeetingProviderApprovals {
        var identifiers: [String] = []
        if codexTextProcessingAllowed {
            identifiers.append(
                CodexTextExecutionAuthorization
                    .providerIdentifier
            )
        }
        guard let selection =
                transcriptionSelection
        else {
            return try MeetingProviderApprovals(
                approvedExternalProviderIdentifiers:
                    identifiers.sorted(),
                speechToTextRoute:
                    MeetingSpeechToTextRouteV1(
                        kind: .recordOnly
                    )
            )
        }
        if selection.providerIdentifier
            == "apple-speech"
        {
            guard selection.modelIdentifier
                    == "speech-analyzer-installed"
            else {
                throw AppWorkflowError
                    .speechToTextConfigurationUnavailable
            }
            return try MeetingProviderApprovals(
                approvedExternalProviderIdentifiers:
                    identifiers.sorted(),
                speechToTextRoute:
                    MeetingSpeechToTextRouteV1(
                        kind: .local,
                        providerIdentifier:
                            selection
                            .providerIdentifier,
                        modelIdentifier:
                            selection
                            .modelIdentifier
                    )
            )
        }
        guard remoteSpeechToTextAllowed,
              classification.restrictionRank
                  < DataClassification.sensitive
                  .restrictionRank
        else {
            throw AppWorkflowError
                .remoteAudioAuthorizationRequired
        }
        let state: IntelligenceConfigurationState
        do {
            state = try intelligenceRepository.load()
        } catch {
            throw AppWorkflowError
                .speechToTextConfigurationUnavailable
        }
        guard let provider = state.providers.first(
            where: {
                $0.identifier
                    == selection.providerIdentifier
                    && $0.modelIdentifier
                        == selection.modelIdentifier
            }
        ),
            provider.purpose == .speechToText,
            provider.connectionState == .ready,
            provider.capabilities.contains(
                .speechToTextBatch
            ),
            try secretStore.read(
                provider.secretIdentifier
            ) != nil
        else {
            throw AppWorkflowError
                .speechToTextConfigurationUnavailable
        }
        identifiers.append(provider.identifier)
        return try MeetingProviderApprovals(
            approvedExternalProviderIdentifiers:
                Array(Set(identifiers))
                .sorted(),
            speechToTextRoute:
                MeetingSpeechToTextRouteV1(
                    kind: .approvedRemote,
                    providerIdentifier:
                        provider.identifier,
                    modelIdentifier:
                        provider.modelIdentifier,
                    intelligenceConfigurationRevision:
                        state.revision
                )
        )
    }

    private func remoteSpeechConfiguration(
        selection: ProviderModelSelectionRecord
    ) throws -> (
        configuration: RemoteProviderConfiguration,
        revision: UInt64
    ) {
        let state: IntelligenceConfigurationState
        do {
            state = try intelligenceRepository.load()
        } catch {
            throw AppWorkflowError
                .speechToTextConfigurationUnavailable
        }
        guard let configuration =
                state.providers.first(
                    where: {
                        $0.identifier
                            == selection
                            .providerIdentifier
                            && $0.modelIdentifier
                                == selection
                                .modelIdentifier
                    }
                ),
              configuration.purpose
                  == .speechToText,
              configuration.connectionState
                  == .ready,
              configuration.capabilities.contains(
                  .speechToTextBatch
              ),
              try secretStore.read(
                  configuration.secretIdentifier
              ) != nil
        else {
            throw AppWorkflowError
                .speechToTextConfigurationUnavailable
        }
        return (
            configuration,
            state.revision
        )
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "BlueMinutes Workspace" : name
    }
}
