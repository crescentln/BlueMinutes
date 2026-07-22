# Target Architecture

Status: Accepted direction; selected MVP implementation accepted through Task 011
Owner: Codex
Last updated: 2026-07-22
Purpose: Define dependency direction and system boundaries without duplicating
field-level contracts, security policy, or storage policy.

## Product shape

MeetingBuddy will be a native macOS modular monolith written primarily in Swift
6. SwiftUI provides the application structure, with narrow AppKit bridges when
native macOS behavior requires them.

The canonical MVP sequence implements the local recorded-meeting vertical
slice plus bounded audio capture, metadata-only UN Web TV access, closed local
automation/stdio MCP, and deterministic historical review. Broader relationship,
organization, enterprise, named-speaker, and real-time coaching capabilities
remain unnumbered post-MVP work.

Meeting audio, transcripts, metadata, and derived intelligence are local by
default. An external route is an explicit policy-authorized exception with a
named provider, bounded data categories, destination, retention behavior,
visible user authorization, and a usable local/offline alternative.

## Module boundaries

Modules are created only when an authorized task needs them. The intended
dependency direction is:

```text
MeetingBuddyApp (composition root)
  -> MeetingBuddyFeatures
  -> MeetingBuddyApplication
  -> concrete Persistence / Tasks / Media / AI adapters

MeetingBuddyFeatures
  -> MeetingBuddyApplication
  -> MeetingBuddyDomain

MeetingBuddyAutomation
  -> MeetingBuddyApplication
  -> MeetingBuddyDomain

MeetingBuddyCLI / MeetingBuddyMCP (local executable adapters)
  -> MeetingBuddyAutomation
  -> MeetingBuddyApplication
  -> MeetingBuddyDomain

MeetingBuddyApplication
  -> MeetingBuddyDomain
  owns use-case APIs and ports for persistence, tasks, media, and AI

MeetingBuddyPersistence
  -> MeetingBuddyApplication (implements persistence ports)
  -> MeetingBuddyDomain

MeetingBuddyTasks
  -> MeetingBuddyApplication (implements task ports)
  -> MeetingBuddyDomain

MeetingBuddyMedia
  -> MeetingBuddyApplication (implements media ports)
  -> MeetingBuddyDomain

MeetingBuddyAI
  -> MeetingBuddyApplication (implements inference ports)
  -> MeetingBuddyDomain
```

`MeetingBuddyDomain` has no dependency on the UI, persistence implementation,
provider SDKs, or arbitrary filesystem paths. Concrete adapters depend inward
on stable contracts.

`MeetingBuddyApplication` owns use-case interfaces and the ports implemented by
concrete repositories, task execution, media, and inference adapters. It
depends only on `MeetingBuddyDomain`; it does not import concrete adapters.

`MeetingBuddyApp` is the sole composition root. It may import concrete adapters
to construct the object graph, but those concrete types do not leak through
application-service APIs. UI features and automation call the same application
services and never bind adapters directly.

`MeetingBuddyTestSupport` may provide synthetic fixtures and builders but must
not become a production dependency.

## Provider and policy boundaries

Application-owned ports separate authorized audio capture, speech-to-text,
translation, extraction/summarization/validation models, semantic/asset
storage, and operating-system secret storage. Concrete local, organization-
hosted, approved-cloud, and experimental adapters remain replaceable and never
enter domain logic.

One model-policy router evaluates sensitivity/access policy, offline or no-
outbound mode, organization policy, deployment environment, permitted
destination/retention, task data categories, and visible user authorization.
A UI dropdown selects only among eligible routes and cannot weaken policy.
Every provider call consumes a minimum versioned package, records the route
decision, and has a non-external operating mode.
For transcript workflows, that mode is an approved local provider or validated
manual transcript/translation intake and review; a disabled control is not a
functional fallback.

## Processing architecture

Processing is a versioned conditional DAG, not one rigid pipeline:

```text
Source acquisition
  -> canonical media or parsed documents
  -> transcription (when applicable)
  -> translation (when applicable)
  -> speaker and capacity assignment
  -> intervention extraction
  -> delegation positions
  -> issue-position structure
  -> independently generated briefing sections
  -> validation
  -> final assembly and export
```

Historical comparison is a query over published objects, not a mandatory node
in every processing job.

Every node declares exact input revision IDs, output schema versions, provider
and prompt metadata, cancellation behavior, and a safe publication gate.

Transcription and hierarchical processing additionally maintain a deterministic
coverage ledger. Publication requires 100 percent accounting for eligible core
ranges/source segments, bounded documented overlap, forward progress, explicit
no-speech/missing/failed outcomes, and exact conclusion-to-evidence links.

