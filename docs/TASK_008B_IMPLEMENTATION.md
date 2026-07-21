# Task 008B UN Web TV and Live-Capture Implementation

Status: Completed pending user acceptance; interactive native-device/TCC proof remains a documented release-validation gap
Date: 2026-07-19
Scope: Only the D1-D5 capability boundary accepted in Task 008A
Pre-task rollback anchor: Git HEAD `e03d05bbf635ebf0af2c668d24e14f1bd73e3255`
Binding decision: [ADR-0013](adr/ADR-0013-task-008a-capture-and-un-web-tv-boundary.md)

## Outcome

MeetingBuddy now has an incrementally durable, audio-only recording path for:

1. an explicitly selected microphone;
2. one application explicitly selected in Apple's system content picker; or
3. those two sources as independent synchronized tracks.

The app creates durable intent and a fresh capture epoch before any provider
starts. It bounds packet buffering and open CAF segments, seals and proves
segment files before committing checkpoints, retains usable bytes after
interruption, and publishes immutable source assets only after finalization
proof. Recording state and Stop remain visible throughout the app. Resume is
explicit, requires a new source selection and acknowledgement, and creates a
new epoch rather than silently substituting a source.

The separately authorized UN Web TV route is metadata-only. It performs one
explicit, credential-free request to a validated exact-host asset page and
returns bounded, untrusted field candidates for review. It exposes no media,
player, playlist, track-discovery, download, browser-credential, or recording
route. Local-file import and manual metadata entry remain the fallback.

No dependency was added. No real microphone/application recording, UN Web TV
request, user workspace migration, or user media write was performed during
implementation verification.

## Accepted-capability traceability

| Task 008A decision | Implemented result | Evidence |
| --- | --- | --- |
| D1: three visible audio-only modes and explicit exclusions | `MacOSAudioCaptureProvider` uses AVFoundation for microphone-only capture and ScreenCaptureKit's `.singleApplication` picker for application audio; it adds only audio/microphone stream outputs and keeps tracks separate | Capture contracts, provider source, UI source checks, packet-relay and interruption tests |
| D2: least entitlement and purpose-string surface | Added only sandbox microphone input and outbound client entitlements plus truthful microphone/system-audio purpose strings; no persistent-content-capture, server, camera, or screen-pixel authority | Plist lint, staged-app entitlement extraction, static forbidden-surface scan |
| D3: exact-host `METADATA_ONLY_NETWORK` | URL validation, every redirect, response status/type/size, authentication challenges, and no-outbound policy fail closed; parsing is bounded and field-provenanced | Synthetic URL transport/parser tests and URL rejection matrix |
| D4: no UN footage acquisition without separately reviewed authority | No acquisition interface or media-return type exists; the UI discloses the no-go and directs the user to the official page/manual local import | Application contracts, adapter source, UI source checks, forbidden media-route scan |
| D5: schema 007, bounded durability, separate provenance, non-auto-active incomplete state | Added recording sessions, events, tracks, epochs, segments, gaps, and checkpoints; finalization emits one manifest plus one SourceAsset per track; interrupted material remains visible but unpublished | v6-to-v7 migration proof, persistence/recovery/finalization tests, manifest tests |

## Runtime design

### Capture authority and lifecycle

The visible workflow is:

```text
explicit mode/source choice + authority acknowledgement
  -> durable RecordingIntent and epoch
  -> transient native selection authorization
  -> Task Manager recording job
  -> bounded per-track packet relay
  -> application-owned segment/checkpoint coordinator
  -> verified manifest and per-track SourceAssets
```

The durable state machine is `preparing`, `recording`, `interrupted`,
`recovering`, `stopping`, `finalizing`, `completed`, `incomplete`, and `failed`.
Unknown future state, checkpoint, manifest, and job payload values fail closed.

The provider receives no database or unrestricted workspace path. Raw
microphone identifiers and selected-application identity remain transient;
durable provenance uses a session-scoped SHA-256 continuity token. On source
stop, format change, queue overflow, checkpoint failure, disk-budget breach, or
native interruption, capture stops admitting packets and records a truthful
interrupted/incomplete path. AVFoundation runtime-error, interruption, and
unexpected-stop notifications now terminate microphone capture exactly once;
the observer is disarmed before a normal user Stop.

### Durability and checkpoint contract

- Each authoritative track uses linear-PCM CAF segments.
- Nominal segment media span is five seconds; the hard open-span limit is six
  seconds.
- Each track's queued media is capped at two seconds. Overflow interrupts the
  source; no packet is silently dropped.
- A segment is sealed, synchronized, structurally validated, SHA-256 hashed,
  and atomically renamed before the segment and checkpoint commit.
