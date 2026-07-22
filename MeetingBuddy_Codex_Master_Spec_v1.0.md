# MeetingBuddy — Codex Master Build Specification

**Version:** 1.1 (stable filename retained)
**Status:** Final build specification  
**Date:** 2026-07-22
**Primary audience:** Codex and human reviewers  
**Current authorized action:** Read `docs/CODEX_EXECUTION_STATE.md`; this
specification does not authorize a task by itself. Tasks 001 through 011 are
accepted, the canonical MVP sequence is complete, and there is no next eligible
numbered task. Post-MVP work and any commit, push, tag, notarization, release,
upload, install, or distribution action require separate explicit authority.

---

## 0. How Codex Must Use This Document

This document is the authoritative product, architecture, security, and delivery specification for MeetingBuddy.

It is **not** authorization to implement the entire product in one pass.

Codex must:

1. obey the current task scope and stop condition;
2. preserve existing user data and functioning code;
3. distinguish observed repository facts from this target architecture;
4. make small, reviewable, tested changes only after the audit is accepted;
5. stop at each milestone boundary and wait for explicit authorization before proceeding;
6. never claim a feature is complete until its applicable acceptance criteria and quality gates pass.

### 0.1 Instruction priority

When instructions conflict, use this order:

1. data integrity, privacy, security, and non-destructive behavior;
2. the explicit scope and stop condition of the current task;
3. user-approved Architecture Decision Records that apply to the exact issue;
4. this master specification;
5. repository-level `AGENTS.md` operational instructions, provided they do not contradict items 1–4;
6. existing implementation conventions;
7. optional examples and suggestions.

If a conflict remains, report it rather than silently choosing a destructive or irreversible path.

### 0.2 Current execution gate

Section 87 records the historical Task 001 bootstrap contract. Current task
status comes only from `docs/CODEX_EXECUTION_STATE.md`, reconciled with Git and
the user's latest explicit authorization. The one-time post-005A roadmap
integration was planning-only: it did not itself start Task 005B, implement
application features, run migrations, add dependencies, or authorize a commit.
Tasks 005B through 011 were later authorized and accepted individually. The
numbered MVP sequence is now complete; deferred capabilities receive a new task
ID only after explicit user promotion.

### 0.3 Recommended Codex model settings

For this project:

- **Repository audit, architecture, security model, schema design, concurrency, migrations, and major refactors:** GPT-5.6 Sol with **max** effort.
- **Bounded implementation tasks with clear acceptance tests:** GPT-5.6 Sol with **high** effort.
- **Mechanical edits, formatting, isolated tests, and documentation cleanup:** GPT-5.6 Sol with **medium** effort.
- **Ultra:** use only for an explicitly authorized, repository-wide task that has multiple genuinely independent workstreams, such as a final release audit or parallelized hardening review. Do not use Ultra as the default implementation mode.

If only one setting is available for the initial work, use **GPT-5.6 Sol — max effort**.

---

# Part I — Product Constitution

## 1. Product mission

Build MeetingBuddy, a native macOS application for diplomats, United Nations delegates, policy researchers, government officials, and other professional meeting users.

MeetingBuddy is not primarily a recorder or transcription application.

Its purpose is to transform live or recorded meetings and related documents into:

- reliable, timestamped transcripts;
- translated records that preserve their relationship to the source language;
- speaker-, actor-, and delegation-level intervention summaries;
- structured diplomatic positions;
- evidence-linked briefing sections;
- reviewable Chinese-language briefings;
- reusable, versioned historical meeting knowledge.

The core principle is:

> Transcription captures what was said. MeetingBuddy explains what matters, while preserving the evidence needed to verify that explanation.

The application must prioritize, in order:

1. diplomatic accuracy;
2. evidence traceability;
3. user control;
4. privacy and data-routing transparency;
5. professional briefing quality;
6. reproducibility;
7. modular AI workflows;
8. long-term maintainability;
9. strict storage discipline;
10. safe automation.

## 2. Primary user scenario

A professional user may:

- prepare for a meeting using agendas, statements, resolutions, letters, and background documents;
- attend a meeting in person;
- listen to a live meeting through UN Web TV;
- process a UN Web TV recording after the meeting;
- import a local audio or video file;
- analyze documents when no recording exists;
- review a two- or three-hour meeting without listening continuously;
- generate a structured Chinese briefing;
- inspect evidence for every material conclusion;
- correct speakers, delegations, translations, and analysis;
- compare confirmed positions with prior meetings;
- preserve reviewed results for future retrieval.

## 3. Product positioning and non-goals

MeetingBuddy must not become:

- a generic note-taking application;
- a ChatGPT wrapper;
- a simple audio recorder;
- a generic meeting-summary tool;
- a fully autonomous political-analysis system;
- an opaque AI knowledge graph;
- an Electron, browser-shell, or generic cross-platform desktop interface;
- a system that silently invents historical memory;
- a system that treats model output as verified fact;
- a system that silently sends sensitive material to cloud providers.

The application interface must be in English.

Meeting content language and output language must be configurable independently. The initial primary briefing output language is Chinese, while source material may be in any supported UN language.

## 4. Final product standard

MeetingBuddy succeeds only if it can process a long diplomatic meeting and produce a briefing that is:

- accurate;
- restrained;
- specific;
- evidence-linked;
- editable;
- reproducible;
- understandable;
- professionally useful;
- model-independent where reasonably possible;
- safe to archive;
- maintainable over many years.

It must remain useful when:

- the transcription model changes;
- the language model changes;
- a provider becomes unavailable;
- the database schema evolves;
- UN Web TV changes its page structure;
- the user switches between local, API, and subscription-backed providers;
- the user disables all cloud AI providers;
- historical data grows substantially.

Architecture and data integrity take priority over short-term demonstrations.

### 4.1 Local-first product boundary

Meeting audio, transcripts, meeting metadata, and derived intelligence remain
on the device by default. Any external processing path must identify the exact
data categories, destination, permitted provider, retention behavior, policy
authority, and visible user authorization before transmission. Every supported
workflow must retain a local/offline or no-external-processing mode; provider
availability never creates transmission authority.

---

# Part II — Technology and Architecture Decisions

## 5. Required implementation language and native stack

### 5.1 Primary language

The production application must be written primarily in **Swift 6 language mode**.

The shipped macOS app must not depend on a bundled Python runtime, Node.js runtime, Electron, Tauri, or a browser-based UI shell.

Python may be used for developer-only fixtures, evaluation utilities, or one-off data preparation, but it must not become a required production runtime.

Rust, C, or C++ may be used only behind a narrow adapter when a mature media or local-model library requires it. Such code must not leak into the domain layer.

### 5.2 UI framework

Use:

- **SwiftUI** for the primary application structure and screens;
- **AppKit bridges** where SwiftUI lacks required macOS behavior;
- native macOS menus, commands, inspectors, sheets, accessibility, keyboard navigation, drag and drop, and file panels.

Do not imitate Windows desktop applications or generic web dashboards.

### 5.3 Platform APIs

Prefer Apple platform APIs:

- `AVFoundation` for media import, inspection, conversion, timing, and playback;
- `ScreenCaptureKit` for authorized application/system audio capture where supported;
- Swift Concurrency (`async/await`, actors, task groups) for concurrency;
- `OSLog`/`Logger` for redacted diagnostic logging;
- Keychain Services for credentials and secrets;
- Uniform Type Identifiers for file handling;
- native sandbox, signing, entitlements, and permission APIs.

A third-party tool such as FFmpeg or a local transcription runtime may be introduced only through an ADR that records purpose, size, licensing, update strategy, security boundary, and removal strategy.

### 5.4 Persistence

Use SQLite as the initial authoritative metadata and semantic-object database.

Preferred implementation:

