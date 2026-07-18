# Domain Contract Baseline

Status: Task 004A persistence realization accepted
Owner: Codex
Last updated: 2026-07-18
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

## Implemented foundation

`MeetingBuddyDomain` is a zero-dependency Swift 6 library. Its public values
are immutable `Sendable` structs or enums. Object-specific logical IDs use
phantom types, so a source-asset ID, evidence ID, revision ID, meeting ID, and
managed-storage ID cannot be assigned interchangeably.

`RevisionEnvelope<ObjectIDTag>` contains:

```text
logical_id
revision_id
object_type
schema_version
lifecycle_status
validation_state
created_at
created_by
published_at
supersedes_revision_id
input_revisions
source_asset_revisions
evidence_revisions
data_classification
generation_metadata
semantic_content_hash
```

Input, source-asset, and evidence relationships use
`SemanticRevisionReference`, which carries object type, logical ID, and exact
revision ID. Public construction derives object type from the logical-ID scope;
it cannot pair an arbitrary type with a strongly typed ID. Reference
collections are sorted during creation and decoding so their canonical
representation does not depend on caller or JSON order. All three dependency
groups reject a reference to the enclosing revision itself.

The v1 lifecycle vocabulary is deliberately limited to `draft` and
`published`. Supersession is represented by a new immutable revision and an
explicit active-revision pointer; this contract provides no in-place publish,
supersede, or update API.

## Hash domains

Two hash domains are explicit:

- `SourceAssetV1.source_content_hash` is the digest of authoritative source
  bytes;
- `RevisionEnvelope.semantic_content_hash` is the digest of canonical semantic
  revision content with the digest field itself omitted.

Every concrete Task 003A/003B semantic object calculates native SHA-256 over a
frozen canonical semantic projection. Whenever a stored semantic hash is
present, the concrete object validates it against the calculated value. A
published revision requires a matching hash, publication timestamp, and valid
validation state. Frozen-digest tests cover `SourceAssetV1`, `EvidenceRefV1`,
and all six Task 003B input objects.

The SourceAsset projection contains object type, schema, classification, exact
dependency sets, meeting context, source/origin metadata, source-byte digest,
MIME type, size, language, acquisition metadata, retention, and optional media
provenance. It omits revision identity/lifecycle/publication/generation fields,
the hash itself, and the relocatable managed-storage identifier. The
EvidenceRef projection contains object type, schema, classification, exact
dependency sets, typed location/source, required excerpt metadata, and
confidence; it omits the same envelope lifecycle/provenance fields and the hash
itself. Frozen digest tests detect projection drift.

## SourceAsset.v1

`SourceAssetV1` binds one immutable source revision to a meeting, asset and
origin kinds, optional structurally safe HTTPS source reference, opaque
managed-storage reference, source-byte digest, MIME type, byte size, language,
acquisition metadata, retention class, and optional media provenance.

The storage reference contains only a typed UUID that the Storage Service
resolves. It cannot represent an absolute path, relative path, home
expansion, file URL, or traversal string. HTTPS validation is structural only;
domain allowlists, redirects, content limits, and SSRF defenses remain the
responsibility of the later network-source adapter.

Local imports, authorized captures, generated assets, and approved HTTPS
downloads require an opaque managed-storage reference. For downloaded content,
the URL remains provenance while the managed copy and source-byte digest keep
exact evidence recoverable. Media provenance is optional at initial intake and
may be attached only when inspection has produced real values; placeholders
are not required.

## EvidenceRef.v1

`EvidenceRefV1` has its own immutable revision envelope. Every tagged
`EvidenceLocation` case contains its exact `SemanticRevisionReference`, so a
locator and source cannot drift apart. Its union supports:

```text
transcript_segment
document_location
media_time_range
user_confirmed_note
meeting_metadata
semantic_object_revision
official_statement
```

Text positions use half-open UTF-8 byte ranges, media positions use integer
milliseconds, and document page/paragraph numbers are one-based. The evidence
kind is derived from the union case and is never a second independently
mutable field. Unknown future union discriminators are rejected because v1
cannot interpret their payload safely.