- The persistence repository rejects a checkpoint committed more than one
  second after its associated segment was sealed.
- Checkpoint payloads are bounded to 65,536 bytes and bind exact per-track
  cursors.
- The cumulative recording disk budget is checked while admitting data.
- Finalization re-verifies staged and managed bytes independently and is
  idempotent across a crash after semantic publication.
- Source segment files move to MeetingBuddy Trash only after the terminal
  completed state commits. Incomplete, failed, partial, orphaned, or tampered
  evidence is retained for review/recovery.

`completed` requires every requested track, a verified final CAF, an immutable
capture manifest, and exact dependency publication. `incomplete` keeps usable
bytes and gaps but creates no automatically active meeting source. A zero-byte
recording never publishes a SourceAsset.

### Restart recovery

Startup recording recovery runs before Task Manager recovery. A process gap
moves an active session through `interrupted` and `recovering`, re-proves sealed
CAF files, rebuilds a damaged latest checkpoint only from immutable rows and
verified files, and classifies partial/orphan/tampered files without deleting
them. Gap identities are deterministic, so repeated recovery is idempotent.

An explicit Resume action is available only for a retryable interrupted job.
It requires fresh microphone/application selection and a fresh authority
acknowledgement, persists a new sequential epoch, and only then retries the
Task Manager job. Workspace switching is blocked while a recording is
nonterminal.

### App termination and visible control

The SwiftUI app uses a narrow AppKit application-delegate bridge to guard Quit.
When a recording is active, the app offers either **Stop, Finalize, and Quit**
or **Keep Recording**. It delays termination while finalizing and cancels Quit
if a terminal state is not reached within the bounded wait. The disclosure
also explains that force quit may leave recoverable incomplete audio.

The root view keeps a recording-status banner and Stop action visible across
navigation. The capture view exposes source mode, explicit microphone choice,
authority acknowledgement, current state, progress, gaps, Resume, and retained
incomplete status. It exposes no screen/video capture choice.

## UN Web TV metadata-only boundary

The adapter accepts only:

```text
https://webtv.un.org/{supported-locale}/asset/{opaque}/{opaque}
```

It rejects user information, query, fragment, IP literals, non-default ports,
lookalike/subdomain/suffix hosts, encoded separators, unsupported locales, and
unbounded path components. The ephemeral session allows one foreground GET,
ordinary platform TLS, no cookie or credential storage, no cache, no
background transfer, at most two exact-host HTTPS redirects, HTTP 200,
`text/html`, bounded headers, and at most 1 MiB of decoded HTML. Authentication
challenges other than ordinary server trust fail closed.

The parser removes active/non-content markup, normalizes bounded plain text,
surfaces conflicts, and returns only approved metadata fields. Each candidate
binds the canonical page URL, retrieval time, parser version, field source,
normalized-value SHA-256, and confidence. It stores no raw HTML by default and
never executes JavaScript or fetches a subresource.

The UI requires an explicit request, displays field provenance, allows a local
correction draft, links to the official page, and preserves manual local-file
import. Metadata does not create a media SourceAsset. Kaltura/player/media,
playlist, language-track discovery, download, browser recording, cookies,
credentials, and redistribution remain absent and out of scope.

## Schema 007 and compatibility

Migration `007_recording_capture_foundation` adds these operational tables:

- `recording_sessions`
- `recording_state_events`
- `recording_tracks`
- `recording_epochs`
- `recording_segments`
- `recording_gaps`
- `recording_checkpoints`

State events, tracks, epochs, segments, gaps, and checkpoints are append-only
under database triggers. Fresh-schema tests cover all tables. The accepted-v6
migration fixture proves exact preservation of the semantic payload, a verified
v6 online backup with `quick_check=ok` and zero foreign-key failures, and the
absence of v7 tables in that rollback copy. Supported prior migrations remain
ordered and migration failure retains the verified backup.

A v6 binary must not open v7 in place. Before real v7 recording data exists,
the verified v6 backup is the downgrade anchor. After capture data exists,
feature rollback means disabling capture/network routes while retaining the v7
workspace; restoring v6 would omit the new recording evidence and is not a
safe default rollback.

## Automated evidence

### Synthetic capture and recovery matrix

