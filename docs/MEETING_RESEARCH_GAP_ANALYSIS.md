# Meeting / Research Gap Analysis

Status: Phase 0 audit output

Date: 2026-07-23

Code baseline: `d473b7037d7014ef0ae4e18d2c72463847347d8e`

Governance disposition:
`docs/adr/ADR-0018-blue-minutes-meeting-research-integration.md` accepts the
recommended compatibility defaults. This file remains a Phase 0 evidence map;
it does not authorize Phase 1.

## 1. Reading guide

The classifications in this document mean:

- **Direct reuse**: the existing implementation can serve the planned
  capability without changing its meaning.
- **Extend**: the accepted implementation remains authoritative, but a
  contract, adapter, association, projection, or new executor is needed.
- **Conflict**: a plan term or behavior is incompatible with an existing
  accepted invariant and must not be implemented literally.
- **Absent**: there is no product/domain/service/persistence implementation for
  the planned capability.

“Absent” is not a defect in the accepted Meeting MVP. It identifies future
work only.

## 2. Target-to-code matrix

| Plan target | Existing path and symbol | Classification | Required compatibility treatment |
| --- | --- | --- | --- |
| Native app and top-level navigation | `Sources/MeetingBuddyApp/MeetingBuddyApp.swift` / `MeetingBuddyDesktopApp`; `Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift` / `MeetingBuddyRootView` | Direct reuse + Extend | Extend the one SwiftUI navigation system only in a later UI phase; flag-off must preserve current sections |
| Meeting | `Sources/MeetingBuddyDomain/MeetingProfileV1.swift` / `MeetingProfileV1` | Direct reuse | Keep the existing type and immutable revision behavior |
| Logical multi-kind Workspace | `WorkspaceManifest.workspaceID` in `Sources/MeetingBuddyApplication/WorkspaceContracts.swift` identifies the physical root | **Conflict + Absent** | Add a distinctly named Research business ID/type; never reinterpret `WorkspaceID` |
| Meeting ↔ Research association | No association exists | Absent | Define only a reference contract in Phase 1; any durable association is a separately authorized future persistence decision, with no fabricated backfill |
| Source | `Sources/MeetingBuddyDomain/SourceAssetV1.swift` / `SourceAssetV1` is Meeting-owned | Extend + Conflict | Retain it as Meeting truth; project/link it into any shared registry |
| Provenance | `Sources/MeetingBuddyDomain/Provenance.swift`; `ProviderMetadata`, `GenerationMetadata`; revision envelopes throughout Domain | Direct reuse | Reuse versioned provider/component metadata and exact revision references |
| WorkspaceSource | No corresponding contract or table | Absent | Define a reference contract after the accepted `ResearchWorkspaceID` boundary; persistence is outside Phase 1 |
| Content hashing | `ContentDigest`; `LocalStorageService.storeFile(...)`; `ManagedAssetRecord.contentHash` | Direct reuse | Reuse integrity hashing |
| Content-addressed ObjectStore and deduplication | Files are `Meetings/<meeting-id>/assets/<uuid>`; no unique content-hash constraint | **Conflict + Absent** | Introduce a seam/adapter first; do not move or merge existing files |
| Transcript audio inference | `AIProviderContracts.swift` / `TranscriptionProvider`; Apple provider and `TranscriptPipelineJobExecutor` | Direct reuse | Keep unchanged |
| Plan `TranscriptProvider.probe/fetch/refresh` | No equivalent source-discovery provider | **Conflict + Absent** | Name it `TranscriptSourceProviding` or equivalent; do not replace ASR provider |
| Transcript source resolver | No resolver or resolution decision | Absent | Add provider-neutral contracts first; resolver owns any skip-ASR decision |
| Time-aligned transcript segments | `TranscriptSegmentV1`, `TranscriptCoverageManifest` | Direct reuse + Conflict | Keep strict audio provenance/coverage; text-only official records require a separate truthful model |
| Imported/UN/official transcript | Manual text publication exists; no discovery/import provider | Absent | Manual correction is not an official/imported provider; connectors are later work |
| Briefing | `BriefingSectionV1`, `ValidationReportV1`, `FinalBriefingV1`; briefing job/review/export services | Direct reuse | Preserve exact revisions, dependencies, review, and export |
| Generic Artifact | No `Artifact`/`ArtifactVersion`; only concrete semantic objects | Extend + Absent | Add a catalog/reference layer pointing to exact existing revisions |
| Evidence | `EvidenceRefV1`, `EvidenceLocation`, `EvidenceLinkedClaim` | Direct reuse | Use as the sole source/locator truth |
| Citation | No generic entity/engine/navigation; evidence locators already exist | Extend + Absent | Add associations, verification, and presentation around `EvidenceRefV1`; do not duplicate locators |
| Conversation / Message / Chat | No product types, tables, services, or UI | Absent | Define provider-neutral context and append-only value contracts only; persistence and UI are outside Phase 1 |
| ResearchRun | No type, repository, table, or job association | Absent | Defer until an executable Research workflow exists; do not overload `JobRecord.meetingID` |
| Tasks | `JobContracts.swift`, `LocalTaskManager`, `SQLiteJobRepository`, task temporary/log stores | Direct reuse + Extend | Register new typed jobs/executors and context; no second runner |
| Persistence/migrations/recovery | `SQLitePersistenceStore`, `SQLiteSchema` v10, bootstrap backup, `SQLiteRecoveryService` | Direct reuse | Keep schema v10 unchanged throughout Phase 1; any future durable Research state requires a separate ADR and authorization |
| Single user-selected data root | `LocalWorkspaceService`, `WorkspaceManifest`, `WorkspaceSecurityScope` | Direct reuse | Keep one root and opaque capabilities |
| Research files/exports/cache/index ownership | Only Meeting assets/exports and shared operational folders exist | Absent | Add explicit ownership/retention under the same root in later phases |
| Product Settings / Setup Guide | No Settings scene or setup flow | Absent | Phase 2 per plan, not Phase 1 UI |
| InstructionProfile / Snapshot / Compiler | No types or persistence | Absent | Add protected layered contracts; user instructions cannot override policy |
| Learned preferences | `HistoricalReviewContracts.swift` / `LearnedPreferenceValue`, `LearnedPreferenceState` | Direct reuse for presentation only | Do not generalize into unrestricted instructions |
| Automation settings | `AutomationContracts.swift` / `AutomationSettingsValues` | Direct reuse only for automation | Do not use as product feature flags or instruction storage |
| Feature flags | No general feature-flag type/service | Absent | Composition-owned, typed, local, default false; persistent settings deferred |
| AI provider policy | `ModelPolicyRouter`, capability-specific provider contracts | Direct reuse + Extend | Preserve specialized ports; optionally add a separate conversational/generation port |
| Codex/OpenAI route | No SDK, client, login, credential, or outbound adapter | **Absent; plan premise conflicts with code** | No Phase 1 provider; require a separate security/privacy/provider decision |
| MCP | `MeetingBuddyMCPEntry`, `AutomationMCPAdapter.exposedCommands` | Direct reuse for local automation only | Never treat as inference, Chat, or Codex |
| UN Web TV | Exact-host metadata-only implementation | Direct reuse for metadata only | It does not authorize media/transcript acquisition; connector work remains later |
| Browser Companion | No implementation | Absent | Remains post-MVP and outside Phase 1 |

