# Storage and Recovery Policy

Status: Task 005A media ownership and full-Xcode native gate accepted
Owner: Codex
Last updated: 2026-07-18
Purpose: Define authoritative representations, storage ownership, retention,
cleanup, migration, and recovery boundaries.

## Authority model

| Data | Authoritative representation |
| --- | --- |
| Original media and official documents | Untouched managed workspace files with content hashes and immutable source revisions |
| Canonical audio | Persistent managed CAF bound to an exact generated source revision and original source revision |
| Semantic revisions, active pointers, jobs, dependency edges, and audit records | SQLite through repositories/services |
| Semantic recovery exports | Versioned JSONL or an equivalent tested format |
| Search/vector indexes, waveforms, previews, and parsed caches | Rebuildable derived data |
| Chunks and transient provider material | Job-owned temporary storage |
| Exported briefings | User-visible derived files linked to exact source revisions |

Large media is not stored as a database BLOB. A database is not claimed to be
reconstructable from arbitrary files unless a tested manifest and recovery path
exist.

## Workspace boundary

The production workspace is user-selected or created through the Workspace
Service. The repository itself is not a user-data workspace.

The target workspace contains separate locations for meetings, models,
database, indexes, backups, logs, task directories, temporary files, and
Workspace Trash. Country and topic views are indexes over semantic objects, not
duplicated directory trees.

Persistent filesystem writes must go through the approved owning persistence
service: Workspace Service, Storage Service, migration bootstrap, or Recovery
Service. Persistent metadata writes must go through repositories. Features
and providers do not write directly to arbitrary paths or SQLite.

The concrete local layout is private to `MeetingBuddyPersistence`. Public
application code receives an ID-based `StorageService`; it cannot obtain the
workspace root or submit caller-selected destination/Trash paths.

## Storage ownership contract

Every storage location must define:

```text
owner
creator
deletor
maximum size or budget
whether it is rebuildable
user visibility
cleanup policy
migration policy
classification policy
```

Temporary data is owned by one job and is cleaned on success, failure,
cancellation, or bounded recovery. Normal launch performs lightweight health
checks and must not rescan or reprocess the entire workspace.

### Implemented location ownership through Task 005A

