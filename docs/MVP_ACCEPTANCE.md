# MVP Acceptance Baseline

Status: Tasks 001 through 011 accepted; selected release is INTERNAL ALPHA
Owner: Codex
Last updated: 2026-07-22
Purpose: Define the acceptance boundary for the first local recorded-meeting
vertical slice and prevent documentation or scaffolding from being mistaken for
product completion.

## MVP boundary

The first usable product path is:

```text
import local audio/video
  -> preserve source provenance
  -> canonicalize audio
  -> create deterministic recoverable chunks
  -> transcribe through one approved route
  -> translate through one approved route
  -> review transcript and speaker assignments
  -> create evidence-linked Issue, Position, Commitment, Decision,
     intervention, and delegation-position objects
  -> create an issue-position matrix
  -> apply a structured meeting template and generate/validate two or three
     independent briefing sections
  -> assemble and export deterministic Markdown
```

This original first-slice boundary excludes UN Web TV, live capture, MCP, local
HTTP control, historical comparison, broad autonomous political analysis, and
release claims. Later accepted tasks added bounded recording and local MCP;
Task 010 now implements historical review as a separately gated add-on without
redefining the original MVP slice.

## Prerequisite task gates

Tasks 003A, 003B, 004A, 004B, 005A, 005B, 006A, and 006B must each be accepted
in order. A later task cannot compensate for a failed prerequisite. Tasks 007
through 011 are also accepted for the selected internal-alpha scope; this does
not satisfy the separate external-distribution gates recorded below.

## Required end-to-end assertions

- Every substantive briefing conclusion navigates to exact evidence.
- No P0 invented national or organizational position exists in applicable
  Golden fixtures.
- Reservations, conditions, and uncertainty survive aggregation.
- Interpretation is never labeled as original wording.
- Translation never overwrites source text.
- Original machine transcript text, human correction lineage, exact source
  audio/time/language, provider/model/version/confidence, speaker assignment,
  and integrity references remain traceable.
- Speaker or translation correction creates a new revision and marks exact
  downstream dependencies stale.
- Locked or manually edited briefing sections are not overwritten.
- Invalid structured provider output is rejected.
- Deterministic transcript coverage proves 100 percent of eligible canonical
  core ranges are accounted for with bounded overlap and explicit no-speech,
  missing, failed, and retried outcomes; unprovable coverage blocks publication.
- Hierarchical extraction and briefing coverage accounts for every eligible
  source segment and links each material conclusion to exact segment IDs or
  other evidence.
- Cancellation, retry, and crash recovery leave consistent persistent state.
- Temporary files are bounded, job-owned, and safely cleaned.
- User source files are never modified.
- Restricted data is not sent externally.
- All meeting data is local by default. Any external route records data
  categories, destination, provider retention, policy authority, and visible
  user authorization, and the workflow retains a local/offline alternative.
- Offline/no-outbound mode cannot be weakened by provider fallback.
- Provider/model choice is constrained by sensitivity, organization policy,
  deployment environment, destination/retention, and user authorization.
- Logs contain no credentials or complete sensitive meeting content by default.
- Secrets use Keychain rather than plaintext configuration.
- Telemetry is disabled by default and excludes meeting/transcript content,
  credentials, titles, filenames, sensitive paths, and identifiable meeting
  metadata; it can be fully disabled and respects no-outbound mode.
- Long media processing does not require loading the full file into memory.
- Markdown export is deterministic and assembled from current validated section
  revisions.

## Task 010 historical-review add-on assertions

- Repeating the same query against the same index generation returns the same
  ordered exact Position revision IDs.
- Search uses confirmed published Positions and rechecks the exact current
  SensitivityLabel/AccessPolicy graph before returning content or counts.
- Every comparison exposes both exact Position/Evidence/security revision
  trails, dates, media-relative effective times, and confidence.
- Missing evidence, unordered effective dates, actor/topic mismatch, wording
  changes alone, silence, and group membership never assert policy change.