## 3. Important “similar but not equivalent” cases

### 3.1 Physical workspace is not a Research workspace

`WorkspaceManifest.workspaceID` identifies the selected filesystem authority.
`SQLitePersistenceStore.validateWorkspaceOwnership(...)` requires a Meeting to
carry that same identity. The planned `kind: meeting | meeting_research |
resolution | document | topic` object is a business collection/context.

Reusing the ID would cause ownership failures and would make recovery,
automation, storage, and Meeting metadata ambiguous.

### 3.2 Manual transcript is not an imported transcript provider

`AppMediaReviewWorkflow.publishManualTranscript(...)` gives the accepted
Meeting pipeline a local fallback and preserves a human-authored revision. It
does not probe an external source, record official authority/completeness,
refresh a canonical record, or choose between alternatives.

### 3.3 Historical review is not Research or Chat

`HistoricalReviewContracts.swift` and `HistoricalReviewView.swift` provide
bounded deterministic search/comparison over confirmed positions. They do not
create a source collection, Research run, open-ended question thread, or
conversation history.

### 3.4 EvidenceRef is not a complete Citation experience

`EvidenceRefV1` already owns the exact source revision and typed locator.
However, there is no generic claim/message/artifact association, runtime
document locator verification, verification-status projection, Evidence
Inspector, or click-to-page/timestamp route.

The missing presentation layer should not become a second evidence truth.

### 3.5 Hash verification is not content-addressed storage

`LocalStorageService` computes SHA-256 and `ManagedAssetRecord` persists it,
which proves byte integrity. Physical identity remains an opaque storage UUID
inside a Meeting directory; no cross-Meeting dedupe or global object tree
exists.

### 3.6 MCP is not a Codex or AI-provider path

`meetingbuddy-mcp` accepts a closed set of local stdio automation commands.
It neither calls a model nor supplies conversation generation. Treating it as
the plan's “existing Codex path” would bypass the accepted provider,
classification, and outbound-routing boundaries.

