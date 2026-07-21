# Historical Review and Learned Preferences

Status: Accepted
Owner: User and Codex
Last updated: 2026-07-21

## Boundary

Meeting History is a local, deterministic review surface over exact published
semantic revisions. It is not general AI memory, relationship-graph inference,
organization synchronization, or an authority to read mail or fetch public
content. Search and comparison add no provider, model, credential, subprocess,
or outbound-network route.

The implementation has three independent state classes:

1. immutable authoritative semantic revisions, including
   `HistoricalComparison.v1`;
2. a generation-stamped, disposable local history index rebuilt from
   authoritative revisions;
3. explicit user-created learned-preference records plus immutable audit
   events.

Deleting or rebuilding the index never deletes a meeting, Position, Evidence,
or comparison revision. Resetting preferences removes every effective
preference value; bounded audit metadata remains visible as audit history and
does not apply a preference.

## Deterministic retrieval

The initial query contract supports actor/country, organization, topic, meeting
body, meeting type, date range, issue, review status, classification ceiling,
and keyset cursor fields. Text normalization is fixed at version 1: POSIX case
and diacritic folding plus whitespace normalization. Matching is lexical and
deterministic; it is not embedding, fuzzy-identity, or political inference.

Only active, current, valid, published, user-confirmed `Position.v1` revisions
enter a generation. Every row retains exact Position, Meeting, Actor, Issue,
SensitivityLabel, AccessPolicy, and Evidence revision IDs. Meeting type is
indexed only when the Meeting cites an exact `MeetingTemplate.v1` revision; it
is never guessed from free text.

Before returning each result, the repository rehydrates the authoritative
bytes and rechecks:

- the exact Position, Meeting, Actor, Issue, SensitivityLabel, AccessPolicy,
  and every Evidence revision are active/current;
- both security objects form a valid graph with the exact Meeting;
- local processing and manual local review are allowed;
- no-outbound mode is required and external processing is denied;
- the most restrictive classification across every returned semantic object
  does not exceed the requested classification ceiling;
- every exact Evidence revision is present and matches the Position envelope.

An unauthorized or stale row contributes no content, result count, or facet.
The stable order is effective date descending, media-relative start descending,
then Position revision ID descending. Repeating the same query against the same
generation produces the same ordered revision IDs. Every keyset cursor is bound
to that generation; a rebuild makes an older cursor fail instead of silently
mixing results from two generations.

Index rebuild is a restricted, local-only Task Manager job. It builds a new
generation transactionally, checks cancellation between candidates, then
switches the singleton generation pointer. Cancellation or failure leaves the
previous authoritative revisions unchanged. Semantic/pointer/stale writes mark
the index dirty. The index can be disabled and later rebuilt.

## Evidence admission

Historical evidence from a document, permitted email import, or permitted
public source must already exist as an exact valid published `SourceAsset.v1`
revision. The admission descriptor binds source kind, revision ID, SHA-256
content hash, byte size, acquisition time, and remote-resource posture.

- Versioned documents require a user-selected local managed copy and disabled
  remote resources.
- Permitted email evidence requires the same bounded local-import shape, no
  source URL, and disabled remote resources.
- Permitted public evidence requires an approved HTTPS-download SourceAsset
  with its retained exact source URL and managed copy.

This contract grants no filesystem, mailbox, browser, or network authority.
Task 010 does not add an email connector or a public-source fetcher. Source
content remains untrusted data and cannot become instructions.

## Comparison semantics

`HistoricalComparison.v1` stores both exact Position, Meeting, Actor, Issue,
SensitivityLabel, AccessPolicy, and Evidence trails, both effective dates and
media-relative effective ranges, and both confidence scores. Source Position
revisions remain immutable.

| Evidence result | Stored state | Permitted language |
| --- | --- | --- |
| Missing qualification, identity/topic closure, exact evidence, or ordered dates | `insufficient_evidence` | Insufficient exact published evidence |
| Same structured position and same wording | `no_confirmed_difference` | Repeated position; no change confirmed |
| Same structured position with different wording | `no_confirmed_difference` | Wording differs; policy change is not established |
| Different structured type, conditions, or reservations | `possible_difference` | Possible change pending user review |
| Added structured reservation | `possible_difference` | Possible new reservation pending user review |
| User accepts a possible difference | `user_confirmed_difference` | User-confirmed change in a superseding revision |

Silence, wording strength alone, or formal group membership never establishes a
position or policy change. Automatic code cannot create a confirmed-change
revision. Confirmation is allowed only for a `possible_difference` candidate
and creates a user-authored published revision that supersedes and cites the
exact candidate.

## Learned Preferences

The closed first-version vocabulary is:

- actor/country order;
- briefing length;
- section order;
- quotation policy;
- grouping;
- terminology;
- frequent templates.

Every value originates in an explicit UI action and records a bounded source
action, creation/update time, version, enabled state, type, and canonical
value. Optimistic versions prevent silent lost updates. Users can inspect,
edit, enable/disable, remove, globally disable, or visibly confirm Reset All.
Disabled values remain visible and editable but are not effective.

Preferences may affect presentation only. They never alter access policy,
classification, no-outbound mode, evidence requirements, model/provider
routing, confirmation rules, protected diplomatic wording, or semantic source
truth. Immutable events record lifecycle action and digests, not raw preference
payloads; their recent action/source/time/digest metadata is inspectable in the
UI. Reset removes all effective rows, restores the default global-enable
setting, and appends a content-free reset event; audit metadata is not an
effective or hidden preference.

## Schema, recovery, and rollback

Schema v10 performs the ordered v9-to-v10 migration. It expands the closed
semantic-object vocabulary for `historical_comparison`, preserves every prior
canonical payload and digest byte-for-byte, and adds:

- `historical_index_state`;
- `historical_position_index`;
- `historical_topic_terms`;
- `historical_evidence_index`;
- `learned_preference_settings`;
- `learned_preferences`;
- `learned_preference_events`.

The standard verified online pre-migration backup is the rollback anchor. A
v9 backup contains no Task 010 tables and reopens as schema v9 with its exact
semantic bytes. Migration creates no fabricated comparison, index, or
preference row. Recovery serialization recognizes
`HistoricalComparison.v1`; derived index rows remain rebuildable.

## Known limits

- Search is lexical, not semantic or fuzzy identity resolution.
- Country equivalence uses exact normalized country codes; topic equivalence
  uses an exact logical Issue ID or exact normalized title.
- There is no principal/enterprise ACL model, organization sync, full
  relationship-graph UI, hidden memory, automatic policy-change claim,
  named-speaker identification, or real-time coaching.
- Preference reset is logical application reset, not a claim of forensic SSD
  erasure; database backups follow the documented retention lifecycle.
- Manual VoiceOver, localization, clean-machine, Developer ID, notarization,
  and release testing remain Task 011 evidence.
