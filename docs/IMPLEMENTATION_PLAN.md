# Implementation Plan

Status: Tasks 001 through 011 accepted; canonical MVP sequence complete
Owner: Codex
Last updated: 2026-07-22
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
| 005B | Local-first ASR/translation interfaces and approved routes, model-policy router, Keychain, provenance/edit lineage, deterministic coverage proof, transcript/translation/speaker review | Provider/policy/Keychain fakes plus approved non-sensitive integration route, 100% coverage, correction, migration, and privacy tests |
| 006A | Independent evidence-linked Participant/Organization/Issue/Position/Commitment/Decision entities, protected claim taxonomy, review UI | Golden diplomatic rules, evidence/segment coverage, schema migration, revision/stale tests |
| 006B | Structured meeting-template foundation, issue-position matrix, independent sections, coverage/evidence validation, final assembly, controlled Markdown export | End-to-end local fixture, template/schema and 100% segment coverage, deterministic export, migration, section lock/regeneration tests |
| 007 | Model-policy, no-outbound, telemetry, secure-storage/export/deletion, accessibility, performance, dependency, and long-meeting hardening | Expanded policy, network, telemetry, secret, storage, migration, coverage, Golden, performance, and accessibility suite |
| 008A | Current UN Web TV/live-capture technical/legal and reliable-recording state/storage spike only | Primary-source evidence, state/checkpoint/test design, capability boundary, go/no-go decisions |
| 008B | Only user-approved web-source and incrementally durable capture capabilities | Permission, provenance, checkpoint, abnormal termination/device-loss, incomplete-state, migration, recovery, and integration tests |
| 009A | Access-policy-aware validated application command layer and CLI | Permission/policy, confirmation, audit, malformed input, rollback, and recursion tests |
| 009B | Local stdio MCP adapter over the closed command layer; no additional provider or network route was approved | Fixed tool allowlist, policy/audit attribution, malformed input, migration, failure, and recursion tests |
| 010 | Published-object search, evidence-based position comparison, and visible learned preferences | Reproducibility, evidence, false-change, reversibility, migration, and performance tests |
| 011 | Release-scope audit, packaging, signing/notarization, update, migrations, no-outbound/telemetry, coverage, recording when selected, and rollback validation | Full quality-gate, clean-machine, migration/recovery, security/privacy, and release-classification report |

## Post-005A requirement allocation

This is the single canonical allocation for the one-time roadmap integration.
Detailed objective, rationale, dependencies, scope, non-goals, components,
data/migration impact, security/privacy, acceptance, tests, completion evidence,
and rollback/compatibility remain in the corresponding controller task.

| Requirement | Immediate owner | Later verification / deferral |
| --- | --- | --- |
| A. Local-first data boundary | Persistent instructions and ADR/security policy now; Task 005B enforces it for ASR/translation | Task 007 hardens no-outbound/fallback; Task 011 audits release behavior |
| B. Reliable and recoverable recording | Task 008A designs state/checkpoint/permission/storage behavior | Task 008B implements incremental persistence, crash/interruption/device-loss recovery, incomplete detection, and abnormal-termination tests; Task 011 audits if selected |
| C. Transcript provenance | Task 005B maps stable IDs, immutable original/edit lineage, audio/time/language/provider/model/confidence, speaker assignment, and integrity references | Task 008B adds microphone/system-audio provenance |
| D. Evidence-linked derived intelligence | Task 006A adds independent typed claims/entities and evidence; Task 006B consumes them | Task 010 owns evidence-based historical comparison; Task 011 audits traceability |
| E. Provider abstraction | Task 005B owns ASR/translation/Secret Store; Task 006A/006B own analysis provider use | Task 008B owns capture adapter; Task 009B adds approved local/organization/cloud adapters |
| F. Model policy routing | Task 005B establishes the application-owned policy router | Task 007 hardens it; Task 009B extends only eligible routes |
| G. Secure local storage | Task 005B implements Keychain-backed secrets | Task 006B controls export; Task 007 owns encryption decision, permissions, retention/deletion; Task 011 verifies signed/update paths |
| H. Long-transcript completeness | Task 005B owns deterministic transcript coverage and fail-closed publication | Tasks 006A/006B retain segment/evidence coverage; Task 007 stress-tests; Task 011 audits |
| I. Privacy-preserving telemetry | Persistent policy now | Task 007 proves default-off/full-disable/no-content/no-sensitive-metadata/no-outbound, and Task 011 audits it; organization/self-hosted telemetry remains deferred pending an explicit destination/retention ADR and new task |
| J. MeetingBuddy domain model | Existing Meeting/Transcript/Evidence/Actor foundations are preserved; Task 006A adds independent Participant/Organization/Issue/Position/Commitment/Decision entities | Task 007 adds independent SensitivityLabel/AccessPolicy entities; Task 010 owns historical position difference; broader relationship UI is deferred |
| K. Structured meeting templates | Task 006B adds versioned extraction schemas, required evidence, validation, and minimal approved types | The accepted baseline retains one multilateral template; a broader catalog remains an unnumbered post-MVP capability requiring explicit promotion |
| L. Deferred capabilities | None are added to Task 006A | See the post-MVP deferred-capability register below |