- a repository/service boundary over SQLite;
- GRDB or an existing mature SQLite layer found during the audit;
- explicit migrations;
- WAL mode;
- controlled checkpoints;
- stable UUIDs;
- large media stored as files rather than database BLOBs.

Do not expose database tables as the public domain or AI schema.

Do not use SwiftData or Core Data objects as semantic contracts. They may only be considered as internal persistence mechanisms if an ADR demonstrates that they meet versioning, migration, audit, and recovery requirements.

### 5.5 Package and build system

Use:

- Xcode;
- Swift Package Manager;
- a native macOS application target;
- Swift Testing and/or XCTest;
- deterministic build and test commands documented in the repository.

Do not introduce CocoaPods or another package manager unless the existing repository already requires it and the audit justifies preserving it.

### 5.6 Deployment target

Recommended default:

- macOS 15 or later;
- Apple Silicon as the primary supported architecture.

The final deployment target must be confirmed through an ADR after the repository audit, based on required capture APIs, local-model support, distribution strategy, and actual user hardware requirements.

### 5.7 Architecture style

Use a **modular monolith**.

Do not create microservices, a local distributed system, or one package per type.

A reasonable initial module boundary is:

```text
MeetingBuddyApp
MeetingBuddyDomain
MeetingBuddyPersistence
MeetingBuddyTasks
MeetingBuddyMedia
MeetingBuddyAI
MeetingBuddyAutomation
MeetingBuddyFeatures
MeetingBuddyTestSupport
```

The audit may recommend fewer modules if the repository is small. Module boundaries must follow dependency direction, not aesthetics.

Domain code must not depend on UI, SQLite, provider SDKs, or filesystem paths.

---

# Part III — Product Modes and Workflow

## 6. Official work modes

The final product must support six formal work modes.

### 6.1 In-room meeting

Capture authorized external audio, microphone input, floor audio, or a user-selected mix during a physical meeting.

### 6.2 Live web meeting

Capture authorized audio from Safari, Chrome, or another selected application while a meeting is streaming. The user must choose the source; the app must not silently record all system sound.

### 6.3 Recorded web meeting

The user pastes a supported UN Web TV page URL. MeetingBuddy attempts to retrieve meeting metadata and permitted media or language tracks, then processes the recording without real-time playback.

### 6.4 Local recording

Import local media such as MP4, MOV, M4A, MP3, WAV, and other formats supported by the selected media stack.

### 6.5 Document-only analysis

Create a meeting record from agendas, statements, resolutions, notes, and related documents when no audio or video is available.

### 6.6 Historical review

Retrieve and compare previously published and confirmed meeting records and delegation positions.

## 7. Main entry points

The principal user actions should be:

- **Start Live Meeting**
- **Process Recording**
- **Analyze Documents**
- **Review History**

`Process Recording` should support:

- UN Web TV link;
- local video or audio file;
- an authorized captured recording.

The recorded-meeting workflow is the first end-to-end product priority.

## 8. Processing workflow must be a conditional DAG

Do not implement one rigid twelve-step linear pipeline.

Use a versioned, conditional directed acyclic graph with four groups.

### 8.1 Source ingestion

```text
Meeting Intake
  → Source Acquisition
  → Media Canonicalization or Document Parsing
  → Transcription, when applicable
  → Translation, when applicable
```

### 8.2 Meeting understanding

```text
Speaker and Actor Assignment
  → Intervention Extraction
  → Delegation Position Creation
  → Issue-Position Structuring
```

### 8.3 Briefing production

```text
Briefing Section Generation
  → Validation
  → Final Assembly
  → Export
```

### 8.4 Knowledge publication and retrieval

```text
Archive Publication
  → Search Index Update
  → Historical Retrieval
  → Historical Comparison
```

Historical comparison is primarily a query workflow over published objects, not a mandatory step in every meeting-processing job.

### 8.5 Node states

Every processing node must support the states:

```text
pending
ready
running
paused
succeeded
failed
skipped
not_applicable
stale
invalidated
cancelled
```

Every node must:

- have one clear responsibility;
- declare exact input revision IDs;
- declare output schema versions;
- be independently rerunnable;
- be idempotent where practical;
- support safe cancellation;
- support recovery where applicable;
- record provider, model, rules, prompt versions, and timing;
- never silently modify upstream objects.

---

# Part IV — Semantic Object Layer

## 9. Semantic object rules

The Semantic Object Layer is the stable contract between:

- persistence;
- application services;
- UI features;
- AI providers;
- prompts;
- automation commands;
- CLI and MCP adapters;
- tests and evaluations.

AI providers must not directly consume:

- SQLite tables;
- arbitrary database rows;
- raw internal IDs without context;
- arbitrary filesystem paths;
- mutable temporary JSON;
- undocumented application state;
- the entire workspace when only a bounded subset is needed.

AI providers may consume only explicit, versioned semantic input packages.

## 10. Common immutable revision envelope

Every semantic object must use a common revision model.

A logical object may have many revisions, but exactly one revision may be the active published revision at a time.

Recommended common fields:

```text
logical_id
revision_id
object_type
schema_version
lifecycle_status
validation_status
created_at
created_by
published_at
supersedes_revision_id
input_revision_ids
source_asset_revision_ids
evidence_refs
data_classification
provider_metadata
content_hash
```

### 10.1 Lifecycle rules

- A persisted revision is immutable.
- Editing creates a new revision.
- Publication changes the active-revision pointer; it does not overwrite an earlier revision.
- Superseded revisions remain auditable according to retention policy.
- Downstream objects must reference exact revision IDs, not only logical IDs.
- Deleting a user-visible logical object normally moves it to Workspace Trash; it does not silently erase audit history.

### 10.2 Canonical meaning

`Canonical` means one active authoritative revision, not one physical copy with no history.

Examples:

- one active canonical audio asset revision;
- one active published transcript revision set;
- one active speaker assignment set;
- one active published intervention-card revision;
- one active delegation-position revision;
- one active briefing draft assembled from exact section revisions.

## 11. Required initial semantic objects

The first contract milestone must define and test the following objects in this order:

1. `SourceAsset.v1`
2. `EvidenceRef.v1`
3. `MeetingProfile.v1`
4. `TranscriptSegment.v1`
5. `TranslationSegment.v1`
6. `Actor.v1`
7. `SpeakingCapacity.v1`
8. `SpeakerAssignment.v1`
9. `InterventionCard.v1`
10. `DelegationPositionCard.v1`
11. `IssuePositionGraph.v1`
12. `BriefingSection.v1`
13. `ValidationReport.v1`
14. `FinalBriefing.v1`
15. `HistoricalComparison.v1`

`CountryCard` may remain a user-facing label or specialized view, but the underlying domain object must support countries, organizations, the UN Secretariat, chairs, experts, observers, and representatives speaking on behalf of groups.

## 12. SourceAsset.v1

Purpose: represent every imported or acquired source.

Required fields should include:

```text
asset_id
revision_id
meeting_id
asset_type
origin_type
source_url
local_storage_reference
content_hash
mime_type
byte_size
language
acquisition_method
acquired_at
retention_class
data_classification
```

Media-specific fields may include:

```text
duration
container_format
codec
sample_rate
channel_layout
language_track
speech_source_kind
canonical_timeline_reference
```

`speech_source_kind` must distinguish:

```text
original_speaker_audio
simultaneous_interpretation
translated_audio_track
unknown
```

An interpretation transcript must never be labeled as a verbatim original statement.

## 13. EvidenceRef.v1

All substantive conclusions must use one typed evidence system.

Evidence kinds:

```text
transcript_segment
document_location
media_time_range
user_confirmed_note
meeting_metadata
semantic_object_revision
official_statement
```

Required fields:

```text
evidence_id
evidence_kind
source_logical_id
source_revision_id
location_or_time_range
excerpt
excerpt_language
translation_status
confidence
classification
```

