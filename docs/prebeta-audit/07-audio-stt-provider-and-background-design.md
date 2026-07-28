# Audio, STT Provider, and Background Design

## Current capture boundary

`MacOSAudioCaptureProvider` supplies native audio packets.
`RecordingPersistenceCoordinator` creates durable intent before capture,
persists sealed segments and checkpoints, and publishes only after exact
verification. Startup recovery re-proves retained bytes and isolates damaged
segments rather than inventing coverage.

Current source choices cover microphone, one authorized application audio
source, or both. They are shown as exact capabilities rather than a generic
device name.

## v4 source/acceptance matrix

| v4 source | Current truth | Required closure evidence |
| --- | --- | --- |
| Whole-system output | Not implemented as a distinct selection | Official ScreenCaptureKit/Core Audio path, self-audio exclusion, permission, interruption, provenance, and 10m/1h/4h/8h runs |
| Selected browser/application | Implemented through the macOS system single-application picker on macOS 15.2+; BlueMinutes audio is excluded | Browser exit/refresh, no-audio, multiple audible tabs, source switch, long-run queue/I/O, and reopen/recovery matrix |
| External USB/line-in/capture device | Enumerated through the current audio-input discovery path, but no dedicated v4 device-management surface or hot-plug closure | Exact name/rate/channels, level, mono/stereo choice, unplug/reconnect, overload/silence, and provenance tests on representative hardware |
| Microphone | Implemented with permission, exact device ID/format, capture, persistence, and recovery contracts | 10m/1h/4h/8h resource, sleep/wake, device-loss, Record Only, local-STT, and stop-release tests |

The current `applicationAudio` contract must not be relabelled as whole-system
audio. External input enumeration is not proof of hot-plug, level, channel
selection, or long-run reliability.

## STT routes

### Local

The accepted Apple `SpeechAnalyzer` route processes application-owned verified
chunks and declares batch STT. Model availability is queried from the platform.
The app must not show a download/delete button unless the platform API can
actually perform and verify that operation.

The package still supports macOS 15 while the production Apple route requires
macOS 26. This support gap needs a separate local-STT platform decision:

- preserve macOS 15 and approve another signed/local backend; or
- raise the minimum OS after explicit compatibility review.

### Remote

No remote STT adapter is authorized or implemented. A future adapter requires:

- exact provider/model and batch/realtime capability;
- API endpoint and TLS policy;
- audio categories and bounded request shape;
- retention/training policy;
- Keychain secret reference;
- user-visible upload destination and API cost owner;
- explicit per-meeting authorization;
- retry/idempotency semantics; and
- local/record-only alternative.

### None / Record Only

This is a first-class route. Audio is recorded and recovered locally. No
transcript is fabricated, Codex is not invoked for STT, and a later explicit
route may process the recording.

## Source switching

A mid-meeting source change must create a new source epoch with exact start
time, capability, permission, device/application identity, and discontinuity
status. It cannot rewrite prior provenance. If a replacement source is
unavailable, retained bytes remain visible and incomplete.

## Streaming and autosave

Realtime STT requires a backend that truly emits partial/final results.
Partials are ephemeral presentation state. Only finalized segments enter the
durable semantic path. Autosave checkpoints:

- sealed audio segment identities;
- final transcript segments;
- exact STT route snapshot;
- source epoch and language;
- last covered canonical range; and
- safe retry state.

Backpressure and bounded queues are mandatory; partial updates may not rebuild
the entire transcript view.

## Background lifecycle

The current `MeetingBuddyApp` terminates when the main window closes during
recording. The target design moves active-session ownership above the window:

- closing the window keeps capture and durable autosave active;
- a menu-bar status item exposes open, pause/resume when supported, and stop;
- reopening attaches to the same session;
- true Quit requests an explicit stop/finalize/flush decision;
- sleep/wake and device loss produce visible epochs and recovery state;
- no window or menu action can start a duplicate capture.

This is a functional reliability slice, not U1.

## Sensitive Meeting

Sensitive Meeting allows local capture and installed local STT only. Remote
STT, Codex text, BYOK cloud text, and research are resolver-denied. No failure
may weaken this rule.
