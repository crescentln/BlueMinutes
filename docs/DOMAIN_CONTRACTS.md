# Domain Contract Baseline

Status: Accepted design constraints; no code exists yet
Owner: Codex
Last updated: 2026-07-17
Purpose: Define semantic invariants and task ownership without reproducing the
master specification's field lists.

## Contract boundary

Semantic objects are the stable contract between persistence, application
services, UI features, AI providers, prompts, automation adapters, and tests.

Database rows, arbitrary filesystem paths, temporary JSON, and undocumented
application state are not semantic contracts.

## Common revision invariants

Every persisted semantic revision must:

- distinguish a stable logical object ID from an immutable revision ID;
- declare its object type and schema version;
- record lifecycle and validation status;
- record exact input and source-asset revision IDs;
- retain typed evidence and data classification;
- retain creation and provider provenance where applicable;
- have a deterministic content representation suitable for hashing;
- never mutate after persistence.

Editing creates a new revision. Publication changes an active pointer rather
than overwriting an earlier revision. Downstream data references exact
revisions, not only logical IDs.

## Initial object sequence

| Task | Contract groups |
| --- | --- |
| 003A | Stable IDs, revision envelope, schema/lifecycle/validation types, data classification, provenance metadata, `SourceAsset.v1`, `EvidenceRef.v1` |
| 003B | `MeetingProfile.v1`, `TranscriptSegment.v1`, `TranslationSegment.v1`, `Actor.v1`, `SpeakingCapacity.v1`, `SpeakerAssignment.v1`, dependency and stale-plan contracts |
| 006A | `InterventionCard.v1`, `DelegationPositionCard.v1` |
| 006B | `IssuePositionGraph.v1`, `BriefingSection.v1`, `ValidationReport.v1`, `FinalBriefing.v1` |
| 010 | `HistoricalComparison.v1` |

No later-task object is to be added early merely to complete this catalog.

## Evidence and provenance

Evidence is a typed union that identifies an exact source revision and an exact
location or time range. A bare filename, logical ID, or database row ID is
insufficient.

The model must preserve the distinction between:

- source fact;
- delegation claim;
- MeetingBuddy extraction;
- MeetingBuddy inference;
- user-confirmed conclusion.

Original speaker audio, simultaneous interpretation, translated audio,
machine translation, human translation, and user-edited translation remain
distinct provenance paths. Translation never overwrites source text.

## Actor and diplomatic rules

- A person, country, organization, formal group, UN organ, chair, expert,
  observer, and represented entity must remain distinguishable.
- A speaker's nationality does not establish the entity represented in an
  intervention.
- Formal group membership does not prove a shared meeting position.
- Silence is not support or opposition.
- Reservations, qualifications, and conditions must survive aggregation.
- Wording variation alone is not evidence of policy change.
- Uncertainty must remain explicit and reviewable.

## Validation and compatibility

Each implemented contract must provide deterministic validation, canonical
serialization, round-trip tests, and an explicit strategy for unknown future
enum values. Invalid provider output must not be imported by filling missing or
unsupported claims.

Compatibility promises are introduced only when backed by real supported
versions and tests; Task 003A must not build a speculative general migration
framework.

## Implementation status

As of Task 002, all objects in this document are target contracts only. Their
existence here is not evidence of code, schema, migration, or test completion.
