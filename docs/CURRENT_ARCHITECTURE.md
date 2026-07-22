# Current Architecture

Status: Tasks 001 through 011 accepted; selected release classified INTERNAL ALPHA
Owner: Codex
Last updated: 2026-07-22
Purpose: Record the observed repository state only; target design belongs in
`TARGET_ARCHITECTURE.md`.

## Executive state

BlueMinutes, whose compatibility-sensitive internal name remains MeetingBuddy,
began as a confirmed greenfield project. The user accepted the Task 001 audit
on 2026-07-17 and confirmed this directory as the canonical root.

The repository contains accepted work through Task 011. Task 010 supplies
deterministic local Meeting History, evidence-qualified immutable comparison,
explicit user-confirmation lineage, visible presentation-only learned
preferences, a Task-Manager index rebuild, and schema v10. Task 011 adds bounded
release hardening and accepted packaging, backup, security, privacy, license,
and verification evidence without adding a schema, provider, model, dependency,
network destination, or feature route. The selected app remains a local
INTERNAL ALPHA, not a release candidate or distributable build.

## Repository state

- Git repository: private `crescentln/BlueMinutes`; local `main` tracks
  `origin/main`. Private source publication began at `5733eb7`, and the current
  pre-status-sync baseline is `4c8025a` after Dependabot PR #1 updated the
  pinned official checkout Action. Accepted Task 011 status baseline is
  `d31b9aa`, Task 011 implementation is `852257c`, and accepted Task 010 commit
  `f371faa` is the pre-Task-011 rollback anchor. These are the current reachable
  equivalents after the authorized private-path and GitHub-noreply history
  sanitizations. No public conversion, tag, notarization submission, binary
  upload, installation, or distribution is authorized.
- Product source files: `Sources/MeetingBuddyDomain/`,
  `Sources/MeetingBuddyApplication/`, `Sources/MeetingBuddyPersistence/`, and
  `Sources/MeetingBuddyTasks/`, `Sources/MeetingBuddyMedia/`,
  `Sources/MeetingBuddyFeatures/`, `Sources/MeetingBuddyApp/`, and Task 005B
  `Sources/MeetingBuddyAI/`, plus Task 009A `Sources/MeetingBuddyAutomation/`
  and `Sources/MeetingBuddyCLI/`, and Task 009B
  `Sources/MeetingBuddyMCP/` executable composition root.
- Xcode projects/workspaces: none.
- Swift Package Manager manifest: `Package.swift`, Swift tools 6.1, Swift 6
  language mode, macOS 15 minimum.
- Build products: eight libraries (`MeetingBuddyDomain`,
  `MeetingBuddyApplication`, `MeetingBuddyPersistence`, `MeetingBuddyTasks`,
  `MeetingBuddyMedia`, `MeetingBuddyAI`, `MeetingBuddyFeatures`, and
  `MeetingBuddyAutomation`) plus `MeetingBuddyApp`, `meetingbuddy-cli`, and
  `meetingbuddy-mcp`; seven test targets are present.
- Dependency: exact GRDB 7.11.1 pin with `Package.resolved`; GRDB is isolated to
  persistence implementation and persistence tests.
- Tests: 248 Swift Testing cases in 43 suites, including exactly five Task 003B
  Golden fixtures, the Task 006A 5/5 diplomatic-rule matrix, Task 006B contract
  and vertical-slice cases, the Task 010 false-change Golden and 10,000-Position
  scale gate, Task 011 resource/backup/release-verifier regressions, the
  post-MVP evidence-integrity and public-brand regressions, disposable
  persistence/recovery, task/runtime, media, provider/pipeline/approved-route,
  automation/CLI, and feature-model cases. Three opt-in installed-model tests
  also pass separately on synthetic-only inputs. GitHub Actions runs the
  synthetic-safe warning-as-error gate; no formatter or linter configuration
  exists.
- No database, recovery snapshot, managed media, credential, or runtime
  workspace is committed. Integration tests create and remove only unique
  system-temporary workspaces.

The accepted evidence and original commands are preserved in
`audits/TASK-001_REPOSITORY_AUDIT.md`.

## Implemented layers

