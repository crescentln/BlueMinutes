# Storage and Recovery Policy

Status: Tasks 001 through 011 accepted; schema v10 and synthetic backup gates verified
Owner: Codex
Last updated: 2026-07-22
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
| Transcript coverage manifests and provider outcomes | SQLite metadata plus job-owned bounded artifacts until verified publication |
| Live recording checkpoints and incomplete recordings | Incrementally durable managed files plus SQLite state through Task Manager and Storage Service |
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

## Transcript completeness storage contract

Task 005B persists or reconstructably derives a coverage manifest bound to the
exact canonical-audio revision and chunk-plan version. It accounts for every
eligible core/physical range, provider result, stable segment ID, verified no-
speech outcome, retry, and missing/failed range. Publication requires a
deterministic 100 percent eligible-range union; an incomplete or unprovable
manifest remains failed/incomplete and cannot become the active transcript set.

Task 006A retains an immutable segment/evidence coverage ledger for
hierarchical extraction. It binds the exact active transcript manifest and
eligible reviewed segment revisions; every segment is substantive or explicitly
non-substantive before publication. Missing, duplicated, or failed coverage
blocks publication. Task 006B now consumes that proof in a second immutable
normalized ledger that maps every eligible segment through exact analysis
outputs/evidence to matrix or section item IDs. Its source-text overlap is
exactly zero, conclusion fan-out is bounded, and missing, duplicated, failed,
or untraceable coverage blocks final publication. No summary output can
substitute for either underlying manifest/ledger.

## Reliable recording storage contract

Task 008A defines and Task 008B implements capture/persistence states including
preparing, recording, interrupted, recovering, stopping, finalizing, completed,
incomplete, and failed. Capture writes bounded durable increments and
checkpoints while recording is active; a meeting is never held only in volatile
memory until stop.

Recovery reconciles checkpoint metadata and bytes after crash, process kill,
OS interruption, permission loss, disk-full, or microphone/system-audio device
disconnection. Recoverable data is preserved; unverified or missing ranges are
shown explicitly, and an incomplete recording is never labeled complete.

### Implemented location ownership through Task 011