Evidence must reference an exact revision and location. A bare filename, logical object ID, or database row ID is insufficient.

## 14. MeetingProfile.v1

Purpose: deterministic meeting intake and configuration.

Suggested fields:

```text
meeting_id
title
meeting_number
meeting_date
organization_or_un_body
agenda_items
source_asset_ids
source_languages
output_language
priority_actors
briefing_template_id
cloud_processing_policy
workspace_reference
review_status
```

AI must not be required merely to create a meeting record.

## 15. TranscriptSegment.v1

Purpose: timestamped source-language text only.

Required fields:

```text
segment_id
revision_id
meeting_id
source_asset_revision_id
start_time
end_time
detected_language
text
confidence
speech_source_kind
transcription_provider
model
model_version
created_at
```

A transcript segment must not summarize, infer diplomatic intent, group countries, compare policy positions, or write briefing prose.

The transcript lineage must also preserve, directly or through exact immutable
references:

```text
stable segment and meeting identity
original machine transcript text
human-edited transcript revision and edit history
microphone, system-audio, or imported-source provenance
source audio revision and exact time range
ASR provider, model, version, and confidence
speaker-assignment revision and speaker confidence
evidence or content-integrity hash
```

Original ASR text is never destructively replaced. A correction creates a new
revision linked to the exact machine transcript revision. Speaker identity and
confidence remain separate speaker-assignment evidence, not an untraceable
string embedded in transcript text. Task 005B must choose a backward-compatible
representation and migration path before persisting production transcripts.

## 16. TranslationSegment.v1

Translation is a first-class stage and object.

Required fields:

```text
translation_id
revision_id
source_segment_revision_id
source_language
target_language
source_text_hash
translated_text
translation_type
provider
model
model_version
prompt_version
alignment_status
confidence
review_status
created_at
```

`translation_type` must distinguish:

```text
machine_translation
human_translation
simultaneous_interpretation_transcript
user_edited_translation
```

Rules:

- translation never overwrites source text;
- machine translation, human translation, and interpretation transcripts remain distinct;
- downstream analysis records which text form it used;
- user edits create a new translation revision;
- evidence displays the source text and translation relationship.

## 17. Actor.v1 and SpeakingCapacity.v1

`Actor` represents a person, country, organization, formal group, UN organ, expert, chair, observer, or other participant.

`SpeakingCapacity` represents how that actor speaks in a particular intervention.

Suggested fields:

```text
actor_id
actor_type
display_name
country_code
organization_id
person_name
canonical_aliases
```

```text
capacity_id
speaker_actor_id
represented_entity_ids
on_behalf_of_entity_ids
meeting_role
capacity_label
effective_time_range
```

Do not assume that a speaker's nationality is identical to the entity represented in an intervention.

Do not treat formal group membership as evidence of a shared position in the current meeting.

## 18. SpeakerAssignment.v1

Purpose: answer who is speaking and in what capacity.

Required fields:

```text
assignment_id
revision_id
meeting_id
transcript_segment_revision_ids
actor_id
speaking_capacity_id
confidence
evidence_refs
assignment_source
review_status
user_confirmed
```

Possible evidence sources include:

- official speaker list;
- programme;
- chair introduction;
- transcript context;
- visible nameplate or screen text;
- UN Web TV chapter data;
- known speaking order;
- user correction.

Low-confidence assignments must enter a review queue. They must not be treated as confirmed.

## 19. InterventionCard.v1

Purpose: structured analysis of one bounded intervention.

Suggested fields:

```text
intervention_id
revision_id
meeting_id
speaker_assignment_revision_id
time_range
intervention_type
short_summary
claims
requests
proposals
support
opposition
reservations
conditions
references
responses_to_other_actors
notable_wording
evidence_refs
confidence
review_status
```

Every substantive item must preserve its claim type and evidence.

The system must distinguish:

- what a delegation stated;
- what it supported;
- what it opposed;
- what it requested;
- what it qualified;
- what MeetingBuddy extracted;
- what MeetingBuddy inferred;
- what the user confirmed.

These categories must not be collapsed into generic prose.

## 20. DelegationPositionCard.v1

Purpose: represent one actor's or represented entity's position across the meeting.

Suggested fields:

```text
position_card_id
revision_id
meeting_id
represented_entity_id
speaking_capacity_ids
overall_position
key_arguments
requests
support
opposition
reservations
conditions
references
responses
notable_wording
possible_new_elements
evidence_refs
confidence
review_status
```

The object must not assert policy change merely because wording differs.

## 21. IssuePositionGraph.v1

Purpose: represent issues, proposals, actors, and positions in a reviewable structure.

The MVP must not introduce a graph database solely because the object is named a graph.

Use a versioned relational or JSON representation such as:

```text
Issue
Proposal
ActorPosition
PositionType
Qualification
Relationship
EvidenceRef
```

Initial output should support an issue–actor–position matrix and a derived visual view.

Position types may include:

```text
supports
opposes
requests
proposes
reserves_position
supports_with_conditions
opposes_with_qualification
no_stated_position
uncertain
```

Silence must not be converted into opposition or support.

## 22. BriefingSection.v1

Each briefing section is generated and managed independently.

Suggested fields:

```text
section_id
revision_id
meeting_id
section_type
section_order
title
content
input_revision_ids
evidence_map
prompt_module_versions
provider_metadata
validation_report_revision_id
manual_edit_status
locked
stale_reason
review_status
```

The user must be able to:

- enable or disable a section;
- reorder sections;
- set target length;
- choose priority actors;
- choose grouping mode;
- set evidence policy;
- regenerate one section;
- preserve manual edits;
- lock a section against AI changes.

A locked section must never be overwritten automatically. If its evidence changes, show that the section is stale and explain why.

## 23. ValidationReport.v1

Validation must combine:

- deterministic checks;
- schema checks;
- evidence checks;
- contradiction detection;
- optional independent model review.

A validation finding should include:

```text
finding_id
severity
finding_type
message
affected_object_revision_ids
evidence_refs
suggested_resolution
blocking
resolved_at
resolved_by
```

The same model must not simply be asked to rewrite its own answer and call that validation.

## 24. FinalBriefing.v1

The official draft must be assembled from exact, current section revisions.

Do not regenerate the entire briefing from the full transcript at final assembly.

Suggested fields:

```text
briefing_id
revision_id
meeting_id
template_revision_id
section_revision_ids
assembled_content
output_language
validation_status
manual_edit_status
export_records
```

## 25. HistoricalComparison.v1

Historical comparison may use only published, reviewable current and historical objects.

Findings must use qualified language such as:

- possible change;
- potentially stronger wording;
- possible new reservation;
- repeated position;
- no confirmed change;
- insufficient evidence.

The system must not automatically state that a country's policy changed.

## 25.1 Extended meeting-intelligence entities

The future semantic layer must represent these as independently addressable,
versioned entities rather than only headings or paragraphs inside a summary:

```text
Meeting
Participant
Organization
TranscriptSegment or Utterance
Issue
Position
Commitment
Decision
Evidence
SensitivityLabel
AccessPolicy
```

`MeetingProfile.v1` may realize Meeting, `EvidenceRef.v1` may realize Evidence,
and existing Actor/SpeakingCapacity contracts may provide identity foundations,
but later task specifications must add any missing independent contracts rather
than hiding them in free-form briefing prose.

A Commitment must be capable of retaining actor, recipient, content,
conditions, deadline, status, exact source evidence, confidence, and human-
confirmation state. A Position must retain actor, issue, content, effective
time, source, confidence, and an evidence-based comparison state rather than a
bare “changed” flag. Evidence must support transcript segments and audio time
ranges as well as documents, email, permitted public sources, and integrity
metadata. Task 006A owns the first typed Issue/Position/Commitment/Decision
foundation; Task 007 owns sensitivity/access-policy hardening; Task 010 owns
historical comparison semantics.