| Layer | Current implementation |
| --- | --- |
| Application/UI | Application-owned storage/task/media/provider/secret/policy/review/export/history ports; a native SwiftUI composition root with workspace/media intake, transcript/analysis/briefing review, Meeting History, qualified comparison, visible learned preferences, and controlled export |
| Domain | Task 003A/003B foundations, eight Task 006A intelligence contracts, five Task 006B template/matrix/briefing contracts, Task 007 security contracts, and independent Task 010 `HistoricalComparison.v1` with exact evidence/dependency/security references |
| Persistence and workspace | Workspace/Storage services plus schema v10 job, transcript, analysis, briefing, recording, automation, historical index, learned-preference, migration, and recovery repositories; the v10 history index is local and rebuildable while comparison revisions and preference audit are durable |
| Task execution and recovery | One `LocalTaskManager` actor with explicit state/progress/checkpoint/cancellation/retry contracts, bounded concurrency, startup recovery, stale-input checks, media/AI executors, and the restricted local-only historical-index rebuild executor |
| Media | AVFoundation inspection for MOV/MP4/M4A/MP3/WAV, task-managed copy/hash intake, canonical 16 kHz mono signed-int16 CAF, exact range issues, deterministic overlapped chunks, checkpointed retry, and persistent canonical publication |
| Transcription, translation, and AI | Provider-neutral application contracts; fail-closed model-policy router; Apple SpeechAnalyzer/SpeechTranscriber, TranslationSession, and Foundation Models guided analysis/briefing on macOS 26+; deterministic test providers; protected prompts; Keychain Secret Store |
| Automation/CLI/MCP | Closed local typed Automation Command Layer, audited SQLite-backed dispatcher, strict `meetingbuddy-cli`, and local-only `meetingbuddy-mcp` stdio adapter with a fixed seven-read-tool allowlist; no HTTP server, remote control, or sensitive/destructive MCP command |
| Historical retrieval | Deterministic local filters over confirmed published Positions, exact Evidence/security revision trails, qualified comparison, explicit user-confirmed superseding revisions, and seven visible presentation-only preference types |

Executable package behavior now covers domain validation, workspace/bookmark
selection, managed media intake, schema v10 persistence/recovery, native media
conversion and recording, installed-model or manual transcript/translation
processing, bounded on-device analysis and briefing, deterministic Markdown,
native review/export, Meeting History/preferences, the closed local CLI, and the
local MCP stdio adapter. Xcode 26.6 builds the app under App Sandbox; Task 010
adds no HTTP, remote-control, provider, mail, or network execution path.

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

The one-time post-005A roadmap integration updates only instructions,
architecture, task specifications, acceptance, and ADR text. It does not change
this observed runtime architecture or reopen Task 005A.

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

The accepted Task 003B implementation adds:

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

The domain values remain storage-neutral. Task 004A now persists their exact
canonical revisions, active pointers, dependency edges, and stale state behind
application repository ports.

## Task 004A persistence foundation

The accepted Task 004A implementation adds:

- validated workspace-relative paths and a manifest-owned private workspace;
- streamed file intake to UUID-named managed paths with SHA-256, exact size,
  classification, retention, collision refusal, and Trash restore;
- a GRDB-backed SQLite schema with explicit version/checksum metadata, foreign
  keys, WAL mode, immutable revision/dependency/event triggers, and fail-closed
  preflight for unknown or drifted schemas;
- typed repositories for all eight Task 003A/003B objects, byte-identical
  idempotent insertion, canonical payload digests, normalized metadata checks,
  exact dependency derivation, and managed-source binding checks;
- one active published pointer per logical object, optimistic compare-and-set,
  recursive current-input publication checks, and atomic persistence of pointer
  events, deterministic stale marks, and current stale state;
- online pre-migration backups normalized for standalone read-only use;
- recovery manifests covering a consistent SQLite backup, validated
  export-only semantic JSONL, asset inventory, and migration version, each
  checked for internal consistency by SHA-256 and exact size;
- synchronous compensation for managed-file import/Trash metadata failures and
  disposable failure-injection tests.

## Task 004B task runtime and crash recovery

The accepted Task 004B implementation adds:

- one application-owned job contract with stable IDs, idempotency digests,
  explicit queued/running/pause/cancellation/terminal states, monotonic
  progress, durable checkpoints, retry metadata, provider-usage metadata,
  exact semantic input/output revision references, and job-owned disk leases;
- one `LocalTaskManager` actor with a 1–16 bounded concurrency limit,
  dependency scheduling, cooperative checkpoint pause/resume and cancellation,
  explicit whole-attempt or durable-node retry, synthetic executor injection,
  deterministic startup conversion of unfinished work to `interrupted`, and a
  fail-closed health result when disk capacity is unknown or a bounded orphan
  or managed-asset recovery scan is truncated;
- SQLite schema version 2 with canonical digest-checked job snapshots,
  optimistic replacement, immutable state events, dependency/input/output
  indexes, uniqueness-backed idempotency, health checks, and an atomic
  stale-input recheck in the success transaction;
