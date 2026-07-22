# Architecture Decision Records

Status: Active index
Owner: Codex
Last updated: 2026-07-22
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
| [ADR-0009](ADR-0009-task-005b-local-transcription-and-translation.md) | Accepted | Apple installed-model transcription/translation on macOS 26+, manual local fallback, and no Task 005B outbound adapter |
| [ADR-0010](ADR-0010-task-006a-local-analysis-route.md) | Accepted | Apple on-device Foundation Models guided extraction on macOS 26+, existing-local-review/no-external fallback, and no Task 006A outbound adapter |
| [ADR-0011](ADR-0011-task-006b-local-briefing-route.md) | Accepted | Three independent Apple on-device guided sections over minimum semantic claims, deterministic validation/assembly, no second reviewer, and controlled local export |
| [ADR-0012](ADR-0012-task-007-workspace-encryption-boundary.md) | Accepted | No application-level workspace encryption in Task 007; private local files, Keychain secrets, readable recovery, and explicit revisit triggers |
| [ADR-0013](ADR-0013-task-008a-capture-and-un-web-tv-boundary.md) | Accepted | Audio-only least-authority capture, recoverable segmented persistence, metadata-only UN Web TV, and no media acquisition absent documented rights |
| [ADR-0014](ADR-0014-task-009a-automation-command-boundary.md) | Accepted | Closed shared command layer, composition-owned authority, immutable local audit/replay, reversible safe settings, and a thin confined CLI |
| [ADR-0015](ADR-0015-task-009b-local-mcp-boundary.md) | Accepted | Local stdio MCP with seven read-authority tools, explicit audit/migration approval, truthful v9 attribution, and no new provider or network route |
| [ADR-0016](ADR-0016-task-010-historical-review-and-preferences.md) | Accepted | Deterministic local history, evidence-qualified comparison, explicit user confirmation, and visible presentation-only preferences |

## Open decisions by blocking task

| Decision | Must be resolved before |
| --- | --- |
| Organization-controlled or self-hosted telemetry route | Any future telemetry implementation; telemetry remains disabled by default |

## Roadmap integration and accepted sequence

The user-authorized 2026-07-18 roadmap integration strengthened the accepted
decisions in ADR-0002 through ADR-0008 for local-first processing, provider and
model-policy boundaries, immutable evidence-linked claims, transcript coverage,
privacy-preserving telemetry, and recoverable recording. No new ADR ID was
needed because these requirements refine existing decision subjects. Task 005A
remains accepted and frozen; that planning-only integration changed no
application behavior. The separately authorized Task 005B implementation adds
ADR-0009 for its concrete production transcription/translation route, and Task
006A adds ADR-0010 for its bounded local analysis route. Task 006B adds
ADR-0011 for its minimum-input local briefing route, deterministic review
boundary, and controlled export; no independent review provider is authorized.
Task 007 adds ADR-0012: the current single-user local workspace format remains
readable and keyless at the application layer, with private permissions,
Keychain-only secrets, and no claim that FileVault is enabled. A different
encryption boundary requires a later explicit ADR and migration design.
Task 008A accepts ADR-0013 without changing runtime behavior: it separates
native audio capture from exact-host metadata-only UN Web TV access, accepts
the least network-client boundary with no-outbound/manual fallback, rejects
automatic media acquisition under the current technical/rights evidence, and
binds Task 008B to the accepted state/checkpoint/migration design.

The canonical greenfield-root and ADR-0013 D1-D5 decisions are closed. Task
008B is accepted. Task 009A adds ADR-0014 for the shared typed command and CLI
boundary without MCP, HTTP, sensitive/destructive execution, provider work, or
remote control. Task 009B adds accepted ADR-0015 for the local stdio MCP
adapter. Task 010 adds accepted ADR-0016 for deterministic local history,
conservative comparison, and explicit presentation-only preferences. There are
no open P0 architecture decisions.

Tasks 001 through 011 are accepted and the canonical MVP sequence is complete.
Task 011 required no new ADR because it added no schema, provider, model,
dependency, network destination, entitlement, updater, or feature route. Its
accepted audit classifies the selected app as INTERNAL ALPHA and leaves
Developer ID/Team ID, notarization/stapling, Gatekeeper distribution,
clean-machine, manual accessibility, live intended-OS capture, and four medium
evidence-integrity gates unresolved. Three low scan findings are mitigated in
accepted source but await follow-up validation. There is no next eligible
numbered task; any post-MVP capability or publication action requires separate
explicit user authorization.

The separately authorized post-MVP security-remediation task adds
[ADR-0017](ADR-0017-evidence-integrity-publication-boundaries.md). It records
application-owned transcript/analysis omission verification and exact human
confirmation gates for consequential analysis and briefing export while
preserving schema v10 and immutable historical payloads.

Some individual ADR headers retain their original in-task acceptance wording
as historical context. This index and `../CODEX_EXECUTION_STATE.md` report the
current binding/accepted state; neither document authorizes a new task.
