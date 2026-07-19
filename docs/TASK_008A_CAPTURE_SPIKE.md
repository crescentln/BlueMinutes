# Task 008A UN Web TV and Live-Capture Spike

Status: Accepted with decisions D1-D5 on 2026-07-19; Task 008B remains separately user-gated
Date: 2026-07-19
Scope: Research, architecture, policy boundaries, and executable test design only
Rollback anchor: Git HEAD `75b11e202c9f10611aada76445f1e5eb2346c914`
Related decision: [ADR-0013](adr/ADR-0013-task-008a-capture-and-un-web-tv-boundary.md)

## Outcome

Task 008B has a technically viable, local-first audio-capture path, but it does
not have a lawful or resilient basis for automatic UN Web TV media acquisition.
The accepted Task 008B boundary therefore keeps two adapters and two authority
boundaries:

1. an audio-only native capture adapter for a microphone, one application
   explicitly selected in Apple's system picker, or both as separate tracks;
2. an optional, user-triggered UN Web TV **metadata-only** adapter that reads
   one pasted public asset page from the exact `webtv.un.org` host and never
   discovers, downloads, or records its media.

The existing local-file import remains the universal fallback. Capturing UN Web
TV footage, extracting Kaltura media or language-track URLs, downloading media,
and redistributing recordings are outside the accepted Task 008B boundary.
UN's current dedicated copyright page says UN footage is not public domain and
requires UN authorization and a licence agreement. Whether a particular local
recording or internal machine-analysis use is permitted is a legal uncertainty,
not a technical inference; Task 008B must not assume permission.

No production code, dependency, entitlement, Info.plist key, schema, real
recording, user workspace, or media asset was changed by this spike.

## Decision vocabulary

- **Accepted baseline** means a binding earlier MeetingBuddy decision that this
  spike preserves; it does not require a new Task 008A choice.
- **Accepted Task 008B boundary** means the user accepted the capability and
  constraints for a later separately authorized Task 008B implementation.
- **Legal/rights-gated** means implementation or use remains disabled until the
  relevant rights are documented; a user acknowledgement alone is not proof of
  permission.
- **Rejected for Task 008B** means the capability must not be implemented in
  Task 008B even if it is technically possible.
- **Deferred** means it needs a later design and separate authorization.

## Current baseline and bounded probes

### Repository and host

- Task 007 is accepted. The startup ledger had no open P0/P1 decision and named
  Task 008A as the next eligible task.
- The current source and tests are clean relative to Git. Twenty pre-existing
  planning/governance/ADR files were already dirty and are preserved.
- The package remains Swift 6, macOS 15+, and has exactly one package
  dependency: GRDB 7.11.1.
- The host probe used macOS 26.5.2, Xcode 26.6, the macOS 26.5 SDK, and Swift
  6.3.3. The deployment minimum remains macOS 15; this spike does not raise it.
- The current ad-hoc `dist/MeetingBuddy.app` is sandboxed and has only
  app-scoped bookmarks and user-selected read/write file access. It has no
  microphone, network client, or persistent content-capture entitlement.
- The current Info.plist has neither `NSMicrophoneUsageDescription` nor
  `NSAudioCaptureUsageDescription`.

These observations describe the current local build, not a Developer ID,
notarized, clean-machine, or App Store distribution result.

### Read-only external probes

On 2026-07-19, two public UN Web TV asset pages returned HTTP 200 without a
credential or authentication challenge. No media request was made. The probes
read only response headers, HTML metadata/field names, the public robots file,
and the public copyright/terms pages.

Representative pages:

- <https://webtv.un.org/en/asset/k1t/k1tezmm4d8>
- <https://webtv.un.org/en/asset/k1d/k1dmvhubyu>
- <https://webtv.un.org/robots.txt>
- <https://webtv.un.org/en/copyright_use>
- <https://www.un.org/en/about-us/terms-of-use>

The probes did not execute page JavaScript, call a Kaltura API, enumerate media
playlists, request a stream, acquire a token, authenticate, or retain a copy of
page/media content in the repository.

## Evidence classification

| Finding | Classification | Consequence |
| --- | --- | --- |
| Current asset URLs use a locale plus `/asset/<opaque>/<opaque>` path | Point-in-time technical observation | Treat both identifiers as bounded opaque values, not a permanent ID grammar |
| Public sampled pages returned HTML without credentials | Point-in-time technical observation | A future challenge, login, or 401/403 must fail to manual fallback |
| Current HTML exposes canonical URL, title, description, date, duration, categories, language labels, and broadcasting entity | Point-in-time technical observation | These may be metadata candidates, each with field-level provenance and user review |
| Current pages load a Kaltura JavaScript player from an opaque entry ID | Point-in-time technical observation | It is implementation detail, not an approved or stable acquisition API |
| Page `Asset Language` values and runtime player tracks are separate surfaces | Technical observation plus uncertainty | Never infer original-versus-interpretation provenance from the page list alone |
| UN's dedicated page says UN footage is not public domain and use requires authorization/licensing | Primary-source policy statement | Default no-go for acquiring or recording UN footage without documented authority |
| UN's general terms discuss personal non-commercial use subject to specific restrictions | Primary-source policy statement | Do not resolve the interaction with the dedicated footage rule; obtain legal/UN confirmation |
| A user says they may record | Product acknowledgement | Useful safety evidence, but not a licence or legal conclusion |
| Apple provides ScreenCaptureKit application/system audio and microphone output on supported macOS versions | Current official platform capability | A native audio-only adapter is feasible; behavior still needs signed manual validation |
| Apple's system content picker scopes a capture session to explicit user selection | Current official platform behavior | Prefer it to broad app/window discovery and persistent capture authority |

