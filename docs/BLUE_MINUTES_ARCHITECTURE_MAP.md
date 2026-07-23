# Blue Minutes Meeting / Research Architecture Map

Status: Phase 0 audit record

Date: 2026-07-23

Audit baseline: `d473b7037d7014ef0ae4e18d2c72463847347d8e` on `main`

Product-plan input: `docs/BLUE_MINUTES_MEETING_RESEARCH_MVP_PLAN.md`

## 1. Scope and evidence boundary

This document maps the Meeting / Research MVP plan to the repository that
exists at the audit baseline. It does not authorize or implement Phase 1.

At the start of the Phase 0 audit, the plan was observed as an untracked file
at the repository root:

```text
BLUE_MINUTES_MEETING_RESEARCH_MVP_PLAN.md
```

The governance-acceptance task moved that file, without changing its content,
to the canonical documentation path:

```text
docs/BLUE_MINUTES_MEETING_RESEARCH_MVP_PLAN.md
```

The Phase 0 evidence below remains tied to the same plan content and audit
baseline.

Phase 0 did not change production code, tests, the SQLite schema, a user
workspace, or existing Meeting behavior. Build products were isolated under
`/tmp/blueminutes-phase0.Pgu3H0`.

## 2. Repository and technology baseline

The application is a native SwiftPM macOS application. The repository does not
contain a Tauri, React, Electron, Cargo, JavaScript, or Python-sidecar
application stack.

| Concern | Observed implementation |
| --- | --- |
| Package definition | `Package.swift`; Swift tools 6.1, Swift 6 language mode, macOS 15 minimum |
| UI | SwiftUI with narrow AppKit lifecycle integration |
| Application entry | `Sources/MeetingBuddyApp/MeetingBuddyApp.swift`; `MeetingBuddyDesktopApp` |
| Feature root | `Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift`; `MeetingBuddyRootView` |
| Feature state | `Sources/MeetingBuddyFeatures/Stores/MediaReviewStore.swift`; `MediaReviewStore` |
| Composition/use-case root | `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`; `WorkspaceRuntime`, `AppMediaReviewWorkflow` |
| Media and capture | AVFoundation, CoreMedia, AudioToolbox, and ScreenCaptureKit |
| Installed-model adapters | Speech, Translation, and FoundationModels behind macOS 26 availability gates |
| Metadata database | SQLite through GRDB |
| File storage | Application-owned local workspace paths and opaque managed-asset references |
| Secret boundary | macOS Keychain through `MacOSKeychainSecretStore` |
| CLI entry | `Sources/MeetingBuddyCLI/MeetingBuddyCLI.swift`; `MeetingBuddyCLIEntry` |
| MCP entry | `Sources/MeetingBuddyMCP/MeetingBuddyMCP.swift`; `MeetingBuddyMCPEntry` |

`Package.swift` declares eight libraries:

- `MeetingBuddyDomain`
- `MeetingBuddyApplication`
- `MeetingBuddyPersistence`
- `MeetingBuddyTasks`
- `MeetingBuddyMedia`
- `MeetingBuddyAI`
- `MeetingBuddyFeatures`
- `MeetingBuddyAutomation`

It also declares three executables (`MeetingBuddyApp`, `meetingbuddy-cli`, and
`meetingbuddy-mcp`), seven test targets, and one external dependency: GRDB
`7.11.1` at an exact version. No second frontend technology is needed for the
plan.

The standard warning-clean build path is:

