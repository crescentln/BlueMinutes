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
- The Storage Service is the only persistent filesystem-write boundary.
- Use explicit ordered migrations, WAL mode, controlled checkpoints, and
  disposable migration tests.
- Recovery exports are versioned and tested. The system does not claim database
  reconstruction until manifests and recovery tests prove it.
- Destructive user-visible deletion normally moves data to Workspace Trash.

## Consequences

- Domain types remain independent of table layout and file paths.
- Provider adapters cannot receive direct database access.
- Migration and recovery work must precede real media/provider data.
- Task 004A must demonstrate backup/rollback behavior without touching a real
  user workspace.

## Open implementation choice

The concrete Swift SQLite adapter is not yet selected. Task 004A must compare
the native alternative with a mature wrapper such as GRDB and record the full
dependency note before adding it.