| Location | Owner / creator | Deletor | Size or budget | Rebuildable / visibility | Cleanup, migration, classification |
| --- | --- | --- | --- | --- | --- |
| `workspace_manifest.json` | Workspace Service | No routine deletor | Fixed v1 metadata; 64 KiB read ceiling | Non-rebuildable identity; internal | Never auto-clean; format-version migration; inherits workspace sensitivity |
| `Meetings/<meeting-id>/assets/` | ID-based Storage Service / managed-file coordinator, invoked by intake, canonical, recording, Trash, restore, and retention-gated purge operations | Explicit confirmed purge after minimum retention; no automatic scheduler | Streamed untouched originals plus generated canonical/recorded audio; bounded by available workspace volume, no silent quota eviction | Original/recorded bytes are authoritative source data; canonical audio is a persistent hash-bound derivative | UUID names; exact source-revision provenance; classification inherited; purge records unlink-without-erasure-guarantee receipts |
| `Database/meetingbuddy.sqlite` | SQLite semantic, job, transcript, analysis, briefing, security, recording, automation, MCP-attribution, history/preference, export, and migration repositories | No database reset/delete path | 16 MiB maximum per semantic or coverage payload; 1 MiB maximum per canonical job snapshot/export record; overall DB bounded by workspace volume | Authoritative semantic, coverage, recording, audit, preference, and operational metadata; historical search projection is rebuildable | Ordered migrations through v10 and online rollback anchors; immutable semantic/coverage/event rows; most restrictive contained classification |
| `Meetings/<meeting-id>/exports/` | Explicit local Markdown export service | No overwrite/delete API in Task 006B | One bounded current final per safe requested filename; bytes equal the validated `FinalBriefing.v1` Markdown | User-visible derived output; reproducible from retained exact revisions | `0700` directory, `0600` file, workspace confinement, symlink/traversal/conflict refusal, atomic rename, exact classification/hash/size/revision audit record |
| `Backups/Migrations/` | Migration bootstrap | No automatic deletor | One SQLite backup per attempted existing-DB migration; no automatic purge in 004A | Recovery authority; internal | Portable DELETE-journal SQLite; migrates with recovery format; same classification as DB |
| `Backups/Recovery/` | Recovery Service | No automatic deletor | One DB backup plus bounded metadata exports per snapshot; no automatic purge in 004A | Point-in-time recovery set; internal | Snapshot-ID directories, integrity descriptors, format version; same classification as captured DB/assets |
| `.Trash/assets/` | Storage Service / managed-file coordinator | Explicit Task 007 purge after visible confirmation, exact item binding, and minimum retention; no automatic scheduler | Same bytes as moved managed assets; bounded by workspace volume | Authoritative retained bytes until purge; user-restorable | Collision-safe restore; crash-safe purge intent/receipt; retains source classification; no forensic-erasure claim |
| `.temp/` | Local Storage Service / managed-asset coordinator | Creating operation or bounded startup reconciliation | At most one deterministic streamed-intake staging copy per active journaled import | Disposable; internal | Cooperative cancellation checks each streamed MiB; removed on success/failure/cancellation or exact operation-ID recovery; workspace-confined; inherits incoming classification |
| `.tasks/<job-id>/` | Task Manager through `LocalTaskTemporaryStorage` | Task Manager on success, cancellation, non-retained failure, restart-only retry, or bounded orphan recovery | Explicit per-job lease, 1 byte–1 TiB contract ceiling, volume-capacity precheck, 10,000-entry scan ceiling | Canonical/transcript chunks and result checkpoints are disposable operational data; internal | `0700` directory, `0600` files, no traversal/symlinks; task audio is regenerated from canonical CAF and discarded after each call; digest-verified result artifacts remain only for eligible checkpoint retry |
| `Logs/Tasks/` | `RotatingTaskLogStore` | Log store retention/rotation | 4 MiB active default, at most 14 archives, approximately 14-day default retention; hard configuration ceilings | Operational diagnostics; internal and redacted | JSONL plus privacy-annotated OSLog; private values removed, public values bounded and credential-redacted; `0700`/`0600` |
| `Models/`, filesystem `Indexes/`, `manifests/` | Workspace Service creates directories only; no accepted filesystem writer | None | Zero-byte content budget in the accepted Task 011 scope | Reserved; Apple installed models are OS-owned, and Task 010 history indexes remain normalized SQLite projections | A future filesystem writer requires explicit ownership, budget, cleanup, migration, and classification policy |
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
- Incomplete live recordings are retained under an explicit user-visible
  recovery/retention state; they are not automatically purged as generic temp.
- Controlled export is explicit and classification-aware. Export never grants
  background upload authority.
- Workspace Trash and file unlink are not described as guaranteed forensic
  erasure on APFS/SSD; stronger deletion requires a threat model and accepted
  encryption/key-destruction design.

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
- SQLite schema version 3 adds immutable transcript coverage manifests, one
  active transcript-manifest pointer per meeting, and immutable pointer events.
  Fresh, v1-to-v3, and v2-to-v3 migrations pass; accepted v2 canary rows remain
  unchanged, and existing databases receive a verified portable pre-migration
  backup.
- SQLite schema version 4 expands the closed semantic-object vocabulary for all
  eight Task 006A intelligence types and adds immutable normalized analysis
  ledgers, segment/evidence/output indexes, one active analysis-ledger pointer
  per meeting, and immutable pointer events. Fresh and accepted v1/v2/v3 paths
  pass; the v3-to-v4 canary proves transcript-era semantic payload bytes are
  unchanged and verifies the portable pre-migration rollback backup.
- SQLite schema version 5 expands the vocabulary for the five Task 006B
  semantic types and adds immutable normalized briefing ledgers, segment/
  evidence/analysis-output/conclusion indexes, active briefing pointer/events,
  and export records. Fresh and accepted v1/v2/v3/v4 paths pass; the v4-to-v5
  canary preserves analysis-era semantic payload bytes and verifies the
  portable schema-v4 rollback backup.
