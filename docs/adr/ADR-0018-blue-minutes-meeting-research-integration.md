# ADR-0018: Blue Minutes Meeting / Research Integration Boundary

Status: Accepted

Date: 2026-07-23

Decision owner: Maintainer

Acceptance scope: Governance and documentation only

Implementation authorization: None

Audit and rollback baseline:
`d473b7037d7014ef0ae4e18d2c72463847347d8e`

Product plan:
`../BLUE_MINUTES_MEETING_RESEARCH_MVP_PLAN.md`

## Context

The Blue Minutes product plan adds a Research area around the accepted Meeting
MVP. It introduces logical research workspaces, shared sources, generic
artifacts, citations, conversations, instruction profiles,
transcript-source resolution, and capability flags.

The current application is a native Swift 6 and SwiftUI modular monolith
declared in `Package.swift`. Its accepted runtime already has:

- the physical data-root identity `WorkspaceID` and `WorkspaceManifest` in
  `Sources/MeetingBuddyApplication/WorkspaceContracts.swift`;
- Meeting identity and ownership in
  `Sources/MeetingBuddyDomain/MeetingProfileV1.swift`;
- Meeting-owned `SourceAssetV1` records in
  `Sources/MeetingBuddyDomain/SourceAssetV1.swift`;
- exact evidence locators in
  `Sources/MeetingBuddyDomain/EvidenceRefV1.swift`;
- immutable briefing and historical objects, including `FinalBriefingV1` and
  `HistoricalComparisonV1`;
- audio-ASR inference through `TranscriptionProvider` in
  `Sources/MeetingBuddyApplication/AIProviderContracts.swift`;
- one durable task runtime, `LocalTaskManager`;
- SQLite schema v10 and GRDB-backed repositories;
- one application-owned local workspace root and managed-file layout;
- deny-by-default provider routing and protected prompt rules.

Several plan terms resemble existing names while carrying different semantics.
Implementing them literally would risk physical workspace ownership,
transcript coverage, evidence truth, immutable revisions, recovery, and the
accepted Meeting flow.

The Phase 0 evidence is recorded in:

- `../BLUE_MINUTES_ARCHITECTURE_MAP.md`;
- `../MEETING_RESEARCH_INTEGRATION_ADR.md`;
- `../MEETING_RESEARCH_GAP_ANALYSIS.md`;
- `../MEETING_RESEARCH_PHASE1_PROPOSAL.md`.

## Decision

### 1. Preserve the accepted application architecture

Research extends the current Swift/SwiftUI/SwiftPM modular monolith and its
existing module boundaries. It does not introduce a second frontend,
JavaScript shell, Python sidecar, external executable, duplicate database,
duplicate task runner, or second user-data root.

New conceptual plan modules do not justify new SwiftPM targets or dependencies
by themselves. Domain contracts belong in `MeetingBuddyDomain`; application
ports, policy, and adapters belong in `MeetingBuddyApplication`; composition
continues through `WorkspaceRuntime` and `AppMediaReviewWorkflow`.

### 2. Keep physical and business workspace identity separate

`WorkspaceID`, `WorkspaceManifest`, and
`MeetingProfileV1.workspaceID` retain their accepted physical-root ownership
meaning.

The logical Research business types are named:

- `ResearchWorkspaceID`;
- `ResearchWorkspaceV1`.

They must not rename, reuse, reinterpret, or share the serialized meaning of
`WorkspaceID`. Meeting-to-Research association is additive. Existing Meetings
must not be rewritten, mass-converted, or assigned fabricated Research
workspaces.

### 3. Use exact references and read-only adapters

Accepted concrete objects remain authoritative:

- `SourceAssetV1` remains Meeting source truth;
- concrete semantic revisions such as `FinalBriefingV1` and
  `HistoricalComparisonV1` retain their payload, hash, dependency, active
  pointer, and stale semantics;
- `EvidenceRefV1` remains the sole typed evidence-locator truth.

A future shared Source view, Artifact catalog, or Citation association may
project or link to those exact revisions. It must not replace them with mutable
generic JSON, duplicate `EvidenceLocation`, rewrite canonical bytes, or infer
authority that the source record does not prove.

### 4. Keep transcript-source discovery separate from ASR

The current `TranscriptionProvider` remains the audio-chunk-to-ASR inference
port. Imported or official transcript discovery uses a distinct
`TranscriptSourceProviding` contract, with selection owned by an
application-level resolver.

Phase 1 may define availability, fetch/refresh snapshot, authority,
completeness, and resolution-decision value types. It does not implement a
network provider or alter the production ASR route.

A provider cannot unilaterally skip local ASR. Text without proven audio
alignment must remain a distinct source snapshot and cannot receive fabricated
timestamps, `TranscriptSegmentV1` provenance, or
`TranscriptCoverageManifest` coverage.

### 5. Keep Conversation contract-only in Phase 1

Conversation is not an existing product capability. Phase 1 may define
provider-neutral context and append-only message value contracts only.

It adds no Conversation persistence and no Conversation or Chat UI. Generated
messages do not become Meeting facts, evidence-backed artifacts, or
human-confirmed claims without the existing validation and confirmation
boundaries. MCP JSON-RPC traffic and automation audit records are not
Conversation messages.

### 6. Compile instructions below protected policy

Instruction precedence is:

```text
non-overridable application policy
  -> protected capability and prompt rules
  -> global structured user profile
  -> template profile
  -> Research workspace profile
  -> request-scoped instruction
  -> immutable instruction snapshot
```

The canonical/default `InstructionSnapshot` representation contains:

- canonical structured configuration;
- exact profile identifiers and versions;
- exact protected-rule module versions;
- a deterministic hash.