- `.tasks/<job-id>` allocation with per-job byte budgets, private permissions,
  confined writes, bounded entry scans, safe terminal cleanup, and
  age/count/symlink-bounded orphan cleanup;
- structured JSONL plus OSLog-compatible logging with private-value removal,
  credential-pattern redaction, value/file/count/retention bounds, rotation,
  and private permissions;
- a durable managed-asset intent/event journal and deterministic startup
  reconciliation for interrupted import, Trash, and restore operations,
  including exact owned-staging cleanup and fail-closed repair reporting;
- disposable state-machine, concurrency, pause/resume, cancellation, retry,
  restart, migration, redaction/rotation, confinement, orphan, and
  filesystem/SQLite interruption tests.

## Task 005A local media and native review

The Task 005A implementation adds:

- accepted ADR-0002 Option A entitlements: App Sandbox, app-scoped bookmarks,
  and user-selected read/write file authority only;
- one persistent app-scoped bookmark for the validated user-selected workspace,
  plus transient source-file scope that ends after the task-managed verified
  copy; no source path or bookmark enters durable job state;
- a SwiftUI `NavigationSplitView` for workspace choice, meeting title,
  classification/language, media selection, explicit multi-track choice,
  speech provenance, managed hash/status, progress, cancellation, and retry;
- real AVFoundation inspection/import coverage for MOV, MP4, M4A, MP3, and WAV,
  with one explicit audio track and no external executable;
- persistent untouched original and generated canonical `SourceAsset.v1`
  revisions, with canonical signed-int16 little-endian interleaved mono PCM in
  CAF at 16 kHz;
- zero-based half-open frame timelines, exact missing/corrupt/decode-failed
  issues, a 50 ms duration tolerance, 30-second cores, and one second of
  context on each side;
- Task-Manager-owned acquisition, streamed output leases, digest/size
  revalidation, compact three-hour checkpoints, chunk-level retry reuse,
  cooperative cancellation, and bounded cleanup;
- a local build/run script and Codex Run action that stage an ad-hoc signed app
  bundle for development verification without claiming release signing.

## Task 005B local transcript and review implementation

The accepted Task 005B work adds:

- `MeetingBuddyAI` adapters for installed Apple Speech and Translation models
  on macOS 26+, with no model download, outbound adapter, or third-party
  dependency, plus a validated human-entered fallback on every supported OS;
- an application-owned policy router over classification, offline mode,
  organization policy, environment, destination, retention, bounded data
  categories, visible authorization, and local availability;
- a macOS Keychain-backed Secret Store port with no plaintext fallback;
- a single Task-Manager transcript pipeline with bounded regenerated chunks,
  structured span validation, deterministic overlap ownership, checkpointed
  retry reuse, cooperative cancellation, provider usage, and atomic stale-input
  publication refusal;
- immutable schema v3 transcript coverage manifests that bind the exact
  canonical source, plan/ranges, route, provider result, stable segment IDs,
  explicit no-speech/failed/missing state, and content hash; only exact 100
  percent core accounting can become active;
- separate immutable transcript and translation revisions, human corrections
  linked to exact prior revisions, deterministic dependent staleness, and exact
  user-confirmed speaker-assignment revisions;
- a SwiftUI transcript workspace with route/policy disclosure, coverage,
  source and translation editors, and uncertain-speaker confirmation.

## Task 006A evidence-linked analysis implementation

The accepted Task 006A work adds:

- independent immutable `Participant.v1`, `Organization.v1`, `Issue.v1`,
  `Position.v1`, `Commitment.v1`, `Decision.v1`, `InterventionCard.v1`, and
  `DelegationPositionCard.v1` contracts with typed claim, qualification,
  confidence, review, provenance, and exact-evidence fields;
- one approved local-device route using Apple Foundation Models guided
  generation on macOS 26+, a fresh no-tool session per reviewed segment,
  application-owned protected rules, no model download, and no outbound or
  Private Cloud Compute adapter;
- provider-neutral request/output contracts and deterministic semantic
  construction that preserve actor/capacity, classification, reservations,
  conditions, commitments, uncertain decisions, and exact source revisions;
- one Task-Manager analysis pipeline and immutable route/prompt/input/runtime/
  segment coverage ledger; publication fails unless every eligible reviewed
  transcript segment is exactly substantive or explicitly non-substantive;
- schema v4 persistence for the eight new object types, normalized immutable
  analysis-ledger history, active/event pointers, atomic publication, recovery,
  exact dependency edges, and downstream stale marks;