## UN Web TV technical findings

### URL and page shape

The sampled canonical form is:

```text
https://webtv.un.org/{locale}/asset/{opaque-group}/{opaque-asset}
```

Current alternate links expose `ar`, `zh`, `en`, `fr`, `ru`, and `es`. The
sample identifiers contain lowercase ASCII letters and digits, and the second
identifier shares a suffix with the current Kaltura entry ID. Those are
observations only. Task 008B must not hard-code current identifier lengths,
derive one identifier from another, or promise that the pattern is permanent.

The metadata-only URL validator should instead require:

- `https` and default port 443;
- exact, case-normalized host `webtv.un.org`, not a suffix or wildcard;
- no user information, IP literal, fragment, or query;
- exactly one supported locale and the `asset` path component;
- exactly two non-empty, URL-safe opaque identifiers, each at most 64 bytes;
- a canonical response URL that passes the same validation.

An unrecognized locale or page shape goes to manual entry. It is not guessed.

### Available metadata

The current pages expose the following without executing JavaScript:

- canonical URL and page locale;
- Open Graph title and description;
- production date in a `<time datetime>` value;
- displayed video length;
- category hierarchy;
- `Asset Language` labels;
- broadcasting UN entity;
- summary and description.

Every value is untrusted page content. Task 008B must normalize it to bounded
plain text, reject control characters/markup in application contracts, and
present it as a candidate for user review. It must not store full HTML by
default or treat page text as instructions.

Field provenance must include at least:

- the exact canonical page URL;
- retrieval time;
- parser strategy and version;
- field source such as `og:title`, production-date field, or visible label;
- normalized-value SHA-256 and confidence;
- whether the user confirmed or replaced the value.

### Media and language tracks

The current asset page embeds a Kaltura PlayKit script, an opaque partner/UI
configuration, and an entry ID, then calls the client player. The page script
can inspect runtime audio tracks. This demonstrates a mechanism used by the
current website; it does not establish a public, supported, licensed, or stable
media API for MeetingBuddy.

The visible `Asset Language` list is availability metadata. It does not prove:

- which runtime track is the floor/original speech;
- whether a language is simultaneous interpretation, translated program audio,
  or another production feed;
- whether a particular track exists for the entire event;
- whether a player/CDN identifier or URL may be retained or downloaded.

Therefore Task 008B must not query player tracks, select a Kaltura track, parse
playlists, or convert a page language into
`original_speaker_audio`/`simultaneous_interpretation` provenance. A user may
confirm a language and speech-source kind only after lawful local acquisition.
Unknown remains `unknown`; it is never silently promoted to original speech.

### Authentication and page changes

The sampled pages were public, but there is no API contract or promise that all
assets remain unauthenticated. If any response requires cookies, a login,
authorization header, token, CAPTCHA, JavaScript execution, or acceptance of a
new access condition, the adapter stops. It must not ask for or reuse browser
credentials.

The parser must be fail-soft for product use and fail-closed for provenance:

1. validate the user-pasted URL;
2. retrieve only that page;
3. prefer canonical/standard metadata;
4. use versioned, bounded UN field selectors only as a secondary strategy;
5. compare independently available values and surface conflicts;
6. require review for missing, conflicting, or unfamiliar shapes;
7. fall back to opening the official page and manual metadata entry.

Parser failure must not block local-file import or live capture. A monitoring
test may detect public-page drift, but Task 008B must not crawl the site. The
current robots file is operational crawl guidance, not permission to copy or
use footage.

### Network, redirects, and SSRF boundary

The optional metadata adapter must not expose a generic URL fetcher. Its
network contract is narrowly fixed:

- one direct, user-initiated GET for a validated asset page;
- ephemeral URL session, no cookies, credentials, persistent cache, referer
  propagation, or background transfer;
- ordinary platform TLS/hostname validation with no custom trust relaxation;
- at most two redirects, with every hop independently revalidated as HTTPS on
  the exact `webtv.un.org` host and default port;
- rejection of cross-host redirects, including `un.org` siblings, URL
  shorteners, Kaltura/CDN hosts, IP literals, loopback, link-local, and private
  destinations;
- response status 200 and `text/html` only;
- decoded-body cap 1 MiB, bounded header count/size, and short connection and
  resource timeouts;
- no subresource, image, script, player, media, or alternate-language fetch;
- no retry loop beyond one explicit user retry and no telemetry payload.

An exact host allow-list and a feature-specific API remove user-controlled host
selection, which is the primary SSRF control. A preflight DNS check cannot by
itself eliminate DNS-rebinding/TOCTOU risk, so Task 008B must also reject every
redirect and authentication challenge outside the exact host and must not
generalize this adapter for other URLs.

### Acquisition, internal analysis, and legal uncertainty

The current UN Web TV copyright page states that UN footage is not public
domain and that any use requires UN authorization and a licence agreement;
licensing fees may apply. The general UN terms contain a personal,
non-commercial-use provision subject to specific restrictions. These sources
do not establish that automated acquisition, re-recording browser audio, or
machine analysis is permitted for this product or the user's intended use.

The Task 008A product recommendation is consequently:

- metadata-only reading may be offered as a user-triggered convenience if the
  user accepts the network/privacy boundary; it makes no media-use claim;
- do not acquire, download, extract, cache, or record UN footage in Task 008B
  without documented UN/rightsholder authority reviewed for the intended use;
- do not implement redistribution or imply that local/internal use avoids the
  dedicated restriction;
