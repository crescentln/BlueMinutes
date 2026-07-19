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
| [ADR-0013](ADR-0013-task-008a-capture-and-un-web-tv-boundary.md) | Accepted for implementation | Audio-only least-authority capture, recoverable segmented persistence, metadata-only UN Web TV, and no media acquisition absent documented rights |

## Open decisions by blocking task

| Decision | Must be resolved before |
| --- | --- |
| Production transcription and translation routes | Task 005B |
| Production inference and optional independent review routes | Task 006A/006B |

Task 007 adds ADR-0012: the current single-user local workspace format remains
readable and keyless at the application layer, with private permissions,
Keychain-only secrets, and no claim that FileVault is enabled. A different
encryption boundary requires a later explicit ADR and migration design.
Task 008A accepts ADR-0013 without changing runtime behavior: it separates
native audio capture from exact-host metadata-only UN Web TV access, accepts
the least network-client boundary with no-outbound/manual fallback, rejects
automatic media acquisition under the current technical/rights evidence, and
binds Task 008B to the accepted state/checkpoint/migration design.

The canonical greenfield-root and ADR-0013 D1-D5 decisions are closed. There
are no open P0 architecture decisions; Task 008B is eligible but remains not
started until separately authorized.
