# Current Architecture

Status: Task 004B accepted
Owner: Codex
Last updated: 2026-07-18
Purpose: Record the observed repository state only; target design belongs in
`TARGET_ARCHITECTURE.md`.

## Executive state

MeetingBuddy is a confirmed greenfield project. The user accepted the Task 001
audit on 2026-07-17 and confirmed this directory as the canonical root.

The repository contains the accepted Task 002 governance baseline, accepted
Task 003A/003B domain work, accepted Task 004A persistence foundation, and
accepted Task 004B operational runtime. Task 004B adds the unified operational
job contract, concrete Task Manager, bounded task storage/logging, and crash
reconciliation. There is still no application executable, UI, production job
executor, or user meeting data.

## Repository state

- Git repository: local `main`; the Task 004B acceptance commit is the current
  checkout, and its predecessor `2ccf57fe8d42c1a6d21bb1cfe3765d1b41687500`
  is the accepted Task 004A rollback anchor.
- Product source files: `Sources/MeetingBuddyDomain/`,
  `Sources/MeetingBuddyApplication/`, `Sources/MeetingBuddyPersistence/`, and
  `Sources/MeetingBuddyTasks/`.
- Xcode projects/workspaces: none.
- Swift Package Manager manifest: `Package.swift`, Swift tools 6.1, Swift 6
  language mode, macOS 15 minimum.
- Build targets: `MeetingBuddyDomain`, `MeetingBuddyApplication`,
  `MeetingBuddyPersistence`, and `MeetingBuddyTasks` libraries plus domain,
  persistence, and task test targets; there is no application entry point.
- Dependency: exact GRDB 7.11.1 pin with `Package.resolved`; GRDB is isolated to
  persistence implementation and persistence tests.
- Tests: 125 synthetic Swift Testing cases in 21 suites, including exactly five
  Task 003B Golden fixtures, 24 disposable persistence/recovery integration
  cases, and 15 Task 004B job/runtime cases; no CI, formatter, or linter
  configuration yet.
- No database, recovery snapshot, managed media, credential, or runtime
  workspace is committed. Integration tests create and remove only unique
  system-temporary workspaces.

The accepted evidence and original commands are preserved in
`audits/TASK-001_REPOSITORY_AUDIT.md`.

## Implemented layers

| Layer | Current implementation |
| --- | --- |
| Application/UI | Storage-neutral persistence/workspace/recovery ports plus Task 004B job/runtime ports; no UI or executable |
| Domain | Task 003A foundation plus Task 003B input contracts, explicit active selection, dependency edges, pure graph validation, and deterministic stale planning |
| Persistence and workspace | Task 004A Workspace/Storage services plus Task 004B schema v2 job repository, durable managed-asset operation journal, bounded task directories, and rotated logs |
| Task execution and recovery | One `LocalTaskManager` actor with explicit job state/progress/checkpoint/cancellation/retry contracts, bounded concurrency, startup health, interrupted-job recovery, orphan cleanup, and stale-input publication checks |
| Media | None |
| Transcription, translation, and AI | None |
| Automation/CLI/MCP | None |
| Historical retrieval | None |

Executable package behavior now covers pure domain creation/validation plus
disposable local workspace, file-storage, SQLite persistence/migration,
recovery snapshots, Trash integration, and synthetic long-running job
execution. There is no application executable, network I/O, provider call,
media conversion, or UI.

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

## Known limitations

- There is no native app target, Xcode project, UI, production executor, media
  conversion, provider, network, briefing, or automation implementation. The
  Task Manager is a library exercised only through synthetic executors.
- The active developer directory contains Command Line Tools rather than the
  full Xcode application. SwiftPM builds pass, but full Xcode integration and
  macOS 15 runtime compatibility have not been verified.
- This Command Line Tools installation does not automatically expose the
  bundled Swift Testing framework and has an incorrect runtime search path.
  Tests passed with explicit paths to the CLT-owned framework and interop
  library; a standard `swift test` invocation still requires a complete or
  repaired Apple developer-tool installation.
- Git history provides accepted Task 004A commit `2ccf57f` as the rollback
  anchor immediately before the Task 004B acceptance commit.
- The semantic JSONL recovery artifact is deliberately export-only; exact
  operational recovery relies on the verified SQLite online backup. A user-
  facing restore workflow is not implemented.
- Managed-asset process-crash windows now have a durable journal and bounded
  startup reconciliation. A user-facing repair/restore UI and automatic Trash
  purge remain unimplemented.
- Final distribution/sandbox and security-scoped bookmark details remain open
  for Task 005A.
- End-to-end product quality gates remain untested; current evidence covers
  Task 003A/003B domain, Task 004A persistence, and Task 004B operational
  runtime/recovery boundaries only.

## Next permitted transition

Task 004B is accepted. Task 005A is next eligible but remains unauthorized;
its distribution/sandbox and canonical media-parameter checkpoints must be
resolved before implementation.