- retain the official URL and the user's authority evidence as provenance if a
  later separately authorized acquisition path is approved;
- prefer a user-obtained, permitted local file through the accepted import
  workflow.

This is a conservative product boundary, not legal advice. Written permission,
licence scope, jurisdiction-specific recording consent, and organizational
policy remain external decisions.

## Native live audio capture findings

### Feasible platform surface

Current Apple documentation and installed SDK headers support these relevant
capabilities:

- ScreenCaptureKit can provide system/application audio sample buffers on
  macOS 13+.
- `SCContentSharingPicker` is available on macOS 14+ and allows explicit system
  UI selection of an application, window, or display for the current capture
  session.
- ScreenCaptureKit microphone output and microphone device selection are
  available on macOS 15+.
- A stream may add only audio and microphone outputs; MeetingBuddy does not
  need to consume or persist screen frames.
- Stream delegate/output errors expose user decline, missing entitlement,
  connection interruption, system stop, and audio/microphone failure classes.

Because MeetingBuddy already targets macOS 15, the recommended MVP does not
raise the deployment minimum.

### Least-authority capture modes

Task 008B should support only these mutually visible choices:

| Mode | Source selection | Stored tracks | MVP disposition |
| --- | --- | --- | --- |
| Microphone only | User chooses an available microphone | One microphone track | Accepted Task 008B boundary |
| One application only | User chooses exactly one application in Apple's system picker | One application-system-audio track | Accepted Task 008B boundary |
| Application plus microphone | Same explicit application selection plus explicit microphone choice | Two independent synchronized tracks | Accepted Task 008B boundary |

The app must not silently use the default microphone, capture all system audio,
capture multiple applications, capture display/window pixels, persist a picker
selection across launches, or switch devices after a disconnect. A system
picker indicator and an in-app recording state must stay visible. Starting a
capture requires a direct user action and an affirmative acknowledgement that
the user has authority and required participant consent.

The acknowledgement is an auditable product guardrail; it is not proof of
legal permission. Organization policy may still deny capture.

### Permission and entitlement proposal

The current app does not possess these capabilities. D2 and D3 accept the
following least configuration surface for Task 008B once that task is
separately authorized:

| Capability | Accepted configuration boundary | Purpose |
| --- | --- | --- |
| Microphone | `com.apple.security.device.audio-input` and `NSMicrophoneUsageDescription` | Sandbox authority plus a truthful TCC purpose string |
| Application/system audio | `NSAudioCaptureUsageDescription` | Explain system-audio capture to the platform/user |
| Optional metadata fetch | `com.apple.security.network.client` | Permit the sandboxed app's tightly scoped outbound HTTPS request |

Task 008B must not request
`com.apple.developer.persistent-content-capture`. Apple documents that
entitlement for persistent remote-control/content-capture cases; it conflicts
with MeetingBuddy's direct, session-scoped user-selection boundary.

The Apple system picker is the least-authority choice and Apple describes it as
avoiding a separate broad screen-recording permission for picker-selected
content. Exact TCC wording and first-run behavior can vary by macOS and signing
context. The ad-hoc spike build is not sufficient proof. A signed Task 008B
manual matrix on macOS 15 and the current macOS release remains mandatory.

No package dependency is proposed. ScreenCaptureKit, AVFoundation, AudioToolbox,
Foundation, CryptoKit, and SQLite are native/currently used system facilities.

### Why `SCRecordingOutput` is not the durability authority

The current SDK's `SCRecordingOutput` writes one recording output and reports
start, failure, and finish. It does not expose MeetingBuddy's required
segment-level close, checkpoint, hash, flush, partial-file ownership, or
restart-reconciliation contract. A single long output also makes process-kill
recovery depend on container finalization that the app cannot prove.

Task 008B should therefore consume audio sample output through a provider
adapter and let a MeetingBuddy persistence coordinator own bounded CAF
segments, durable state, and publication. `SCRecordingOutput` is rejected as
the authoritative source writer for this milestone.

### Track and time provenance

Microphone and application audio remain separate from capture through source
publication:

- each packet carries a session ID, epoch ID, track ID, monotonically ordered
  packet sequence, media presentation interval, host-time interval, sample
  rate, channel count/layout, and format revision;
- the platform adapter emits bounded PCM packets and never writes a file or
  queries SQLite;
- a shared capture epoch records the system/application selection and
  microphone selection that were explicitly authorized;
- source change, device disconnect, permission change, stream recreation,
  sleep/wake discontinuity, or format change ends the epoch;
- a resumed capture creates a new epoch and an exact gap/discontinuity entry;
- microphone and system audio are never collapsed into an authoritative mixed
  track. A mix may be a later generated derivative with both exact source
  revisions.

Raw hardware unique IDs and full device names are unnecessary tracking data.
Persist a per-session SHA-256 token over the platform device identifier plus
session ID, a bounded source class, selected-at time, format, and change reason.
This supports same-session device continuity without creating a cross-workspace
hardware identifier. The hash is an integrity/provenance identifier, not an
anonymity or cryptographic access-control claim.

## Recording state contract

### Invariants

1. A recording-session intent, requested source set, policy/classification
   snapshot, and direct-user authorization event are durable before capture is
   started.
2. No more than one state transition is committed for a state-version number;
   every transition is append-only and idempotent.
3. Audio is written only through the approved recording persistence
   coordinator into the session's bounded workspace authority.
4. Each selected source is an independent track. Missing packets or a stopped
   track create an explicit half-open gap; they are never replaced silently.
5. `completed` means all required selected tracks and epochs have provable
   coverage and verified final assets. It never means merely that stop returned.
