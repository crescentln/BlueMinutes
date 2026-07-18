# Storage and Recovery Policy

Status: Task 004A storage foundation accepted
Owner: Codex
Last updated: 2026-07-18
Purpose: Define authoritative representations, storage ownership, retention,
cleanup, migration, and recovery boundaries.

## Authority model

| Data | Authoritative representation |
| --- | --- |
| Original media and official documents | User workspace files with content hashes |
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

### Task 004A location ownership

| Location | Owner / creator | Deletor | Size or budget | Rebuildable / visibility | Cleanup, migration, classification |
| --- | --- | --- | --- | --- | --- |
| `workspace_manifest.json` | Workspace Service | No routine deletor | Fixed v1 metadata; 64 KiB read ceiling | Non-rebuildable identity; internal | Never auto-clean; format-version migration; inherits workspace sensitivity |
| `Meetings/<meeting-id>/assets/` | ID-based Storage Service / managed-file coordinator | Trash transition only; no permanent-delete API in 004A | Streamed user-selected bytes; bounded by available workspace volume, no silent quota eviction | Authoritative source bytes; user data | Retention from the managed record; UUID names; classification recorded per asset |
| `Database/meetingbuddy.sqlite` | SQLite persistence repositories/migrations | No reset/delete path | 16 MiB maximum per semantic payload; overall DB bounded by workspace volume | Authoritative metadata; internal | Ordered migrations and online rollback anchor; most restrictive contained classification |
| `Backups/Migrations/` | Migration bootstrap | No automatic deletor | One SQLite backup per attempted existing-DB migration; no automatic purge in 004A | Recovery authority; internal | Portable DELETE-journal SQLite; migrates with recovery format; same classification as DB |
| `Backups/Recovery/` | Recovery Service | No automatic deletor | One DB backup plus bounded metadata exports per snapshot; no automatic purge in 004A | Point-in-time recovery set; internal | Snapshot-ID directories, integrity descriptors, format version; same classification as captured DB/assets |
| `.Trash/assets/` | Storage Service / managed-file coordinator | No permanent-delete API in 004A | Same bytes as moved managed assets; bounded by workspace volume | Authoritative retained bytes; user-restorable | Collision-safe restore; future explicit retention/empty policy; retains source classification |
| `.temp/` | Local Storage Service in 004A | Creating operation | At most one streamed intake staging copy per active call | Disposable; internal | Removed on success/failure; must remain workspace-confined; inherits incoming asset classification |
| `Models/`, `Indexes/`, `Logs/`, `.tasks/`, `manifests/` | Workspace Service creates directories only; no active 004A writer | None in 004A | Zero-byte content budget in 004A | Reserved; not evidence of implemented features | Ownership/budget must be activated by the owning later task before any content is written |

## Retention defaults

- Permanent user data is not automatically deleted without a defined user
  retention rule.
- Original compressed media is kept by default; later UI may offer verified
  transcript-based deletion or per-meeting choice.
- Structured transcript revisions are authoritative; Markdown and plain text
  are derived renderings.
- Workspace Trash retains deleted user-visible objects for a reviewable period,
  initially 30 days, with restore and explicit empty actions.
- General logs are bounded and initially target approximately 14 days; crash
  diagnostics target approximately 30 days, subject to the telemetry ADR.
- Rebuildable data must have a tested rebuild path before automatic cleanup is
  enabled.

## Migrations and recovery

- SQLite uses explicit ordered migrations and WAL mode with controlled
  checkpoints.
- Migration tests run only in disposable workspaces.
- A migration creates a backup or other tested rollback anchor before changing
  user data.
- A failure cannot leave a partially committed logical object or ambiguous
  active-revision pointer.
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

Task 004A implements the foundation in two concrete boundaries:

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
  failures without permanently deleting the only copy;
- `SQLiteRecoveryService` creates a consistent online SQLite backup plus
  versioned semantic JSONL, asset-hash inventory, migration record, and a
  manifest that checks every artifact's SHA-256 and byte size for internal
  consistency and corruption detection.

The recovery SQLite backup is authoritative and independently read-only
portable. The semantic JSONL is explicitly export-only; Task 004A does not
claim that it reconstructs active pointers, stale events, Trash state, or all
operational metadata. Automatic Trash purge is not implemented.

All Task 004A migration and storage integration tests use unique disposable
directories under the system temporary directory. No production or user
workspace was created or migrated.

Task 004B still owns durable operation journaling, startup reconciliation of a
process interruption between filesystem and SQLite writes, job-owned temporary
data, cancellation, retry, and crash recovery. Distribution/sandbox bookmark
policy remains the Task 005A checkpoint.

## At-rest protection

Task 004A stores workspace data and backups as plaintext files. It applies
`0700` to managed directories and `0600` to manifests, databases, backups,
exports, and managed source files. Confidentiality therefore relies on the
macOS account boundary and host/volume encryption such as FileVault when the
operator has enabled it; MeetingBuddy does not claim to detect or configure
FileVault.

Backups receive the same classification and permission posture as their
source data. Task 004A adds no application-level encryption and no encryption
key. Any later application-level encryption requires a separate accepted ADR
covering Keychain storage, key loss/recovery, migration, backup restore,
rotation, and failure behavior before implementation.