- SQLite schema version 6 adds exact `SensitivityLabel.v1` and
  `AccessPolicy.v1` revisions plus retention, Trash/purge, storage-report, and
  telemetry-policy state. Accepted v5 payload bytes remain exact and the
  verified schema-v5 online backup is the downgrade boundary.
- SQLite schema version 7 adds recording sessions, immutable state events,
  tracks, epochs, segments, gaps, and checkpoints. Incomplete and completed
  recording evidence remains distinguishable; older binaries must restore the
  verified schema-v6 backup rather than open v7 in place.
- SQLite schema version 8 adds immutable automation command records, normalized
  policy inputs, result events, and versioned reversible safe settings. Its
  verified schema-v7 backup is the durable downgrade boundary.
- SQLite schema version 9 extends the closed automation audit-origin vocabulary
  for local stdio MCP attribution. It adds no semantic object, provider route,
  listener, or arbitrary database/filesystem authority and preserves a verified
  schema-v8 rollback backup.
- SQLite schema version 10 expands the closed vocabulary for
  `historical_comparison` and adds one generation-stamped, disposable historical
  Position/topic/Evidence index plus learned-preference settings, canonical
  values, and immutable audit events. Accepted v9 migration preserves exact
  semantic payload bytes and digests, creates a verified portable v9 rollback
  backup, and fabricates no history, comparison, or preference. A cancelled
  index rebuild cannot expose a partial generation.
- Managed-asset import, Trash, and restore persist an intent before bytes move,
  append immutable operation events, and reconcile bounded unfinished entries
  at startup by completing, rolling back, or reporting repair required.
- Recovery artifacts include a workspace manifest, semantic snapshot, asset
  hashes, migration version, integrity descriptors, and an authoritative
  portable SQLite backup.
- User data is never silently reset, discarded, or overwritten to repair a
  schema problem.
- Task 005B adds the transcript coverage proof outside the closed semantic-
  object vocabulary through an ordered backward-compatible migration and
  repository. Task 006A expands that vocabulary and persists analysis coverage
  through schema v4. Task 006B expands it again and persists briefing coverage,
  exact active chains, and export records through schema v5. Tasks 007 through
  009B add the accepted security, recording, automation, and MCP-attribution
  state through schema v9. Task 010 expands the vocabulary and adds historical/
  preference storage through schema v10; Task 011 adds no schema.
  Every later task adding a semantic object must also update that vocabulary
  and SQLite constraint with an online backup/rollback anchor, supported-prior-
  state and unknown-future tests, failure injection, close/reopen verification,
  and recovery-manifest coverage.

## Dependency status

SQLite remains the metadata store. GRDB 7.11.1 is now the approved, exactly
pinned Swift adapter and is isolated inside `MeetingBuddyPersistence`. The
reviewed dependency, license, update, removal, and validation record is
[`dependencies/GRDB.md`](dependencies/GRDB.md). Domain and application targets
do not import GRDB or expose database handles.

## Current implementation status

Accepted Tasks 001 through 011 implement the current foundation in concrete
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
- `TranscriptPipelineJobExecutor` regenerates only bounded canonical chunks,
  stores digest-verified text/result checkpoints for retry, removes temporary
  audio, and asks the repository to atomically validate the exact current input
  before publishing transcript/translation revisions and the coverage proof;
- `SQLitePersistenceStore` schema v3 stores immutable coverage manifests,
  active/event pointers, separate semantic transcript/translation revisions,
  exact dependency/stale state, and durable incomplete failure/missing ranges.
- `AnalysisPipelineJobExecutor` submits one bounded reviewed segment at a time,
  records durable incomplete coverage on failure, deterministically aggregates
  only validated claims, and publishes no semantic object until exact complete
  coverage and the resolved graph pass;
- `SQLitePersistenceStore` schema v4 stores all eight independent intelligence
  revisions plus immutable normalized analysis-ledger history, active/event
  pointers, atomic exact-input publication, user-correction lineage, and
  downstream stale state. Recovery snapshots include and verify this state.