6. `incomplete` is visible and retained by default. It is never automatically
   promoted to the active meeting source or described as complete.
7. `failed` means no usable verified audio can be published. Prior state/audit
   evidence may remain, but no zero-byte SourceAsset is created.
8. Terminal state is immutable. Recovery is repeatable and cannot demote or
   rewrite a completed recording.
9. Unknown future state/checkpoint versions fail closed and leave bytes
   untouched for a newer build.

### Allowed transitions

| From | To | Required condition |
| --- | --- | --- |
| `preparing` | `recording` | Permissions/source still match, writer is ready, and first valid packet is accepted under a durable session intent |
| `preparing` | `stopping` | User cancels/stops after intent creation |
| `preparing` | `failed` | Permission denied, source unavailable, capacity denied, or no usable byte was ever sealed |
| `recording` | `interrupted` | Permission/source/device/OS/provider/persistence continuity is lost or watchdog expires |
| `recording` | `stopping` | User requests stop/cancel or duration/storage policy limit is reached |
| `interrupted` | `recovering` | In-process or startup reconciler obtains the exact session lease |
| `recovering` | `recording` | User explicitly reselects/re-authorizes; a new epoch is durable before samples resume |
| `recovering` | `stopping` | User chooses to retain/finalize available bytes without resuming |
| `recovering` | `finalizing` | Automatic recovery has reconciled all sealed/partial files and no resume is requested |
| `stopping` | `finalizing` | New packet admission is closed and every writer has returned a final seal/failure result |
| `finalizing` | `completed` | Required coverage, hashes, manifest, managed assets, and semantic publication all verify |
| `finalizing` | `incomplete` | At least one usable sealed interval exists but a gap, missing required track, truncated final interval, or publication precondition remains |
| `finalizing` | `failed` | No usable sealed interval survives or integrity cannot be established |

All other transitions are invalid. An observed nonterminal state after process
restart is first durably marked `interrupted`, then leased as `recovering`.

### State responsibilities

| State | Durable meaning | User-visible behavior |
| --- | --- | --- |
| `preparing` | Intent, policy, requested tracks, source/permission snapshot, disk budget, and task/session IDs exist | “Preparing”; no recording claim yet |
| `recording` | Provider and bounded writers are active; latest sealed checkpoint is visible | Persistent recording indicator, elapsed captured/verified time, active tracks |
| `interrupted` | Continuity is no longer trusted; no silent packet admission | Immediate warning and known reason; prior sealed audio remains |
| `recovering` | One reconciler owns the session and is validating files/rows | Progress plus Resume with re-selection, Finish incomplete, or Retain choices |
| `stopping` | New samples are rejected; queues drain within a bounded deadline | “Stopping”; repeated stop/cancel is idempotent |
| `finalizing` | Segments, gaps, manifest, hashes, and managed publication are being verified | “Finalizing”; closing the app warns that work is incomplete |
| `completed` | All required source assets and immutable manifest are verified/published | Complete status and normal downstream eligibility |
| `incomplete` | Verified recoverable audio exists with an exact reason/gap manifest | Prominent incomplete badge; no automatic downstream activation |
| `failed` | No verified usable audio can be published | Failure reason and recovery/cleanup guidance; never a complete recording |

## Incremental storage and checkpoint contract

### Ownership and layout

- The Task Manager owns the long-running capture job and cancellation intent.
- The recording persistence coordinator owns session state, segment sealing,
  checkpoints, recovery, and final publication through repositories and the
  existing Workspace/Storage services.
- The platform capture provider owns only the live `SCStream`, system picker
  authorization, microphone selection, and conversion to bounded packets.
- No provider receives SQLite, workspace paths, a whole workspace, or a generic
  file writer.
- Each session gets one opaque, private staging authority. No caller supplies a
  path. Sealed segments are registered as temporary managed assets; `.partial`
  files are confined to the same session-owned staging directory and are never
  semantic assets.

### Segment and flush bounds

- File format: native CAF, linear PCM, preserving the actual capture sample
  rate/channels for the authoritative per-track capture.
- Nominal segment duration: 5.0 seconds per track on the common epoch timeline.
- Hard open-segment media-span bound: 6.0 seconds. If a writer cannot seal by
  that bound, capture transitions to `interrupted`; it must not accumulate a
  longer volatile-only recording.
- A sealed segment is closed, synchronized, reopened for header/frame
  validation, sized, SHA-256 hashed, and atomically renamed before a database
  checkpoint references it.
- A checkpoint transaction is committed no later than one second after the
  segment seal. Failure to commit stops packet admission and enters
  `interrupted`.
- The packet handoff is bounded to at most two seconds per track. Backpressure
  overflow creates an exact gap and interruption; packets are never silently
  dropped and memory never grows with meeting duration.

These bounds limit the expected crash-loss window to at most the current
unsealed segment (six seconds of media per active track). They do not claim
physical power-loss durability beyond macOS/filesystem guarantees. Task 008B
must test process kill and injected ordering failures; sudden hardware power
loss remains a proof gap.

### Filesystem/database commit ordering

For each segment:

1. create an opaque `.partial` file inside the session authority;
2. stream bounded PCM frames while tracking exact first/last media and host
   timestamps;
3. close and synchronize the file;
4. validate readable CAF structure and expected frame interval;
5. calculate size and SHA-256;
6. atomically rename to an immutable opaque segment name;
7. in one SQLite transaction, register the temporary managed asset, insert the
   immutable segment descriptor, update the rolling track digest/checkpoint,
   append any gap/state event, and advance the session state version.

