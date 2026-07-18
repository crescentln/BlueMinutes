# Current Architecture

Status: Task 005A accepted after full-Xcode validation
Owner: Codex
Last updated: 2026-07-18
Purpose: Record the observed repository state only; target design belongs in
`TARGET_ARCHITECTURE.md`.

## Executive state

MeetingBuddy is a confirmed greenfield project. The user accepted the Task 001
audit on 2026-07-17 and confirmed this directory as the canonical root.

The repository contains the accepted Task 002 governance baseline, accepted
Task 003A/003B domain work, accepted Task 004A persistence foundation, and
accepted Task 004B operational runtime, and accepted Task 005A native local-
media implementation. Task 005A adds the first native SwiftUI executable,
task-managed local media acquisition, AVFoundation canonical audio/chunking,
and minimal source/status review. No
real user meeting data, provider, network route, transcription, translation,
briefing, capture, or automation implementation is present.

## Repository state

- Git repository: local `main`; predecessor
  `c6f91058fef868ff033eb28e71d4d3c885afa7dd` is the accepted Task 004B
  rollback anchor for the authorized Task 005A acceptance commit. No push was
  authorized.
- Product source files: `Sources/MeetingBuddyDomain/`,
  `Sources/MeetingBuddyApplication/`, `Sources/MeetingBuddyPersistence/`, and
  `Sources/MeetingBuddyTasks/`, plus Task 005A `Sources/MeetingBuddyMedia/`,
  `Sources/MeetingBuddyFeatures/`, and `Sources/MeetingBuddyApp/`.
- Xcode projects/workspaces: none.
- Swift Package Manager manifest: `Package.swift`, Swift tools 6.1, Swift 6
  language mode, macOS 15 minimum.
- Build products: six libraries (`MeetingBuddyDomain`,
  `MeetingBuddyApplication`, `MeetingBuddyPersistence`, `MeetingBuddyTasks`,
  `MeetingBuddyMedia`, and `MeetingBuddyFeatures`) plus the
  `MeetingBuddyApp` executable; five corresponding test targets are present.
- Dependency: exact GRDB 7.11.1 pin with `Package.resolved`; GRDB is isolated to
  persistence implementation and persistence tests.
- Tests: 145 Swift Testing cases in 25 suites, including exactly five Task 003B
  Golden fixtures, 24 disposable persistence/recovery cases, 18 task/runtime
  cases, 13 media cases, and four feature-model cases; no CI, formatter, or
  linter configuration yet.
- No database, recovery snapshot, managed media, credential, or runtime
  workspace is committed. Integration tests create and remove only unique
  system-temporary workspaces.

The accepted evidence and original commands are preserved in
`audits/TASK-001_REPOSITORY_AUDIT.md`.

## Implemented layers

| Layer | Current implementation |
| --- | --- |
| Application/UI | Application-owned storage/task/media/review ports; a native SwiftUI `MeetingBuddyApp` composition root with workspace, meeting/source policy, track/provenance selection, source verification, progress, cancellation, and retry review |
| Domain | Task 003A foundation plus Task 003B input contracts, explicit active selection, dependency edges, pure graph validation, and deterministic stale planning |
| Persistence and workspace | Task 004A Workspace/Storage services plus Task 004B schema v2 job repository, durable managed-asset operation journal, bounded task directories, and rotated logs |
| Task execution and recovery | One `LocalTaskManager` actor with explicit job state/progress/checkpoint/cancellation/retry contracts, bounded concurrency, startup health, interrupted-job recovery, orphan cleanup, stale-input publication checks, and Task 005A intake/canonical executors |
| Media | AVFoundation inspection for MOV/MP4/M4A/MP3/WAV, task-managed copy/hash intake, canonical 16 kHz mono signed-int16 CAF, exact range issues, deterministic overlapped chunks, checkpointed retry, and persistent canonical publication |
| Transcription, translation, and AI | None |
| Automation/CLI/MCP | None |
| Historical retrieval | None |

Executable package behavior now covers pure domain creation/validation,
workspace and bookmark selection, managed local-file intake, SQLite
persistence/migration, recovery and Trash integration, task execution, native
media conversion, and minimal SwiftUI review. Xcode 26.6 can stage, ad-hoc sign,
and launch `dist/MeetingBuddy.app` under App Sandbox; no network I/O, provider
call, capture, transcription, translation, or briefing generation exists.

