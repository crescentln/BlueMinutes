# Storage and Recovery Policy

Status: Accepted authority model; implementation is deferred to Tasks 004A/004B
Owner: Codex
Last updated: 2026-07-17
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

Persistent filesystem writes must go through the Storage Service. Persistent
metadata writes must go through repositories. Features and providers do not
write directly to arbitrary paths or SQLite.

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
  hashes, and migration version once implemented.
- User data is never silently reset, discarded, or overwritten to repair a
  schema problem.

## Dependency status

SQLite is the accepted metadata store. The concrete Swift adapter remains open:
GRDB is preferred by the master specification, but it is not approved or added
until Task 004A records the required dependency note and validation plan.

## Current implementation status

No workspace, database, schema, migration, backup, recovery artifact, Trash,
model store, cache, or user meeting data exists in Task 002.