This ordering avoids a database row pointing to a file that was never renamed.
A crash between steps 6 and 7 can leave an orphan sealed file. Recovery scans
only the known session directory, validates its opaque name/header/hash, and
either reconciles it against the expected next sequence or leaves it quarantined
for user-visible review. A `.partial`, truncated, duplicate, out-of-order, or
hash-mismatched file is never counted as covered audio.

### Checkpoint format

`meetingbuddy.recording-checkpoint.v1` is canonical JSON and remains within the
existing 65,536-byte `JobCheckpoint` bound. It contains no audio, title, URL,
raw device ID/name, transcript, or filesystem path. It contains:

- format identifier/version;
- session/job/meeting IDs and state version;
- current state and last state-event ID;
- current epoch and exact requested/required track IDs;
- per track: last sealed sequence, last covered half-open media interval,
  sealed-frame count, last segment digest, and rolling descriptor-chain digest;
- outstanding gap/discontinuity count and reconciliation-required flag;
- checkpoint creation time and integrity digest.

The full immutable segment/event ledger remains in normalized SQLite rows; the
bounded checkpoint is a restart cursor, not a second authority. Recovery proves
the cursor against rows and files before advancing it.

### Final publication and incomplete recordings

Finalization creates:

1. one verified authoritative CAF SourceAsset per captured track, retaining
   exact epoch timing and explicit silence only where the manifest records a
   known gap;
2. one canonical JSON capture manifest stored as a generated document
   `SourceAsset.v1` with a private MeetingBuddy MIME type;
3. an exact input-revision reference from every captured-audio SourceAsset to
   that manifest SourceAsset, so the existing semantic hash/dependency graph
   binds audio publication to the immutable provenance/gap description;
4. optional later canonical 16-kHz mono and mixed outputs as generated
   derivatives through the already accepted media job, never as a replacement
   for separate original tracks.

The manifest records session state, track/epoch ranges, known gaps, segment and
final-file hashes, bounded device tokens, format changes, state-event digest,
permission/source-selection evidence, authority-acknowledgement time, and the
UN/other source category if supplied. It stores no raw page HTML, credentials,
or unrestricted path.

A `completed` session may publish and activate its captured source assets after
all checks pass. An `incomplete` session retains verified session-owned bytes
and its operational manifest but does **not** automatically activate a normal
meeting SourceAsset. A later explicit “Use incomplete capture” action must show
known missing ranges, record a new user acknowledgement, generate the immutable
capture-manifest SourceAsset, and then publish the bounded available audio.
Downstream coverage is 100% of that published audio file, while the capture
manifest continues to disclose meeting-time gaps. No silence insertion may
erase that distinction.

Temporary segments are removed only after final assets and manifest are
hash-verified, registered, committed, reopened, and independently readable.
Normal removal uses the existing recoverable storage boundary; crash recovery
must tolerate both retained and already-cleaned segments idempotently.

## Abnormal and cancellation behavior

| Condition | Required state/result | Data rule |
| --- | --- | --- |
| Permission denied before start | `preparing -> failed` | No SourceAsset; retain only content-free audit reason |
| User stops before first sealed interval | `preparing -> stopping -> finalizing -> failed` | No zero-byte asset; idempotent cleanup |
| User stops normally | `recording -> stopping -> finalizing` | Seal current valid partial interval, then complete/incomplete by coverage |
| Task cancellation | Same semantic path as visible Stop | Cancellation never unlinks already sealed user audio |
| Permission revoked or system picker Stop | `recording -> interrupted` | Seal only provably valid frames; record exact end/gap |
| Selected application exits | `recording -> interrupted` | No automatic substitution; resume requires a new system-picker selection/epoch |
| Microphone disconnects/default changes | `recording -> interrupted` for required mic track | Never switch devices silently; prior track remains valid |
| One optional track fails | `interrupted`, then explicit user choice | Continuing with fewer tracks creates a new epoch and visible missing-track gap |
| Sample format changes | End epoch and interrupt | Resume only with a new recorded format epoch |
| Sleep/wake or host-clock discontinuity | Interrupt and record gap | Never compress real elapsed gap out of provenance |
| Backpressure/watchdog timeout | Interrupt | Record exact last accepted/sealed interval; no silent drop |
| Disk preflight failure | `preparing -> failed` | No segment directory or SourceAsset publication |
| Disk fills during segment | Interrupt/finalize incomplete | Discard invalid `.partial`; retain prior sealed segments |
| Disk fills after rename/before DB | Startup recovery/quarantine | Reconcile only after header/hash/sequence proof |
| App crash or `SIGKILL` | Startup marks nonterminal session interrupted/recovering | At most current unsealed segment is lost; sealed checkpoints are re-proved |
| Checkpoint truncated/corrupt | `recovering`, then incomplete/failed | Rebuild cursor from immutable rows/files; never trust corrupt bytes |
| Hash mismatch/tamper | `recovering -> finalizing -> incomplete/failed` | Quarantine mismatched segment; never publish it |
| Crash during final publication | Idempotent recovery | Publish all manifest/assets in one logical operation or expose incomplete; no duplicate active revision |
| Cancel races with finalization | State-version compare-and-swap | A committed terminal result wins; cancel cannot demote completed data |
| Repeated restart/recovery | Same terminal result and hashes | No duplicate segment, asset, event, or state transition |

## Accepted adapter contracts for Task 008B

The application-facing ports are SDK-neutral. ScreenCaptureKit types stay
inside the macOS adapter.