---

# Part V — Versioning, Dependencies, and Invalidation

## 26. Dependency graph

Every derived revision must record exact input revision IDs.

The system must maintain dependency edges sufficient to answer:

- which outputs depend on this revision;
- which outputs became stale after a correction;
- which outputs can be recomputed automatically;
- which user-edited or locked outputs require review rather than replacement.

Typical chain:

```text
SourceAsset
  → TranscriptSegment
  → TranslationSegment
  → SpeakerAssignment
  → InterventionCard
  → DelegationPositionCard
  → IssuePositionGraph
  → BriefingSection
  → FinalBriefing
```

## 27. Invalidation rules

When the active revision of an upstream object changes:

1. identify all downstream revisions that reference the superseded revision;
2. mark them `stale` with a machine-readable reason;
3. do not present stale objects as current validated results;
4. do not silently delete them;
5. offer a recomputation plan;
6. do not overwrite locked or manually edited sections;
7. show the user what evidence or input changed.

Examples:

- correcting a speaker may invalidate interventions, positions, and briefing sections;
- editing a translation may invalidate analysis that used that translation;
- changing a meeting's cloud policy does not rewrite past output, but may change allowed future providers;
- replacing source media invalidates all time-linked downstream objects unless timeline equivalence is verified.

## 28. Publication gates

A semantic object may be published only when:

- schema validation passes;
- required evidence exists;
- required upstream inputs are published or explicitly accepted as provisional;
- blocking validation findings are resolved;
- review-state requirements for the object type are met.

Invalid AI output must never be silently imported.

---

# Part VI — Evidence and Diplomatic Analysis Rules

## 29. Claim taxonomy

Every material claim must be classified as one of:

```text
source_fact
delegation_claim
meetingbuddy_extraction
meetingbuddy_inference
user_confirmed_conclusion
```

The UI and generated briefing must not blur these categories.

### Protected rules

The following rules are non-negotiable:

- never fabricate a national or organizational position;
- never convert silence into support or opposition;
- never present a delegation claim as objective fact;
- never infer policy change from wording variation alone;
- preserve reservations, qualifications, and conditions;
- distinguish fact, stated position, extraction, and analysis;
- mark uncertainty;
- require evidence for substantive conclusions;
- prioritize official documents over uncertain transcript text where appropriate;
- distinguish original wording from interpretation or translation;
- do not infer group alignment from formal membership alone.

## 30. Briefing language and style

Chinese briefing output must be:

- formal;
- restrained;
- specific;
- concise without omitting material qualifications;
- actor-explicit;
- evidence-backed;
- free from journalistic exaggeration;
- free from generic filler.

Use precise verbs such as:

- stated;
- emphasized;
- supported;
- opposed;
- requested;
- proposed;
- expressed reservations;
- conditioned support on;
- responded to.

Ceremonial material should normally be omitted unless it has substantive significance.

## 31. China statement comparison

The application must support comparing a prepared Chinese or English statement with delivered remarks.

The result must distinguish:

```text
prepared_wording
delivered_wording
omission
addition
paraphrase
ad_lib_remark
possible_substantive_change
editorial_or_oral_variation
uncertain_difference
```

Every difference must retain evidence and timestamps. The system must not infer a policy change without sufficient historical and contextual evidence.

---

# Part VII — Prompt and AI Provider Architecture

## 32. Prompt architecture

Do not use one giant prompt.

Use four layers:

### Layer 1 — Protected core rules

Immutable application rules such as the protected diplomatic rules in Section 29, privacy policy, evidence requirements, and prompt-injection isolation.

Ordinary users and AI automation cannot modify this layer.

### Layer 2 — Diplomatic writing rules

Formal Chinese style, actor attribution, treatment of uncertainty, omission of filler, and terminology policy.

### Layer 3 — Bounded task modules

Examples:

```text
document_extraction
speaker_identification
intervention_extraction
delegation_position_creation
position_grouping
china_statement_comparison
right_of_reply_analysis
briefing_overview
major_actors
assessment
historical_comparison
evidence_validation
```

Each module must have one bounded purpose, an input schema, an output schema, tests, and a compatible schema range.

### Layer 4 — Template and user preferences

Examples:

- section order;
- priority actors;
- target length;
- grouping mode;
- quotation policy;
- terminology preferences;
- section-specific instructions.

User preferences cannot override protected rules, privacy policy, or evidence requirements.

## 33. Structured AI outputs

AI modules must return structured output first.

Every generated object must record:

```text
provider
model
client_version
prompt_module_versions
output_schema_version
template_version
generation_time
input_object_revision_ids
privacy_route
```

Validate:

1. syntax;
2. schema;
3. enums and required fields;
4. evidence references;
5. semantic constraints;
6. allowed provider route;
7. output size and content limits.

Do not accept malformed or partially valid output by silently filling unsupported claims.

## 34. Separate inference providers from agent-control adapters

The architecture must distinguish:

### 34.1 Inference Provider

Used by MeetingBuddy to perform bounded transcription, translation, extraction, analysis, validation, or briefing generation.

### 34.2 Agent Control Adapter

Used by Codex, Claude Code, or another external agent to inspect or operate MeetingBuddy through validated commands.

These are separate trust boundaries. Do not reuse one interface for both.

## 35. Provider abstraction

Provider-facing business logic must use narrow application-owned interfaces for:

```text
authorized audio capture
speech-to-text
translation
summary, extraction, validation, and generation models
local models
organization-hosted models
approved cloud models
semantic and asset storage
operating-system secret storage
```

Storage and secret-storage interfaces are not inference providers, but they
follow the same dependency rule: concrete implementation details never enter
MeetingBuddy domain logic. Possible inference providers include:

```text
LocalTranscriptionProvider
LocalTranslationProvider
LocalLLMProvider
OpenAIAPIProvider
AnthropicAPIProvider
GeminiAPIProvider
OpenRouterProvider
CodexSubscriptionProvider
ClaudeCodeSubscriptionProvider
```

Each task module must declare:

```text
allowed_providers
minimum_capability
expected_input_size
output_schema
preferred_provider
fallback_provider
privacy_requirement
subscription_safe_batching
```

Provider selection must eventually be driven by MeetingBuddy's own evaluations rather than general reputation.

### 35.1 Model policy routing

An application-owned model-policy router decides which providers and models
are eligible. It evaluates at least:

```text
meeting sensitivity and access policy
offline or no-outbound-network mode
organization policy
deployment environment
permitted data destination and provider retention
visible user authorization
task capability and bounded data categories
```

A model dropdown is only a preference among already-eligible routes. It cannot
override policy. A denied or unavailable route fails closed and never falls
back to a less restrictive destination. Task 005B establishes the interface
and enforcement for transcription/translation; Tasks 006A/006B reuse it for
derived intelligence; Tasks 007 and 009B harden and extend it.

## 36. Subscription-backed providers

Official locally installed clients may be supported when technically and contractually appropriate.

They must be marked **Experimental** until reliability, privacy, and structured-output behavior are validated.

Do not:

- scrape cookies;
- extract OAuth credentials;
- imitate web clients;
- convert subscriptions into API keys;
- bypass official usage controls;
- depend on undocumented internal protocols.

A subscription provider must:

- detect whether the official client is installed;
- perform a bounded capability check;
- request explicit connection approval;
- create a restricted per-job directory;
- provide only required materials;
- require structured output;
- validate results;
- handle quota and login errors;
- support cancellation;
- clean temporary files;
- never read account credentials;
- never become the only production provider path.

Example job directory:

```text
Workspace/.tasks/<job-id>/
├── input/
├── instructions.md
├── schema.json
└── output/
```

Do not copy the entire workspace into an AI job.

