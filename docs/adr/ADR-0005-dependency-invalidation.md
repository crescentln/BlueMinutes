# ADR-0005: Dependency Invalidation and Stale Propagation

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 003B

## Context

Corrections to a transcript, translation, speaker, or source may invalidate
positions and briefing sections. Silent replacement would make reviewed output
unreliable; retaining outdated output as current would be equally unsafe.

## Decision

- Every derived revision records exact input revision IDs.
- Dependency edges are explicit and queryable.
- Replacing an active upstream revision deterministically identifies affected
  downstream revisions and marks them stale with a machine-readable reason.
- Stale, invalidated, or blocked output cannot silently publish as current.
- Prior output remains available for audit and is not silently deleted.
- Recalculation is planned from the changed dependency boundary rather than
  rerunning the entire meeting.
- Locked or manually edited briefing sections are never overwritten; they are
  marked stale and require user review.
- A job rechecks that its inputs are still current immediately before
  publication.
- Transcript and hierarchical coverage manifests are exact publication inputs.
  A missing source range/segment or unprovable 100 percent coverage blocks the
  dependent transcript, extraction, section, or final briefing rather than
  silently publishing a partial result.

## Consequences

- Task 003B must implement a deterministic stale-plan contract before the
  database executor exists.
- Task 004A persists edges and stale state transactionally.
- Later UI must explain which input changed and which outputs are affected.
- Idempotency keys and publication gates include exact input revisions.
- Accepted Tasks 005B, 006A, and 006B test injected omissions, bounded overlap,
  retries, restarts, and segment-to-conclusion traceability. Task 011 re-audits
  those structural gates but leaves provider-only `noSpeech` and
  `nonSubstantive` closure as medium evidence-integrity findings requiring
  human review.