- A confirmed change exists only as a user-authored superseding revision of an
  exact possible-difference candidate.
- All seven preference types are visible, editable, disableable, removable,
  globally disableable, and resettable; none can alter protected rules.
- History indexing and comparison remain local/no-outbound and add no mail,
  public-source fetch, provider, credential, subprocess, or listener authority.
- A cancelled rebuild exposes no partial generation; schema v9 rollback retains
  exact prior canonical bytes; 10,000 published Positions remain inside the
  recorded rebuild/query performance bounds.

## Accepted Task 011 release boundary

- The current new-scratch suite passes 242 tests in 42 suites, and the three
  opt-in installed-model cases pass separately on synthetic-only inputs.
- Fresh schema v10, every supported v1-v9 migration, pre-migration rollback
  backup, unknown-future rejection, injected failure, and recovery gates pass.
- The selected arm64 app passes closed-layout, privacy/license, exact-source,
  ad-hoc Hardened Runtime, entitlement, launch, idle-network, and synthetic cold
  backup verification.
- The accepted classification is INTERNAL ALPHA, not RELEASE CANDIDATE. The
  local ignored archive is not authorized for publication or distribution.
- Four medium evidence-integrity findings remain open. Three low resource
  findings are mitigated in accepted source but require a follow-up scan.
- Developer ID/Team ID, notarization/stapling, affirmative Gatekeeper
  distribution approval, clean-machine install/update/rollback, approved icon/
  localization, manual accessibility, and intended-OS live TCC/capture evidence
  remain incomplete.

The bullets above preserve the historical Task 011 acceptance boundary. The
separately authorized post-MVP remediation in ADR-0017 implements conservative
application-owned `noSpeech`/`nonSubstantive` confirmation, exact-ledger human
confirmation before consequential analysis use, and confirmation of every
briefing section/final before export. It does not change the accepted MVP task
sequence or satisfy the remaining binary-distribution gates.

## Quality-gate matrix

| Gate | MVP evidence required |
| --- | --- |
| Storage discipline | Owned locations, budgets, cleanup, migration, and recovery tests |
| Evidence integrity | Exact revision/location references for all substantive claims |
| Prompt/schema consistency | Versioned bounded inputs/outputs and rejected invalid output |
| Briefing quality | Golden rubric for restrained, actor-explicit Chinese briefing text |
| Automation safety | Accepted closed command/CLI boundary and fixed local stdio MCP read-tool allowlist; no HTTP, remote control, or sensitive/destructive MCP command |
| Provider integrity | Approved route, visible policy, no credential or subscription misuse |
| Semantic-object integrity | Providers consume semantic packages rather than tables or arbitrary paths |
| Privacy/routing integrity | Classification inheritance and deny-by-default route tests |
| Revision integrity | Immutable revisions, active pointers, dependency edges, and stale propagation tests |
| Transcript completeness | Exact coverage manifest, bounded overlap, forward progress, injected omission failure, and segment traceability |
| Local-first/model policy | Destination/retention/authorization evidence, local/offline path, and no-outbound/fallback tests |
| Secret and telemetry privacy | Keychain boundary plus default-off/full-disable, excluded-content/metadata, and no-network evidence |
| Schema compatibility | Ordered migrations, online rollback anchors, supported-prior-state, failure, and recovery tests for every new object |

## Verification classes

Each implementation task must report:

- deterministic build command;
- unit tests;
- integration tests in disposable workspaces;
- applicable Golden fixtures;
- failure, cancellation, and recovery tests;
- manual native macOS verification where UI or permission behavior matters;
- dependency, license, storage, privacy, and documentation impact.

Exact commands are introduced with the first Swift package/project and then
kept current in the execution ledger and implementation plan.

## Current status

Tasks 003A and 003B verify the foundational and input-side semantic contracts:
immutable values, exact revision references, fail-closed
classification, deterministic validation, native semantic-hash verification,
stable v1 serialization, provenance separation, explicit active-published
selection, dependency edges, and deterministic transitive stale planning.

