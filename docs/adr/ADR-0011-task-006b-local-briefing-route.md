# ADR-0011: Task 006B Local Briefing and Export Route

Status: Accepted
Date: 2026-07-18
Decision owners: Codex under the user's Task 006B authorization
Applies from: Task 006B

## Context

Task 006B must turn current validated Task 006A intelligence into independent,
evidence-linked briefing sections without sending meeting content elsewhere or
rewriting the raw transcript as one opaque prompt. It also permits an optional
separate reviewing provider only if that route is specifically authorized.

## Decision

- Reuse the application-owned model-policy router and Apple on-device
  Foundation Models boundary selected in ADR-0010. Each section receives only
  its bounded validated intelligence claims and opaque evidence identifiers.
  Raw transcript, audio, database access, workspace paths, tools, retrieval,
  cloud, and Private Cloud Compute are excluded.
- Use one fresh no-tool guided-generation session for each of exactly three v1
  sections. Generation is independent and section-specific; final assembly is
  deterministic application code over current validated section revisions.
- Treat all claim text as untrusted data under application-owned protected
  rules. Provider output remains a candidate and must close over every exact
  supplied source key exactly once, preserve conditions/reservations, remain
  within its schema/byte bound, and pass deterministic evidence, entity,
  coverage, contradiction, provenance, current-input, and classification
  validation before publication.
- Do not add an independent reviewing provider in Task 006B. No external or
  second-provider destination, retention, credential, model policy, or user
  authorization was granted. Deterministic fail-closed validation and explicit
  manual review are the approved review boundary.
- Store the meeting template, sparse issue-position matrix, sections,
  validation report, and final briefing as independent immutable semantic
  revisions. A lock or manual edit creates a new user revision. Stale inputs or
  a locked/user-edited target cannot be silently regenerated or exported.
- Export only after an explicit user action to the workspace-owned meeting
  export directory. Require the exact active current valid final and exact
  classification, confine the filename/path, refuse different existing bytes,
  write privately and atomically, and persist an audit record. Export is a
  local file operation, not transmission authority.

## Rejected alternatives

- A whole-transcript or whole-briefing rewrite pass is rejected because it
  weakens exact coverage, section independence, and provenance.
- A graph database is rejected; the v1 graph is a deterministic typed sparse
  matrix over exact Issue, represented-entity, and Position revisions.
- A cloud or independent reviewing provider is rejected for this task because
  no outbound destination or retention/credential policy is authorized.
- Free-form Markdown as the authoritative template is rejected. The versioned
  template owns section inputs, schemas, validation rules, byte bounds, prompt
  modules, and renderer version; Markdown is a deterministic derived view.
- Overwriting an existing export or generated section is rejected in favor of
  immutable revisions, compare-and-swap pointers, and conflict refusal.

## Consequences

- Automatic briefing generation requires macOS 26+, an available supported
  Apple on-device model, and a visibly authorized local-only policy decision.
  When unavailable, no external fallback occurs and existing local content is
  preserved.
- Apple model prose is not itself reproducible across OS model updates. Exact
  inputs, adapter/prompt/schema versions, validated semantic outputs, coverage,
  final assembly, and exported Markdown hashes remain recorded and testable.
- The first template is deliberately narrow: one multilateral diplomatic
  meeting type and three sections. Historical comparison and the broader
  template catalog remain later-task work.
- No dependency, credential, entitlement, network implementation, telemetry,
  capture authority, or external retention path is added.

## Validation required before Task 006B completion

- Contract and canonical round-trip tests for template, graph, multi-Position
  cells, sections, reports, final briefing, incompatible schema, and exact
  qualification preservation.
- Deterministic section independence/regeneration, lock/manual-edit, coverage,
  contradiction, stale-input, export, provider-denial/failure, close/reopen,
  and recovery tests in disposable workspaces.
- Fresh and accepted v1/v2/v3/v4-to-v5 migration, byte-preserving v4 canary,
  verified rollback backup, unknown-future, and failure-injection tests.
- One opt-in real installed Apple Foundation Models run using only bounded
  project-authored synthetic evidence-linked claims.
- Full warnings-as-errors tests/builds, package/entitlement boundary checks,
  no-network/credential/artifact scans, app launch, and signature inspection.

## References

- [ADR-0010](ADR-0010-task-006a-local-analysis-route.md)
- [Task 006B briefing foundation](../BRIEFING_FOUNDATION.md)