```sh
swift package resolve
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

`script/build_and_run.sh --stage-only` provides the repository's local
application-bundle staging path. It builds the `MeetingBuddyApp` debug product,
assembles `dist/MeetingBuddy.app`, and uses ad-hoc signing by default. Phase 0
used SwiftPM build and test directly; it did not stage or launch an app bundle.

## 3. Runtime composition and current user flow

`MeetingBuddyDesktopApp` constructs `AppMediaReviewWorkflow` and
`MediaReviewStore`, then renders `MeetingBuddyRootView`. After the user selects
a local workspace, `WorkspaceRuntime.init(descriptor:)` composes:

- `SQLitePersistenceStore`;
- `LocalStorageService` and `ManagedAssetCoordinator`;
- `LocalTaskManager` and job executors;
- media import, canonical-audio, and recording services;
- exact-host UN Web TV metadata lookup;
- on supported systems, Apple installed-model transcription, translation,
  analysis, and briefing providers;
- local telemetry, rotating logs, recovery, and storage reporting.

The visible sidebar is Meeting-oriented:

```text
Local Media
Record Audio
UN Web TV Metadata
Transcript Review
Analysis Review
Briefing
Meeting History
Storage
```

There is no Research, Conversation, Chat, Settings, or Setup Guide route.

The main accepted pipeline is:

```text
selected local workspace
  -> media import or recording
  -> MeetingProfileV1 + policy + SourceAssetV1
  -> canonical audio
  -> transcript/translation revisions
  -> analysis intelligence revisions
  -> briefing sections/validation/final briefing
  -> human review, export, and historical index
