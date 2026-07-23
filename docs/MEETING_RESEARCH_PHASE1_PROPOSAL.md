# Meeting / Research Phase 1 Proposal

Status: **Proposed; not authorized**

Date: 2026-07-23

Phase 0 baseline: `d473b7037d7014ef0ae4e18d2c72463847347d8e`

Governing decision:
`docs/adr/ADR-0018-blue-minutes-meeting-research-integration.md`

## 1. Outcome

The smallest compatible Phase 1 is a hidden compatibility foundation inside
the existing Swift modular monolith. It introduces precise cross-domain
contracts and adapters, keeps every capability default-off, and does not alter
the accepted Meeting UX or processing path.

Phase 1 must not be treated as authorization for Research behavior, connectors,
an outbound AI provider, or a storage rewrite.

This proposal is intentionally divided into exactly two independently
reviewable change groups. Neither group is authorized by this document, and
both remain schema-v10 work.

## 2. Goals

1. Reserve unambiguous types for a future logical Research workspace without
   changing physical `WorkspaceID`.
2. Expose existing Meeting sources, briefings, comparisons, and evidence
   through read-only compatibility references.
3. Define provider-neutral Conversation, Instruction, Artifact, Citation, and
   transcript-source contracts.
4. Reuse the existing task, provider-policy, persistence, security, and local
   workspace boundaries.
5. Add a typed, composition-owned capability set whose defaults cause no
   visible or behavioral change.
6. Keep schema v10 and all existing user data unchanged.

## 3. Non-goals

Phase 1 will not:

- add a Research navigation item, tab, window, or workspace UI;
- change `MeetingBuddyRootView`'s visible sections when defaults are used;
- refactor media intake, recording, ASR, analysis, briefing, history, storage,
  CLI, MCP, or automation flows;
- rename or reinterpret `WorkspaceID` or `MeetingProfileV1.workspaceID`;
- loosen transcript time/provenance/coverage requirements;
- implement UN, ODS, browser, search, document-fetch, or transcript connectors;
- add Codex/OpenAI or another external model adapter;
- read cookies, add credentials, or create a network destination;
- introduce a second frontend, sidecar, database, task manager, or file root;
- move, deduplicate, re-hash, backfill, or garbage-collect existing assets;
- convert existing semantic payloads into generic Artifact JSON;
- change a user's existing database or schema;
- add Setup Guide or Settings UI; those remain a later plan phase.

## 4. Accepted terminology

The following names are recommended because they avoid collisions:

| Concept | Proposed name | Existing name intentionally preserved |
| --- | --- | --- |
| Selected physical data root | `WorkspaceID`, `WorkspaceManifest` | Existing meaning unchanged |
| Future business Research collection | `ResearchWorkspaceID`, `ResearchWorkspaceV1` | Must not be called or encoded as the physical `WorkspaceID` |
| Existing audio inference port | `TranscriptionProvider` | Existing protocol unchanged |
| External/imported transcript discovery | `TranscriptSourceProviding` | Separate capability |
| Source-selection policy | `TranscriptSourceResolving` / `TranscriptResolutionDecision` | Application-owned; provider cannot self-select |
| Existing evidence truth | `EvidenceRefV1` | Existing typed locator unchanged |
| Citation presentation/link | `CitationAssociation` | References EvidenceRef; does not copy locator |
| Generic artifact view | `ArtifactDescriptor`, `ArtifactVersionRef` | References exact concrete semantic revision |
| Feature switch set | `AppCapabilities` | Not `AutomationSettingsValues` |

ADR-0018 accepts these names and their semantic separation for Phase 1.

## 5. Change group 1: contracts and read-only compatibility adapters

### 5.1 Intended source changes

The exact filenames may be adjusted to existing file-size conventions during
implementation, but the target ownership should be:

