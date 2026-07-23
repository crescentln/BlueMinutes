# Meeting / Research Integration Compatibility Decision

Status: **Phase 0 supporting record; canonicalized by ADR-0018**

Date: 2026-07-23

Decision owner: Maintainer

Scope: Phase 0 recommendation and audit rationale only

## 1. Status and authority

This document records the detailed compatibility rationale derived from
`docs/BLUE_MINUTES_MEETING_RESEARCH_MVP_PLAN.md` and the Phase 0 code audit.
The maintainer accepted its recommended defaults in
`docs/adr/ADR-0018-blue-minutes-meeting-research-integration.md`, which is the
canonical and binding decision record.

This supporting record does not itself authorize Phase 1 implementation,
schema work, production behavior, a numbered Task 012, or external
publication.

The proposal must remain compatible with the accepted decisions in:

- `docs/adr/ADR-0001-language-ui-and-platform.md`
- `docs/adr/ADR-0003-persistence-and-recovery.md`
- `docs/adr/ADR-0004-immutable-revisions.md`
- `docs/adr/ADR-0005-dependency-invalidation.md`
- `docs/adr/ADR-0006-provider-and-agent-boundaries.md`
- `docs/adr/ADR-0007-data-classification-and-cloud-routing.md`
- `docs/adr/ADR-0009-task-005b-local-transcription-and-translation.md`
- `docs/adr/ADR-0013-task-008a-capture-and-un-web-tv-boundary.md`
- `docs/adr/ADR-0016-task-010-historical-review-and-preferences.md`
- `docs/adr/ADR-0017-evidence-integrity-publication-boundaries.md`

## 2. Context

The existing product is a Swift 6 native macOS modular monolith. Its accepted
Meeting flow has:

- one user-selected physical data root identified by `WorkspaceID`;
- Meeting-owned `SourceAssetV1` records and managed files;
- immutable semantic revisions, active pointers, dependencies, and stale
  propagation;
- a durable local task manager;
- local installed-model provider routes with deny-by-default external routing;
- schema-v10 SQLite metadata and file-backed assets;
- exact evidence and transcript-coverage requirements.

The plan introduces a second product area, Research, plus logical workspaces,
shared sources, conversations, generic artifacts, citations, instruction
profiles, transcript-source resolution, feature flags, and eventually external
connectors and providers.

Several plan terms overlap existing names but have different meanings. A
direct generalization would put the accepted Meeting baseline at unnecessary
risk.

## 3. Phase 0 recommendations accepted by ADR-0018

### D1. Preserve the native modular monolith

Research will extend the current Swift/SwiftUI/SwiftPM application and existing
module boundaries. Phase 1 will add no second frontend stack, Python sidecar,
external executable, or duplicate persistence/task runtime.

No new SwiftPM module or dependency should be added merely to mirror the
plan's conceptual module diagram. New contracts should initially live in the
existing `MeetingBuddyDomain` and `MeetingBuddyApplication` targets; concrete
persistence and composition should remain in their current targets.

### D2. Separate the two meanings of Workspace

The existing terms retain their exact meaning:

- `WorkspaceID` and `WorkspaceManifest` identify the selected physical user
  data root.
- `MeetingProfileV1.workspaceID` continues to prove that the Meeting belongs
  to that data root.

The plan's business-level object uses the distinct contract names
`ResearchWorkspaceID` and `ResearchWorkspaceV1`. It must not reuse, rename, or
reinterpret `WorkspaceID`.

Meeting-to-Research association will be additive. Existing Meetings will not
be mass-converted, assigned fabricated Research workspaces, or rewritten.

### D3. Use adapters and links, not a generic rewrite

Accepted objects remain authoritative:

- `SourceAssetV1` remains the source asset for an accepted Meeting.
- `FinalBriefingV1`, `HistoricalComparisonV1`, and other semantic contracts
  retain their exact payload, revision, hash, dependency, and stale behavior.
- `EvidenceRefV1` remains the canonical evidence locator.

Future shared views will link to these exact objects:

- a source registry may project or associate an existing source revision;
- an artifact catalog may point to an exact semantic revision;
- a citation association may point to an exact `EvidenceRefV1`.

The compatibility layer must not copy locators into a competing Citation truth,
wrap existing briefing payloads in mutable generic JSON, or rewrite historical
canonical bytes.

### D4. Keep transcript-source discovery separate from ASR inference

`TranscriptionProvider` remains the application-owned audio-chunk-to-ASR
inference port.

A future discovery interface will use a different name, for example:

```swift
public protocol TranscriptSourceProviding: Sendable {
    func probe(_ context: TranscriptSourceContext) async throws
        -> TranscriptSourceAvailability
    func fetch(_ reference: TranscriptSourceReference) async throws
        -> TranscriptSourceSnapshot
    func refresh(_ reference: TranscriptSourceReference) async throws
        -> TranscriptSourceSnapshot
}
```

