# Current Architecture

Status: Task 003B completed pending user acceptance
Owner: Codex
Last updated: 2026-07-18
Purpose: Record the observed repository state only; target design belongs in
`TARGET_ARCHITECTURE.md`.

## Executive state

MeetingBuddy is a confirmed greenfield project. The user accepted the Task 001
audit on 2026-07-17 and confirmed this directory as the canonical root.

The repository contains the accepted Task 002 governance baseline, the
accepted Task 003A foundation, and the completed-but-unaccepted Task 003B
input-side domain implementation. It remains one independently buildable Swift
domain module with synthetic contract tests. There is no application target
and no user meeting data.

## Repository state

- Git repository: local `main`; HEAD remains the accepted Task 003A rollback
  anchor, with the uncommitted Task 003B review set in the working tree.
- Product source files: `Sources/MeetingBuddyDomain/` only.
- Xcode projects/workspaces: none.
- Swift Package Manager manifest: `Package.swift`, Swift tools 6.0, Swift 6
  language mode, macOS 15 minimum.
- Build targets: `MeetingBuddyDomain` library and
  `MeetingBuddyDomainTests`; there is no application entry point.
- Dependencies and lockfiles: none.
- Tests: 86 synthetic Swift Testing cases in 13 suites, including exactly five
  clearly labeled Task 003B Golden fixtures; no CI, formatter, or linter
  configuration yet.
- Databases, migrations, media, models, credentials, and runtime workspaces:
  none.

The accepted evidence and original commands are preserved in
`audits/TASK-001_REPOSITORY_AUDIT.md`.

## Implemented layers

| Layer | Current implementation |
| --- | --- |
| Application/UI | None |
| Domain | Task 003A foundation plus Task 003B input contracts, explicit active selection, dependency edges, pure graph validation, and deterministic stale planning |
| Persistence and workspace | None |
| Task execution and recovery | None |
| Media | None |
| Transcription, translation, and AI | None |
| Automation/CLI/MCP | None |
| Historical retrieval | None |

The only executable product flow is pure in-memory creation, validation,
canonical JSON encoding, and decoding of foundational domain values. There is
no persistence, file I/O, network I/O, provider call, media operation, or UI.

## Governance now present

Task 002 established:

- repository-local operating instructions;
- current and target architecture boundaries;
- domain, storage, security, acceptance, and implementation-plan documents;
- accepted and proposed ADRs;
- a concise execution-state ledger;
- a persisted copy of the accepted Task 001 audit;
- a local Git repository for working-tree visibility and future rollback.

These artifacts do not themselves implement product behavior.

## Task 003A domain foundation

The accepted Task 003A implementation adds:

- phantom-typed UUID identifiers for logical objects, revisions, meetings,
  source assets, evidence, and managed storage objects;
- an immutable generic revision envelope with exact input, source-asset, and
  evidence revision references;
- v1 schema, lifecycle, validation, data-classification, origin, acquisition,
  retention, speech-source, and translation-status contracts;
- `SourceAssetV1` with a source-byte digest and opaque managed-storage
  reference rather than a filesystem path;
- `EvidenceRefV1` with seven typed location variants and an exact source
  revision, required excerpt/language/translation metadata, and source-kind
  compatibility checks;
- provider-neutral generation metadata with prompt/generator versions, output
  schema, template version, generation time, and privacy route, without
  credentials or SDK types;
- native SHA-256 calculation and verification over documented SourceAsset and
  EvidenceRef semantic projections;
- deterministic fail-closed decoding/validation and a constrained canonical
  JSON profile.

## Task 003B input and invalidation contracts

The current Task 003B review set adds:

- `MeetingProfileV1`, `TranscriptSegmentV1`, `TranslationSegmentV1`,
  `ActorV1`, `SpeakingCapacityV1`, and `SpeakerAssignmentV1`;
- distinct original-audio, interpretation, translated-audio, machine/human
  translation, and user-edit provenance paths;
- explicit review and user-confirmation state, including fail-closed uncertain
  speaker handling;
- exact dependency edges, explicit active-published revision selection,
  invalidation reasons, and deterministic transitive stale plans;
- pure cross-object reference, provenance, meeting, range, text-hash, actor,
  and classification checks;
- exactly five project-authored synthetic Golden fixtures with explicit rights
  and provenance manifests and no unsupported diplomatic inference.

All behavior is in-memory and storage-neutral. No active pointer, dependency
edge, or stale mark is persisted or executed yet.

## Known limitations

- There is no native app target, Xcode project, UI, persistence, task, media,
  provider, network, or automation implementation.
- The active developer directory contains Command Line Tools rather than the
  full Xcode application. SwiftPM builds pass, but full Xcode integration and
  macOS 15 runtime compatibility have not been verified.
- This Command Line Tools installation does not automatically expose the
  bundled Swift Testing framework and has an incorrect runtime search path.
  Tests passed with explicit paths to the CLT-owned framework and interop
  library; a standard `swift test` invocation still requires a complete or
  repaired Apple developer-tool installation.
- Git history provides the accepted Task 003A rollback anchor.
- Distribution/sandbox details and concrete third-party dependencies remain
  open decisions recorded in the ADR index.
- End-to-end product quality gates remain untested; only the Task 003A/003B
  domain, serialization, validation, provenance, stale-plan, Golden-fixture,
  and boundary gates have evidence.

## Next permitted transition

Task 003B is complete but not accepted. Codex must stop at this boundary. Task
004A becomes eligible only after the user accepts Task 003B and explicitly
authorizes the next task; it may then add persistence under its separate
dependency and migration checkpoints.