Task 004A adds repository-backed exact canonical revisions, one active pointer
per logical object, optimistic pointer changes, persisted exact dependency
edges/stale events/current state, managed source-file hash and size bindings,
private Workspace/Trash services, ordered SQLite migration with online rollback
anchors, and integrity-checked recovery artifacts. The recovery SQLite backup is
authoritative; semantic JSONL is explicitly export-only.

Task 004B adds the single operational job state machine and Task Manager,
bounded concurrency, monotonic progress and durable checkpoint pause/resume,
cooperative cancellation, whole-attempt or durable-node retry, exact
dependency/idempotency indexes,
job-owned temporary storage, redacted/rotated logs, startup database/disk/orphan
health, interrupted-job recovery, and durable filesystem/SQLite operation
reconciliation. The success transaction atomically rejects semantic inputs that
became stale after execution started. Unknown disk capacity and truncated
orphan or managed-asset recovery scans fail the startup health result closed.

Task 005A adds the native local-media portion of the path: sandbox-scoped
workspace/source selection, task-managed streamed copy and SHA-256 binding,
persistent untouched original and generated canonical source revisions,
AVFoundation inspection of MOV/MP4/M4A/MP3/WAV, canonical 16 kHz mono signed-
int16 CAF, exact half-open timeline issues, deterministic recoverable chunks,
checkpoint reuse, cancellation cleanup, and minimal source/status review. The
source URL/bookmark never enters durable task state, and no source fixture is
modified.

Task 005B adds the local input-understanding portion: an application-owned
model-policy router, installed Apple Speech/Translation production adapters on
macOS 26+, a validated manual local fallback, Keychain Secret Store, one
checkpointed transcript task, immutable schema v3 coverage manifests, exact
100 percent core accounting, separate transcript/translation revisions,
correction lineage/stale propagation, and uncertain-speaker confirmation. No
outbound adapter or meeting-data transfer is authorized.

Task 006A adds the evidence-linked analysis portion: eight independent
intelligence contracts, typed claim and qualification vocabularies, a bounded
Apple on-device Foundation Models route, protected prompt modules, deterministic
semantic and graph validation, immutable schema-v4 route/coverage history,
exact 100 percent reviewed-segment accounting, local card inspection, and
immutable position correction with dependent stale propagation. Provider
output cannot publish a completed commitment, confirmed decision, historical
policy change, or unsupported position. No external analysis route or real
meeting content is authorized or used.

Task 006B adds the first complete structured briefing portion: one immutable
multilateral template, a sparse exact-Position matrix, three independently
generated/validated sections, immutable manual edits and locks, exact one-
section regeneration, a zero-source-text-overlap segment-to-conclusion ledger,
ten blocking deterministic validation categories, evidence/time navigation,
schema-v5 persistence/recovery, and explicit deterministic local Markdown
export. Stale upstream revisions and invalid/locked sections fail closed; no
external or independent reviewing provider is authorized.

Task 007 adds accepted local-first/security hardening: exact sensitivity and
access-policy revisions, no-outbound and model-policy enforcement,
default-disabled content-free telemetry, private storage accounting,
recoverable Trash and retention-gated unlink receipts, schema v6, long-meeting
coverage stress, and automated accessibility/keyboard structure. ADR-0012
intentionally rejects application-level workspace encryption for this local
single-user boundary.

Tasks 008A and 008B add the accepted bounded capture path: metadata-only exact-
host UN Web TV access, audio-only microphone or user-selected application
capture, incremental managed segments, durable checkpoints, explicit
incomplete/recovery states, schema v7, and Task-Manager integration. Automatic
UN Web TV media/player acquisition, browser recording, redistribution, and
hidden capture remain rejected or out of scope.

Tasks 009A and 009B add the accepted closed Automation Command Layer, strict
local CLI, schema-v8 audit/settings history, and a local stdio MCP adapter with
seven read-authority tools and schema-v9 attribution. They add no HTTP listener,
remote access, arbitrary path/SQL command, sensitive/destructive MCP operation,
credential route, or additional inference provider.