- `BriefingPipelineJobExecutor` creates only independent bounded section
  candidates, records durable incomplete coverage on provider failure, and
  atomically publishes no final until exact eligible-segment/conclusion
  coverage and all deterministic validation categories pass;
- `SQLitePersistenceStore` schema v5 stores the five briefing semantic types,
  normalized immutable coverage/index history, active/event pointers, atomic
  one-section/manual replacement, export audit records, and downstream stale
  state. Recovery snapshots include and verify this state;
- `LocalMarkdownExportService` writes only the exact current valid final to the
  meeting-owned exports directory after explicit authorization, classification
  match, safe-name/path and conflict checks, private staging, byte verification,
  and atomic rename.
- `SQLiteHistoricalReviewRepository` rebuilds a complete local index generation
  from authoritative confirmed published Positions, switches generations in
  one transaction, and retains exact Position/Meeting/Actor/Issue/security/
  Evidence revision IDs. Disabling or rebuilding this projection does not
  delete semantic revisions.
- Schema v10 stores typed learned-preference values separately from immutable
  lifecycle events. Remove and Reset All delete effective value rows; audit
  events retain bounded action/provenance and digests but no raw value payload.
  This logical reset is not a forensic-erasure claim, and older verified backups
  continue to follow workspace backup retention.
- Task 007 adds schema-v6 security-policy storage, bounded storage reporting,
  recoverable Trash, and crash-safe retention-gated unlink intent/receipts.
- Task 008B adds schema-v7 recording state plus incrementally sealed managed
  segments and checkpoints that recover or remain visibly incomplete.
- Task 009A adds schema-v8 command/audit and reversible safe-settings authority;
  Task 009B extends only schema-v9 audit-origin attribution for local stdio MCP.

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

Task 009A schema v8 adds immutable command records, exact normalized policy
input revisions, immutable result events, a singleton versioned safe-settings
projection, and immutable settings events. Migration does not rewrite semantic
payloads and does not materialize the compiled version-zero default. A patch or
rollback writes its settings event, next compare-and-swap projection, and
successful command result in one SQLite transaction. Recovery validates every
automation payload hash/canonical form, normalized inputs, event relationship,
and the complete settings chain. The automatic pre-migration v7 backup is the
only supported durable schema rollback; v8 tables must not be deleted in place.

Task 010 schema v10 uses the same online-backup boundary. The v9-to-v10 canary
proves canonical semantic bytes/digests remain exact, the migrated index starts
dirty and empty, and no learned preference or HistoricalComparison is invented.
Rollback opens the verified v9 backup rather than deleting v10 tables in place.
History indexes are rebuildable; published comparisons and preference audit
events are authoritative durable metadata.

## At-rest protection

Tasks 004A/004B store workspace data and backups as plaintext files. They apply
`0700` to managed directories and `0600` to manifests, databases, backups,
exports, and managed source files. Confidentiality therefore relies on the
macOS account boundary and host/volume encryption such as FileVault when the
operator has enabled it; MeetingBuddy does not claim to detect or configure
FileVault.

Backups receive the same classification and permission posture as their
source data. Tasks through 011 add no application-level workspace encryption
or workspace encryption key; accepted ADR-0012 intentionally preserves the
readable single-user local format. The Task 005B Secret Store uses Keychain for
secrets, while host/account and volume protection remain operator controls. A
future encrypted format requires a separate accepted ADR covering Keychain
storage, key loss/recovery, migration, backup restore, rotation, and failure
behavior before implementation.

Task 011 verifies a cold independent copy only against a disposable synthetic
workspace: exact content/metadata/xattr/BSD-flag inventories, independent file
identities, owner-only usable permissions, SQLite integrity, stable initial/
final inventories, and production-path reopen pass. Hard-linked, read-only, and
BSD-flag-mismatched copies fail. The verifier takes no OS-level lock, so
MeetingBuddy must remain quit throughout copy and verification. No real user
workspace was read or changed, and an actual older-binary rollback plus clean-
machine restore remains untested.
