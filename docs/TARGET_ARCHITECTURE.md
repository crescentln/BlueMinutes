# Target Architecture

Status: Accepted architecture direction; implementation is task-gated
Owner: Codex
Last updated: 2026-07-18
Purpose: Define dependency direction and system boundaries without duplicating
field-level contracts, security policy, or storage policy.

## Product shape

MeetingBuddy will be a native macOS modular monolith written primarily in Swift
6. SwiftUI provides the application structure, with narrow AppKit bridges when
native macOS behavior requires them.

The first implementation priority is a local recorded-meeting vertical slice.
Live capture, UN Web TV, automation adapters, and historical knowledge remain
later task-gated capabilities.

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

## Authoritative boundaries

- Semantic-object contracts: `DOMAIN_CONTRACTS.md`
- Persistent authority, workspace ownership, and recovery: `STORAGE_POLICY.md`
- Classification, cloud routing, secrets, and trust boundaries:
  `SECURITY_PRIVACY.md`
- Milestone acceptance and quality gates: `MVP_ACCEPTANCE.md`
- Sequencing and exclusions: `IMPLEMENTATION_PLAN.md`
- Accepted and open decisions: `adr/README.md`

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

The accepted Task 005A implementation realizes `MeetingBuddyApp` as the sole
composition root plus `MeetingBuddyFeatures` and `MeetingBuddyMedia` targets.
Both user-authorized source acquisition and canonical conversion use the one
`MeetingBuddyTasks` runtime. `MeetingBuddyPersistence` remains the only GRDB
consumer and owns managed files, job storage, task files/logs, and recovery
adapters. The Task 005A full-Xcode native gate passes. Task 005B may extend
these boundaries only after separate authorization and resolution of its
production transcription/translation route decision.

## Deliberately deferred choices

- whether a later task needs an Xcode project in addition to the current
  SwiftPM application/product layout;
- Developer ID provisioning, notarization, and clean-machine release mechanics;
- production transcription, translation, and inference providers;
- UN Web TV acquisition mechanics and live-capture entitlements.

These choices are resolved only in their assigned tasks and ADRs.
