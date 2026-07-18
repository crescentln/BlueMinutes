# Implementation Plan

Status: Task 005A accepted after implementation and full-Xcode native validation
Owner: Codex
Last updated: 2026-07-18
Purpose: Map repository work to controller tasks without granting autonomous
phase progression or duplicating detailed task specifications.

## Operating rule

The controller remains authoritative for task scope, acceptance, and stop
conditions. This plan records repository allocation and dependency order only.
Codex must stop after every task report.

## Task map

| Task | Repository outcome | Primary verification |
| --- | --- | --- |
| 003A | First `MeetingBuddyDomain` Swift module; stable IDs, common revision and validation types, `SourceAsset.v1`, `EvidenceRef.v1`, serialization and builders | Swift build/test, deterministic validation, serialization round trips |
| 003B | Meeting, transcript, translation, actor, capacity, speaker, dependency, active-revision, and stale-plan contracts; five minimal Golden fixtures | Provenance, compatibility, stale-plan, and fixture tests |
| 004A | Workspace/Storage services, SQLite repositories, migrations, active pointers, dependency persistence, recovery and Trash foundations | Disposable migration, repository round-trip, integrity, backup/recovery tests |
| 004B | Single Task Manager, job state machine, progress, cancellation, retry, temp ownership, logging, and crash recovery | State-machine, concurrency, cancellation, retry, redaction, and recovery tests |
| 005A | Native local-file intake, source hashing, AVFoundation-first canonical audio, timeline, chunking, minimal source/status review | Media fixtures, timestamp tolerance, chunk determinism, cleanup and cancellation tests |
| 005B | Approved transcription/translation providers, structured validation, persistence, transcript/translation/speaker review, Keychain and route display | Provider fakes plus approved integration route, correction and privacy tests |
| 006A | Evidence-linked intervention and delegation-position analysis, protected prompt modules, review UI | Golden diplomatic rules, evidence validation, revision/stale tests |
| 006B | Issue-position matrix, independent briefing sections, validation, final assembly, evidence navigation, Markdown export | End-to-end local fixture, deterministic export, section lock/regeneration tests |
| 007 | Reliability, privacy, storage, accessibility, performance, dependency, and long-meeting hardening | Expanded failure, recovery, routing, Golden, performance, and accessibility suite |
| 008A | Current UN Web TV/live-capture technical and legal spike only | Primary-source evidence, capability boundary, go/no-go decisions |
| 008B | Only user-approved web-source and capture capabilities | Permission, provenance, failure, recovery, and integration tests |
| 009A | Validated application command layer and CLI | Permission, confirmation, audit, malformed input, and recursion tests |
| 009B | MCP and separately approved experimental provider adapters | Boundary, quota, failure, credential, and recursion tests |
| 010 | Published-object search, historical comparison, and visible learned preferences | Reproducibility, evidence, reversibility, and performance tests |
| 011 | Release-scope audit, packaging, signing, notarization, clean-machine and rollback validation | Full quality-gate and release-classification report |

## Initial repository allocation

- Task 003A creates only the minimum Swift package/module structure needed for
  an independently buildable domain target and tests.
- Application, persistence, task, media, AI, automation, feature, and test-
  support modules are created when their owning task first needs them.
- No empty production module or placeholder implementation is created merely to
  resemble the target diagram.

## Decision checkpoints

- Before 003A: Task 002 accepted and no open P0 decisions.
- Before 003B: each of the five Golden fixtures is synthetic or has recorded
  license and source provenance.
- Before 004A: persistence dependency note and migration test strategy.
  Resolved by the exact GRDB 7.11.1 pin, `docs/dependencies/GRDB.md`, and the
  disposable on-disk migration harness.
- Before 004B: Task 004A accepted and no open P0 decision. Resolved; Task 004B
  adds no dependency and migrates schema version 1 to version 2 only through a
  verified disposable rollback-anchor test.
- Before 005A: distribution/sandbox/file-access direction and media acceptance
  parameters. Resolved by accepted ADR-0002 Option A and ADR-0008: independent
  Developer ID direction, App Sandbox, one persistent workspace bookmark,
  transient source authority, five local formats, canonical 16 kHz mono
  signed-int16 CAF, 50 ms tolerance, and deterministic 30-second cores with
  one-second context.