`TranscriptSourceResolver` will be application-owned. A provider cannot
unilaterally decide to skip local ASR. The resolver must record the selected
primary source, authoritative reference, ASR decision, reason, and alternatives.

The accepted `TranscriptSegmentV1` requires time-aligned audio provenance and
the transcript ledger proves canonical-audio frame coverage. An official or
imported text transcript without timestamps must therefore remain a distinct
source snapshot; it must not be coerced into `TranscriptSegmentV1` by inventing
time ranges, source revisions, or coverage.

### D5. Treat Citation as an EvidenceRef projection

`EvidenceRefV1` is the evidence truth. A future Citation layer may add:

- association to an artifact version, claim, or message;
- computed or persisted verification status;
- display labels and excerpts;
- locator validation and click-through navigation.

It must reference the exact evidence revision and must not duplicate or weaken
the typed `EvidenceLocation`. A conclusion with an invalid or unresolvable
locator remains visibly unverified and cannot be silently upgraded.

### D6. Add Conversation as a separate append-only record boundary

Conversation does not currently exist. Phase 1 is limited to provider-neutral
contracts:

- an append-only `Message` value for user/provider turns;
- a mutable projection only for non-authoritative metadata such as title,
  archive status, or last-updated time;
- an exact context snapshot containing scope, classification, referenced
  revisions, instruction snapshot, and provider/run metadata.

Conversation messages are not semantic Meeting facts merely because they were
generated in a Meeting context. Claims intended for a durable artifact must
pass the existing evidence, validation, and human-confirmation boundary.

MCP JSON-RPC traffic and automation audit events are not Conversation records.
Conversation persistence and UI are outside Phase 1 and require separate
authorization.

### D7. Layer Instructions below protected policy

The instruction compiler will have explicit precedence and immutability:

```text
non-overridable application policy
  -> protected capability/prompt rules
  -> global structured user profile
  -> template profile
  -> logical workspace profile
  -> request-scoped instruction
  -> immutable compiled snapshot
```

Later user layers may refine presentation and task intent, but they cannot
change:

- evidence and citation requirements;
- prompt-injection handling;
- provider destination, retention, or data classification;
- network/offline policy;
- tool authority;
- diplomatic and factual validation gates;
- human-confirmation requirements.

`AutomationSettingsValues` and learned presentation preferences will not be
repurposed as an instruction store.

The durable/default representation of `InstructionSnapshot` is canonical
structured configuration, exact profile versions, protected-rule module
versions, and a deterministic hash. Full compiled prompt text is not persisted
by default. Any later exception requires a separate privacy and retention
decision.

### D8. Reuse the current task runtime

Research work will register new typed `JobType` values and
`TaskJobExecutor` implementations with `LocalTaskManager`. It will use the
same durable state machine, idempotency, dependency, checkpoint, cancellation,
input-revision revalidation, task directory, redacted log, and recovery
boundaries.

A typed Research context/run association may be added without changing the
meaning of an existing `JobRecord.meetingID`. There will be no second queue or
background-job subsystem.

### D9. Extend storage without moving accepted Meeting files

The selected local workspace root remains the only user data root.

Phase 1 may introduce only an ObjectStore compatibility seam over existing
hash-verified managed assets. It will not move files or claim physical
content-addressing or deduplication.

Existing files under `Meetings/<meeting-id>/assets/` will not be moved,
renamed, hard-linked, deduplicated, garbage-collected, or backfilled. If a
future content-object catalog is approved, it should initially apply only to
new objects, retain legacy aliases, and include classification/retention in
reference and collection decisions. SHA-256 equality alone is not sufficient
authority to merge differently classified or retained data.

### D10. Keep feature flags composition-owned and default off

Phase 1 flags will be strongly typed, local, and injected at the app
composition root. At minimum:

```text
research
transcriptSourceResolution
sharedObjectStore
conversationPersistence
```

All default to `false`. They cannot be changed by imported content, model
output, an automation command, or remote configuration.

With `research == false`:

- `MediaReviewSection` and `MeetingBuddyRootView` remain visibly unchanged;
- no Research job or migration backfill starts;
- no network/provider route becomes available;
- accepted Meeting open/import/transcript/analysis/briefing/history/storage
  behavior remains the regression oracle.

Persistent user-controlled flags are deferred beyond Phase 1. Phase 1 uses an
in-memory/static capability set.

### D11. Keep Phase 1 on schema v10

Phase 1 is contract, read-only adapter, and default-off capability work only.
It does not add persistence, change the database schema, or modify user data.
Schema v10 remains the compatibility boundary.