## Governance now present

Task 002 established:

- repository-local operating instructions;
- current and target architecture boundaries;
- domain, storage, security, acceptance, and implementation-plan documents;
- accepted and proposed ADRs;
- a concise execution-state ledger;
- a persisted copy of the accepted Task 001 audit;
- a local Git repository for working-tree visibility and future rollback.

These artifacts do not themselves implement product behavior.

## Task 003A domain foundation

The accepted Task 003A implementation adds:

- phantom-typed UUID identifiers for logical objects, revisions, meetings,
  source assets, evidence, and managed storage objects;
- an immutable generic revision envelope with exact input, source-asset, and
  evidence revision references;
- v1 schema, lifecycle, validation, data-classification, origin, acquisition,
  retention, speech-source, and translation-status contracts;
- `SourceAssetV1` with a source-byte digest and opaque managed-storage
  reference rather than a filesystem path;
- `EvidenceRefV1` with seven typed location variants and an exact source
  revision, required excerpt/language/translation metadata, and source-kind
  compatibility checks;
- provider-neutral generation metadata with prompt/generator versions, output
  schema, template version, generation time, and privacy route, without
  credentials or SDK types;
- native SHA-256 calculation and verification over documented SourceAsset and
  EvidenceRef semantic projections;
- deterministic fail-closed decoding/validation and a constrained canonical
  JSON profile.

## Task 003B input and invalidation contracts

The accepted Task 003B implementation adds:

- `MeetingProfileV1`, `TranscriptSegmentV1`, `TranslationSegmentV1`,
  `ActorV1`, `SpeakingCapacityV1`, and `SpeakerAssignmentV1`;
- distinct original-audio, interpretation, translated-audio, machine/human
  translation, and user-edit provenance paths;
- explicit review and user-confirmation state, including fail-closed uncertain
  speaker handling;
- exact dependency edges, explicit active-published revision selection,
  invalidation reasons, and deterministic transitive stale plans;
- pure cross-object reference, provenance, meeting, range, text-hash, actor,
  and classification checks;
- exactly five project-authored synthetic Golden fixtures with explicit rights
  and provenance manifests and no unsupported diplomatic inference.

The domain values remain storage-neutral. Task 004A now persists their exact
canonical revisions, active pointers, dependency edges, and stale state behind
application repository ports.

## Task 004A persistence foundation

The accepted Task 004A implementation adds:

- validated workspace-relative paths and a manifest-owned private workspace;
- streamed file intake to UUID-named managed paths with SHA-256, exact size,
  classification, retention, collision refusal, and Trash restore;
- a GRDB-backed SQLite schema with explicit version/checksum metadata, foreign
  keys, WAL mode, immutable revision/dependency/event triggers, and fail-closed
  preflight for unknown or drifted schemas;
- typed repositories for all eight Task 003A/003B objects, byte-identical
  idempotent insertion, canonical payload digests, normalized metadata checks,
  exact dependency derivation, and managed-source binding checks;
- one active published pointer per logical object, optimistic compare-and-set,
  recursive current-input publication checks, and atomic persistence of pointer
  events, deterministic stale marks, and current stale state;
- online pre-migration backups normalized for standalone read-only use;
- recovery manifests covering a consistent SQLite backup, validated
  export-only semantic JSONL, asset inventory, and migration version, each
  checked for internal consistency by SHA-256 and exact size;
- synchronous compensation for managed-file import/Trash metadata failures and
  disposable failure-injection tests.

## Task 004B task runtime and crash recovery

The accepted Task 004B implementation adds:

- one application-owned job contract with stable IDs, idempotency digests,
  explicit queued/running/pause/cancellation/terminal states, monotonic
  progress, durable checkpoints, retry metadata, provider-usage metadata,
  exact semantic input/output revision references, and job-owned disk leases;