| Location | Owner / creator | Deletor | Size or budget | Rebuildable / visibility | Cleanup, migration, classification |
| --- | --- | --- | --- | --- | --- |
| `workspace_manifest.json` | Workspace Service | No routine deletor | Fixed v1 metadata; 64 KiB read ceiling | Non-rebuildable identity; internal | Never auto-clean; format-version migration; inherits workspace sensitivity |
| `Meetings/<meeting-id>/assets/` | ID-based Storage Service / managed-file coordinator, invoked by Task 005A intake and canonical jobs | Trash transition only; no permanent-delete API | Streamed untouched original plus generated canonical CAF; bounded by available workspace volume, no silent quota eviction | Original is authoritative source bytes; canonical is a persistent hash-bound derivative; user data | Retention from each managed record; UUID names; exact source-revision provenance; classification inherited |
| `Database/meetingbuddy.sqlite` | SQLite persistence and job repositories/migrations | No reset/delete path | 16 MiB maximum per semantic payload; 1 MiB maximum per canonical job snapshot; overall DB bounded by workspace volume | Authoritative semantic and operational metadata; internal | Ordered migrations and online rollback anchor; immutable events; most restrictive contained classification |
| `Backups/Migrations/` | Migration bootstrap | No automatic deletor | One SQLite backup per attempted existing-DB migration; no automatic purge in 004A | Recovery authority; internal | Portable DELETE-journal SQLite; migrates with recovery format; same classification as DB |
| `Backups/Recovery/` | Recovery Service | No automatic deletor | One DB backup plus bounded metadata exports per snapshot; no automatic purge in 004A | Point-in-time recovery set; internal | Snapshot-ID directories, integrity descriptors, format version; same classification as captured DB/assets |
| `.Trash/assets/` | Storage Service / managed-file coordinator | No permanent-delete API in 004A | Same bytes as moved managed assets; bounded by workspace volume | Authoritative retained bytes; user-restorable | Collision-safe restore; future explicit retention/empty policy; retains source classification |
| `.temp/` | Local Storage Service / managed-asset coordinator | Creating operation or bounded startup reconciliation | At most one deterministic streamed-intake staging copy per active journaled import | Disposable; internal | Cooperative cancellation checks each streamed MiB; removed on success/failure/cancellation or exact operation-ID recovery; workspace-confined; inherits incoming classification |
| `.tasks/<job-id>/` | Task Manager through `LocalTaskTemporaryStorage` | Task Manager on success, cancellation, non-retained failure, restart-only retry, or bounded orphan recovery | Explicit per-job lease, 1 byte–1 TiB contract ceiling, volume-capacity precheck, 10,000-entry scan ceiling | Canonical/chunks are disposable operational data; internal | `0700` directory, `0600` files, no traversal/symlinks; writable leases are finalized by hash/size; verified canonical/chunks remain only for eligible checkpoint retry |
| `Logs/Tasks/` | `RotatingTaskLogStore` | Log store retention/rotation | 4 MiB active default, at most 14 archives, approximately 14-day default retention; hard configuration ceilings | Operational diagnostics; internal and redacted | JSONL plus privacy-annotated OSLog; private values removed, public values bounded and credential-redacted; `0700`/`0600` |
| `Models/`, `Indexes/`, `manifests/` | Workspace Service creates directories only; no active Task 005A writer | None through Task 005A | Zero-byte content budget through Task 005A | Reserved; not evidence of implemented features | Ownership/budget must be activated by the owning later task before any content is written |
| App-container preferences | `MeetingBuddyApp` workspace security-scope service | App when selection is replaced, stale, invalid, or unhealthy | One app-scoped workspace bookmark | Non-user-content authority token; internal | Never stores a source bookmark/path; governed by App Sandbox; native enforcement verified with a synthetic workspace and relaunch |

## Retention defaults

- Permanent user data is not automatically deleted without a defined user
  retention rule.
- Original compressed media is kept by default; later UI may offer verified
  transcript-based deletion or per-meeting choice.
- Canonical audio is a persistent generated source revision because it is the
  authoritative timeline input for downstream work; it is not a redundant
  temporary chunk.
- Structured transcript revisions are authoritative; Markdown and plain text
  are derived renderings.
- Workspace Trash retains deleted user-visible objects for a reviewable period,
  initially 30 days, with restore and explicit empty actions.
- General logs are bounded and initially target approximately 14 days; crash
  diagnostics target approximately 30 days, subject to the telemetry ADR.
- Rebuildable data must have a tested rebuild path before automatic cleanup is
  enabled.
- Canonical chunks are rebuildable from the verified canonical CAF. They are
  removed after success/cancellation and retained only while an eligible
  checkpointed retry needs their verified descriptors.

## Migrations and recovery

- SQLite uses explicit ordered migrations and WAL mode with controlled
  checkpoints.
- Migration tests run only in disposable workspaces.
- A migration creates a backup or other tested rollback anchor before changing
  user data.
- A failure cannot leave a partially committed logical object or ambiguous
  active-revision pointer.
- SQLite schema version 2 adds the job runtime and managed-asset operation
  journal. Opening an accepted version-1 database creates and verifies a
  portable rollback anchor before applying version 2.
- Managed-asset import, Trash, and restore persist an intent before bytes move,
  append immutable operation events, and reconcile bounded unfinished entries
  at startup by completing, rolling back, or reporting repair required.
- Recovery artifacts include a workspace manifest, semantic snapshot, asset
  hashes, migration version, integrity descriptors, and an authoritative
  portable SQLite backup.
- User data is never silently reset, discarded, or overwritten to repair a
  schema problem.

## Dependency status