### 3.7 Prompt modules are not user Instructions

`DiplomaticAnalysisPrompt.protectedRules` and
`DiplomaticBriefingPrompt.protectedRules` are application-owned safety and
validation rules. Learned preferences only influence presentation.

A future instruction system must compile user intent below those boundaries;
it must not turn protected rules into editable settings.

## 4. Governance dispositions and future decision gates

These are not current release defects. ADR-0018 either closes a Phase 1
default or explicitly defers the subject beyond Phase 1.

| Gate | ADR-0018 disposition | Evidence required at the applicable future gate |
| --- | --- | --- |
| Business workspace terminology | **Closed for Phase 1:** `ResearchWorkspaceID` / `ResearchWorkspaceV1` | Contract tests proving physical `WorkspaceID` is unchanged |
| Source canonical identity | **Partly closed:** Phase 1 uses exact read-only revision references; universal refresh/dedupe identity is deferred | Connector- and storage-specific canonical-key rules before durable refresh/dedupe |
| Text-transcript truth model | **Closed for Phase 1:** optional timing remains truthful and cannot satisfy audio coverage without proof | Contract/golden fixtures for authority, completeness, timing, and alignment |
| Conversation authority | **Closed for Phase 1:** provider-neutral append-only contracts only; no persistence or UI | Separate retention/deletion/export decision before persistence |
| Instruction snapshot privacy | **Closed for Phase 1:** canonical structured config + exact versions + deterministic hash; no full compiled prompt by default | Separate privacy/retention review before any full-prompt persistence |
| Artifact compatibility | **Closed for Phase 1:** catalog/reference projections point to exact immutable revisions | Adapter identity, revision, and stale-behavior tests |
| Citation verification | **Closed for Phase 1:** Citation references exact `EvidenceRefV1`; no locator duplication | Validator/failure/navigation fixtures before a visible inspector |
| Feature-flag authority | **Closed for Phase 1:** local, static, composition-owned, all false | Default-off and no-remote/model/automation-mutation tests |
| Persistent Research state | **Deferred beyond Phase 1:** schema remains v10 | Separate ADR, exact durable requirement, migration/backup/restore design, and authorization |
| External provider route | **Deferred beyond Phase 1** | Separate provider ADR/security review and visible authorization design |
| Physical deduplication | **Deferred beyond Phase 1** | Classification/retention-aware reference and GC rules plus recovery benchmark |

## 5. Potentially destructive changes and avoidance

| Potential change | Breakage mechanism | Required avoidance |
| --- | --- | --- |
| Rename or reinterpret `WorkspaceID` | Violates Meeting-to-root ownership and corrupts storage/recovery semantics | Introduce `ResearchWorkspaceID` or another distinct business type |
| Make every old Meeting a generic Workspace | Fabricates state and expands migration blast radius | Optional additive link; no automatic backfill |
| Replace `TranscriptionProvider` | Breaks the current task-owned audio ASR pipeline | Add a separate source-discovery protocol |
| Make `TranscriptSegmentV1.timeRange` optional | Weakens accepted deterministic audio coverage | Keep the current type strict; add an upstream text-source snapshot model |
| Synthesize timestamps/source revisions for official text | Creates false provenance and coverage | Preserve unknown/absent timing explicitly and fail closed |
| Replace concrete semantic objects with generic Artifact JSON | Breaks decoders, hashes, dependencies, stale propagation, and golden fixtures | Artifact catalog references exact existing revisions |
| Duplicate `EvidenceLocation` inside Citation | Creates two disagreeing locator truths | Citation references an exact `EvidenceRefV1` revision |
| Add Research kinds to `BriefingSectionType` | Breaks the closed Meeting briefing contract | Separate Research templates/artifact contracts later |
| Rebuild `semantic_revisions` for Phase 1 convenience | Risks all immutable objects, FKs, triggers, and canonical bytes | Prefer new tables; do not change closed vocabulary unless strictly required |
| Change `managed_assets.meeting_id` or move old files | Breaks journals, Trash, recovery, exports, and source bindings | Preserve legacy files/rows; adapter and new-object seam only |
| Deduplicate solely by SHA-256 | Can merge data with incompatible classification/retention | Include authority, classification, retention, and references in a later design |
| Add a second task runner/database/frontend | Creates competing state, recovery, and policy paths | Reuse existing Swift modules, `LocalTaskManager`, and SQLite authority |
| Let user instructions override protected rules | Can weaken evidence, privacy, routing, and human confirmation | Explicit immutable policy layer above compiled user instructions |
| Add visible Research navigation while flag is false | Changes accepted Meeting UX before Research is usable | Root-view/navigation regression tests and composition-owned default-off flag |
| Call Codex directly from a feature | Bypasses model policy and data authorization | Application-owned provider port; adapter requires separate authorization |
| Treat UN metadata support as download authority | Expands network/rights scope without evidence | Keep exact-host metadata-only boundary; later connector-specific decision |
| Introduce future persistent Research tables without a separate gate | Changes the supported-data compatibility boundary | Keep Phase 1 at schema v10; require a separate ADR, backup, migration, and tested rollback before any later schema work |