Transcript and note locations require matching transcript/note revision types;
meeting metadata requires a meeting revision; document, media, and official
statement locations require a SourceAsset revision; a generic semantic-object
location accepts any known semantic object type. Excerpt text, language, and
translation status form one required value and are preserved as untrusted data
without instruction handling or Unicode rewriting. JSON Pointer escapes are
validated. Cross-object validation that an evidence classification is at least
as restrictive as its resolved source requires loading that revision and is
intentionally deferred to a later application/persistence service.

## Generation provenance

`GenerationMetadata` records provider/model/client identity, sorted exact
prompt or generator module versions, output schema version, template version,
generation time, and a local-only or approved-cloud privacy route. Exact input
object revisions remain in the enclosing revision envelope, avoiding a second
independently mutable input list. The recorded output schema must match the
enclosing revision schema. Identifiers are bounded opaque values and cannot be
filesystem paths; credentials and provider SDK types are not part of the
domain contract.

## Task 003B input-side contracts

`MeetingProfileV1` provides AI-independent meeting intake: bounded meeting
metadata, typed resolved or unresolved organization identity, deterministic
agenda ordering, source/output languages, priority actors, a meeting-level
cloud-processing policy, and explicit review/user-confirmation state. The
relocatable workspace identifier is operational context and is deliberately
outside the semantic hash.

`TranscriptSegmentV1` preserves exact bounded source text, integer media time,
detected language, confidence, review state, and a tagged provenance path to
one exact SourceAsset revision. Original-speaker audio, simultaneous
interpretation, translated audio, and explicitly unknown tracks are different
cases; only the first can report `isOriginalVerbatim`.

`TranslationSegmentV1` preserves translated text beside its exact source
transcript revision and the SHA-256 of the source transcript's unmodified UTF-8
bytes. Machine, human, interpretation-related, and user-edited translations
remain typed. Machine output requires provider-neutral generation provenance;
a user edit must supersede and retain the exact prior translation revision as
an input.

`ActorV1` keeps identity separate from meeting capacity. Its closed identity
union represents people, countries, international organizations, formal
groups, UN organs, the UN Secretariat, unidentified participants, and other
explicit identities without coercing non-country actors into country fields.
`SpeakingCapacityV1` then binds one exact speaker Actor revision to explicit
representation relationships and a meeting role. `SpeakerAssignmentV1` binds
exact transcript, Actor, capacity, and evidence revisions. Uncertain
assignments must remain unconfirmed and in `needs_review`; confirmed
assignments require a user-created, explicitly confirmed revision.

`InputContractGraphValidation` performs pure checks that need resolved objects:
exact-reference matching, meeting consistency, source-track kind and time
bounds, source-text digest and language matching, actor/capacity consistency,
and fail-closed classification inheritance. Classification checks require a
validated `ResolvedDependencyClassification` for every exact envelope input,
source-asset, and evidence revision; a missing dependency fails rather than
silently lowering the result. The type-erased view is ephemeral validator
input, not a persisted semantic object. These checks perform no I/O and are not
a persistence or provider service.

## Active revision and deterministic stale planning

`ActivePublishedRevisionSelection` is a storage-neutral explicit pointer. The
selector accepts exactly one matching concrete revision and requires that
revision to be published, valid, and protected by its verified semantic hash.
List order and timestamps never imply active state. A previously published
revision may be reactivated; `supersedes_revision_id` records immutable edit
lineage rather than every pointer move.

`DependencyEdge` records exact upstream and downstream revision references and
whether the relationship came from the input, source-asset, or evidence group.
Tagged invalidation reasons retain the exact replaced or invalidated root.
`DeterministicStalePlanner` is a side-effect-free planner: it validates an
acyclic, duplicate-free graph, walks the transitive dependency closure in
stable order, emits each affected revision once with a causal path and an
explicit handling action, and rejects a replacement that depends on what it
replaces. Initial publication and idempotent reselection produce an empty plan.
Task 004A now persists pointer changes, exact dependency edges, stale events,
and current stale state atomically. The planner remains pure; recomputation and
the full invalidation executor belong to later tasks.

## Task 004A persistence realization