Live recording uses the same Task Manager and storage services. It persists
incrementally, checkpoints durably, records capture/persistence states, and
recovers or visibly marks incomplete data after crash, interruption, disk
failure, or audio-device loss. Nothing later may treat volatile-only capture as
a completed meeting.

## Meeting intelligence and templates

The implemented semantic layer independently addresses Meeting, Participant,
Organization, TranscriptSegment, Issue, Position, Commitment, Decision,
Evidence, SensitivityLabel, and AccessPolicy. `MeetingProfile`, Actor/Capacity,
`EvidenceRef`, and `DataClassification` remain foundations; no separate
Utterance alias is introduced merely to duplicate a reviewed transcript
segment. Future entities require task-owned compatible migrations rather than
embedding authoritative state in summary sections.

Derived intelligence distinguishes original source, machine transcription,
human correction, AI extraction, AI inference, and human-confirmed fact. Every
material claim retains exact evidence. Structured meeting templates are
versioned schemas with required entities/evidence and validation rules; Markdown
is only one rendering.

## Authoritative boundaries

- Semantic-object contracts: `DOMAIN_CONTRACTS.md`
- Persistent authority, workspace ownership, and recovery: `STORAGE_POLICY.md`
- Classification, cloud routing, secrets, and trust boundaries:
  `SECURITY_PRIVACY.md`
- Milestone acceptance and quality gates: `MVP_ACCEPTANCE.md`
- Sequencing and exclusions: `IMPLEMENTATION_PLAN.md`
- Accepted and open decisions: `adr/README.md`
- Implemented Task 006B briefing slice: `BRIEFING_FOUNDATION.md`

## Cross-cutting invariants

- AI consumes bounded, versioned semantic packages, never tables or the full
  workspace.
- Published revisions are immutable; active pointers can move without erasing
  history.
- Upstream replacement produces deterministic stale propagation.
- Source wording, interpretation, translation, extraction, inference, and user
  confirmation remain distinguishable.
- A substantive diplomatic conclusion requires exact evidence.
- Long-running operations share one Task Manager and bounded temporary-storage
  policy.
- External agents use the Automation Command Layer and cannot bypass the same
  application services used by the UI.
- Schema additions use ordered backward-compatible migrations, backup/rollback
  anchors, and supported-prior-state tests.
- Telemetry is disabled by default, content-free, metadata-minimized, fully
  disableable, and compatible with no-outbound-network mode.

The accepted implementation realizes `MeetingBuddyApp` as the sole app
composition root, with `MeetingBuddyFeatures`, `MeetingBuddyMedia`,
`MeetingBuddyAI`, `MeetingBuddyAutomation`, CLI, and MCP adapters behind
application-owned ports. Source acquisition, canonical conversion, transcript
processing, analysis, briefing, recording, and history-index rebuild use the
one `MeetingBuddyTasks` runtime. `MeetingBuddyPersistence` remains the only
GRDB consumer and owns schema v10 semantic, coverage, security, recording,
automation/MCP-attribution, history/preference, managed-file, job, export, and
recovery state.

ADRs 0009 through 0011 select installed Apple on-device speech, translation,
analysis, and minimum-input briefing with local/manual fallbacks and no
outbound inference adapter. ADR-0013 limits UN Web TV to exact-host metadata
and capture to visible audio-only routes. ADRs 0014 and 0015 close automation
to the typed local command/CLI boundary and seven read-authority stdio MCP
tools. Task 011 adds no module, schema, provider, model, dependency, network
destination, or feature route; it accepts the selected architecture only as
INTERNAL ALPHA.

## Deliberately deferred choices

- whether a later task needs an Xcode project in addition to the current
  SwiftPM application/product layout;
- Developer ID provisioning, notarization, Gatekeeper distribution approval,
  clean-machine release mechanics, and any updater;
- automatic UN Web TV media/player acquisition beyond the accepted metadata-
  only route, and any capture entitlement broader than the exact reviewed set;
- any application-level encryption scheme and key-recovery design;
- organization/self-hosted telemetry implementation;
- complete relationship graph UI, organization synchronization, enterprise
  administration, complex cross-organization access, full named-speaker
  identification, and real-time coaching/recommendations. Their prerequisites
  are recorded in `IMPLEMENTATION_PLAN.md` and they have no executable task ID.

These choices require a new explicit task and any applicable ADR or release
authorization; the completed MVP sequence grants none of them automatically.