- Before 005B: approved transcription and translation routes plus cloud policy.
- Before 006A: approved inference route and analysis-fixture provenance.
- Before 008B: user-accepted 008A technical/legal boundaries.
- Before 009B: shared command layer proven and each adapter separately approved.
- Before 011 publication: explicit commands for commit, push, tag, notarize,
  release, or distribution as applicable.

## Change-group discipline

Each task plan declares at most the number of coherent review groups needed for
its acceptance criteria. Commits are created only after the user accepts the
task and explicitly requests a commit. Publication remains separately
authorized.

## Build-command status

Task 003A introduced the first deterministic package commands:

```sh
swift package dump-package
swift package show-dependencies --format json
swift build --configuration debug -Xswiftc -warnings-as-errors
swift build --configuration release -Xswiftc -warnings-as-errors
swift test --enable-swift-testing --parallel -Xswiftc -warnings-as-errors
```

Xcode 26.6 build 17F113 is installed and selected at
`/Applications/Xcode.app/Contents/Developer`. Its first-launch status is
complete, so the standard commands above now run without Command Line Tools
framework or runtime overrides. Task 005A was verified with:

```sh
xcode-select -p
xcodebuild -version
xcodebuild -checkFirstLaunchStatus
swift test --enable-swift-testing --parallel -Xswiftc -warnings-as-errors
```

The standard test command passes 145 tests in 25 suites for the accepted Task
005A implementation. The 24 persistence/recovery integration tests and 18 task/runtime
tests use unique
disposable on-disk workspaces and cover
workspace identity, path and symlink guards; missing, empty, current, foreign,
and unknown-future database states; injected migration rollback and portable
backup, including accepted schema-v1 to schema-v2 migration; all eight semantic
repository contracts; immutable revisions; recursive
current-input publication gates; active/stale transaction atomicity across
restart; recovery inventory and tamper detection;
no asset bytes in SQLite; and failure-injected, compensated, collision-safe
Trash transitions. Task 004B cases additionally cover job state-machine and
repository integrity, bounded concurrency, pause/resume, cancellation, retry,
interrupted startup recovery, stale-input success refusal, disk budgets,
over-budget cleanup, orphan bounds, log redaction/rotation, and journaled
import/Trash/restore reconciliation across close/reopen.

Task 005A adds 13 media tests and four feature-model tests. They cover all five
approved native formats through real AVFoundation inspection and managed
intake; exact canonical PCM settings and duration; deterministic 30-second
core/one-second-context ranges; a compact three-hour checkpoint below the
65,536-byte job limit; process-local source authority; Task-Manager-owned
streamed acquisition; partial-copy cancellation cleanup; persistent original
and canonical source revisions; chunk retry reuse; exact gap reporting; source
immutability; terminal task cleanup; and exact routing of one SwiftUI importer
between workspace folders and the five approved media types. Test-only MOV
construction may use an AVFoundation export session; product conversion uses
readers/writers only.

The following Task 005A development gates also pass:

```sh
swift build --configuration debug -Xswiftc -warnings-as-errors
swift build --configuration release -Xswiftc -warnings-as-errors
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/MeetingBuddy.app
codesign -dvvv --entitlements :- dist/MeetingBuddy.app
```

The script stages `dist/MeetingBuddy.app`, applies an ad-hoc signature with only
App Sandbox, app-scoped bookmarks, and user-selected read/write entitlements,
launches the app, and verifies a live process. A full-Xcode native run also
observed App Sandbox initialization and its application container, presented
the native workspace Open panel, selected only a synthetic workspace, verified
its SQLite integrity, persisted exactly one app-scoped bookmark, and restored
that authority after relaunch. That run exposed competing SwiftUI
`fileImporter` modifiers; the implementation now uses one purpose-routed
importer and the new regression test verifies both workspace and media routes.

The current app is ad-hoc signed development evidence. Gatekeeper rejection is
expected for that signature, and no valid Developer ID identity is installed.
Developer ID provisioning, notarization, and clean-machine release validation
remain Task 011 gates. Task 005A is accepted. Task 005B remains unauthorized,
and its production transcription/translation route P1 decision must be resolved
before implementation.