| Scenario | Result |
| --- | --- |
| Normal 5.1-second capture | Two verified segments, checkpoint at the five-second boundary, separate manifest/audio dependencies, completed terminal state, source segments trashed only afterward |
| Provider/source loss after usable bytes | Partial bytes sealed where possible, explicit gap, visible incomplete state, no SourceAsset publication |
| Bounded disk budget | Admission stops, partial evidence retained, failed terminal state, no publication |
| Process restart | Sealed CAF re-proved, deterministic process gap recorded, repeat recovery idempotent |
| Corrupt latest checkpoint | Rebuilt from immutable database rows and verified CAF files, then stable across repeat recovery |
| Tampered segment | Bytes retained and classified, never counted complete or published, repeated recovery stable |
| Crash after semantic publication | Exact staging and immutable revisions reused; restart completes atomically and trashes source segments only after commit |
| Stop before first byte | Failed without zero-byte asset; partial inventory remains classified |
| Task Manager cancellation after a sealed segment | Visible Stop, provider starts only after durable intent, cancellation-independent cleanup reaches completed publication |
| Interrupted job resume | Retry requires fresh authorization and a new epoch; retained prior bytes stay incomplete because the gap remains truthful |
| AVFoundation runtime error/interruption/unexpected stop | Injected notification ends microphone capture once; normal Stop disarms the observer |

### Web, contract, and UI matrix

- Exact recording transition-pair validation and unknown-future payload
  rejection pass.
- Three-hour synthetic cursor/checkpoint bounds pass without retaining meeting-
  duration packet memory.
- Manifest round-trip, future-version rejection, and inconsistent provenance
  rejection pass.
- Exact-host URL acceptance/rejection, markup/script/media exclusion,
  conflict/provenance hashing, no-outbound-before-network, single-request,
  credential-free, status/MIME/body-limit, and no-subresource tests pass.
- The two-second-equivalent packet queue admits its bound and reports overflow
  without silent loss.
- Source checks confirm the persistent recording banner, visible Stop, explicit
  acknowledgement, Resume/new-epoch disclosure, incomplete status, exact web
  boundary, manual fallback, and absence of a screen-capture choice.

### Commands and results

| Command | Result |
| --- | --- |
| `swift test --enable-swift-testing --parallel -Xswiftc -warnings-as-errors` | 212 tests in 37 suites pass; three opt-in Apple installed-model routes are skipped by design |
| `swift build -Xswiftc -warnings-as-errors` | Debug build passes |
| `swift build -c release -Xswiftc -warnings-as-errors` | Release build passes |
| `swift package dump-package` and `swift package show-dependencies` | Package resolves; dependency surface is unchanged |
| `plutil -lint Configuration/MeetingBuddy-Info.plist Configuration/MeetingBuddy.entitlements` | Both files valid |
| `MEETINGBUDDY_SIGN_IDENTITY=- ./script/build_and_run.sh --stage-only` | Current app stages and signs without launching or restoring a real workspace |
| `codesign --verify --deep --strict --verbose=2 dist/MeetingBuddy.app` | Staged diagnostic app verifies |
| staged-app `codesign -d --entitlements :-` inspection | Sandbox, microphone input, outbound client, app-scoped bookmark, and user-selected read/write only |
| `git diff --check` and forbidden-surface scans | No whitespace error; no screen recording output, persistent capture entitlement, generic fetch route, or production media-acquisition surface |

The ad-hoc staged app is diagnostic evidence only. It is not Developer ID,
notarization, Gatekeeper, clean-machine, or distribution proof.

## Native device and permission matrix

| Native case | Automated/static proof | Interactive status |
| --- | --- | --- |
| Microphone grant/deny | Purpose string, sandbox entitlement, AVFoundation permission gate, fail-closed contract compile and tests | Not run; requires user-controlled TCC choice and a non-sensitive selected input |
| Permission revoked during capture | Runtime stop/interruption path and deterministic injected notification test | Not run against live TCC |
| Microphone unplug/change | No silent device replacement; source-stop/format-change path and new-epoch resume tests | Not run with physical/virtual device removal |
| One-application picker grant/cancel | `.singleApplication`, session-scoped filter, one included application required, cancel/invalid-selection errors compile | Not run with Apple's interactive picker |
| Application exits or stream is stopped | ScreenCaptureKit delegate ends each source relay and retains incomplete data | Not run with a selected application |
| Microphone plus application audio | Separate output types, track IDs, files, manifest entries, and publication contracts compile/test | Not run as a live two-track recording |
| Sleep/OS interruption | AVFoundation notifications and ScreenCaptureKit delegate map to interrupted capture | Injected only; no real sleep cycle |
| Quit while recording | AppKit termination guard source/build/accessibility checks | Not exercised against real capture |
| Long native capture and process kill | Five/six-second, three-hour cursor, recovery, corruption, and crash-fault tests pass with synthetic CAF | No real multi-hour native capture, SIGKILL, or sudden-power-loss run |

