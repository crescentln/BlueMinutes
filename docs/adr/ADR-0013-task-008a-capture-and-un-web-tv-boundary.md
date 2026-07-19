# ADR-0013: Task 008A Capture and UN Web TV Boundary

Status: Accepted for Task 008B implementation; Task 008B remains separately user-gated
Date: 2026-07-19
Decision owners: User, with Codex recommendations under Task 008A authorization
Applies from: Task 008B once separately authorized
Evidence: [Task 008A spike](../TASK_008A_CAPTURE_SPIKE.md)

## Context

MeetingBuddy needs live microphone/application-audio capture and a useful UN
Web TV intake path without weakening local-first privacy, recording invisibly,
losing long meetings on crash, guessing speech-language provenance, or treating
a website's current player implementation as a supported acquisition API.

Task 007 left the app sandboxed with no microphone/network entitlement, no
system/microphone purpose strings, no live-capture implementation, and no
outbound meeting-data route. Existing local import, task management, managed
storage, immutable SourceAsset revisions, exact dependency edges, canonical
CAF audio, and schema-v6 recovery are accepted baselines.

Current official evidence establishes a technically feasible ScreenCaptureKit
audio path. It does not establish permission to acquire UN footage. UN Web TV's
dedicated copyright page says the footage is not public domain and requires UN
authorization/licensing. Current public pages expose useful HTML metadata and a
Kaltura client player, but no reviewed stable media/track API.

## Decision

On 2026-07-19, the user accepted D1-D5, including D3 as
`METADATA_ONLY_NETWORK`. Task 008B is limited to the following boundaries and
still requires a separate implementation command.

### 1. Separate adapters and authority

- A native `AuthorizedAudioCaptureProvider` may emit audio packets only after
  direct user action, explicit source choice, current permission, exact policy
  snapshots, and durable recording intent.
- A separate `UNWebTVMetadataSource` may return bounded, untrusted metadata
  candidates from one validated official page. It cannot return media URLs,
  player IDs, playlists, cookies, credentials, tokens, or acquisition handles.
- Neither adapter receives SQLite, a whole workspace, an unrestricted path, or
  authority belonging to the other adapter.
- Local file import remains the universal offline/manual fallback and cannot be
  disabled by either adapter's failure.

### 2. Bounded audio-only capture

- Allow microphone-only, one system-picker-selected application's audio only,
  or both as two independent tracks.
- Use Apple's session-scoped system content picker. Add no screen/video output,
  all-system capture, multi-application capture, background/hidden capture,
  persistent selection, or persistent content-capture entitlement.
- Keep a visible system/in-app recording indicator. Require an affirmative
  authority/consent acknowledgement at start; treat it as product evidence, not
  legal clearance.
- Do not silently choose or replace a microphone/application. Disconnect,
  permission loss, app exit, sleep/clock discontinuity, or format change ends
  the epoch and interrupts capture. Resume requires explicit re-selection and
  a new epoch.
- Preserve microphone and application audio as separate authoritative source
  tracks. Any later mix is a generated derivative linked to both exact source
  revisions.

### 3. Least entitlement surface

- Microphone mode requires explicit approval to add
  `com.apple.security.device.audio-input` and a truthful
  `NSMicrophoneUsageDescription`.
- Application/system-audio mode requires a truthful
  `NSAudioCaptureUsageDescription`.
- The optional metadata adapter requires explicit approval to add
  `com.apple.security.network.client`; no-outbound/offline policy disables the
  adapter and preserves manual entry/import.
- Do not add `com.apple.developer.persistent-content-capture`, server/listener
  authority, a generic browser/fetch surface, or a new package dependency.

### 4. Application-owned capture durability

- Do not use a single `SCRecordingOutput` file as durability authority. The
  platform provider emits bounded audio packets; a MeetingBuddy persistence
  coordinator owns files, SQLite, checkpoints, recovery, and publication.
- Use explicit states: `preparing`, `recording`, `interrupted`, `recovering`,
  `stopping`, `finalizing`, `completed`, `incomplete`, and `failed`.
- Create the durable session intent before starting the provider.
- Store each track as nominal five-second linear-PCM CAF segments with a hard
  six-second open-segment media-span bound. Seal, synchronize, validate, hash,
  and atomically rename before committing the segment/checkpoint transaction.
- Bound queued audio to two seconds per track. Backpressure or checkpoint
  deadline failure interrupts capture and records a gap; no packet is silently
  dropped and memory cannot grow with meeting duration.
- Recovery treats `.partial`, orphan, truncated, duplicate, out-of-order, and
  hash-mismatched segments explicitly. It never counts unproved bytes as
  covered audio.
- `completed` requires exact required-track coverage plus verified manifest and
  assets. `incomplete` retains usable bytes and exact gaps but is not
  automatically activated as a meeting source. `failed` publishes no zero-byte
  source.

### 5. Immutable capture provenance

- Persist mutable recording-session/epoch/track/segment/gap/event/checkpoint
  records in new schema-007 operational tables.
- Finalize one authoritative CAF SourceAsset per track and one immutable
  canonical JSON capture manifest stored as a generated document
  `SourceAsset.v1`.
- Every captured-audio SourceAsset includes the manifest SourceAsset's exact
  revision as an input dependency. The manifest binds state, epochs, devices,
  formats, timing/gaps, segment/final hashes, user-authorization time, and
  event-chain evidence without exposing raw hardware IDs, page HTML,
  credentials, or filesystem paths.
- Use a session-scoped SHA-256 token for device continuity instead of retaining
  a stable raw hardware identifier. Never infer original/interpretation status
  from a device or current web-page language list.
- An explicit later “Use incomplete capture” action must display gaps and
  record a new acknowledgement before publishing available incomplete audio.