```swift
public protocol CaptureCapabilityProvider: Sendable {
    func snapshot() async -> CaptureCapabilitySnapshot
}

public protocol CaptureSourcePicker: Sendable {
    func requestSelection(_ request: CaptureSelectionRequest) async throws
        -> CaptureSelectionAuthorization
}

public protocol AuthorizedAudioCaptureProvider: Sendable {
    func prepare(_ request: PreparedCaptureRequest) async throws
        -> PreparedCapture
    func start(
        _ prepared: PreparedCapture,
        sink: any CapturedAudioPacketSink
    ) async throws -> CaptureHandle
    func stop(_ handle: CaptureHandle) async
}

public protocol CapturedAudioPacketSink: Sendable {
    func accept(_ packet: CapturedAudioPacket) async
        -> CapturePacketDisposition
}

public protocol RecordingSessionRepository: Sendable {
    func createIntent(_ intent: RecordingIntent) async throws
        -> RecordingSessionSnapshot
    func transition(_ transition: RecordingTransition) async throws
        -> RecordingSessionSnapshot
    func seal(_ segment: SealedCaptureSegment) async throws
        -> RecordingCheckpoint
    func recover(_ sessionID: RecordingSessionID) async throws
        -> RecordingRecoveryOutcome
}
```

`CapturePacketDisposition` is `accepted`, `backpressure`, or `stop`; there is no
silent-drop outcome. Requests contain exact policy/classification revisions,
requested tracks, capacity lease, user-authorization event, and no workspace
path. Selection authorization is session/epoch-scoped and is not persisted as
a reusable platform object.

The web adapter is separate and cannot produce media:

```swift
public protocol UNWebTVMetadataSource: Sendable {
    func metadataCandidate(for url: ValidatedUNWebTVAssetURL) async throws
        -> UNWebTVMetadataCandidate
}
```

The result contains only bounded field candidates and provenance. It contains
no player entry, media URL, playlist, cookie, token, or downloader handle.

## Schema 007 and compatibility plan

Task 008B would add one ordered additive migration,
`007_recording_capture_foundation`, after a verified schema-v6 SQLite online
backup. The proposed mutable operational tables are:

| Table | Purpose and critical constraints |
| --- | --- |
| `recording_sessions` | Session/job/meeting IDs, requested tracks, state/version, policy/classification revision IDs, user-authorization event, timestamps, terminal reason, optional final manifest revision; one current row per session |
| `recording_state_events` | Append-only legal transition, reason enum, actor, prior/new versions, time; unique transition idempotency key |
| `recording_epochs` | Explicit source selection, permission snapshot, per-session device token, OS/API/app version, start/end host/media time, source/format change reason |
| `recording_tracks` | Required/optional role, source kind, epoch association, actual format, first/last interval, continuity status |
| `recording_segments` | Track/epoch/sequence, temporary managed-asset reference, half-open intervals, frame count, size/hash, rolling-chain digest, seal/checkpoint time; immutable and uniquely ordered |
| `recording_gaps` | Track/epoch, exact half-open host/media interval when known, reason, detection source, user acknowledgement; overlap validation |
| `recording_checkpoints` | Bounded canonical checkpoint payload/hash, state version, creation time, superseded marker; append-only |

The migration need not rebuild or alter accepted semantic tables. It reuses the
existing `SourceAsset.v1`, managed-asset, dependency-edge, job, backup, and
recovery contracts. Capture manifests are generated document SourceAssets, so
no new semantic object discriminator is required.

Migration rules:

- fresh and schema v1-v6 workspaces must reach v7 with accepted semantic
  payload bytes and active pointers unchanged;
- failure at every migration statement rolls back to schema v6 and preserves a
  verified, readable v6 backup;
- unknown future migrations, states, event reasons, checkpoint versions, or
  manifest versions fail closed without rewriting bytes;
- current MeetingBuddy may disable capture/network features while continuing
  to read v7 and existing imported media;
- an older v6 binary must not open v7 in place. Downgrade requires closing the
  app and restoring the verified pre-migration v6 backup;
- after any real v7 capture, restoring that old backup would omit later capture
  records and is not a safe feature rollback. Preserve the v7 workspace and
  disable the feature instead; a downgrade requires explicit user-led export or
  workspace-copy planning.

Task 008A itself runs no migration and creates no runtime rollback need. Its
documentation can be reverted relative to the stated Git anchor with a
targeted user-authorized change that preserves unrelated dirty documents.

## Capability matrix for Task 008B

| Capability | Disposition | Boundary |
| --- | --- | --- |
| Existing user-selected local-file import | Accepted baseline | Must remain fully usable and unchanged |
| Local-first/no-outbound operation | Accepted baseline | Capture and manual metadata work without network; telemetry remains disabled by default |
| Visible audio-only microphone capture | Accepted Task 008B boundary | Direct action, mic permission/entitlement, explicit device, authority acknowledgement |
| Visible audio-only one-application capture | Accepted Task 008B boundary | Apple system picker, audio output only, no persistent selection |
| Simultaneous application plus mic | Accepted Task 008B boundary | Separate tracks/epochs; no authoritative mix |
| Bounded checkpoint/recovery and schema 007 | Accepted Task 008B boundary | Five-second segments, six-second hard open bound, incomplete not auto-active |
| One pasted UN Web TV page metadata read | Accepted Task 008B boundary | Exact host, explicit request, bounded HTML, reviewed candidates, manual fallback |
| Network client entitlement | Accepted for metadata-only mode | No-outbound policy can disable use; no generic network surface |
| Recording/acquiring UN Web TV footage | Legal/rights-gated; default no-go | Requires documented UN/rightsholder authority for intended use and separate review |
| Automatic Kaltura/player/media/playlist/track discovery | Rejected for Task 008B | No supported/licensed stable contract was established |
| Media download, stream capture, credential/token/cookie use | Rejected for Task 008B | No bypass, authentication, downloader, or hidden acquisition |
| Browser automation as acquisition architecture | Rejected for Task 008B | Manual open/import is the fallback |
| All-system, multi-application, screen/window/video capture | Rejected for Task 008B | Broader than audio MVP and least-authority boundary |
| Persistent content-capture entitlement/background capture | Rejected for Task 008B | Direct user awareness and session-scoped selection are mandatory |
| Silent microphone substitution or automatic source continuation | Rejected for Task 008B | Device/source change interrupts and creates a new explicitly authorized epoch |
| Redistribution/export of acquired UN footage | Rejected for Task 008B | No licence or product requirement supports it |
| Cloud upload/processing of live capture | Deferred | Separate provider, data-policy, destination, retention, authorization, and offline fallback review |

