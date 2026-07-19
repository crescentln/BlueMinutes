# Architecture Decision Records

Status: Active index
Owner: Codex
Last updated: 2026-07-19
Purpose: Index binding decisions and visible open questions. ADRs do not grant
task authorization.

## Status meanings

- `Accepted`: binding for later implementation unless superseded by a user-
  approved ADR.
- `Proposed`: a recommendation or explicit deferral; not yet a binding product
  choice.
- `Superseded`: retained for history and linked to its replacement.
- `Rejected`: retained with the reason it was not adopted.

## Index

| ADR | Status | Decision |
| --- | --- | --- |
| [ADR-0001](ADR-0001-language-ui-and-platform.md) | Accepted | Swift 6, native macOS UI, modular monolith, initial platform baseline |
| [ADR-0002](ADR-0002-distribution-and-sandbox.md) | Accepted | Option A: independent Developer ID direction, App Sandbox, persistent workspace bookmark, transient source authority |
| [ADR-0003](ADR-0003-persistence-and-recovery.md) | Accepted | SQLite metadata authority, file-based assets, explicit recovery boundary |
| [ADR-0004](ADR-0004-immutable-revisions.md) | Accepted | Immutable semantic revisions and active published pointers |
| [ADR-0005](ADR-0005-dependency-invalidation.md) | Accepted | Exact dependency edges and deterministic stale propagation |
| [ADR-0006](ADR-0006-provider-and-agent-boundaries.md) | Accepted | Inference providers and agent-control adapters are separate boundaries |
| [ADR-0007](ADR-0007-data-classification-and-cloud-routing.md) | Accepted | Classification inheritance and deny-by-default cloud-routing intersection |
| [ADR-0008](ADR-0008-media-and-external-processes.md) | Accepted | Native media APIs first; no external executable is currently approved |
| [ADR-0012](ADR-0012-task-007-workspace-encryption-boundary.md) | Accepted for implementation | No application-level workspace encryption in Task 007; private local files, Keychain secrets, readable recovery, and explicit revisit triggers |
| [ADR-0013](ADR-0013-task-008a-capture-and-un-web-tv-boundary.md) | Proposed | Audio-only least-authority capture, recoverable segmented persistence, metadata-only UN Web TV option, and no media acquisition absent documented rights |

## Open decisions by blocking task

| Decision | Must be resolved before |
| --- | --- |
| Production transcription and translation routes | Task 005B |
| Production inference and optional independent review routes | Task 006A/006B |
| ADR-0013 decisions D1-D5: live-capture scope/permissions, UN metadata mode and media-rights boundary, and schema-007 durability contract | Task 008B; requires explicit Task 008A acceptance and a separate implementation command |

Task 007 adds ADR-0012: the current single-user local workspace format remains
readable and keyless at the application layer, with private permissions,
Keychain-only secrets, and no claim that FileVault is enabled. A different
encryption boundary requires a later explicit ADR and migration design.
Task 008A adds proposed ADR-0013 without changing runtime behavior: it separates
native audio capture from optional UN Web TV metadata, rejects automatic media
acquisition under the current technical/rights evidence, and specifies the
state/checkpoint/migration design that Task 008B may use only after acceptance.

The canonical greenfield-root decision remains closed. ADR-0013 decisions
D1-D5 are now open P0 boundaries because Task 008B cannot begin safely without
explicit user acceptance.