`MeetingBuddyApplication` defines storage-neutral repository, workspace,
storage, managed-file, active-state, and recovery ports. It depends only on the
domain module and exposes neither SQL/GRDB records nor an unrestricted
workspace layout to providers.

`MeetingBuddyPersistence` stores each supported concrete object as the exact
validated canonical JSON bytes plus a separate SHA-256 of those bytes and
indexed envelope metadata. The persistence digest is intentionally distinct
from `semantic_content_hash`: the latter verifies semantic meaning under
each object's frozen projection, while the former detects any stored-payload
byte change. Fetch revalidates the digest, canonical bytes, concrete object,
and normalized metadata.

Insertion is byte-idempotent and append-only. Reusing a revision ID for
different bytes fails. SQL triggers reject revision and dependency update or
deletion. Dependencies are derived from the envelope rather than accepted as a
caller-supplied graph. Exact unresolved dependencies are permitted only for a
non-valid draft, which safely accommodates the accepted
`user_confirmed_note` evidence location before a concrete note contract exists;
valid, published, and active revisions require every upstream revision to be
resolved.

The active-pointer repository enforces one row per object type/logical ID,
requires a current published/valid/hash-verified exact revision, and uses an
expected-current compare-and-set. Pointer event, pointer move, deterministic
stale marks, and currency-state writes share one SQLite transaction. Historical
revision payloads remain unchanged, and stale active state is returned
explicitly rather than silently presented as current.

Managed source files remain outside SQLite. A `SourceAssetV1` with an opaque
storage reference can be persisted only when active managed metadata matches
its meeting, byte hash, byte size, classification, and retention. SQLite stores
only that metadata and canonical semantic payloads, never source-file bytes.

## Task 003B Golden fixtures

The test target contains exactly five minimal, project-authored synthetic
fixtures: ordinary delegation intervention, reservation/qualification,
uncertain speaker, interpretation versus original, and prepared China wording
versus delivered wording. Every fixture declares synthetic ownership,
third-party-source absence, reuse status, human-review status, and the limits of
its simulated source descriptor. They contain no real meeting, person, media,
license, or provider claim. Expected observations are limited to direct source
text/provenance assertions; the China fixture explicitly forbids inferring a
real-world attribution or policy change.

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

Each implemented contract provides deterministic validation, canonical
serialization, round-trip tests, and an explicit strategy for unknown future
enum values. Invalid provider output must not be imported by filling missing or
unsupported claims.

Open string vocabularies decode an unknown raw value as
`unrecognized(rawValue)` when inspected independently, so it is not confused
with a known case. Validated composite decoding rejects unknown object type,
lifecycle, validation, classification, hash, origin, acquisition, retention,
speech-source, translation, or privacy-route semantics. Unknown classification
ranks above `restricted`, so standalone aggregation fails closed. The known
speech-source value `unknown` remains distinct from an unrecognized future raw
value.

`CanonicalJSON` defines the project-specific v1 profile:

- UTF-8 JSON with sorted keys and no pretty printing;
- explicit snake_case coding keys;
- lowercase UUID and hexadecimal strings;
- integer epoch milliseconds, byte offsets, durations, sizes, and confidence
  millionths rather than floating-point wire values;
- omitted optional values and stably sorted reference collections.

This is a constrained deterministic schema profile, not a claim of general
RFC 8785 conformance. `CanonicalJSON.decodeValidated` is the public import
entry point; the unchecked generic decoder is module-internal. Every public
`Decodable` path for a validated scalar or composite runs its invariants, so a
caller using `JSONDecoder` directly also cannot create an invalid domain
object. Unknown additive object fields are ignored, but missing required
fields, malformed structure, unknown closed union cases, and unsupported v1
composite semantics fail deterministically.

Compatibility promises are introduced only when backed by real supported
versions and tests; the domain-contract tasks do not build a speculative
general migration framework.

## Implementation status

Tasks 003A, 003B, and 004A are accepted. Task 004A realizes their persistence
contract behind separate application and concrete SQLite/filesystem modules.
There is still no application executable,
Task Manager, media conversion, provider call, UI, stale recomputation
executor, or briefing analysis.