Running these rows would require the user to approve TCC, choose an application
or microphone, and potentially capture private ambient/application audio. This
Task did not infer that authorization. Until those rows are completed on the
intended signed identity on macOS 15 and the current supported macOS release,
native permission/device behavior is a stated proof gap and the build is not a
release candidate.

## Exact Task 008B change surface

Configuration and packaging:

- `Configuration/MeetingBuddy-Info.plist`
- `Configuration/MeetingBuddy.entitlements`
- `script/build_and_run.sh`

Application and domain/application contracts:

- `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`
- `Sources/MeetingBuddyApp/MeetingBuddyApp.swift`
- `Sources/MeetingBuddyApplication/CaptureManifestContracts.swift`
- `Sources/MeetingBuddyApplication/CaptureProviderContracts.swift`
- `Sources/MeetingBuddyApplication/MediaReviewWorkflow.swift`
- `Sources/MeetingBuddyApplication/RecordingCaptureJobContracts.swift`
- `Sources/MeetingBuddyApplication/RecordingContracts.swift`
- `Sources/MeetingBuddyApplication/RecordingFileContracts.swift`
- `Sources/MeetingBuddyApplication/UNWebTVMetadataContracts.swift`
- `Sources/MeetingBuddyApplication/WorkspaceContracts.swift`

Media, persistence, and recovery:

- `Sources/MeetingBuddyMedia/CapturePacketRelay.swift`
- `Sources/MeetingBuddyMedia/CaptureSourceAssetFactory.swift`
- `Sources/MeetingBuddyMedia/MacOSAudioCaptureProvider.swift`
- `Sources/MeetingBuddyMedia/RecordingCaptureJobExecutor.swift`
- `Sources/MeetingBuddyMedia/RecordingPersistenceCoordinator.swift`
- `Sources/MeetingBuddyMedia/UNWebTVMetadataHTMLParser.swift`
- `Sources/MeetingBuddyMedia/URLSessionUNWebTVMetadataSource.swift`
- `Sources/MeetingBuddyPersistence/LocalRecordingFileStore.swift`
- `Sources/MeetingBuddyPersistence/LocalRecordingRecoveryService.swift`
- `Sources/MeetingBuddyPersistence/SQLiteRecordingSessionRepository.swift`
- `Sources/MeetingBuddyPersistence/SQLiteSchema.swift`

Features:

- `Sources/MeetingBuddyFeatures/Models/MediaReviewModels.swift`
- `Sources/MeetingBuddyFeatures/Stores/MediaReviewStore.swift`
- `Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift`
- `Sources/MeetingBuddyFeatures/Views/RecordingCaptureView.swift`
- `Sources/MeetingBuddyFeatures/Views/UNWebTVMetadataView.swift`

Tests and execution evidence:

- `Tests/MeetingBuddyAITests/AnalysisPipelineIntegrationTests.swift`
- `Tests/MeetingBuddyFeaturesTests/Task008BViewAccessibilityTests.swift`
- `Tests/MeetingBuddyMediaTests/RecordingContractAndMetadataTests.swift`
- `Tests/MeetingBuddyMediaTests/RecordingPersistenceIntegrationTests.swift`
- `Tests/MeetingBuddyPersistenceTests/RecoveryAndTrashTests.swift`
- `Tests/MeetingBuddyPersistenceTests/WorkspaceAndMigrationTests.swift`
- `docs/TASK_008B_IMPLEMENTATION.md`
- `docs/CODEX_EXECUTION_STATE.md`

The twenty pre-existing dirty planning/governance/architecture/ADR files were
not part of this implementation and remain preserved. `Package.swift` and
`Package.resolved` are unchanged.

## Rollback and residual risk

- Code rollback anchor: `e03d05bbf635ebf0af2c668d24e14f1bd73e3255`.
- Data rollback anchor before first real v7 capture: the verified schema-v6
  online backup created by migration.
- After v7 recording data exists, disable capture/network routes while keeping
  the v7 workspace; never delete incomplete/user recordings or restore v6 by
  default.
- Removing the new entitlements disables future capture/metadata access but
  does not make existing v7 data unreadable to the current code.
- Unsupported or changed web pages always retain official-page/manual metadata
  and local-file import fallback.
- Real TCC, hardware/device changes, application exits, sleep, force kill,
  long-duration native I/O, and sudden power loss remain unverified as described
  in the native matrix.
- No universal UN Web TV, UN media acquisition, redistribution, screen/video,
  all-system, multi-app, hidden/background/persistent capture, cloud processing,
  real-time coaching, or response recommendation is claimed or implemented.

No branch, commit, tag, push, release, deployment, or next-task work was
performed.