## 6. Gaps grouped by the plan's Phase 1 deliverables

### Source / Provenance

Reuse:

- `SourceAssetV1`
- `ContentDigest`
- `EvidenceRefV1`
- `ProviderMetadata`
- `GenerationMetadata`
- exact semantic revision envelopes

Gap:

- a Meeting-independent source identity and source-to-logical-workspace
  association.

Minimum response:

- a reference/projection contract around existing source revisions;
- no source payload rewrite and no physical-file movement.

### Extensible Artifact

Reuse:

- concrete immutable briefing and historical-review objects;
- active pointers, dependencies, stale propagation, and exact revisions.

Gap:

- generic discovery/catalog metadata and future Research artifact kinds.

Minimum response:

- `ArtifactDescriptor` and `ArtifactVersionRef` pointing to existing exact
  revisions;
- no generic replacement for `FinalBriefingV1`.

### Conversation context

Reuse:

- stable typed IDs, canonical encoding patterns, classification policy, and
  provider generation metadata.

Gap:

- all product Conversation behavior and storage.

Minimum response:

- provider-neutral context and append-only message contracts;
- no persistence in Phase 1; a reviewed durable use case and separate
  authorization are required later;
- no UI and no model provider in Phase 1.

### InstructionProfile foundation

Reuse:

- protected prompt rules;
- versioned components and generation metadata;
- presentation-only learned preferences;
- model-security policy snapshots.

Gap:

- structured profiles, compilation precedence, immutable snapshot, and product
  settings.

Minimum response:

- contracts/compiler tests that prove protected rules cannot be overridden;
- no Setup Guide UI until the plan's later phase.

### TranscriptProvider interface

Reuse:

- current `TranscriptionProvider` for local ASR;
- task, coverage, review, and correction pipeline.

Gap:

- source availability/fetch/refresh, source authority/completeness, and
  explainable resolution.

Minimum response:

- a separately named interface and resolver contract;
- no network provider and no change to the current ASR route.

### Feature flags

Reuse:

- app composition root and dependency injection.

Gap:

- a typed capability set and flag-off regression proof.

Minimum response:

- local composition-owned values, all false by default;
- no remote service, automation mutation, or persistent UI setting.

### Data migration and old-data compatibility

Reuse:

- ordered GRDB migrations, online pre-migration backup, failure injection,
  unknown-future rejection, recovery manifests, and prior-version fixtures.

Gap:

- no durable Phase 1 requirement; ADR-0018 fixes Phase 1 at schema v10.

Minimum response:

- keep contract-only work schema-free;
- treat any future persistence proposal as outside Phase 1 and require its own
  ADR, explicit authorization, supported-prior-state migration proof, byte
  preservation, reopen/recovery evidence, full Meeting regression, and a
  tested backup restore.

## 7. Deliberately deferred gaps

The following plan items do not belong in the minimum compatibility phase:

- visible Research shell or top-level navigation;
- Setup Guide and product Settings UI;
- UN transcript, UN Digital Library, ODS, or Browser Companion connectors;
- Codex/OpenAI or another outbound provider;
- Research search/fetch orchestration;
- Resolution, Document, Topic, or Meeting Research workflows;
- rich Evidence Inspector and PDF navigation;
- physical cross-workspace content-addressed deduplication or garbage
  collection;
- ResearchRun execution and metrics;
- Meeting-to-Research and Research-to-Meeting user journeys.

Deferring them is necessary to keep Phase 1 small; it is not a claim that the
product plan no longer needs them.

## 8. Residual unknowns

Phase 0 did not and should not:

- inspect a real user's Meeting workspace contents;
- read Keychain credentials or bookmark values;
- contact UN, ODS, Codex/OpenAI, or any other external service;
- test official transcript formats, timestamps, rights, or update behavior;
- run the GUI, live microphone/screen capture, or installed-model quality path;
- benchmark any future Research migration because persistence is outside the
  accepted Phase 1 boundary and no such design exists.

The exact validation route for each unknown is listed in
`docs/BLUE_MINUTES_ARCHITECTURE_MAP.md` and the proposed implementation gates
are listed in `docs/MEETING_RESEARCH_PHASE1_PROPOSAL.md`.