## 37. Recursive-call prevention

Every AI job must record origin and recursion policy.

Example:

```text
origin = meetingbuddy
allow_recursive_meetingbuddy_calls = false
```

A subscription-provider job must not call MeetingBuddy's automation interface unless a separately reviewed workflow explicitly permits it.

---

# Part VIII — Security, Privacy, and Trust Boundaries

## 38. Data classification

Every source and derived object must have one of:

```text
public
internal
sensitive
restricted
```

Derived objects inherit the highest classification of their inputs unless an explicit, reviewed declassification action changes it.

A summary is not automatically less sensitive than its source.

## 39. Cloud-routing policy

Local processing is the default for every classification. An external route
exists only after an explicit architectural policy decision names a permitted
provider and the product can display the exact bounded categories, destination,
retention behavior, and authorizing policy. The user must visibly authorize
the route, and the same workflow must remain operable without that external
path.

A provider call is allowed only when all of the following permit it:

```text
task.allowed_providers
meeting.cloud_processing_policy
asset.data_classification
user.provider_policy
provider.data_policy
offline_or_no_outbound_mode
organization.policy
deployment.environment
destination_and_retention_policy
visible_user_authorization
```

Default policy:

- `public`: local by default; cloud requires an explicit approved route and
  visible user authorization;
- `internal`: cloud requires explicit meeting or workspace permission;
- `sensitive`: local by default; cloud requires explicit per-policy approval and clear disclosure;
- `restricted`: no external processing unless a separately defined institutional policy explicitly permits it.

The UI must display the processing route before a task starts and in task history.

## 40. Prompt-injection isolation

Imported documents, transcripts, web pages, metadata, subtitles, and media-derived text are untrusted source content.

Instructions found inside source material must never modify:

- application policy;
- protected prompt rules;
- tool permissions;
- provider routing;
- file access;
- automation behavior;
- deletion or upload decisions.

Source text must be passed to models as quoted or delimited data, not as trusted instructions.

## 41. Secrets and credentials

- Store API keys and tokens in macOS Keychain.
- Never write credentials to project files, logs, task directories, crash reports, or exports.
- Never read or reuse credentials belonging to another application.
- Redact sensitive values in diagnostic views.

## 42. Local API and automation security

A local HTTP API is not required for the first automation milestone.

If later justified:

- it is disabled by default;
- it binds only to loopback by default;
- it requires per-session authorization;
- remote network access requires explicit, high-risk confirmation;
- destructive commands require additional confirmation;
- all requests are validated and audited;
- paths are canonicalized and restricted to authorized roots;
- symbolic-link and path-traversal escapes are blocked.

## 43. External process security

Any external media or model executable must run through a restricted adapter with:

- explicit executable path;
- validated arguments;
- no shell interpolation;
- bounded working directory;
- bounded output size;
- timeout and cancellation;
- captured, redacted diagnostics;
- version detection;
- quarantine/signing checks where applicable.

## 44. Network source security

For supported web sources:

- use HTTPS;
- use an explicit domain allowlist;
- restrict redirects;
- validate content type and size;
- prevent access to local network or file URLs;
- do not bypass access controls;
- retain the source URL and acquisition method;
- provide a manual local-import fallback.

## 45. Distribution and entitlements

Before implementing recording and external-process features, create ADRs for:

- Mac App Store versus independently signed distribution;
- App Sandbox policy;
- microphone permission;
- screen and application-audio capture permission;
- file-access bookmarks;
- external executable policy;
- automatic updates;
- crash reporting and telemetry.

### 45.1 Privacy-preserving telemetry

Telemetry and third-party crash reporting are disabled by default unless a
later accepted ADR explicitly enables an opt-in route. Any future telemetry:

- contains no meeting audio, transcript, document, or derived-intelligence
  content;
- contains no API key, token, meeting title, filename, sensitive path, or
  identifiable meeting metadata;
- can be fully disabled and respects a no-outbound-network mode;
- documents destination, retention, operator, and user/organization control;
- may support an organization-controlled or self-hosted destination only after
  separate review.

Telemetry is never a prerequisite for normal application operation.

## 46. Encryption policy

Do not invent custom cryptography.

Credentials must use Keychain. Workspace-at-rest protection must be documented. If application-level encryption is required, it must be designed through a separate security ADR with key recovery, migration, backup, and corruption handling.

Sensitive local storage also requires minimum filesystem permissions,
controlled export, documented retention, secure deletion semantics appropriate
to the underlying storage, and redacted diagnostics. Signed and verified update
paths are a Task 011 release gate. Do not claim guaranteed physical erasure on
copy-on-write or flash storage without platform evidence.

---

# Part IX — Storage and Recovery

## 47. Authority model

Use the following authority model:

| Data | Authoritative representation |
|---|---|
| Original media and official documents | Workspace files with content hashes |
| Object revisions, active pointers, jobs, audit records | SQLite |
| Semantic-object recovery snapshots | Versioned JSONL or equivalent export |
| Search and vector indexes | Rebuildable derived data |
| Temporary chunks and transient model output | Temporary workspace only |
| Exported briefings | User-visible derived files linked to source revisions |

Do not claim the database can be reconstructed from arbitrary files unless a tested recovery manifest exists.

## 48. Recommended workspace

```text
MeetingBuddy/
├── Meetings/
│   └── <meeting-id>/
│       ├── assets/
│       ├── documents/
│       ├── exports/
│       └── manifests/
├── Models/
│   ├── Transcription/
│   ├── Translation/
│   ├── Embeddings/
│   └── LocalLLM/
├── Database/
│   └── meetingbuddy.sqlite
├── Indexes/
├── Backups/
├── Logs/
├── .tasks/
├── .temp/
└── .Trash/
```

Country and topic views should normally be indexes over semantic objects, not duplicated directory trees.

## 49. Storage classes

### Permanent user data

- meeting profiles;
- official documents;
- retained source media;
- transcripts;
- translations;
- notes;
- published semantic objects;
- final briefings;
- user-marked permanent versions.

Never delete automatically without a defined user retention rule.

### Rebuildable data

- search indexes;
- vector indexes;
- waveforms;
- parsed-document caches;
- generated previews.

The application must prove they can be rebuilt.

### Temporary data

- download fragments;
- audio chunks;
- processing inputs;
- transient AI outputs;
- temporary exports.

Temporary data must be owned by a job and cleaned on success, failure, cancellation, or recovery according to policy.

## 50. Storage discipline

Every storage location must define:

```text
owner
creator
deletor
maximum_size
rebuildable
user_visibility
cleanup_policy
migration_policy
classification_policy
```

The app must never grow indefinitely without explanation.

### 50.1 Logs

Use rotation and size limits.

Recommended defaults:

- general logs: approximately 14 days;
- crash diagnostics: approximately 30 days;
- no API keys;
- no complete sensitive meeting content by default;
- no unlimited raw provider stdout.

### 50.2 Workspace Trash

Deleted user objects normally move to `.Trash/` for 30 days, with restore and explicit empty actions.

### 50.3 Audio policy

Offer:

```text
keep_compressed_original
delete_after_verified_transcript
ask_for_each_meeting
```

Default: `keep_compressed_original`.

### 50.4 Transcript policy

Use a canonical structured transcript revision set as the source of truth. Markdown and plain text are derived renderings.

## 51. Recovery manifests

Create tested recovery artifacts such as:

```text
workspace_manifest.json
semantic_snapshot.jsonl
asset_hashes.json
migration_version.json
```

Recovery behavior must be tested before claiming that a workspace can reconstruct the database.

---

# Part X — Unified Task Manager

## 52. Central task system

All long-running operations must use one Task Manager, including:

- media acquisition;
- audio extraction;
- transcription;
- translation;
- document parsing;
- embedding;
- analysis;
- briefing generation;
- validation;
- export;
- index rebuild.