SQLite remains the metadata store. GRDB 7.11.1 is now the approved, exactly
pinned Swift adapter and is isolated inside `MeetingBuddyPersistence`. The
reviewed dependency, license, update, removal, and validation record is
[`dependencies/GRDB.md`](dependencies/GRDB.md). Domain and application targets
do not import GRDB or expose database handles.

## Current implementation status

Accepted Tasks 004A through 005A implement the current foundation in concrete
boundaries:

- `LocalWorkspaceService` creates or opens a manifest-owned, symlink-checked
  private workspace with separate meetings, models, database, indexes,
  backups, logs, task, temporary, Trash, and manifest locations;
- `LocalStorageService` stream-copies authorized regular files into opaque
  UUID-named managed locations, computes SHA-256 and exact byte size, confines
  paths to the workspace, uses private permissions, verifies bytes, and only
  moves/restores managed files through Workspace Trash;
- `SQLitePersistenceStore` owns schema migration, exact canonical revision
  payloads, active pointers, derived dependency edges, stale events/current
  state, managed-asset metadata, and source-file bindings;
- `ManagedAssetCoordinator` compensates synchronous filesystem/database
  failures without permanently deleting the only copy and now journals intent,
  filesystem application, completion/rollback, and repair state for bounded
  restart reconciliation;
- `SQLiteRecoveryService` creates a consistent online SQLite backup plus
  versioned semantic JSONL, asset-hash inventory, migration record, and a
  manifest that checks every artifact's SHA-256 and byte size for internal
  consistency and corruption detection;
- `SQLiteJobRepository` stores canonical job snapshots, immutable state events,
  exact dependency/input/output references, and optimistic versions, and
  rechecks semantic input currency atomically before success publication;
- `LocalTaskTemporaryStorage` confines each job to one budgeted private
  `.tasks/<job-id>` directory, supports streamed writable-file leases with
  final hash/size verification, and performs bounded, age-checked, symlink-safe
  orphan cleanup;
- `RotatingTaskLogStore` stores bounded structured diagnostics with private
  value removal, credential-pattern redaction, private permissions, rotation,
  count limits, and retention limits.
- `LocalMediaIntakeJobExecutor` keeps source-file authority process-local,
  streams copy/hash work through the one Task Manager, re-inspects the managed
  copy, and publishes the immutable original source revision only after all
  checks pass;
- `CanonicalAudioJobExecutor` persists the generated canonical CAF and its
  exact provenance, while task-owned deterministic chunks and compact
  checkpoints remain rebuildable and bounded.

The recovery SQLite backup is authoritative and independently read-only
portable. The semantic JSONL is explicitly export-only; Task 004A does not
claim that it reconstructs active pointers, stale events, Trash state, or all
operational metadata. Automatic Trash purge is not implemented.

All Task 004A/004B migration, storage, and runtime integration tests use unique
disposable directories under the system temporary directory. No production or
user workspace was created or migrated.

Task 005A keeps the user-selected original untouched, copies it into managed
storage, and separates persistent canonical audio from temporary chunks.
ADR-0002 resolves the workspace/source bookmark policy. A full-Xcode native run
verifies App Sandbox initialization, synthetic-workspace selection through the
Open panel, exactly one persisted app-scoped bookmark, and scoped restoration
after relaunch. The purpose-routed importer regression test covers the approved
media route without introducing durable source authority.

## At-rest protection

Tasks 004A/004B store workspace data and backups as plaintext files. They apply
`0700` to managed directories and `0600` to manifests, databases, backups,
exports, and managed source files. Confidentiality therefore relies on the
macOS account boundary and host/volume encryption such as FileVault when the
operator has enabled it; MeetingBuddy does not claim to detect or configure
FileVault.

Backups receive the same classification and permission posture as their
source data. Tasks through 005A add no application-level encryption and no
encryption key. Any later application-level encryption requires a separate accepted ADR
covering Keychain storage, key loss/recovery, migration, backup restore,
rotation, and failure behavior before implementation.
