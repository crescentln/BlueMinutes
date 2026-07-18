# ADR-0003: Persistence Authority and Recovery

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 004A

## Context

MeetingBuddy must preserve large source assets, immutable semantic revisions,
active pointers, jobs, evidence, and recoverable history without coupling
providers or UI code to storage layout.

## Decision

- SQLite is authoritative for semantic revision metadata, active pointers,
  dependency edges, jobs, and audit records.
- Original media and official documents remain workspace files identified by
  content hashes; large binaries are not SQLite BLOBs.
- Search indexes, waveforms, previews, and vector indexes are rebuildable.
- Repositories and services are the only persistent metadata boundary.
- Approved persistence services are the only persistent filesystem-write
  boundaries: Workspace Service owns layout and manifest creation, Storage
  Service owns managed files and Trash, migration bootstrap owns rollback
  anchors, and Recovery Service owns recovery snapshots.
- Use explicit ordered migrations, WAL mode, controlled checkpoints, and
  disposable migration tests.
- Recovery exports are versioned and tested. The system does not claim database
  reconstruction until manifests and recovery tests prove it.
- Destructive user-visible deletion normally moves data to Workspace Trash.
- GRDB 7.11.1 is the approved Swift adapter over system SQLite. It is pinned
  exactly and confined to `MeetingBuddyPersistence`; domain and application
  contracts expose no GRDB or SQL type.
- A consistent SQLite online backup is the authoritative exact recovery
  artifact. The versioned semantic JSONL snapshot is an integrity-checked,
  validated export only until a later task proves full operational-state
  reconstruction from it.

## Consequences

- Domain types remain independent of table layout and file paths.
- Provider adapters cannot receive direct database access.
- Migration and recovery work must precede real media/provider data.
- Task 004A must demonstrate backup/rollback behavior without touching a real
  user workspace.
- The package requires Swift tools 6.1 to match the reviewed GRDB release.
- The complete dependency, license, validation, update, and removal record is
  maintained in [`../dependencies/GRDB.md`](../dependencies/GRDB.md).