The 175 tests in 31 suites include exactly five original clearly labeled Golden
fixtures, a 5/5 Task 006A diplomatic-rule matrix, Task 006B contract and local
vertical-slice cases, and disposable persistence/recovery, task/runtime, media,
provider/pipeline, and feature-model coverage. They pass with the standard
selected-Xcode command; three opt-in live Apple cases are explicitly skipped
in the ordinary suite. Separate Task 006A and Task 006B installed Foundation
Models cases pass only project-authored synthetic inputs. No test opened or
migrated a real user workspace or used real meeting content.

At the contract and persistence levels, the evidence confirms that translation does not replace
source text, interpretation cannot claim original wording, uncertain speakers
remain unconfirmed, edits create new immutable revisions, and active upstream
replacement yields stable causal stale marks without mutating history. Injected
failures prove that a pointer change and its stale-state writes roll back
together, while close/reopen tests prove retained state.

Task 004B evidence passes the cancellation/retry/crash-consistency,
temporary-file ownership, and log-default assertions at the infrastructure
level. Task 005A supplies the first production executors and proves task-owned
local acquisition/canonical processing, partial-copy cancellation, verified
chunk retry reuse, exact-range checkpoints, and terminal cleanup. A
completion/cancellation race is explicit: an executor that has returned its
committed publication succeeds; a cancellation observed before publication
rolls back or publishes no canonical output.

Task 005B passes the provider-route, local/offline transcription and
translation, exact coverage, retry/cancellation/restart/stale-input, Keychain,
manual review, correction, translation-separation, and speaker-review gates.
Task 006A passes provider-fake and approved-route checks, 5/5 diplomatic Golden
rules, exact evidence/segment coverage, malformed-output/import rejection,
schema-v4 prior-state and rollback/recovery, immutable correction, and stale-
dependency gates. Typed intervention and delegation-position cards are
inspectable and their underlying Position can be corrected in the native UI.
Task 006B passes template/schema compatibility, multi-Position qualification,
exact coverage/evidence, section independence/regeneration, manual edit/lock,
provider failure, contradiction/historical-claim rejection, repeated upstream
correction/stale blocking, controlled export, schema-v5 prior-state/rollback/
recovery, deterministic hashes, and installed-model synthetic-route gates.
Task 010 passes deterministic filters/cursors, classification/policy denial,
exact evidence/security/effective-time comparison, insufficient/wording-only
Golden cases, user-confirmed superseding lineage, all preference lifecycle
operations, atomic index cancellation/rebuild, schema-v9 migration/backup,
local-only Task Manager routing, accessibility structure, and the documented
10,000-Position scale gate. It adds no provider, network route, or real meeting
content.

Task 011 passes the current 242-test/42-suite new-scratch gate, with a
9.081141167-second 10,000-Position rebuild and 0.319461-second first filtered
page on the reference host. It also passes the supported v1-v9 migration,
synthetic cold-backup, local packaging, closed-layout, privacy/license,
Hardened Runtime, entitlement, and bounded launch/idle-network gates. The first
local briefing slice and selected internal-alpha scope are implemented; full
stale-chain refresh UX, JSONL-only reconstruction, external distribution,
manual accessibility/visual polish, live intended-OS capture proof, and the
four medium evidence-integrity gaps are not claimed complete.

Xcode 26.6 can build, ad-hoc sign, launch, package, and locally verify the SwiftPM
app bundle. The native and packaged-app checks use only synthetic or empty
state, verify the accepted sandbox/bookmark/media routes, and do not read a real
user workspace. Tasks 001 through 011 are accepted and frozen. No valid signing
identity, Team ID, notarization ticket, affirmative Gatekeeper distribution
result, clean-machine proof, tag, push, upload, installation, or distribution
exists; each external release action remains separately authorized.