## Schema and migration allocation

The accepted SQLite schema has a closed semantic-object vocabulary. Each task
that adds a durable semantic type owns its ordered migration, repositories,
online backup/rollback anchor, supported-prior-state and unknown-future tests,
failure injection, close/reopen verification, and recovery-manifest coverage:

- Task 005B: implemented schema v3 immutable transcript coverage manifest,
  active pointer/events, and repositories without changing the closed v1
  semantic-object vocabulary;
- Task 006A: implemented schema v4 Participant/Organization and Issue/Position/
  Commitment/Decision/Intervention/DelegationPosition types plus immutable
  normalized analysis coverage/history;
- Task 006B: implemented schema v5 MeetingTemplate, IssuePositionGraph,
  BriefingSection, ValidationReport, and FinalBriefing types plus immutable
  normalized briefing coverage/history and export records;
- Task 007: implemented schema v6 `SensitivityLabel.v1` and `AccessPolicy.v1`,
  retention/Trash/unlink audit state, and default-disabled telemetry policy;
- Task 008B: implemented schema v7 recording session, state/event, track,
  epoch, segment, gap, and checkpoint state;
- Task 009A: implemented schema v8 command/audit, exact policy-input, result,
  and reversible safe-settings state;
- Task 009B: implemented schema v9 audit-origin vocabulary for the local stdio
  MCP adapter without adding a semantic object or provider route;
- Task 010: implemented schema v10 `HistoricalComparison.v1`, normalized
  generation-stamped search metadata, and learned-preference state/audit.

The planning integration itself implemented no migration. Separately authorized
tasks now implement and verify the ordered migrations through Task 010 schema
v10; Task 010 specifically proves accepted-v9 byte preservation and rollback.

## Post-MVP deferred-capability register

These entries have no executable task ID. Promote one into a new numbered task
only through explicit user authorization after its prerequisites pass:

Every promotion also requires Tasks 005B, 006A, 006B, 007, and 008B to be
accepted—not merely deferred—so transcript provenance, evidence integrity,
provider abstraction/model policy, security, and recording reliability are
complete. The table adds capability-specific prerequisites beyond that shared
gate.

| Deferred capability | Required prerequisites before promotion |
| --- | --- |
| Complete relationship graph UI | Tasks 006A, 006B, 007, and 010 accepted; exact evidence and migration performance proven |
| Full organization synchronization | Tasks 007, 009A, and 010 accepted; external-source, conflict, retention, and organization-policy ADR approved |
| Enterprise administration console | Tasks 007 and 009A accepted; independent SensitivityLabel/AccessPolicy model and audit/rollback gates proven |
| Complex cross-organization access management | Tasks 007 and 009A accepted; institutional identity, authorization, sharing, revocation, and threat-model decisions approved |
| Full named-speaker identification | Tasks 005B, 007, and 008B accepted; biometric/privacy, consent, false-match, local-model, and deletion decisions approved |
| Real-time political or negotiation coaching | Tasks 006A, 006B, 007, 008B, and the relevant speaker/access foundations accepted; separate product, safety, evidence, latency, and human-control ADR approved |
| Automatic real-time response recommendations | Same prerequisites as coaching plus explicit prohibition/confirmation boundaries and failure-mode evaluation; never an automatic action channel |

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
- At the start of 005B: resolved by ADR-0009 before the production adapter
  call. Installed Apple Speech/Translation runs locally on macOS 26+, manual
  local review is the fallback, no third-party dependency/model download was
  added, and no external destination or meeting-data transfer is authorized.
- At the start of 006A: resolved by ADR-0010 before the real adapter call.
  Apple Foundation Models guided extraction runs only on device on macOS 26+
  after availability, locale, policy, and visible-authorization checks. The
  approved live route uses only the versioned project-authored synthetic
  fixture; no external destination, dependency, credential, model download, or
  meeting-data transfer is authorized.
- Before 008B: resolved by the user-accepted ADR-0013 technical/legal and
  recording-state boundary.
- Before 009B: resolved by the accepted Task 009A shared command layer and
  ADR-0015 local stdio-only adapter decision.
- After Task 011 acceptance and before any publication: explicit commands for
  commit, push, tag, notarization, release, upload, installation, or
  distribution remain required as applicable.

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

The accepted Task 005A baseline passed 145 tests in 25 suites. The 24
persistence/recovery integration tests and 18 task/runtime
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

