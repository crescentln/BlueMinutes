# MVP Acceptance Baseline

Status: Task 003B contract gates verified pending acceptance; end-to-end MVP remains untested
Owner: Codex
Last updated: 2026-07-18
Purpose: Define the acceptance boundary for the first local recorded-meeting
vertical slice and prevent documentation or scaffolding from being mistaken for
product completion.

## MVP boundary

The first usable product path is:

```text
import local audio/video
  -> preserve source provenance
  -> canonicalize audio
  -> create deterministic recoverable chunks
  -> transcribe through one approved route
  -> translate through one approved route
  -> review transcript and speaker assignments
  -> create evidence-linked intervention and delegation-position objects
  -> create an issue-position matrix
  -> generate and validate two or three independent briefing sections
  -> assemble and export deterministic Markdown
```

This boundary excludes UN Web TV, live capture, MCP, local HTTP control,
historical comparison, broad autonomous political analysis, and release claims.

## Prerequisite task gates

Tasks 003A, 003B, 004A, 004B, 005A, 005B, 006A, and 006B must each be accepted
in order. A later task cannot compensate for a failed prerequisite.

## Required end-to-end assertions

- Every substantive briefing conclusion navigates to exact evidence.
- No P0 invented national or organizational position exists in applicable
  Golden fixtures.
- Reservations, conditions, and uncertainty survive aggregation.
- Interpretation is never labeled as original wording.
- Translation never overwrites source text.
- Speaker or translation correction creates a new revision and marks exact
  downstream dependencies stale.
- Locked or manually edited briefing sections are not overwritten.
- Invalid structured provider output is rejected.
- Cancellation, retry, and crash recovery leave consistent persistent state.
- Temporary files are bounded, job-owned, and safely cleaned.
- User source files are never modified.
- Restricted data is not sent externally.
- Logs contain no credentials or complete sensitive meeting content by default.
- Long media processing does not require loading the full file into memory.
- Markdown export is deterministic and assembled from current validated section
  revisions.

## Quality-gate matrix

| Gate | MVP evidence required |
| --- | --- |
| Storage discipline | Owned locations, budgets, cleanup, migration, and recovery tests |
| Evidence integrity | Exact revision/location references for all substantive claims |
| Prompt/schema consistency | Versioned bounded inputs/outputs and rejected invalid output |
| Briefing quality | Golden rubric for restrained, actor-explicit Chinese briefing text |
| Automation safety | Not applicable to the first slice unless an automation adapter is added later |
| Provider integrity | Approved route, visible policy, no credential or subscription misuse |
| Semantic-object integrity | Providers consume semantic packages rather than tables or arbitrary paths |
| Privacy/routing integrity | Classification inheritance and deny-by-default route tests |
| Revision integrity | Immutable revisions, active pointers, dependency edges, and stale propagation tests |

## Verification classes

Each implementation task must report:

- deterministic build command;
- unit tests;
- integration tests in disposable workspaces;
- applicable Golden fixtures;
- failure, cancellation, and recovery tests;
- manual native macOS verification where UI or permission behavior matters;
- dependency, license, storage, privacy, and documentation impact.

Exact commands are introduced with the first Swift package/project and then
kept current in the execution ledger and implementation plan.

## Current status

Tasks 003A and 003B now verify the foundational and input-side semantic
contracts: immutable values, exact revision references, fail-closed
classification, deterministic validation, native semantic-hash verification,
stable v1 serialization, provenance separation, explicit active-published
selection, dependency edges, and deterministic transitive stale planning. The
86 synthetic tests in 13 suites include exactly five clearly labeled Golden
fixtures and pass with the documented environment-scoped CLT command.

At the contract level, the evidence confirms that translation does not replace
source text, interpretation cannot claim original wording, uncertain speakers
remain unconfirmed, edits create new immutable revisions, and active upstream
replacement yields stable causal stale marks without mutating history. It does
not prove persistence or execute stale-state changes.

The remaining end-to-end assertions stay `NOT TESTED` or `NOT APPLICABLE`
until their owning tasks are implemented. Task 003B does not establish a
database, repository integrity constraints, provider routing, media
processing, briefing analysis, recovery, UI review, or user-facing MVP
behavior.
