# ADR-0004: Immutable Semantic Revisions

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 003A

## Context

Diplomatic conclusions must remain attributable to exact source, translation,
speaker, prompt, provider, and user-review inputs. In-place mutation would erase
the evidence needed to reproduce or challenge an output.

## Decision

- A logical semantic object may have multiple immutable revisions.
- Logical IDs and revision IDs are distinct strongly typed identifiers.
- Exactly one revision may be the active published revision where the object
  type requires one.
- Editing creates a new revision; publication moves an active pointer.
- Superseded revisions remain auditable subject to retention policy.
- Derived revisions record exact input and source-asset revision IDs.
- Manual edits, locks, provider metadata, schema versions, classification, and
  evidence remain part of revision provenance.

## Consequences

- No mutable in-place revision update API is permitted.
- Persistence must enforce active-pointer integrity transactionally.
- Serialization, round-trip, compatibility, and revision-replacement tests are
  required from the first domain milestone.
- User-visible history and stale status can be explained without deleting prior
  output.