- an Analysis Review workspace showing the route, explicit **Analyze Locally**
  authorization, prompt/input hashes, full coverage, typed intervention and
  delegation-position cards, exact evidence, identity/capacity, correction,
  and stale state.

## Task 006B structured briefing implementation

The accepted Task 006B work adds:

- immutable `MeetingTemplate.v1`, `IssuePositionGraph.v1`,
  `BriefingSection.v1`, `ValidationReport.v1`, and `FinalBriefing.v1`
  contracts plus a single built-in multilateral template and three exact
  independently generated sections;
- a sparse issue-by-represented-entity matrix that preserves every exact
  current Position revision, polarity, statement, reservation, condition, and
  optional exact delegation card without inferring missing cells or group
  alignment;
- one local Apple Foundation Models guided section provider over bounded
  validated intelligence claims/evidence identifiers, with fresh no-tool
  sessions and no raw transcript, audio, external fallback, or second reviewer;
- a zero-source-text-overlap hierarchical coverage ledger and ten-category
  deterministic fail-closed validation, including exact conclusion/evidence
  navigation, qualification preservation, and prohibited historical claims;
- Task-Manager-owned initial generation and exact one-section regeneration;
  immutable user edits/locks and atomic section/report/final/ledger replacement;
- schema v5 semantic repositories, normalized briefing ledgers/indexes,
  pointer/events, controlled export records, migration/rollback/recovery, and
  downstream stale propagation;
- a Briefing Review workspace with route proof, validation/coverage/matrix
  state, per-section editor/lock/regeneration, deterministic preview, and
  explicit classification-checked local Markdown export.

Exact versions, hashes, verification evidence, and limitations are recorded in
[`BRIEFING_FOUNDATION.md`](BRIEFING_FOUNDATION.md).

## Task 009A shared automation command implementation

The accepted Task 009A work adds a closed typed command
catalog in `MeetingBuddyApplication`, one shared dispatcher and strict CLI
adapter in `MeetingBuddyAutomation`, a thin `meetingbuddy-cli` composition
root, and SQLite v8 audit/settings authority. Permissions come only from the
trusted composition root; replay nonces and recursion metadata fail closed;
meeting policy status binds the exact active/current MeetingProfile,
SensitivityLabel, and AccessPolicy graph; diagnostics use one restricted task
directory; and the only mutable value is a versioned, compare-and-swap,
server-side-reversible activity-list bound.

No export, provider/model execution, recording, job mutation, destructive
filesystem operation, credential/access-policy mutation, arbitrary path/SQL,
network control, MCP, or HTTP command exists. Exact catalog, policy, audit,
migration, CLI, test, and rollback evidence is recorded in
[`TASK_009A_AUTOMATION.md`](TASK_009A_AUTOMATION.md) and
[ADR-0014](adr/ADR-0014-task-009a-automation-command-boundary.md).

## Task 010 historical review and learned preferences

The accepted Task 010 work adds:

- deterministic local actor/country, organization, topic, body, meeting-type,
  issue, date, review-status, and classification-filter contracts over exact
  confirmed published Position revisions;
- schema v10 generation-stamped Position/topic/Evidence search tables, dirty
  triggers, index enable/disable, atomic rebuild, and a restricted local-only
  Task Manager executor;
- query-time exact SensitivityLabel/AccessPolicy/current-state reauthorization
  before content or counts are returned;
- immutable `HistoricalComparison.v1` with exact current/historical Position,
  Meeting, Actor, Issue, security, Evidence, effective date/time, and confidence
  fields; wording-only differences cannot become confirmed change;
- a user-only superseding confirmation revision for evidence-supported possible
  differences;
- exact-integrity evidence-admission contracts for already-authorized versioned
  document, bounded local email import, and approved public-source `SourceAsset`
  revisions, without granting mail/network/file authority;
- seven typed, visible, editable, disableable, removable, resettable
  presentation-only preferences with optimistic versions and immutable
  content-free audit metadata;
- SwiftUI Meeting History, Historical Context Search, comparison, evidence,
  effective-time, and Learned Preferences controls.

The detailed semantics, rollback boundary, and limitations are recorded in
[`HISTORICAL_REVIEW.md`](HISTORICAL_REVIEW.md) and
[ADR-0016](adr/ADR-0016-task-010-historical-review-and-preferences.md).

## Task 011 release audit and hardening