| Proposed path | Proposed symbols and responsibility |
| --- | --- |
| `Sources/MeetingBuddyDomain/ResearchIntegrationValues.swift` | Stable IDs and closed scalar values for `ResearchWorkspaceID`, `ArtifactID`, `ArtifactVersionID`, `ConversationID`, `MessageID`, `InstructionProfileID`, `InstructionSnapshotID`, and source authority/completeness |
| `Sources/MeetingBuddyApplication/ResearchIntegrationContracts.swift` | `SharedSourceRef`, `ArtifactDescriptor`, `ArtifactVersionRef`, `ConversationContext`, append-only `ConversationMessage`, `InstructionProfile`, `InstructionSnapshot`, and repository-neutral validation |
| `Sources/MeetingBuddyApplication/TranscriptSourceContracts.swift` | `TranscriptSourceContext`, `TranscriptSourceReference`, `TranscriptSourceAvailability`, `TranscriptSourceSnapshot`, `TranscriptSourceProviding`, `TranscriptResolutionDecision`, `TranscriptSourceResolving` |
| `Sources/MeetingBuddyApplication/ResearchCompatibilityAdapters.swift` | Read-only adapters from `SourceAssetV1`, `FinalBriefingV1`, and `HistoricalComparisonV1` to the new reference/projection types |
| `Sources/MeetingBuddyApplication/CitationContracts.swift` | `CitationAssociation` and verification projection referencing an exact `EvidenceRefV1` revision |
| `Tests/MeetingBuddyDomainTests/ResearchIntegrationValueTests.swift` | Validation, canonical encoding, stable-ID, unknown-value, and forward-compatibility tests |
| `Tests/MeetingBuddyAITests/ResearchIntegrationContractTests.swift` | Adapter identity, exact-revision, instruction precedence, append-only message, and citation-source-of-truth tests; this existing target already depends on Application, Domain, AI, Persistence, and Tasks |
| `Tests/MeetingBuddyAITests/TranscriptSourceContractTests.swift` | Availability/decision fixtures, provider/resolver separation, and fail-closed completeness tests |

No new SwiftPM product, target, or dependency is proposed.

### 5.2 Contract requirements

#### Source and provenance

`SharedSourceRef` must be a reference, not a replacement for
`SourceAssetV1`. At minimum it carries:

- exact source ID and revision;
- source kind and canonical-key claim;
- authority and completeness values;
- classification and retention;
- optional content digest and external reference;
- versioned provenance.

An adapter must not infer an official authority level from a URL or Meeting
metadata.

#### Artifact

`ArtifactVersionRef` identifies one of:

- an exact existing semantic object type and revision; or
- a future native Research artifact version type.

`ArtifactDescriptor.currentVersion` is a projection pointer. It does not make
an old immutable `FinalBriefingV1` mutable and does not replace the existing
active-revision repository.

#### Conversation

`ConversationMessage` is append-only and includes:

- role and bounded content;
- context kind and exact referenced revisions;
- classification;
- instruction snapshot reference;
- optional provider/run metadata;
- creation time.

Generated text is not promoted into Meeting facts or an Artifact without the
applicable evidence, validation, and human-confirmation service.

#### Instructions

The compiler must accept structured layers and emit an immutable snapshot with:

- canonical configuration;
- profile IDs and versions;
- protected-rule module versions;
- deterministic hash;
- optional compiled text only if the approved privacy design permits it.

Tests must prove that lower layers cannot change provider/network policy,
classification, tool authority, citation requirements, human confirmation, or
protected diplomatic/factual rules.

#### Transcript source

`TranscriptSourceSnapshot` must represent optional timing truthfully. It must
not satisfy `TranscriptCoverageManifest` unless an explicit adapter can prove
canonical-audio alignment and complete frame coverage.

`TranscriptResolutionDecision` includes:

- selected primary source, if any;
- authoritative reference, if distinct;
- `shouldRunLocalASR`;
- a machine-readable and displayable reason;
- considered alternatives;
- the policy/input snapshot used for the decision.

### 5.3 Acceptance criteria

- All new contracts compile in Swift 6 strict concurrency mode.
- Existing public contracts have no signature or semantic change.
- Existing semantic payload bytes and hashes are untouched.
- Adapter tests point to exact source/evidence/artifact revisions.
- A text transcript with no timestamps cannot be adapted into an audio
  coverage manifest.
- An untrusted provider result cannot decide to skip ASR.
- Instruction precedence and non-overridable policy are deterministic.
- The complete pre-existing test suite remains green.

### 5.4 Rollback

Revert the new files and their tests. There is no database, UI, file-layout, or
user-data state to undo.

## 6. Change group 2: default-off capability composition

### 6.1 Intended source changes

| Proposed path | Proposed responsibility |
| --- | --- |
| `Sources/MeetingBuddyApplication/AppCapabilities.swift` | Immutable typed values such as `research`, `transcriptSourceResolution`, `conversationPersistence`, and `sharedObjectStore`; all defaults false |
| `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift` | Inject the capability snapshot into `WorkspaceRuntime` without registering new production behavior |
| `Sources/MeetingBuddyApp/MeetingBuddyApp.swift` | Construct the default capability snapshot explicitly |
| `Tests/MeetingBuddyFeaturesTests/AppCapabilitiesTests.swift` | Default values, no remote/automation mutation, canonical description |
| `Tests/MeetingBuddyFeaturesTests/MeetingBuddyRootViewStructureTests.swift` | Flag-off navigation and visible-copy regression |

No new test target is proposed. App composition remains covered by the full
suite plus the manual flag-off smoke below.

### 6.2 Behavior