No feature may invent its own background-job system.

## 53. Job contract

A job should record:

```text
job_id
job_type
meeting_id
origin
requested_by
created_at
started_at
finished_at
state
progress
current_node
input_revision_ids
output_revision_ids
provider_metadata
privacy_route
retry_count
checkpoint
idempotency_key
temporary_directory
error_record
```

## 54. Task behavior

The Task Manager must support:

- creation;
- dependency scheduling;
- progress;
- pause and resume where technically valid;
- cancellation;
- retry by chunk or node;
- crash recovery;
- cleanup;
- error reporting;
- disk limits;
- provider-usage metadata;
- idempotency;
- stale-input detection before publication.

A task must verify that its input revisions are still current before publishing output.

## 55. Long-media rules

- Never require loading an entire multi-hour media file into memory.
- Preserve a canonical timeline.
- Process stable chunks with overlap rules documented.
- Track missing, corrupt, or failed ranges.
- Resume from the last verified checkpoint.
- Do not permanently retain redundant chunk copies after canonicalization and verification.

### 55.1 Reliable and recoverable recording

Any live recording implementation must persist incrementally while capture is
in progress. A complete meeting must never exist only in volatile memory until
the user stops recording.

The recording contract must define explicit capture, persistence, checkpoint,
interruption, recovery, incomplete, finalizing, completed, and failed states.
It must checkpoint recoverable media and metadata, detect abnormal termination,
recover or clearly mark incomplete recordings, handle microphone/system-audio
device disconnection, and preserve truthful missing ranges. Task 008A fixes the
technical/permission design; Task 008B implements it with crash, interruption,
device-loss, disk-full, and forced-termination tests. Real-time coaching or
response recommendations cannot precede this gate.

### 55.2 Long-transcript completeness

Transcription, chunk merging, hierarchical extraction, and summarization must
be deterministic and must prove coverage before publication:

- every expected core range and source segment has exactly one accounted-for
  outcome;
- physical overlap is bounded, documented, and never double-counted as new
  source content;
- missing, failed, empty/no-speech, and retried ranges remain explicit;
- processing makes measurable forward progress and cannot loop silently;
- the coverage union equals 100 percent of the eligible source timeline or
  segment set;
- inability to prove coverage is a blocking failure;
- every conclusion retains the exact supporting segment IDs or other evidence.

Task 005B owns transcript coverage manifests and fail-closed publication;
Tasks 006A/006B own evidence/coverage ledgers for hierarchical processing; Task
007 owns multi-hour stress and failure testing.

## 56. Startup health check

Normal launch should perform only lightweight checks:

- workspace access;
- database schema version;
- WAL state;
- unfinished jobs;
- orphan task directories;
- interrupted media processing;
- available disk space;
- missing required models.

Do not scan or reprocess the entire workspace during ordinary launch.

---

# Part XI — UN Web TV and Media Sources

## 57. UN Web TV product boundary

UN Web TV processing is a required product capability, but it must follow a dedicated technical and legal validation milestone.

The adapter should attempt to retrieve:

- meeting title;
- date;
- duration;
- UN body;
- meeting number;
- agenda information;
- page description;
- available language tracks;
- source URL.

The user must be able to review and correct metadata.

## 58. Track provenance

The application must record whether the transcript came from:

- original speaker audio;
- UN simultaneous interpretation;
- another translated audio track;
- unknown or mixed source.

Interpretation must never be represented as verbatim original wording.

## 59. Acquisition rules

- Use permitted, supported access methods only.
- Do not bypass authentication, access controls, DRM, or technical restrictions.
- Do not imply redistribution or republication rights.
- Retain source URL, source type, acquisition time, and track provenance.
- Provide a manual local-file fallback when automatic acquisition fails.
- Page or stream changes must fail safely without corrupting an existing meeting record.

---

# Part XII — User Interface

## 60. Native macOS design

Preferred layout:

```text
Sidebar
  → Main Content
  → Inspector
```

The interface should be:

- clean;
- restrained;
- information-dense without clutter;
- keyboard accessible;
- suitable for long professional review sessions;
- consistent with native macOS conventions.

Advanced options should remain hidden until needed.

## 61. Review-first interaction

Core review screens must support:

- source and processing-route inspection;
- transcript and translation alignment;
- speaker and capacity correction;
- low-confidence review queues;
- evidence navigation by timestamp or document location;
- stale-object warnings;
- section regeneration and locking;
- validation findings;
- clear distinction between source, extraction, inference, and user confirmation.

## 62. Storage dashboard

Provide a Storage page showing:

- total workspace size;
- meetings;
- audio;
- documents;
- models;
- database;
- indexes;
- backups;
- temporary files;
- logs and cache.

Actions may include:

- Review Large Meetings;
- Manage AI Models;
- Clear Temporary Files;
- Rebuild Index;
- Reveal Workspace;
- Empty Workspace Trash.

Before cleanup, display clearly:

```text
Will remove
Will not remove
```

## 63. Cloud privacy display

The user must be able to see, before and after processing:

- which stage runs locally;
- which provider is used;
- whether cloud processing occurs;
- what exact object or excerpt is sent;
- whether original media is uploaded;
- which policy authorized the route.

---

# Part XIII — Briefing System

## 64. Section model

Meeting templates are versioned structured contracts, not only Markdown
formatting. A template may define meeting type, extraction schemas, required
entities, required evidence links, validation rules, section assembly, and
output renderings. Initial and future types may include bilateral,
multilateral-consultation, internal-coordination, negotiation, board, project,
and investor meetings.

Task 006B implements only the template foundation and the smallest types needed
by its approved vertical slice. Broader template catalogs and relationship UI
remain post-MVP work after evidence, provider, and security gates.

Possible sections include:

- Meeting Overview;
- Briefers and Main Presentations;
- Major Issues;
- Group Positions;
- Major Countries or Actors;
- China Statement;
- Right of Reply;
- Negotiation Dynamics;
- Assessment;
- Follow-Up Items;
- Custom Section.

Each section must have:

- an input contract;
- a prompt module set;
- an output schema;
- target length settings;
- validation rules;
- an independent regeneration command;
- provider-routing configuration.

## 65. Grouping modes

Support at least:

```text
formal_groups
policy_positions
```

Formal groups may include P5, EU, NATO, NAM, and regional groups, but membership does not prove a shared current-meeting position.

Policy-position groups may include labels such as:

- supports enhanced reporting;
- opposes the proposed mechanism;
- favors negotiations;
- expresses legal reservations.

AI-generated group labels must remain reviewable.

## 66. Manual edits

- Manual edits create a new section revision.
- Locking prevents automated replacement.
- Regeneration must never modify a locked revision.
- If upstream evidence changes, the locked section becomes stale and displays the affected evidence.
- The user decides whether to retain, revise, or regenerate it.

---

# Part XIV — Historical Knowledge and Preferences

## 67. Historical retrieval

Initial historical retrieval must be deterministic and filterable by:

- country or actor;
- organization;
- topic;
- meeting body;
- date range;
- issue;
- review status.

Only published objects may be treated as confirmed history.

## 68. Learned preferences

The first version must not attempt general hidden memory.

Permitted learned preferences include:

- country or actor order;
- briefing length;
- section order;
- quotation policy;
- grouping preference;
- terminology preference;
- frequently used templates.

All learned preferences must be:

- visible;
- editable;
- disableable;
- removable;
- resettable;
- attributable to explicit user behavior.

Use the labels:

- **Learned Preferences**
- **Meeting History**
- **Historical Context**

Do not market the initial system as general AI memory.

---

# Part XV — Automation Architecture

## 69. Shared command layer

External agents must operate through one typed Automation Command Layer.

Preferred delivery order:

```text
Shared Command Layer
  → CLI
  → MCP adapter
  → Local HTTP API only if a concrete client requirement exists
```