Task 005B raises the standard full-suite result to 157 tests in 28 suites and
passes debug/release builds with warnings as errors. Its provider/pipeline
tests cover policy allow/deny and missing facts, Keychain, malformed spans,
exact 100 percent coverage, deterministic context ownership, no-speech versus
failed/missing, retry reuse, cancellation cleanup, restart, atomic stale-input
refusal, immutable corrections, translation separation, stale propagation,
manual fallback, and speaker confirmation. The opt-in command below also
passes with locally generated synthetic audio and installed production Apple
models; the ordinary full suite skips only that opt-in live case:

```sh
MEETINGBUDDY_RUN_LIVE_APPLE_MODELS=1 swift test --filter AppleProviderLiveTests -Xswiftc -warnings-as-errors
```

Task 006A raises the standard full-suite result to 166 tests in 29 suites and
passes debug/release builds with warnings as errors. Its six analysis-pipeline
tests cover all eight semantic contracts, direct-decoder safety, protected
prompts, deterministic route/input/prompt/fixture history, exact evidence and
100 percent segment accounting, injected omission/duplication/provider failure,
atomic publication, immutable correction, stale propagation, close/reopen,
recovery, and a 5/5 diplomatic-rule matrix. Migration 004 covers fresh and
accepted v1/v2/v3 workspaces; the v3 canary rows remain byte-identical and the
verified pre-migration backup restores schema v3 without analysis tables. The
ordinary suite skips the two explicitly opt-in Apple live cases. The Task 006A
installed-model route separately passes with only the versioned synthetic
fixture:

```sh
MEETINGBUDDY_RUN_LIVE_APPLE_ANALYSIS=1 swift test --enable-swift-testing --filter AppleProviderLiveTests.installedAppleFoundationModelAnalyzesOnlyVersionedSyntheticText -Xswiftc -warnings-as-errors
```

Task 006B raises the standard full-suite result to 175 tests in 31 suites and
passes debug/release builds with warnings as errors. Its contract and five
pipeline tests cover template compatibility, multi-Position/qualification
preservation, deterministic exact-input graph revisions, zero-overlap complete
segment/conclusion coverage, independent regeneration, manual edit/lock,
provider denial/failure, contradiction/historical-claim rejection, repeated
upstream correction/stale blocking, controlled deterministic export, and
close/reopen. Migration 005 covers fresh and accepted v1/v2/v3/v4 workspaces;
the v4 canary rows remain byte-identical and the verified backup restores
schema v4 without briefing tables. The ordinary suite skips three explicit
live Apple cases. The Task 006B installed-model route separately passes only
bounded project-authored synthetic claims:

```sh
MEETINGBUDDY_RUN_LIVE_APPLE_BRIEFING=1 swift test --enable-swift-testing --filter AppleProviderLiveTests.installedAppleFoundationModelGeneratesOnlyEvidenceKeyedSyntheticBriefing -Xswiftc -warnings-as-errors
```

Exact contract/module versions, coverage behavior, fixture hashes, migration/
rollback evidence, privacy route, export boundary, and limitations are recorded
in [`BRIEFING_FOUNDATION.md`](BRIEFING_FOUNDATION.md).

Task 010 adds the independent historical-review slice without a new product
target or dependency: deterministic local query/index contracts, exact
published Position/Evidence/security trails, qualified
`HistoricalComparison.v1`, user-only superseding confirmation, already-admitted
document/email/public-source integrity descriptors, seven typed visible
preferences, a local-only Task Manager rebuild, schema v10 migration/rollback,
false-change Golden coverage, accessibility structure, and a 10,000-Position
scale gate. Exact behavior and limitations are recorded in
[`HISTORICAL_REVIEW.md`](HISTORICAL_REVIEW.md) and
[ADR-0016](adr/ADR-0016-task-010-historical-review-and-preferences.md).

Task 011 keeps schema v10 and adds bounded resource/correctness hardening,
privacy/license resources, clean-scratch local packaging verification, and
cold synthetic whole-workspace backup verification. The final new-scratch gate
passes 242 tests in 42 suites; 10,000 published Positions rebuild in
9.081141167 seconds and the first filtered page returns in 0.319461 seconds on
the reference host. Fresh v10, every supported v1-v9 migration, rollback
backup, unknown-future rejection, injected failure, and recovery gates pass.

Tasks 001 through 011 are accepted and frozen. The selected arm64 app is an
ad-hoc Hardened Runtime INTERNAL ALPHA, not a release candidate or distributable
build. Developer ID, Team ID, notarization/stapling, affirmative Gatekeeper
distribution approval, clean-machine install/update/rollback, approved icon/
localization, manual accessibility, intended-OS live TCC/capture proof, and
four medium evidence-integrity findings remain open. There is no next eligible
numbered MVP task; post-MVP promotion and every publication action require
separate explicit user authorization.

Historical note: the four medium findings were open at Task 011 acceptance.
The separately authorized post-MVP security-remediation work implements the
ADR-0017 application-owned omission and exact human-confirmation gates without
reopening the numbered MVP sequence or adding a product feature, dependency,
network route, provider, or schema migration. Private GitHub publication and
any later public conversion remain separately authorized maintenance actions.
