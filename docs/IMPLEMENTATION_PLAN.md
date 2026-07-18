# Implementation Plan

Status: Accepted task map; each task still requires explicit authorization
Owner: Codex
Last updated: 2026-07-17
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
- Before 005A: distribution/sandbox/file-access direction and media acceptance
  parameters.
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

No build, test, format, or lint command exists in Task 002. Task 003A must add
and document the first deterministic commands when it creates the Swift module.
