# ADR-0009: Task 005B Local Transcription and Translation Route

Status: Accepted for Task 005B implementation; task acceptance remains user-gated
Date: 2026-07-18
Decision owners: Codex under the user's Task 005B authorization
Applies from: Task 005B

## Context

Task 005B requires one production-capable transcription route, one production-
capable translation route, and a usable local/offline fallback. Starting the
task did not authorize outbound meeting-data transfer or a new dependency.
The selected route must preserve the macOS 15 minimum while using capabilities
available on the current macOS 26 development and validation host.

## Decision

- On macOS 26 or later, use Apple's `SpeechAnalyzer` with
  `SpeechTranscriber` for prerecorded transcription and Apple's
  `TranslationSession` for translation.
- Use only models that the operating system already reports as installed. The
  MeetingBuddy processing path does not initiate a model download.
- Both adapters execute on this Mac. The transcription destination is the
  local device for bounded canonical-audio chunks; the translation destination
  is the local device for bounded transcript text. Provider retention is not
  applicable, and durable results remain in the user-selected workspace.
- The application-owned model-policy router remains the authority. Its inputs
  include classification, offline mode, organization policy, deployment
  environment, destination, retention, bounded data categories, visible user
  authorization, and installed-model availability.
- Task 005B authorizes no cloud or other outbound adapter. A policy-complete
  external candidate still fails closed because no provider, destination, or
  transfer was approved.
- On macOS 15 through 25, or whenever a requested Apple model/language pair is
  unavailable, preserve a validated manual transcript/translation publication
  path. Publication requires the user to explicitly confirm complete timeline
  accounting. Manual content is human-entered and retains revision, source,
  timeline, language, classification, and edit provenance.
- Production credentials, if a later authorized route needs them, use the
  application Secret Store port backed only by macOS Keychain. The selected
  Apple route needs no application credential.
- Add no third-party dependency. `Speech`, `Translation`, `AVFAudio`,
  `Security`, and `CryptoKit` are Apple system frameworks covered by the
  platform SDK; the existing exact GRDB dependency is unchanged.

## Rejected alternatives

- A deterministic fake is retained for tests but is not a production route.
- A bundled third-party local model is deferred because Task 005B does not
  authorize its model footprint, license, update, or packaging lifecycle.
- A cloud ASR or translation service is rejected for this task because no
  outbound destination, retention contract, credential, or data-transfer
  authority was granted.
- A disabled provider button is not accepted as an offline fallback; the
  manual local publication and review workflow remains functional.

## Consequences

- Apple-model transcription/translation is available only when the running OS
  and installed language assets support it; otherwise the UI explains and
  exposes the manual local path.
- Provider-specific framework types remain inside `MeetingBuddyAI`. Domain and
  application contracts remain provider-neutral.
- Apple does not expose an installed asset revision through these adapters;
  `model_version` therefore records the exact host macOS version, while
  `model_identifier` records the Speech/Translation capability and
  `client_version` records the MeetingBuddy adapter contract.
- No network, capture, microphone, or additional sandbox entitlement is added.
- Route decisions and provider/model/client versions remain visible in the
  transcript coverage manifest and Task Manager provider-usage history.
- Removing or disabling either Apple adapter leaves existing transcript data
  readable and the manual local path usable.

## Validation

- A synthetic AIFF generated locally with `/usr/bin/say` passed installed-
  model transcription and English-to-Simplified-Chinese translation on the
  macOS 26 validation host.
- Deterministic integration tests cover policy denial, exact chunk ownership,
  no-speech/failure/missing distinctions, retry reuse, cancellation, restart,
  stale-input rollback, manual publication, corrections, stale propagation,
  and speaker confirmation.
- No real meeting content or outbound transfer is used as evidence.