With the default snapshot:

- no Research feature service is constructed;
- no Research executor is registered;
- no database migration is requested by a capability;
- no visible navigation, label, settings, or keyboard route appears;
- no network, provider, or file work occurs;
- every accepted Meeting flow uses the same production types and routes.

The capability set is an application composition input. It is not read from an
imported file, transcript, model response, MCP command, or remote service.
Persisted user-controlled flags are deferred until a visible product behavior
requires them.

### 6.3 Acceptance criteria

- A default construction produces all-false integration capabilities.
- `MediaReviewSection` cases and default `MeetingBuddyRootView` navigation are
  unchanged.
- Existing Meeting import → canonical audio → transcript → analysis → briefing
  → history/storage automated regressions pass.
- The CLI and MCP command catalogs are unchanged.
- No outbound connection or new entitlement is introduced.
- `git diff` contains no dependency, schema, or file-layout change.

### 6.4 Manual smoke

On a disposable local workspace:

1. launch the app and open/create a workspace;
2. confirm the existing sidebar and keyboard navigation;
3. import the synthetic fixture;
4. complete or inspect transcript, analysis, and briefing review;
5. open history and storage;
6. quit/reopen and confirm the workspace bookmark and accepted state;
7. confirm no Research text or control is visible.

Live installed-model, microphone, and screen-capture checks remain separately
opt-in and must be reported as unverified if not run.

### 6.5 Rollback

Revert the capability injection. Because defaults never create durable state,
rollback is source-only.

## 7. Future persistence gate (outside Phase 1)

ADR-0018 fixes Phase 1 at schema v10. No Phase 1 group may add a repository,
table, migration, backfill, or durable Research record.

If a later visible Research workflow proves a durable requirement, the
maintainer must authorize a separate architecture and implementation task.
That future gate must identify:

1. the exact records that require persistence and why contract-only state is
   insufficient;
2. retention, deletion, export, classification, and recovery behavior;
3. exact links to existing Meeting, source, artifact, and evidence revisions;
4. an ordered backward-compatible migration and supported-prior-state tests;
5. a verified pre-migration backup and tested old-binary rollback plan;
6. proof that no existing Meeting row, canonical payload, managed file, or
   user workspace is fabricated, rewritten, moved, or deduplicated.

No table names or migration version are accepted by this proposal.

## 8. Validation commands

Use an isolated scratch path and keep live installed-model flags explicit:

```sh
swift package dump-package >/dev/null
swift build --scratch-path <phase1-scratch> -Xswiftc -warnings-as-errors

MEETINGBUDDY_RUN_LIVE_APPLE_MODELS=0 \
MEETINGBUDDY_RUN_LIVE_APPLE_ANALYSIS=0 \
MEETINGBUDDY_RUN_LIVE_APPLE_BRIEFING=0 \
swift test --scratch-path <phase1-scratch> -Xswiftc -warnings-as-errors
```

Additional repository checks:

```sh
git diff --check
git status --short --branch
rg -n 'Research|Conversation|Instruction|TranscriptSource' Sources Tests
```

The final validation report must separate:

- synthetic-safe automated evidence;
- opt-in live installed-model evidence;
- manual GUI/accessibility evidence;
- migration/restore evidence;
- unverified external connector/provider behavior.

## 9. Phase 1 acceptance checklist

The human reviewer should not accept Phase 1 unless every in-scope item is
true:

- [ ] No existing public type was renamed or reinterpreted.
- [ ] Physical `WorkspaceID` and logical Research identity are separate.
- [ ] `TranscriptionProvider` is unchanged.
- [ ] Text-only transcripts do not fabricate audio timing or coverage.
- [ ] Existing source, evidence, and artifact revisions remain authoritative.
- [ ] Conversation output cannot silently become confirmed Meeting fact.
- [ ] User instructions cannot override protected policy.
- [ ] All integration capabilities default to false.
- [ ] Default UI and Meeting flows are unchanged.
- [ ] No connector, credential, Codex route, or new network destination exists.
- [ ] No dependency, sidecar, second frontend, task runner, or database exists.
- [ ] Schema remains v10; no persistence, migration, backfill, or user-data
      write is introduced.
- [ ] Warning-clean build and the complete test suite pass.
- [ ] Manual/live gaps are reported honestly.

## 10. Recommended review order

1. Review the accepted governance boundary in
   `docs/adr/ADR-0018-blue-minutes-meeting-research-integration.md`.
2. If desired, explicitly authorize change group 1 only.
3. Require validation and a stop for review at the group 1 boundary.
4. Consider change group 2 only under a later, separate authorization.

No Phase 1 work has been performed or authorized by the Phase 0 audit or the
governance-acceptance task.