```

Every long-running stage is routed through `LocalTaskManager`; semantic outputs
are immutable revisions with active pointers, exact dependencies, and stale
propagation.

## 4. Required implementation map

### 4.1 Meeting

Primary domain type:

- `Sources/MeetingBuddyDomain/MeetingProfileV1.swift`;
  `MeetingProfileV1`

Creation and persistence:

- `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`;
  `AppMediaReviewWorkflow.meetingProfile(...)`
- the same file;
  `AppMediaReviewWorkflow.persistMeetingAndDefaultPolicy(...)`
- `Sources/MeetingBuddyPersistence/SQLitePersistenceStore.swift`;
  semantic-revision repository implementation and workspace ownership checks

A Meeting is created as part of media intake or recording. There is no generic
business-level `Workspace` entity or Meeting repository screen. The existing
`MeetingProfileV1.workspaceID` identifies the selected physical data root and
must equal `WorkspaceManifest.workspaceID`; it is not the plan's logical,
multi-kind Workspace identifier. Reinterpreting it would violate existing
ownership validation.

Classification: **directly reusable Meeting model and flow; naming and
association extension required for a future logical Research workspace**.

### 4.2 Transcript / ASR

Provider and policy contracts:

- `Sources/MeetingBuddyApplication/AIProviderContracts.swift`;
  `TranscriptionProvider`, `TranscriptionRequest`,
  `TranscriptionChunkResult`, `TranslationProvider`,
  `ModelPolicyRouter`

Installed-model implementations:

- `Sources/MeetingBuddyAI/AppleOnDeviceProviders.swift`;
  `AppleOnDeviceTranscriptionProvider`,
  `AppleOnDeviceTranslationProvider`

Pipeline and review:

- `Sources/MeetingBuddyAI/TranscriptPipelineJob.swift`;
  `TranscriptPipelineJobExecutor`
- `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`;
  `startTranscript(...)`, `publishManualTranscript(...)`,
  transcript correction and speaker-confirmation methods
- `Sources/MeetingBuddyFeatures/Views/TranscriptReviewView.swift`;
  `TranscriptReviewView`
- `Sources/MeetingBuddyApplication/TranscriptCoverageContracts.swift`;
  transcript publication and deterministic coverage contracts

The current `TranscriptionProvider` consumes task-owned bounded audio chunks.
It is not the plan's `probe/fetch/refresh` interface for imported or official
transcript sources. The current pipeline proves deterministic 100-percent
source-segment coverage, preserves original/translation/correction provenance,
and fails closed on an unprovable gap.

There is a manual transcript fallback, but no imported-transcript provider,
UN-transcript provider, authoritative-record provider, availability probe, or
`TranscriptSourceResolver`.

Classification: **local ASR pipeline directly reusable; external transcript
selection is absent and must be added beside, not substituted for,
`TranscriptionProvider`**.

### 4.3 Briefing

Domain models:

- `Sources/MeetingBuddyDomain/MeetingTemplateV1.swift`;
  `MeetingTemplateV1`
- `Sources/MeetingBuddyDomain/IssuePositionV1.swift`;
  `IssueV1`, `PositionV1`, `IssuePositionGraphV1`
- `Sources/MeetingBuddyDomain/BriefingV1.swift`;
  `BriefingSectionV1`, `ValidationReportV1`, `FinalBriefingV1`

Application and pipeline:

- `Sources/MeetingBuddyAI/BriefingSemanticFactory.swift`;
  `BriefingSemanticFactory.builtInTemplate(...)`
- `Sources/MeetingBuddyAI/BriefingPipelineJob.swift`;
  `BriefingPipelineJobExecutor`
- `Sources/MeetingBuddyAI/BriefingAssemblyFactory.swift`;
  `BriefingAssemblyPriorState` and the
  `BriefingSemanticFactory.makePublication(...)` assembly extension
- `Sources/MeetingBuddyAI/BriefingManualReviewService.swift`;
  `BriefingManualReviewService`
- `Sources/MeetingBuddyPersistence/LocalMarkdownExportService.swift`;
  `LocalMarkdownExportService`
- `Sources/MeetingBuddyFeatures/Views/BriefingReviewView.swift`;
  `BriefingReviewView`

The accepted built-in template contains three sections: overview, issues, and
delegations. The flow supports section regeneration, manual edits and locks,
human confirmation, stale blocking, deterministic validation, and local
Markdown export.

`FinalBriefingV1` is already an immutable, evidence-linked artifact in the
ordinary meaning of the word, but the code has no generic `Artifact`,
`ArtifactVersion`, or artifact catalog.

Classification: **directly reusable briefing implementation; a non-invasive
catalog/adapter is needed for a generic Artifact view**.

### 4.4 Evidence / Citation

Core types:

- `Sources/MeetingBuddyDomain/EvidenceRefV1.swift`;
  `EvidenceRefV1`, `EvidenceLocation`
- `Sources/MeetingBuddyDomain/IntelligenceValues.swift`;
  `EvidenceLinkedClaim`, `EvidenceSupportStatus`
- `Sources/MeetingBuddyDomain/Provenance.swift`;
  `ProviderMetadata`, `VersionedComponent`, `GenerationMetadata`

`EvidenceLocation` already represents transcript segments, document
locations, media ranges, user notes, meeting metadata, semantic revisions, and
official statements. Analysis and briefing validators retain exact evidence
references and prevent unsupported publication.

The UI generally exposes revision identifiers and evidence counts. There is no
generic `Citation`, `CitationEngine`, locator-verification service,
verification-status lifecycle, or click-through navigation from a claim to a
page/paragraph/timestamp.

Classification: **`EvidenceRefV1` is the reusable source-of-truth substrate;
unified citation projection, validation, and navigation are absent**.

### 4.5 Conversation / Chat

No `Conversation`, `Message`, `Chat`, conversation service, conversation
repository, chat view, or corresponding schema table exists under `Sources/`
or `Tests/`.

Historical comparison in
`Sources/MeetingBuddyApplication/HistoricalReviewContracts.swift` is a
deterministic review feature, not a conversation system.

Classification: **currently absent**.

### 4.6 AI Provider / Codex calls

The application owns typed provider contracts for transcription, translation,
analysis, and briefing:

- `Sources/MeetingBuddyApplication/AIProviderContracts.swift`;
  `TranscriptionProvider`, `TranslationProvider`, `AnalysisProvider`,
  `BriefingSectionProvider`, `ModelPolicyRouter`
- `Sources/MeetingBuddyAI/DiplomaticAnalysisPrompt.swift`;
  `DiplomaticAnalysisPrompt.protectedRules`
- `Sources/MeetingBuddyAI/DiplomaticBriefingPrompt.swift`;
  `DiplomaticBriefingPrompt.protectedRules`

Current production composition uses installed Apple model adapters on supported
systems, with local/manual fallbacks. `ModelPolicyRouter` contains an
`approvedExternal` route vocabulary, but the current router denies that route
because no approved outbound adapter is installed.

There is no Codex client, OpenAI API provider, subscription-login provider,
cookie access, or direct external-agent invocation in the application.
`meetingbuddy-mcp` is a local stdio automation transport and is not an AI
inference provider. Its allowlist is defined by
`AutomationMCPAdapter.exposedCommands` in
`Sources/MeetingBuddyAutomation/AutomationMCPAdapter.swift`.

Classification: **provider policy and specialized provider contracts are
reusable; a general generation contract and any approved Codex adapter are
absent**.

### 4.7 Tasks / background jobs

Contracts and runtime:

- `Sources/MeetingBuddyApplication/JobContracts.swift`;
  `JobRequest`, `JobRecord`, `JobState`, `JobCheckpoint`,
  `JobInputPayload`, `JobStateMachine`
- `Sources/MeetingBuddyTasks/LocalTaskManager.swift`;
  `LocalTaskManager`
- `Sources/MeetingBuddyPersistence/SQLiteJobRepository.swift`;
  `SQLiteJobRepository`
- `Sources/MeetingBuddyPersistence/LocalTaskTemporaryStorage.swift`;
  `LocalTaskTemporaryStorage`
- `Sources/MeetingBuddyPersistence/RotatingTaskLogStore.swift`;
  `RotatingTaskLogStore`

The task manager provides durable state, idempotency keys, dependencies,
checkpointing, progress, cooperative cancellation, pause/resume, retry,
bounded concurrency, input-revision revalidation, owned temporary storage,
redacted logs, and startup recovery.

The GUI composition currently registers media intake, canonical audio,
recording capture, historical-index rebuild, and—when available—transcript,
analysis, and briefing executors. There is no separate Tasks screen.

Classification: **directly reusable; future Research jobs require new
`JobType`/executor registration and a typed Research context, not a second
runner**.

### 4.8 Persistence / database

Primary implementation:

- `Sources/MeetingBuddyPersistence/SQLitePersistenceStore.swift`;
  `SQLitePersistenceStore`
- `Sources/MeetingBuddyPersistence/SQLiteSchema.swift`;
  `SQLiteSchema`, `SQLiteSchema.currentVersion`
- `Sources/MeetingBuddyPersistence/SQLiteSchema.swift`;
  `SQLiteDatabaseBootstrap` for database open, migration, backup, and
  fail-closed checks
- `Sources/MeetingBuddyPersistence/SQLiteRecoveryService.swift`;
  `SQLiteRecoveryService`

The current schema version is 10. It stores workspace metadata, immutable
semantic revisions and active pointers, dependencies and stale marks, managed
assets, jobs and events, transcript/analysis/briefing ledgers, exports,
security/storage/recording state, automation settings/audit data, and
historical indexes/preferences.

`SQLiteSchema` registers the accepted ordered migrations:

```text
001_initial_persistence
002_task_runtime
003_transcript_coverage
004_analysis_intelligence
005_briefing_foundation
006_security_storage_hardening
007_recording_capture_foundation
008_automation_command_audit_settings
009_mcp_audit_origin
010_historical_review_preferences
```

The schema has no Conversation, Message, logical Research workspace,
WorkspaceSource, ResearchRun, generic Artifact/Citation, or instruction-profile
tables. `semantic_revisions.object_type` and the corresponding Swift decoder
allowlist are closed vocabularies. Extending them by rebuilding the table is a
high-risk choice and is not required for a minimal Phase 1.

GRDB enables WAL and foreign keys. Pending migrations create an online SQLite
backup first; unknown future versions, migration checksum mismatch, and
workspace-identity mismatch fail closed.

Classification: **database, migration, backup, and recovery machinery directly
reusable; all Research persistence must be additive and compatibility-tested**.

### 4.9 Working folder / storage

Contracts and services:

- `Sources/MeetingBuddyApplication/WorkspaceContracts.swift`;
  `WorkspaceManifest`, `WorkspaceService`, `StorageService`,
  `ManagedAssetRecord`
- `Sources/MeetingBuddyPersistence/LocalWorkspaceService.swift`;
  `LocalWorkspaceService`
- `Sources/MeetingBuddyPersistence/LocalWorkspaceDescriptor.swift`;
  `LocalWorkspaceDescriptor`, `WorkspaceLayout`
- `Sources/MeetingBuddyPersistence/LocalStorageService.swift`;
  `LocalStorageService`
- `Sources/MeetingBuddyPersistence/ManagedAssetCoordinator.swift`;
  `ManagedAssetCoordinator`
- `Sources/MeetingBuddyApp/WorkspaceSecurityScope.swift`;
  `WorkspaceSecurityScope`

Observed layout:

```text
<selected-root>/
├── Meetings/
├── Models/
├── Database/meetingbuddy.sqlite
├── Indexes/
├── Backups/
├── Logs/
├── .tasks/
├── .temp/
├── .Trash/
├── manifests/
└── workspace_manifest.json
```

Managed files are streamed, hashed with SHA-256, and stored below
`Meetings/<meeting-id>/assets/<storage-object-id>.<extension>`. Briefing
exports are stored below `Meetings/<meeting-id>/exports/`. Callers receive
opaque references rather than unrestricted root paths. Operation journals,
path confinement, recovery, bounded task directories, storage reporting, and
recoverable Trash behavior are already implemented.

This is one user-selected data root, but it is not the plan's proposed global
content-addressed ObjectStore. Files use Meeting ownership and UUID-based
paths; equal hashes do not imply one physical object or cross-Meeting
deduplication. `managed_assets.meeting_id` is non-null.

Classification: **the data-root and safety boundary are directly reusable;
shared Research objects and optional deduplication require a compatibility
extension without relocating accepted Meeting files**.

### 4.10 Settings / Instructions

Existing fragments:

- `Sources/MeetingBuddyApp/WorkspaceSecurityScope.swift`;
  one security-scoped workspace bookmark in app `UserDefaults`
- `Sources/MeetingBuddyApplication/AutomationContracts.swift`;
  `AutomationSettingsValues`, `VersionedAutomationSettings`
- `Sources/MeetingBuddyApplication/HistoricalReviewContracts.swift`;
  `LearnedPreferenceValue`, `LearnedPreferenceState`
- `Sources/MeetingBuddyApplication/AIProviderContracts.swift`;
  `ModelSecurityPolicySnapshot`, `ModelPolicyRouter`
- `Sources/MeetingBuddyAI/DiplomaticAnalysisPrompt.swift` and
  `DiplomaticBriefingPrompt.swift`; protected, versioned prompt modules

Automation settings currently expose only the bounded
`status_list_limit`. Learned preferences affect presentation only and cannot
override evidence, security, or model-routing policy. Provider routes are
decided from exact policy snapshots, not ordinary preferences.

There is no top-level Settings scene, Setup Guide, general feature-flag
service, `InstructionProfile`, `InstructionSnapshot`, `InstructionCompiler`,
or Global → Template → Workspace → Request compilation chain.

Classification: **security/policy and prompt-versioning principles are
reusable; the product-facing settings and instruction system are absent**.

## 5. Build and test baseline

The audit used the current checked-out sources and an isolated SwiftPM scratch
directory:

```sh
swift package dump-package >/dev/null
swift build \
  --scratch-path /tmp/blueminutes-phase0.Pgu3H0 \
  -Xswiftc -warnings-as-errors