### 6. Metadata-only UN Web TV path

- Accept only a user-pasted HTTPS asset URL on the exact `webtv.un.org` host,
  default port, one current supported locale, and two bounded opaque path IDs.
  Reject userinfo, IP literals, query/fragment, host suffixes/lookalikes, and
  unknown shapes.
- Make one explicit foreground GET with an ephemeral credential-free session,
  ordinary TLS validation, a 1 MiB decoded-body cap, short timeouts, and at most
  two same-host HTTPS redirects. Fetch no subresources.
- Parse only bounded title, description, canonical URL, production date,
  duration, category, language-availability, broadcasting entity, and summary
  candidates. Record field-level parser provenance and require user review on
  absence, conflict, or drift.
- Treat all page values as untrusted text. Do not execute JavaScript, retain
  HTML by default, crawl/search, authenticate, query Kaltura, discover player
  tracks/media, download, or capture the stream.
- Failure falls back to opening the official page and manual metadata entry.
  Metadata alone does not create a media SourceAsset.

### 7. UN footage and third-party rights boundary

- Task 008B does not download, extract, re-record browser audio, or analyze UN
  footage unless documented UN/rightsholder authority for the intended use is
  supplied and separately reviewed.
- A self-attestation is not substituted for the required authority. The app
  also makes no redistribution right claim.
- A later authorized acquisition must keep official URL, authority evidence,
  exact language/original-versus-interpretation provenance, destination,
  retention, and local/offline alternative distinct.
- General microphone/application capture remains subject to participant,
  jurisdiction, venue, and organization rules. MeetingBuddy records the user's
  acknowledgement but provides no legal conclusion.

### 8. Migration, compatibility, and rollback

- Migration `007_recording_capture_foundation` is additive and runs only after
  a verified schema-v6 SQLite online backup.
- Fresh and accepted v1-v6 workspaces must migrate without changing accepted
  semantic payload bytes, managed media, active pointers, or imported-media
  behavior. Injected failure leaves a readable verified v6 backup.
- Unknown future migration/state/checkpoint/manifest values fail closed and do
  not rewrite bytes.
- Current code may disable capture/network features while retaining a readable
  v7 workspace. A v6 binary must not open v7 in place; downgrade requires
  restoring the v6 backup.
- After real v7 capture data exists, restoring the old v6 backup would omit new
  recording state and is not a safe feature rollback. Preserve the v7
  workspace and disable the capability unless the user explicitly plans a
  data-preserving downgrade.

## Capability dispositions

### Accepted baseline

- user-selected local-file import;
- local-first/no-outbound operation and manual fallback;
- explicit user awareness, no hidden recording, exact provenance, managed
  storage, Task Manager ownership, immutable published revisions, and visible
  incomplete/failure state.

### Accepted for the Task 008B implementation boundary

- the three bounded audio-only capture modes;
- the least microphone/system-audio configuration changes;
- schema 007 and the segment/checkpoint/manifest contract;
- the exact-host metadata-only adapter and network-client entitlement, with
  mandatory no-outbound/manual fallback.

### Legal/rights-gated

- recording or otherwise acquiring UN Web TV footage;
- any third-party capture where the user cannot document recording/content
  authority.

### Rejected for Task 008B

- player/Kaltura/media/playlist/track extraction or automatic download;
- browser automation, credentials, token/cookie extraction, access-control or
  protected-content bypass;
- screen/video, all-system, multi-app, persistent, hidden, or background
  capture;
- authoritative mixed-only recording, silent source substitution, cloud
  upload/processing, or redistribution.

## Consequences

- The accepted capture path is native, audio-only, local, visible, and
  recoverable, but it adds sensitive TCC onboarding and an additive migration.
- Separate tracks and an immutable manifest preserve evidentiary meaning at the
  cost of more files, state, and finalization work.
- Five-second segments bound expected process-crash loss and memory but require
  multi-hour I/O/file-count proof. Sudden power-loss durability remains outside
  what process fault injection can prove.
- Metadata convenience can add a narrow outbound request. No-outbound users
  keep full manual/local functionality.
- The UN Web TV media path remains intentionally limited because current rights
  and stability evidence does not support automatic acquisition.

## Rejected alternatives

- **One long platform recording file:** lacks the required bounded
  checkpoint/restart contract and makes container finalization a single failure
  boundary.
- **Mix microphone and application audio during capture:** destroys independent
  provenance and makes source/device loss harder to disclose.
- **Use the website player as an API:** current Kaltura details are private
  implementation shape with no reviewed stability/permission contract.
- **Use browser automation when parsing fails:** disguises page drift and access
  changes instead of preserving a reliable manual fallback.
- **Grant broad/persistent capture authority:** conflicts with direct user
  selection, least privilege, and no-hidden-recording requirements.
- **Publish incomplete audio as complete:** violates evidence integrity and
  deterministic coverage requirements.
- **Treat personal/internal use as automatically permitted:** resolves a legal
  uncertainty that the cited UN sources do not resolve for this product/use.

## Accepted user decisions

- **D1:** accepted the bounded audio-only capture modes and explicit exclusions.
- **D2:** accepted the corresponding least entitlement/purpose-string surface.
- **D3:** accepted exact-host `METADATA_ONLY_NETWORK` mode with network-client
  entitlement and mandatory no-outbound/manual fallback.
- **D4:** accepted the default no-go for UN footage acquisition/recording absent
  documented permission and separate review.
- **D5:** accepted schema 007, five/six-second durability bounds, separate-track
  provenance, manifest binding, and non-auto-active incomplete state.

D1-D5 are resolved and this ADR is binding for Task 008B. Acceptance of the ADR
does not itself authorize Task 008B; the user must still issue the controller
command separately.
