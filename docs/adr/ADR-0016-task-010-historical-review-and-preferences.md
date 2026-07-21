# ADR-0016: Task 010 Historical Review and Preference Boundary

Status: Accepted
Date: 2026-07-21
Decision owners: User and Codex

## Context

Accepted Position, Evidence, security-policy, revision, invalidation, Task
Manager, and local-review foundations now permit useful historical retrieval.
The risk is that a convenient “memory” feature could hide provenance, leak
unauthorized history, mistake wording or group membership for policy change,
or silently alter protected behavior through preferences.

Task 010 also requires schema evolution from the closed v9 semantic vocabulary,
rebuild and rollback behavior, and bounded historical performance without
adding an outbound provider or an unapproved evidence adapter.

## Decision

1. Historical search is a deterministic local repository over a disposable,
   versioned SQLite index. Authoritative semantic objects remain immutable.
2. Only confirmed, user-confirmed, valid published Positions are indexed. Every
   result retains exact linked revisions and is re-authorized against the
   current exact SensitivityLabel and AccessPolicy before content or counts are
   returned.
3. Index rebuild uses the single Task Manager as a restricted local-only job
   and atomically replaces one complete generation.
4. `HistoricalComparison.v1` is an independent semantic object. Automatic
   results are limited to insufficient, no-confirmed-difference, or possible
   states with fixed qualified language.
5. Wording, silence, or formal group membership cannot establish a policy
   change. A confirmed difference requires an explicit user-authored
   superseding revision that cites the exact possible-difference candidate.
6. Evidence admission binds an already-admitted exact `SourceAsset.v1`
   revision, SHA-256, byte size, acquisition time, and source kind. It grants no
   file, email, browser, or network authority.
7. Learned preferences use a closed typed vocabulary and explicit user-action
   provenance. Values are visible, editable, disableable, removable, and
   resettable. They may affect presentation only and cannot change security,
   evidence, provider/model routing, confirmation, or diplomatic rules.
8. Schema v10 preserves prior canonical bytes and adds rebuildable history
   indexes plus preference state/events. The verified v9 online backup is the
   rollback anchor; migration fabricates no history or preference.

## Consequences

- Search may omit a record when any exact dependency or policy fact is missing;
  this is intentional fail-closed behavior.
- Rebuild cost is explicit and testable, while normal semantic publication does
  not synchronously maintain a complex search projection.
- Audit actions remain durable after a preference is removed or reset, but raw
  values do not remain in the effective preference table.
- Initial retrieval is lexical and conservative. It cannot claim fuzzy identity,
  semantic similarity, organizational authority, or geopolitical truth.
- Task 010 adds no dependency, provider, model, credential, subprocess,
  listener, mail connector, public-source fetcher, or outbound-network path.

## Alternatives rejected

- Hidden vector/LLM memory: rejected because it is opaque, non-deterministic,
  difficult to reset, and unsafe for access control.
- Automatic “policy changed” classification: rejected because wording and
  incomplete context cannot prove policy change.
- Mutable comparison fields on Position: rejected because it would rewrite
  source truth and obscure evidence/review lineage.
- Direct live mail/web search: rejected because Task 010 does not grant account,
  credential, network, retention, or provider authority.
- Preferences embedded in prompts or application defaults: rejected because
  users could not reliably inspect, disable, remove, or reset them.

## Validation obligations

- deterministic filter/order and repeated-query fixtures;
- exact revision/evidence and effective-time/confidence trails;
- insufficient-evidence and wording-only Golden regressions;
- user-confirmed superseding lineage;
- policy/classification fail-closed tests with no content/count leakage;
- all seven preference types and edit/disable/remove/reset proof;
- Task Manager rebuild, cancellation-safe atomic generation replacement, scale,
  v9 migration/backup/rollback/recovery, and no-outbound static evidence.

Detailed operational behavior is recorded in
[`../HISTORICAL_REVIEW.md`](../HISTORICAL_REVIEW.md).