MEETINGBUDDY_RUN_LIVE_APPLE_MODELS=0 \
MEETINGBUDDY_RUN_LIVE_APPLE_ANALYSIS=0 \
MEETINGBUDDY_RUN_LIVE_APPLE_BRIEFING=0 \
swift test \
  --scratch-path /tmp/blueminutes-phase0.Pgu3H0 \
  -Xswiftc -warnings-as-errors
```

| Check | Result |
| --- | --- |
| Package manifest parse | Passed |
| Warning-as-error debug build | Passed in 35.55 seconds |
| Synthetic-safe complete test suite | **248 tests in 43 suites passed** in 35.015 seconds |
| Resolved external dependency | GRDB 7.11.1 |
| Toolchain | Swift 6.3.3, arm64-apple-macosx26.0 |
| Host build tools | Xcode 26.6 (17F113) |
| Host OS | macOS 26.5.2 (25F84), arm64 |

The three live installed-model environment flags were explicitly disabled.
Therefore this baseline proves the deterministic, synthetic-safe suite, but
does not prove installed model availability, model quality, microphone/screen
capture permissions, or a manual GUI journey on this machine.

Existing integration suites already exercise the critical Meeting path:

- `TranscriptPipelineIntegrationTests`
- `AnalysisPipelineIntegrationTests`
- `BriefingPipelineIntegrationTests`
- `CanonicalAudioIntegrationTests`
- `RecordingPersistenceIntegrationTests`
- `WorkspaceAndMigrationTests`
- `RecoveryAndTrashTests`
- `TaskManagerTests`

No new behavioral smoke test was added because Phase 0 made no business-code
change. The full suite is the recorded regression baseline for the future
flag-off comparison.

## 6. Unknowns and validation route

| Unknown after Phase 0 | Required validation before the affected phase |
| --- | --- |
| Which official transcript/document sources and formats are legally and technically supported | Connector-specific fixture and terms review; do not infer from UN Web TV metadata support |
| Desired authority/completeness ordering among official transcript, official record, local ASR, import, and human correction | Product decision plus resolver contract/golden tests |
| Approved Codex or other external generation route | Separate provider/security decision identifying authentication, data categories, destination, retention, offline alternative, and visible authorization |
| Conversation retention, export, deletion, and privacy behavior | Product/privacy decision before Message persistence |
| Whether Phase 1 needs physical content-addressed storage | ADR decision and storage migration benchmark; default to compatibility adapter and no byte movement |
| Real v10 workspace migration duration at user scale | Sanitized copy or large synthetic fixture with backup, failure-injection, and recovery timing |
| Accessibility and UX of future Research navigation | Flagged UI prototype and manual VoiceOver/keyboard review in a later authorized phase |
| Installed Apple model behavior | Opt-in live-model tests on a machine with required models installed |

## 7. Phase 0 conclusion

The accepted Meeting implementation is a coherent native modular monolith and
does not require a rewrite. Its task runtime, immutable revision model,
evidence substrate, local workspace boundary, SQLite migration/recovery
machinery, and provider policy are strong reuse points.

The largest integration hazards are semantic rather than technological:

1. the plan's logical `Workspace` conflicts with the existing physical-root
   `WorkspaceID`;
2. the plan's `TranscriptProvider` is not the existing audio-ASR
   `TranscriptionProvider`;
3. current managed assets are Meeting-owned, not shared content-addressed
   objects;
4. generic Artifact, Citation, Conversation, Instructions, ResearchRun, and
   feature flags do not exist;
5. Codex is not a current application provider.

The binding governance decision is:

- `docs/adr/ADR-0018-blue-minutes-meeting-research-integration.md`

The supporting Phase 0 analysis is recorded in:

- `docs/MEETING_RESEARCH_INTEGRATION_ADR.md`
- `docs/MEETING_RESEARCH_GAP_ANALYSIS.md`
- `docs/MEETING_RESEARCH_PHASE1_PROPOSAL.md`

ADR-0018 accepts the compatibility defaults only. It does not authorize Phase
1, create Task 012, or change the Phase 0 build/test baseline.
