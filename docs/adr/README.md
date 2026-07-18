# Architecture Decision Records

Status: Active index
Owner: Codex
Last updated: 2026-07-17
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
| [ADR-0002](ADR-0002-distribution-and-sandbox.md) | Proposed | Distribution channel and final sandbox policy remain open |
| [ADR-0003](ADR-0003-persistence-and-recovery.md) | Accepted | SQLite metadata authority, file-based assets, explicit recovery boundary |
| [ADR-0004](ADR-0004-immutable-revisions.md) | Accepted | Immutable semantic revisions and active published pointers |
| [ADR-0005](ADR-0005-dependency-invalidation.md) | Accepted | Exact dependency edges and deterministic stale propagation |
| [ADR-0006](ADR-0006-provider-and-agent-boundaries.md) | Accepted | Inference providers and agent-control adapters are separate boundaries |
| [ADR-0007](ADR-0007-data-classification-and-cloud-routing.md) | Accepted | Classification inheritance and deny-by-default cloud-routing intersection |
| [ADR-0008](ADR-0008-media-and-external-processes.md) | Accepted | Native media APIs first; no external executable is currently approved |

## Open decisions by blocking task

| Decision | Must be resolved before |
| --- | --- |
| Final distribution channel, sandbox, bookmarks, and app-update path | Task 005A implementation plan |
| Concrete SQLite Swift adapter and dependency review | Task 004A |
| Canonical audio representation, timeline tolerance, and chunk parameters | Task 005A |
| Production transcription and translation routes | Task 005B |
| Production inference and optional independent review routes | Task 006A/006B |
| UN Web TV acquisition and live-capture entitlement boundaries | Task 008B, after Task 008A |

There are no open P0 architecture decisions after the user confirmed the
canonical greenfield root.