Full compiled prompt text is not persisted by default. User instructions
cannot override evidence requirements, prompt-injection handling,
classification, provider destination or retention policy, offline/network
policy, tool authority, diplomatic/factual validation, or human confirmation.
`AutomationSettingsValues` and learned presentation preferences are not
repurposed as instruction storage.

### 7. Reuse tasks and add only a storage compatibility seam

Future executable Research work must use typed `JobType` values,
`TaskJobExecutor`, and the existing `LocalTaskManager`. It must not overload
the meaning of `JobRecord.meetingID` or create a second background-job system.

Phase 1 may define an ObjectStore compatibility seam over existing managed
assets. It does not move, rename, hard-link, deduplicate, backfill,
garbage-collect, or reclassify files under
`Meetings/<meeting-id>/assets/`. SHA-256 equality alone never authorizes
merging objects with potentially different classification or retention.

### 8. Make capabilities local, static, and default off

`AppCapabilities` is an immutable composition-owned value. Its Research
integration capabilities are all `false` by default, including:

- `research`;
- `transcriptSourceResolution`;
- `sharedObjectStore`;
- `conversationPersistence`.

Imported content, model output, automation, MCP, and remote configuration
cannot change these values. With defaults, `MediaReviewSection`,
`MeetingBuddyRootView`, provider routes, job registration, network behavior,
and all accepted Meeting flows remain unchanged.

### 9. Keep Phase 1 on schema v10

Phase 1 contains no persistence implementation, schema migration, backfill, or
user-data write. SQLite schema v10 remains unchanged.

Any later durable Research requirement is outside Phase 1 and requires:

1. a separate accepted ADR;
2. explicit implementation authorization;
3. an ordered backward-compatible migration;
4. supported-prior-state and failure-injection tests;
5. a verified pre-migration backup;
6. a tested rollback using the supported prior binary and data state;
7. proof that canonical bytes, active pointers, dependencies, Meeting rows,
   managed-file references, recovery records, and existing files are
   preserved.

No future migration version or table family is accepted by this ADR.

### 10. Add no outbound provider or connector in Phase 1

The repository has no existing Codex/OpenAI application-provider route. Local
stdio MCP is an automation boundary, not an inference provider.

Phase 1 adds no:

- Codex/OpenAI or other outbound model adapter;
- credential, cookie access, or login flow;
- external network destination;
- UN transcript/document or ODS connector;
- Browser Companion;
- automatic media acquisition.

Any outbound adapter requires a separate provider/security/privacy decision
covering exact data categories, classification inheritance, destination,
authentication, provider retention, organization policy, visible user
authorization, local/offline alternative, and failure behavior.

### 11. Bound the unapproved Phase 1 proposal to two groups

The smallest compatible Phase 1 proposal contains exactly two reviewable
groups:

1. contracts and read-only compatibility adapters;
2. default-off capability composition.

This grouping is a governance boundary, not implementation authorization.
Each group requires a later exact user command, validation, and stop for human
review. There is no Phase 1 persistence group.

## Consequences

Positive:

- the accepted Meeting application and user data remain untouched;
- ambiguous plan terms gain explicit, non-conflicting meanings;
- future work can reuse task, evidence, immutable revision, provider-policy,
  recovery, and local-storage foundations;
- each possible implementation slice remains narrow and reversible;
- an external provider, connector, migration, or visible Research surface
  cannot enter through an implicit plan assumption.

Costs and limitations:

- compatibility references require explicit mapping code;
- Research remains invisible and non-executable until separately authorized;
- Conversation has no durability or UI in Phase 1;
- text-only transcripts remain separate from time-aligned audio transcript
  segments unless alignment is proven;
- generic discovery, rich citation navigation, connectors, external models,
  physical deduplication, and durable Research state remain later work.

## Rejected alternatives

- Reinterpret physical `WorkspaceID` as a logical multi-kind workspace.
- Rewrite accepted Meeting objects into a generic Workspace/Artifact schema.
- Replace `TranscriptionProvider` with transcript-source discovery.
- Duplicate evidence locators in a competing Citation representation.
- Treat local MCP as a Codex or conversational-inference provider.
- Introduce a second UI stack, database, task runtime, or filesystem root.
- Move or deduplicate existing files to simulate a content-addressed store.
- Add an unused schema migration for future planned models.
- Let imported content, models, automation, or remote configuration enable
  Research capabilities.

## Authority, initiative, and rollback

This ADR accepts governance defaults only. It:

- does not create Task 012;
- does not change `current_task: "011"` or the accepted MVP task sequence;
- does not authorize Phase 1;
- does not authorize production code, tests, schema, dependencies, UI,
  network access, credentials, user-data access, commit, push, or Pull Request.

Blue Minutes Meeting / Research is an independent post-MVP initiative recorded
in `../CODEX_EXECUTION_STATE.md`.

The rollback anchor for this governance-only change is
`d473b7037d7014ef0ae4e18d2c72463847347d8e`. Before commit, rollback is a local
documentation revert. No application, database, or user-data rollback is
required because none changed.

## Deferred validation

The following remain unknown until a separately authorized phase reaches
them:

- official transcript/document formats, authority, update behavior, and
  rights;
- connector-specific network and authentication behavior;
- external-provider data handling and model quality;
- Conversation retention, deletion, export, and privacy behavior;
- visible Research UX and accessibility;
- any future persistence design, migration duration, backup, and restore;
- live installed-model, microphone, screen-capture, and full GUI behavior.

Their required validation routes are listed in
`../BLUE_MINUTES_ARCHITECTURE_MAP.md` and
`../MEETING_RESEARCH_GAP_ANALYSIS.md`.