## Manual fallback

The fallback is always available and never disguised as failure recovery:

1. open the official UN Web TV page in the user's browser without automation;
2. let the user type or confirm bounded metadata in MeetingBuddy;
3. if the user has lawful authority to obtain a local media file, use the
   existing security-scoped local import;
4. preserve the user-selected file as the original SourceAsset and keep URL,
   language, original/interpretation status, and authority evidence distinct;
5. if no permitted media exists, retain metadata/bookmark notes only and do not
   create a media SourceAsset or transcript claim.

Live capture has a separate fallback: microphone-only capture when the user is
authorized and system-audio capture is unavailable, or normal local-file import
after the meeting. MeetingBuddy must never recommend another recorder,
screen-scraper, or access-control workaround.

## Executable Task 008B test design

### Deterministic automated tests

| Area | Test fixture/fault | Required assertion |
| --- | --- | --- |
| State machine | Every state pair plus unknown serialized state | Only the listed transitions pass; terminal/unknown states never mutate |
| Durable intent | Fake provider emits immediately; repository delays intent | Provider cannot start before durable intent; no volatile-only session |
| Normal mic/application/both | Synthetic deterministic PCM packets on one/two clocks | Separate exact tracks, hashes, epochs, manifest refs, and completed state |
| Segment bound | Packets at/around 5 s and 6 s | Normal seal at 5 s; >6 s inability interrupts; memory stays bounded |
| Backpressure | Sink stalls and queue fills | Explicit interruption/gap; no silent sample loss or unbounded allocation |
| Stop before bytes | Stop at each preparing boundary | Failed/no zero-byte asset; cleanup idempotent |
| Stop with partial interval | Stop at every packet boundary | Valid partial is sealed once; final coverage/hash is exact |
| Process kill matrix | Inject termination after every filesystem/DB step | Prior sealed segments survive; partial/orphan classification matches ordering |
| Truncated CAF | Truncate header, middle, and tail | Never counted or published; prior verified segments remain |
| Checkpoint corruption | Bit flip, truncation, stale cursor, wrong digest/version | Rebuild from rows/files or fail closed; never skip a segment |
| Segment tamper | Content, size, sequence, track, epoch, or time mismatch | Quarantine and incomplete/failed; no active SourceAsset |
| Disk full | Preflight, partial write, sync, rename, DB transaction, final join | Exact state and retained prior bytes; no orphan active semantic revision |
| Permission loss/system stop | Fake provider errors at every segment offset | Interrupted state, exact last accepted interval, explicit reason |
| Device/app change | Disconnect, default change, selected app exits/relaunches | No silent substitution; resume requires explicit new epoch |
| Format change | Sample rate/channel/layout changes midstream | End epoch and interrupt; provenance retains both formats |
| Sleep/clock change | Synthetic host-time discontinuity | Gap recorded; elapsed meeting time is not compressed |
| Cancellation race | Cancel before/after stop, seal, manifest, asset, terminal commit | One terminal outcome; no data unlink or duplicate publication |
| Finalization crash | Failure after each manifest/asset publication step | Logical all-or-visible-incomplete recovery; idempotent exact revisions |
| Repeated recovery | Run recovery N times after each injected failure | Stable state, hashes, counts, and active pointers |
| Incomplete use | User declines/accepts “Use incomplete” | Default no activation; accepted path binds exact gap manifest |
| Three-hour run | Synthetic two-track PCM with controlled gaps/restart | Bounded memory, expected segment count/storage, exact continuous ranges |
| Migration | Fresh and v1-v6, injected failure, future v8/unknown enum | v7 success or verified v6 rollback; accepted payload bytes unchanged |
| Feature disable | v7 workspace with capture/network disabled | Existing import/review/recovery works with zero capture/network invocation |
| URL validation | Encodings, userinfo, ports, IPs, lookalike/subdomains, queries/fragments | Only exact bounded official asset URLs pass |
| Redirect/SSRF | Cross-host, scheme downgrade, private/link-local/loopback, redirect loop | Request stops before disallowed target; no generic fetch escape |
| HTTP boundary | 401/403/429/5xx, auth challenge, bad MIME, oversized/decompression body | Manual fallback; no credential prompt, retry loop, or partial candidate |
| Parser drift | Synthetic old/current/missing/conflicting field shapes | Field provenance/confidence exact; unknown/conflict requires review |
| Untrusted text | Markup, control chars, huge fields, prompt-like metadata | Bounded plain text only; no instruction/tool authority |
| Media exclusion | Synthetic page contains player/CDN/playlist values | Result exposes none and makes no subresource request |
| No outbound | Policy disables metadata route | No URL session or socket action; manual import/capture stays usable |
| Privacy | Logs/telemetry/checkpoints/recovery snapshots inspected | No audio, title, URL, page text, device name/ID, credential, or path leakage |