- one `LocalTaskManager` actor with a 1–16 bounded concurrency limit,
  dependency scheduling, cooperative checkpoint pause/resume and cancellation,
  explicit whole-attempt or durable-node retry, synthetic executor injection,
  deterministic startup conversion of unfinished work to `interrupted`, and a
  fail-closed health result when disk capacity is unknown or a bounded orphan
  or managed-asset recovery scan is truncated;
- SQLite schema version 2 with canonical digest-checked job snapshots,
  optimistic replacement, immutable state events, dependency/input/output
  indexes, uniqueness-backed idempotency, health checks, and an atomic
  stale-input recheck in the success transaction;
- `.tasks/<job-id>` allocation with per-job byte budgets, private permissions,
  confined writes, bounded entry scans, safe terminal cleanup, and
  age/count/symlink-bounded orphan cleanup;
- structured JSONL plus OSLog-compatible logging with private-value removal,
  credential-pattern redaction, value/file/count/retention bounds, rotation,
  and private permissions;
- a durable managed-asset intent/event journal and deterministic startup
  reconciliation for interrupted import, Trash, and restore operations,
  including exact owned-staging cleanup and fail-closed repair reporting;
- disposable state-machine, concurrency, pause/resume, cancellation, retry,
  restart, migration, redaction/rotation, confinement, orphan, and
  filesystem/SQLite interruption tests.

## Task 005A local media and native review

The Task 005A implementation adds:

- accepted ADR-0002 Option A entitlements: App Sandbox, app-scoped bookmarks,
  and user-selected read/write file authority only;
- one persistent app-scoped bookmark for the validated user-selected workspace,
  plus transient source-file scope that ends after the task-managed verified
  copy; no source path or bookmark enters durable job state;
- a SwiftUI `NavigationSplitView` for workspace choice, meeting title,
  classification/language, media selection, explicit multi-track choice,
  speech provenance, managed hash/status, progress, cancellation, and retry;
- real AVFoundation inspection/import coverage for MOV, MP4, M4A, MP3, and WAV,
  with one explicit audio track and no external executable;
- persistent untouched original and generated canonical `SourceAsset.v1`
  revisions, with canonical signed-int16 little-endian interleaved mono PCM in
  CAF at 16 kHz;
- zero-based half-open frame timelines, exact missing/corrupt/decode-failed
  issues, a 50 ms duration tolerance, 30-second cores, and one second of
  context on each side;
- Task-Manager-owned acquisition, streamed output leases, digest/size
  revalidation, compact three-hour checkpoints, chunk-level retry reuse,
  cooperative cancellation, and bounded cleanup;
- a local build/run script and Codex Run action that stage an ad-hoc signed app
  bundle for development verification without claiming release signing.

## Known limitations

- There is no Xcode project, provider, network, transcription, translation,
  briefing, capture, or automation implementation. The native UI is the
  deliberately minimal Task 005A review surface, not final UI polish.
- Xcode 26.6 build 17F113 is installed and selected. Standard debug/release
  builds and `swift test` pass, and a native run verifies sandbox initialization,
  the workspace Open panel, synthetic-workspace bookmark persistence, and
  scoped-bookmark restoration after relaunch.
- The staged bundle is ad-hoc signed and therefore is not release evidence.
  No valid Developer ID identity is installed; provisioning, Gatekeeper,
  notarization, and clean-machine validation remain Task 011 work.
- Commit predecessor `c6f9105` is the Task 004B rollback anchor for the accepted
  Task 005A change.
- The semantic JSONL recovery artifact is deliberately export-only; exact
  operational recovery relies on the verified SQLite online backup. A user-
  facing restore workflow is not implemented.
- Managed-asset process-crash windows now have a durable journal and bounded
  startup reconciliation. A user-facing repair/restore UI and automatic Trash
  purge remain unimplemented.
- ADR-0002 and the canonical media parameters are resolved. Release signing,
  notarization, automatic updates, capture entitlements, and any later
  distribution changes remain separately task-gated.
- End-to-end product quality gates remain untested; current evidence extends
  through Task 005A local media code but does not cover providers or the first
  full briefing vertical slice.

## Next permitted transition

Tasks 004B and 005A are accepted, and the Task 005A full-Xcode native gate
passes. Task 005B is eligible but not authorized; resolve its production
transcription/translation route P1 decision before implementation.
