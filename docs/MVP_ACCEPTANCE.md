# MVP Acceptance Baseline

Status: Task 005A accepted; end-to-end MVP remains untested
Owner: Codex
Last updated: 2026-07-18
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
  -> create evidence-linked intervention and delegation-position objects
  -> create an issue-position matrix
  -> generate and validate two or three independent briefing sections
  -> assemble and export deterministic Markdown
```

This boundary excludes UN Web TV, live capture, MCP, local HTTP control,
historical comparison, broad autonomous political analysis, and release claims.

## Prerequisite task gates

Tasks 003A, 003B, 004A, 004B, 005A, 005B, 006A, and 006B must each be accepted
in order. A later task cannot compensate for a failed prerequisite.

## Required end-to-end assertions

- Every substantive briefing conclusion navigates to exact evidence.
- No P0 invented national or organizational position exists in applicable
  Golden fixtures.
- Reservations, conditions, and uncertainty survive aggregation.
- Interpretation is never labeled as original wording.
- Translation never overwrites source text.
- Speaker or translation correction creates a new revision and marks exact
  downstream dependencies stale.
- Locked or manually edited briefing sections are not overwritten.
- Invalid structured provider output is rejected.
- Cancellation, retry, and crash recovery leave consistent persistent state.
- Temporary files are bounded, job-owned, and safely cleaned.
- User source files are never modified.
- Restricted data is not sent externally.
- Logs contain no credentials or complete sensitive meeting content by default.
- Long media processing does not require loading the full file into memory.
- Markdown export is deterministic and assembled from current validated section
  revisions.

## Quality-gate matrix

| Gate | MVP evidence required |
| --- | --- |
| Storage discipline | Owned locations, budgets, cleanup, migration, and recovery tests |
| Evidence integrity | Exact revision/location references for all substantive claims |
| Prompt/schema consistency | Versioned bounded inputs/outputs and rejected invalid output |
| Briefing quality | Golden rubric for restrained, actor-explicit Chinese briefing text |
| Automation safety | Not applicable to the first slice unless an automation adapter is added later |
| Provider integrity | Approved route, visible policy, no credential or subscription misuse |
| Semantic-object integrity | Providers consume semantic packages rather than tables or arbitrary paths |
| Privacy/routing integrity | Classification inheritance and deny-by-default route tests |
| Revision integrity | Immutable revisions, active pointers, dependency edges, and stale propagation tests |

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

The 145 tests in 25 suites include exactly five clearly labeled Golden
fixtures, 24 disposable persistence/recovery tests, 18 task/runtime tests, 13
media tests, and four feature-model tests. They pass with the standard selected-
Xcode command. No test opened or migrated a real user workspace.

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

The remaining end-to-end assertions stay `NOT TESTED` or `NOT APPLICABLE`
until their owning tasks are implemented. Provider routing, transcription,
translation, briefing analysis, full review, and user-facing end-to-end MVP
behavior are not claimed. Recovery restore UX and JSONL-only reconstruction
are also not claimed.

Xcode 26.6 can build, ad-hoc sign, launch, and process-verify the SwiftPM app
bundle. The native run observed App Sandbox initialization, presented the
workspace Open panel, persisted one app-scoped workspace bookmark, and restored
it after relaunch using only a synthetic workspace. The purpose-routed importer
regression test covers the workspace and five-format media routes. Developer ID
provisioning, Gatekeeper/notarization, and clean-machine validation remain
Task 011 release gates. Task 005A is accepted. Task 005B is not started and its
production transcription/translation route decision remains unresolved.