Tests use fake providers, disposable workspaces, deterministic PCM/timestamps,
fault-injected storage/repositories, a local synthetic HTTP protocol stub, and
minimal synthetic HTML. They must not commit a copyrighted page snapshot or
real meeting audio.

### Opt-in platform/manual tests for Task 008B

- Inspect debug/release entitlements and Info.plist; prove only the explicitly
  accepted keys are present.
- On macOS 15 and the current macOS release, test first grant, denial, Settings
  change, revocation, system picker Stop, app quit, and relaunch for microphone
  and system audio separately.
- Capture only a controlled synthetic tone from a MeetingBuddy-owned helper and
  optional room silence; never use a real meeting or UN footage.
- Validate one-application selection, no screen-frame persistence, separate
  tracks, source indicator, app exclusion behavior, protected/silent content
  handling, device unplug, sleep/wake, and long-duration CPU/memory/storage.
- Sign with the intended Task 008B development identity for permission
  continuity. Ad-hoc-only TCC results are diagnostic, not release proof.
- Re-run no-outbound socket evidence with metadata disabled and with one
  explicit metadata request; attribute only MeetingBuddy process connections.

## Proof gaps that remain after Task 008A

- No written UN licence/authorization or legal opinion was provided. UN footage
  acquisition, browser-audio recording, and internal analysis remain blocked.
- UN Web TV exposes no reviewed public stability/versioning contract for the
  sampled HTML/player shape. Page and Kaltura behavior may change without
  notice.
- The mapping from visible language labels to runtime original/interpretation
  tracks is unproven and intentionally unsupported.
- Exact ScreenCaptureKit/TCC behavior is unverified on the macOS 15 minimum,
  Developer ID/notarized builds, managed Macs, and every current hardware class.
- ScreenCaptureKit may omit or silence protected content. MeetingBuddy must show
  missing audio; it must not attempt a bypass.
- Process-kill and injected-failure tests cannot prove survival of sudden power
  loss, APFS/SSD controller failure, or OS/kernel corruption.
- Five-second segmentation, CPU, I/O, thermal, file-count, and clock behavior
  need a Task 008B multi-hour synthetic run on representative Macs.
- Jurisdiction, participant consent, venue rules, organization policy, and
  third-party rights vary. The proposed acknowledgement is not legal clearance.
- Manual VoiceOver, permission-dialog accessibility, localization, clean-machine
  signing, notarization, and final packaging remain later validation gates.

## Current primary sources

UN sources, accessed 2026-07-19:

- [UN Web TV Copyright & Use](https://webtv.un.org/en/copyright_use)
- [United Nations Terms of Use](https://www.un.org/en/about-us/terms-of-use)
- [Representative UN Web TV asset 1](https://webtv.un.org/en/asset/k1t/k1tezmm4d8)
- [Representative UN Web TV asset 2](https://webtv.un.org/en/asset/k1d/k1dmvhubyu)
- [UN Web TV schedule](https://webtv.un.org/en/schedule)
- [UN Web TV robots file](https://webtv.un.org/robots.txt)

Apple sources and current SDK references, accessed/inspected 2026-07-19:

- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [ScreenCaptureKit system picker, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10053/)
- [Capture HDR content with ScreenCaptureKit, including audio and microphone updates, WWDC24](https://developer.apple.com/videos/play/wwdc2024/10088/)
- [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)
- [NSMicrophoneUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
- [NSAudioCaptureUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription)
- [App Sandbox audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.microphone)
- [App Sandbox outgoing-network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
- [Persistent content-capture entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture)
- [Allow apps to record screen and system audio on Mac](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)
- [Control microphone access on Mac](https://support.apple.com/en-us/102071)
- Installed macOS 26.5 SDK `ScreenCaptureKit.framework/Headers`, including
  `SCStream.h`, `SCStreamConfiguration.h`, `SCContentSharingPicker.h`, and
  `SCRecordingOutput.h`.

Official documentation and headers establish API surface, not MeetingBuddy's
production correctness. The latter remains Task 008B test evidence.

## Accepted decisions for Task 008B

On 2026-07-19, the user explicitly accepted:

- **D1 — Accepted bounded general capture:** audio-only microphone, one
  system-picker-selected application, or both as separate tracks; reject
  screen/video, all-system, multi-app, hidden/background, and silent source
  substitution.
- **D2 — Accepted least entitlements:** approve the microphone entitlement and
  microphone purpose string when microphone capture is selected, plus the
  system-audio purpose string for application audio; reject persistent content
  capture. Exact final wording remains part of Task 008B review.
- **D3 — Accepted `METADATA_ONLY_NETWORK`:** an explicit, metadata-only HTTPS
  request to the exact official host with the network client entitlement and
  no-outbound/manual fallback. No generic fetch or media route is authorized.
- **D4 — Accepted the UN media no-go:** no UN footage download, stream/player
  discovery, browser-audio recording, or analysis acquisition without
  documented permission/licence and a separate evidence review; no
  redistribution in Task 008B.
- **D5 — Accepted durability/schema contract:** schema 007 operational tables,
  five-second CAF segments, six-second maximum open span, bounded checkpoint,
  separate-track provenance, immutable manifest binding, and incomplete data
  retained but not automatically activated.

All five boundaries are accepted. Task 008B may implement only these accepted
boundaries and remains not started until a separate authorization command.

## Stop condition

Task 008A stops here. No Task 008B implementation has begun.

**NEXT ELIGIBLE COMMAND: PROCEED TO TASK 008B**