No adapter may directly modify SQLite or arbitrary configuration files.

## 70. Initial commands

Possible commands:

```text
get_app_status
get_workspace_status
get_settings
describe_settings
update_settings
list_models
list_templates
get_template
update_template
validate_template
list_meetings
get_meeting_status
create_meeting
import_document
process_recording
generate_briefing
regenerate_section
export_briefing
run_diagnostics
get_storage_report
```

Each command must use the same validation, permission, transaction, audit, and error-handling services as the UI.

## 71. Permission levels

### Read

Status, meeting lists, templates, storage, and processing state.

### Safe configuration

Typed, reversible changes such as model preference, section length, actor order, or grouping mode.

### Operational action

Create meeting, import document, process recording, generate briefing, rebuild index, or download model.

### Destructive or sensitive

Always require explicit confirmation:

- delete meeting;
- delete original audio;
- empty Trash;
- move workspace;
- delete model;
- send sensitive material to a cloud provider;
- change credentials;
- enable remote network access;
- start recording without direct user awareness.

## 72. Safe patches and audit

Agents must not overwrite complete settings files.

Use typed commands or validated patches.

Every change must be:

- validated;
- attributable;
- reversible where practical;
- logged with previous and new values;
- linked to approval when required.

Provide an in-app activity view.

---

# Part XVI — Quality Gates and Testing

## 73. Mandatory quality gates

A feature is incomplete if it violates any gate.

### Gate 1 — Storage discipline

Application data, cache, logs, jobs, and models do not grow without defined limits and ownership.

### Gate 2 — Evidence integrity

Every substantive diplomatic conclusion is traceable to exact evidence.

### Gate 3 — Prompt and schema consistency

Modular prompts, structured inputs, versioned schemas, and validation reduce variation across providers.

### Gate 4 — Briefing quality

Output meets professional diplomatic requirements and avoids generic summary language.

### Gate 5 — Automation safety

External agents operate only through validated, permissioned, auditable commands.

### Gate 6 — Provider integrity

Subscription clients are not misrepresented as APIs, and credentials or undocumented protocols are not extracted.

### Gate 7 — Semantic object integrity

AI consumes stable semantic objects, not database tables, arbitrary paths, or temporary internal formats.

### Gate 8 — Privacy and routing integrity

No source or derived data is sent to a provider in violation of its classification or user policy.

### Gate 9 — Revision integrity

Published revisions are immutable, dependencies are exact, and upstream corrections produce correct stale propagation.

### Gate 10 — Transcript completeness

No transcript or hierarchical processing result publishes unless deterministic
coverage proves that every eligible source range/segment is accounted for and
all conclusions retain source evidence.

### Gate 11 — Recording durability

Capture persists incrementally, exposes truthful durable states, and recovers
or explicitly marks incomplete data after interruption, device loss, or crash.

### Gate 12 — Local-first and telemetry integrity

Meeting data stays local unless an explicit approved route is visibly
authorized; offline/no-outbound operation remains available, and telemetry is
default-off and excludes sensitive content and metadata.

## 74. Golden Test Set

Create the Golden Test Set from the first contract milestone, not at the end.

Suggested cases:

- Security Council briefing;
- First Committee general debate;
- right-of-reply exchange;
- technical expert meeting;
- ambiguous speaker identification;
- China prepared statement versus delivered statement;
- formal group membership with divergent positions;
- interpretation error;
- no meaningful policy change;
- long UN Web TV recording.

Each case should record:

```text
test_case_version
source_provenance
licensing_status
expected_semantic_objects
expected_key_positions
expected_reservations
expected_evidence
forbidden_claims
ideal_briefing_sections
known_failure_patterns
reviewer
scoring_rubric
```

## 75. Minimum release assertions

Before a milestone is accepted:

- 100% of substantive briefing claims have valid evidence references;
- no P0 fabricated position exists in the applicable Golden Test Set;
- reservations and qualifications required by the expected result are preserved;
- interpretation text is never labeled original wording;
- correcting a speaker or translation marks dependent objects stale;
- locked sections are not overwritten;
- cancellation and crash recovery leave the workspace consistent;
- temporary files are bounded and owned;
- logs contain no credentials and no complete sensitive meeting content by default;
- `restricted` data is not sent externally;
- invalid structured output is rejected;
- long media is processed without loading the entire file into memory;
- build, unit tests, and applicable integration tests pass.

## 76. Definition of Done template

Every implementation task must define:

```text
1. Functional behavior
2. Input and output schemas
3. Failure behavior
4. Cancellation and recovery behavior
5. Storage ownership and cleanup
6. Privacy and provider-routing behavior
7. Unit tests
8. Integration tests
9. Golden Test impact
10. Documentation or ADR impact
11. Manual verification steps
12. Known limitations
```

---

# Part XVII — Delivery Plan

## 77. Milestone 0 — Repository audit and decisions

Deliverables:

- factual repository map;
- current architecture and data-flow map;
- gap matrix;
- reusable-component list;
- risk register;
- decision requests;
- proposed first implementation milestone;
- existing build and test commands.

No code or documentation changes are authorized in the first audit task.

## 78. Milestone 1 — Core contracts

After audit approval:

- create or update `AGENTS.md`;
- create accepted ADRs;
- define common revision envelope;
- define SourceAsset and EvidenceRef;
- define MeetingProfile, TranscriptSegment, TranslationSegment, Actor, SpeakingCapacity, and SpeakerAssignment;
- define validation states and enums;
- define dependency and invalidation contracts;
- add serialization, compatibility, migration, and round-trip tests;
- establish five minimal Golden Test fixtures.

No broad UI, UN Web TV implementation, historical comparison, or automation adapters.

## 79. Milestone 2 — Local recorded-meeting vertical slice

Build one usable end-to-end path:

```text
Import local audio or video
  → Canonicalize audio
  → Create recoverable chunks
  → Transcribe with one provider
  → Translate with one provider
  → Review transcript and speaker assignments
  → Generate Intervention Cards
  → Generate Delegation Position Cards
  → Generate a basic issue-position matrix
  → Generate two or three briefing sections
  → Validate evidence
  → Assemble and export Markdown
```

This slice must also establish local-first provider policy, transcript edit
lineage, deterministic 100 percent transcript coverage, evidence-linked typed
Issue/Position/Commitment/Decision foundations, and structured template
contracts in their assigned controller tasks. It must not move live-recording,
enterprise, or real-time coaching scope into Task 005B.

Include the minimum Workspace Service, Task Manager, persistence, logging, and recovery required by this path.

Do not implement every work mode before this vertical slice is usable.

## 80. Milestone 3 — Reliability, privacy, and hardening

Add:

- crash recovery;
- retry by chunk;
- storage dashboard;
- data classification;
- provider-routing enforcement;
- prompt-injection tests;
- log redaction;
- stale propagation UI;
- long-meeting tests;
- provider failure tests;
- destructive-operation tests;
- expanded Golden Test Set.
- default-off content-free telemetry policy and no-outbound-network tests;
- model-policy routing hardening;
- controlled export, retention, secure-deletion semantics, and any required
  at-rest encryption ADR;
- multi-hour transcript coverage tests that fail on injected omissions.

## 81. Milestone 4 — Live capture and UN Web TV

First perform a technical and legal spike for:

- supported URL patterns;
- metadata extraction;
- media and language-track discovery;
- page-change resilience;
- permitted acquisition methods;
- manual fallback.

Then implement:

- authorized application-audio capture;
- in-room capture;
- UN Web TV adapter;
- language-track provenance;
- safe failure and recovery.
- incremental recording persistence and durable checkpoints;
- interruption, abnormal-termination, and device-disconnection recovery;
- explicit incomplete-recording detection and states.

## 82. Milestone 5 — Automation and additional providers