Any future durable Research requirement is outside Phase 1 and requires a
separate ADR, explicit implementation authorization, an ordered
backward-compatible migration, supported-prior-state tests, a verified backup,
and a tested rollback plan. It must not rebuild `semantic_revisions`, alter
`managed_assets.meeting_id`, rewrite canonical payloads, fabricate associations
for old Meetings, or move existing file bytes.

### D12. Do not create an outbound provider in Phase 1

The plan's reference to an “existing Codex path” is not true of the current
code. Phase 1 may define a provider-neutral conversation/generation capability
contract, but it will add:

- no Codex/OpenAI implementation;
- no cookie access;
- no credential;
- no external network destination;
- no UN transcript/document connector;
- no automatic media acquisition.

Any outbound adapter requires a separate decision identifying data categories,
classification inheritance, destination, authentication, retention,
organization policy, visible user authorization, local/offline alternative,
and failure behavior. Feature code must never call an external client directly.

## 4. Alternatives rejected by this proposal

### A. Convert Meeting into one generic Workspace/Artifact schema

Rejected because it would conflate physical and business workspace identity,
rewrite frozen semantic objects, enlarge the migration blast radius, and risk
evidence/dependency integrity without delivering a Phase 1 user benefit.

### B. Replace `TranscriptionProvider` with the plan's TranscriptProvider

Rejected because audio inference and transcript-source discovery have
different inputs, authority, completeness, privacy, and failure semantics.

### C. Introduce a Research database, task runner, or frontend

Rejected because the accepted modular monolith already provides the needed
persistence, task, security, and UI composition boundaries. Duplication would
create competing truth and recovery paths.

### D. Move all files into a hash-addressed object tree

Rejected for Phase 1 because current Meeting ownership, operation journals,
Trash, backup, and recovery are path-aware. Hashing already proves integrity;
physical deduplication is a separate storage decision.

### E. Treat MCP as the Codex provider

Rejected because local agent-control commands and application inference are
explicitly separate accepted boundaries.

### F. Persist every planned model immediately

Rejected because Phase 1's purpose is compatibility foundation, not premature
Research behavior. Persistence should be justified by an observable durable
requirement and introduced behind a separate migration gate.

## 5. Consequences

Positive consequences:

- accepted Meeting behavior and data remain untouched;
- Phase 1 can be reviewed in small, reversible slices;
- new concepts retain type-safe boundaries instead of overloaded names;
- Research can reuse task, evidence, recovery, and local-first foundations;
- an external provider or connector cannot accidentally appear through a
  product-plan assumption.

Costs and limitations:

- adapters and associations add some explicit mapping code;
- a generic Research view cannot initially treat every Meeting object as a
  native Research object;
- text-only transcripts will remain separate from time-aligned transcript
  segments until a truthful alignment/coverage model is approved;
- physical deduplication and rich citation navigation are deferred;
- any later persistence proposal requires a new ADR and substantial
  compatibility evidence before it can enter an implementation scope.

## 6. Governance dispositions

ADR-0018 closes the Phase 1 governance defaults as follows:

1. The logical business types are `ResearchWorkspaceID` and
   `ResearchWorkspaceV1`; physical `WorkspaceID` keeps its accepted meaning.
2. Conversation is contract-only in Phase 1: no persistence and no UI.
3. `InstructionSnapshot` uses canonical structured configuration, exact
   profile/protected-module versions, and a deterministic hash; full compiled
   prompt text is not persisted by default.
4. Shared Source, Artifact, and Citation compatibility uses read-only
   references to exact accepted revisions; `EvidenceRefV1` remains locator
   truth.
5. An ObjectStore is a compatibility seam only; no physical move, dedupe,
   backfill, or garbage collection is in Phase 1.
6. `TranscriptSourceProviding` remains separate from
   `TranscriptionProvider`; no provider can fabricate timing/coverage or
   unilaterally skip ASR.
7. `AppCapabilities` is local, static, composition-owned, and all false by
   default.
8. Phase 1 remains schema v10. Any future persistence proposal is a separate
   initiative gate, not a third Phase 1 change group.

Source authority/completeness rules, connector rights, external providers,
physical deduplication, and durable retention policies remain deliberately
deferred beyond Phase 1.

## 7. Rollback boundary

For the present governance task, rollback is a documentation-only revert to
the audit baseline
`d473b7037d7014ef0ae4e18d2c72463847347d8e`; no runtime or data state changed.

For a future approved Phase 1:

- contract/adapter work rolls back by reverting the corresponding source
  change while flags remain off;
- capability-composition work rolls back by reverting the all-false
  composition seam;
- no database rollback is part of Phase 1 because schema remains v10.

The Phase 1 source rollback anchor must be the exact human-reviewed repository
HEAD at authorization time. The Phase 0 audit baseline was
`d473b7037d7014ef0ae4e18d2c72463847347d8e`; it must not be assumed current
later.