The accepted Task 011 work keeps schema v10 and the existing feature routes,
while adding three-hour canonical planning, 32-track media-inspection, streamed
copy byte-limit, monotonic blocked-HTML cleanup, and recording-reconciliation
restore guards. It also adds an app privacy manifest, bundled GRDB privacy and
MIT-license resources, coherent clean-scratch local packaging verification,
and cold synthetic whole-workspace backup verification.

The selected arm64 app passes the 242-test suite, migration/recovery, closed
bundle layout, ad-hoc Hardened Runtime, exact-entitlement, local launch, idle
network, privacy, dependency, license, and synthetic backup gates. It remains
INTERNAL ALPHA because Developer ID/Team ID, notarization/stapling, affirmative
Gatekeeper distribution approval, clean-machine install/update/rollback,
approved icon/localization, manual accessibility, and intended-OS live
TCC/capture remain unresolved. At the Task 011 gate, four medium
evidence-integrity findings also remained unresolved; the later post-MVP
remediation is recorded separately below. Three low scan findings are mitigated
in accepted source but require a follow-up scan.

Exact gate results and residual constraints are recorded in
[`TASK_011_RELEASE_CANDIDATE_AUDIT.md`](TASK_011_RELEASE_CANDIDATE_AUDIT.md)
and [`audits/TASK-011_VERIFICATION_EVIDENCE.md`](audits/TASK-011_VERIFICATION_EVIDENCE.md).

## Post-MVP evidence-integrity remediation

The separately authorized remediation adds no schema migration, provider,
network route, dependency, or product capability. It closes the four Task 011
medium paths through conservative publication boundaries:

- provider-only `noSpeech` cannot close transcript coverage without
  application-owned exact-digital-silence confirmation over the exact core;
- provider-only `nonSubstantive` cannot omit meaningful text and requires an
  exact revision/text-digest confirmation under a closed marker policy;
- analysis candidates remain quarantined until the user confirms the exact
  active candidate ledger ID, hash, and every claim; and
- local briefing export requires all exact current sections and the final to be
  user-created and confirmed.

The current full suite passes 248 tests in 43 suites with zero failures; the
three installed Apple-model tests remain opt-in. Exact contracts, compatibility,
and residual risk are recorded in [ADR-0017](adr/ADR-0017-evidence-integrity-publication-boundaries.md)
and [`audits/TASK-012_SECURITY_REMEDIATION.md`](audits/TASK-012_SECURITY_REMEDIATION.md).

## Known limitations

- There is no Xcode project, external/cloud provider, outbound meeting-data
  route, HTTP/remote automation adapter, or sensitive/destructive CLI or MCP
  command. The native transcript, analysis, briefing, recording, bounded local
  CLI, and local stdio MCP surfaces are task scope, not final visual,
  accessibility, or release polish.
- Xcode 26.6 build 17F113 is installed and selected. Standard debug/release
  builds and `swift test` pass, and a native run verifies sandbox initialization,
  the workspace Open panel, synthetic-workspace bookmark persistence, and
  scoped-bookmark restoration after relaunch.
- The staged bundle is ad-hoc signed with Hardened Runtime and is local
  internal-alpha evidence only. Task 011 confirms that no valid Developer ID,
  Team ID, notarization ticket, affirmative Gatekeeper distribution result, or
  clean-machine proof exists.
- Accepted Task 011 status is `d31b9aa`; implementation is `852257c`, and
  `f371faa` is the pre-Task-011 rollback anchor after the authorized
  private-path and GitHub-noreply history sanitizations.
- The semantic JSONL recovery artifact is deliberately export-only; exact
  operational recovery relies on the verified SQLite online backup. A user-
  facing restore workflow is not implemented.
- Managed-asset process-crash windows now have a durable journal and bounded
  startup reconciliation. A user-facing repair/restore UI and automatic Trash
  purge remain unimplemented.
- ADR-0002 and the canonical media parameters are resolved. Task 011 verified
  the exact five accepted app entitlements, but Developer ID signing,
  notarization, automatic updates, and any distribution remain separately
  authorized and incomplete.
- Task 006B has only one multilateral template/three sections, no full stale-
  briefing refresh action, no independent truth-review provider, and
  conservative lexical/exact-qualification contradiction checks. Task 010
  retrieval is likewise conservative lexical/exact identity rather than fuzzy
  geopolitical inference. The post-MVP controls require exact human
  confirmation for consequential analysis and briefing export, but human review
  remains fallible and is not automatic truth verification.

## Next permitted transition

Tasks 001 through 011 are accepted, and there is no next eligible numbered MVP
task. Any post-MVP capability must be explicitly promoted into a new numbered
task. Commit, push, tag, notarization, release, upload, installation, and
distribution remain separate user-authorized actions.