Implement in order:

1. shared command layer;
2. CLI;
3. MCP adapter;
4. one API or local-model fallback;
5. experimental Codex subscription adapter;
6. experimental Claude Code subscription adapter;
7. local HTTP only if justified.

## 83. Milestone 6 — Historical review and preferences

Add:

- deterministic historical search;
- evidence-based comparison;
- user confirmation of possible changes;
- transparent learned preferences;
- larger historical performance tests.

## 83.1 Post-MVP deferred capability boundary

The following are not part of Task 005B or the initial vertical slice: a
complete relationship-graph UI, full organization synchronization, enterprise
administration, complex cross-organization access management, full named-
speaker identification, and real-time political/negotiation coaching or
automatic response recommendations. The canonical implementation plan records
their prerequisite gates. They receive a numbered implementation task only
after the user explicitly promotes one into scope.

---

# Part XVIII — Coding and Repository Rules

## 84. Coding rules

Codex must:

1. prefer clear native platform APIs over fragile UI automation;
2. route domain persistence through repositories and services;
3. route disk writes through the Storage Service;
4. route long-running operations through the Task Manager;
5. route external inference through provider interfaces;
6. route external agent control through the Automation Command Layer;
7. prevent AI providers from querying SQLite directly;
8. keep downloaded models outside the app bundle;
9. avoid hidden, unbounded caches;
10. avoid retaining full raw provider output indefinitely;
11. avoid logging credentials or complete sensitive content;
12. reject invalid model output;
13. use stable enums and typed schemas instead of free-form strings where appropriate;
14. keep prompts independent of database layout;
15. avoid giant prompts and giant manager classes;
16. preserve locked sections;
17. preserve uncertainty in speaker assignments;
18. avoid unsupported policy-change claims;
19. require confirmation for destructive or sensitive actions;
20. avoid features outside the authorized milestone;
21. preserve useful existing code unless evidence supports replacement;
22. add tests with every behavioral change;
23. update relevant ADRs and documentation in the same change;
24. leave no unexplained placeholder production code.
25. keep meeting data local unless an explicit approved route satisfies the
    local-first outbound contract;
26. prove complete transcript/source-segment coverage before publication;
27. store secrets only through the operating-system secret-store boundary;
28. require backward-compatible migrations, rollback anchors, and prior-state
    tests for schema changes;
29. keep telemetry default-off, content-free, metadata-minimized, fully
    disableable, and compatible with no-outbound-network mode;
30. implement external product behavior independently rather than copying
    code from another repository merely to reproduce it.

## 85. Dependency rule

Before adding a dependency, record:

```text
purpose
expected_binary_or_install_size
maintenance_status
security_history
native_alternative
removal_strategy
licensing_implications
```

Prefer small, replaceable adapters over large frameworks.

## 86. Repository documentation target

After the audit is accepted, the repository should evolve toward:

```text
AGENTS.md
docs/
├── PRODUCT_CONSTITUTION.md
├── CURRENT_ARCHITECTURE.md
├── TARGET_ARCHITECTURE.md
├── DOMAIN_CONTRACTS.md
├── PIPELINE.md
├── STORAGE_POLICY.md
├── SECURITY_PRIVACY.md
├── AI_PROVIDER_ARCHITECTURE.md
├── AUTOMATION_SECURITY.md
├── QUALITY_GATES.md
├── MVP_ACCEPTANCE.md
└── adr/
    ├── ADR-0001-language-and-ui-stack.md
    ├── ADR-0002-deployment-and-distribution.md
    ├── ADR-0003-persistence-and-recovery.md
    ├── ADR-0004-object-versioning.md
    ├── ADR-0005-provider-boundaries.md
    └── ADR-0006-media-tooling.md

tasks/
├── TASK-0001-repository-audit.md
├── TASK-0002-core-contracts.md
└── TASK-0003-local-media-vertical-slice.md
```

Do not create all documents merely to satisfy a list. Each document must have a clear owner, purpose, and non-duplicated content.

---

# Part XIX — Historical Initial Codex Task

## 87. Task 001 — Read-Only Repository and Architecture Audit (accepted history)

Task 001 is complete and retained here as the original bootstrap contract. It
is not the current task and must not be reopened merely because this historical
section exists. Current status and the next eligible task come from the
execution ledger.

### Objective

Audit the current MeetingBuddy repository against this master specification.

This is a read-only discovery task.

Do not implement features or modify repository files.

### Restrictions

Do not:

- edit, create, delete, rename, or move repository files;
- install or upgrade dependencies;
- change Xcode project settings;
- run destructive commands;
- perform database migrations;
- access external services or user accounts;
- delete code that appears unused;
- create placeholder implementations;
- claim that planned features already exist;
- rewrite functioning code solely to match the target architecture;
- create branches or commits.

You may run existing, documented, non-destructive inspection, build, and test commands. Do not fix failures during this task.

### Required inspection

Inspect and report:

1. repository structure;
2. language, frameworks, deployment target, and build system;
3. application entry points;
4. UI architecture;
5. current domain models;
6. persistence and file-storage behavior;
7. long-running task and concurrency implementation;
8. media ingestion and audio processing;
9. transcription, translation, and AI-provider integrations;
10. existing automation, CLI, MCP, or local API surfaces;
11. privacy, credentials, logging, permissions, entitlements, and network behavior;
12. tests, fixtures, CI, and build verification;
13. reusable components;
14. duplicated or competing infrastructure;
15. conflicts with this specification;
16. data-loss, security, privacy, platform, and external-dependency risks;
17. decisions that materially block the first implementation milestone.

### Evidence rules

For every material finding:

- cite the exact repository path;
- cite the relevant type, function, target, configuration key, or code range;
- distinguish observed fact from inference;
- distinguish current architecture from target architecture;
- mark uncertainty explicitly;
- do not describe an uninspected component as absent merely because it was not found in one search.

### Required output

Return one report with these sections:

#### A. Executive assessment

A concise factual summary and overall readiness judgment.

#### B. Repository map

Targets, modules, directories, entry points, dependencies, and build system.

#### C. Current architecture and data flow

Observed UI, domain, persistence, task, media, provider, and automation flows.

#### D. Gap matrix

For each gap include:

```text
priority: P0, P1, or P2
observed evidence
product impact
recommended direction
ADR or user decision required: yes/no
```

#### E. Conflicts and contradictions

Conflicts between the existing repository, this target architecture, and any existing project documentation.

#### F. Reusable components

Code, tests, models, adapters, or UI that should be preserved.

#### G. Risk register

Include data loss, privacy, security, maintainability, concurrency, migration, platform, provider, licensing, and external-source risks.

#### H. Decision requests

List only decisions that materially block Milestone 1 or the local recorded-meeting vertical slice.

#### I. Proposed first implementation milestone

Propose the smallest coherent implementation sequence, limited to no more than three reviewable commits. Do not implement it.

#### J. Verification commands

List the exact existing commands for build, unit tests, integration tests, formatting, linting, and other relevant checks.

#### K. Files that would need modification later

List likely files or directories, but do not modify them.

### Stop condition

Stop after returning the audit report.

Do not modify documentation.  
Do not define schemas.  
Do not implement code.  
Do not create commits.  
Do not proceed to Milestone 1 without explicit user authorization.

---

# Part XX — Historical User Authorization Template

This example records the original transition after Task 001. It is not the
current next command; the execution ledger now controls that fact.

After reviewing Task 001, the user could authorize the next task with language similar to:

```text
Proceed with Milestone 1 only.
Use GPT-5.6 Sol at max effort for architecture and schema decisions.
Implement only the approved core-contract scope from the audit.
Keep each change reviewable, run the agreed tests, and stop after the milestone report.
Do not begin the local-media vertical slice until I approve it.
```

---

# End of Specification
