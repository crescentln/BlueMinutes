# Performance Baseline

## Reproducible build baseline

Host evidence captured on 2026-07-28:

- macOS 26.5.2 (25F84), Apple silicon
- Xcode 26.6 (17F113)
- Swift 6.3.3
- exact GRDB 7.11.1
- rollback anchor `b41ae589e40ce9811a64c389899bc9639f8188d2`

Fresh isolated scratch-path results:

| Gate | Result |
| --- | --- |
| `swift package dump-package` | Pass |
| Debug build with `-warnings-as-errors` | Pass, 34.31 s |
| Release build with `-warnings-as-errors` | Pass, 92.98 s |
| Full `swift test` with `-warnings-as-errors` | Pass, process exit 0 |

The full output includes Swift Testing suites rather than relying on the
XCTest wrapper's zero-test summary.

## Foundation working-tree validation

A second new scratch root validated the uncommitted Issue #60 foundation tree:

| Gate | Result |
| --- | --- |
| `swift package dump-package` | Pass |
| Debug build with `-warnings-as-errors` | Pass, 31.91 s |
| Release build with `-warnings-as-errors` | Pass, 79.97 s |
| Provider-routing focus | 13 tests pass |
| Public-brand focus | 4 tests pass |
| Historical scale shard | 1 test passes; 10,000 positions, 9.77 s rebuild, 0.34 s first page |
| Remaining synthetic-safe shard | 444 tests in 58 suites pass |
| Native-window shards | 12 isolated tests pass |
| Visual contract shard | 11 discovered tests pass; the exact-runner harness is explicitly skipped locally |
| Three-hour retry simulation | 1 isolated test passes |

The split gate covers 469 discovered tests. Three installed Apple-model tests
and the pinned GitHub-runner visual harness remain explicit environment-gated
skips. A monolithic local invocation returned zero but terminated without the
required Swift Testing aggregate line, so it was rejected as evidence; the
repository's CI-shaped isolated shards above are the accepted local result.
The fully pinned native visual harness still requires its exact macOS 26.4
GitHub runner image.

## Current functional working-tree validation

The self-relative 0.4.0 candidate commit containing this document is based on protected main
`77a4deca11190587c557e081667fb6c0e64a0f4a`. Final local refresh on
2026-07-29 produced:

| Gate | Result |
| --- | --- |
| `swift package dump-package` | Pass |
| CI-shaped non-GUI Debug gate with `-warnings-as-errors` | Pass: 520 tests in the remaining shard, the isolated 10,000-position scale test, and the isolated three-hour retry test |
| Local native-window and visual shards | Not accepted on this invocation: the Codex desktop test process could not activate its AppKit window and returned typed `applicationActivationFailed` / `accessibilityWindowUnavailable`; the pinned PR runner remains required |
| Fresh full Release build with `-warnings-as-errors` | Pass in a new scratch root, 105.08 s |
| `git diff --check` | Pass |
| Added-line and untracked-file credential-pattern scan | Pass after excluding diff path headers |

The current tree contains 545 discovered tests. The 520-test synthetic-safe
shard truthfully skips three installed Apple-model probes and three installed
official-Codex probes. The scale and three-hour shards pass separately. The 12
native-window tests and 11-test visual-contract shard are not counted as a
local pass on this refresh because AppKit activation was unavailable; their
exact PR runner results remain merge-blocking evidence. The accepted local
shards still include Codex transport/runtime contracts, independent OpenAI STT,
provider routing, configuration persistence, recording recovery, real
AVFoundation canonical-audio processing, transcript outline/search,
content-free diagnostics, brand, and About. Earlier exact-candidate evidence
retains the prior native-window results but is not substituted for the final
source.

The first fresh Release attempt exposed a Swift 6.3 WMO empty-partition link
failure for the standalone synthetic STT fixture source. The fixture was placed
in the concrete `OpenAISTTSupport.swift` compilation unit, after which a new
scratch root completed the full Release build in one command. Repeating a failed
build in place is not used as the closure evidence.

## Existing scale evidence

The suite includes:

- three-hour transcript pipeline retry/coverage tests;
- 10,000-position historical index/search bounds;
- bounded disk-budget interruption;
- segmented recording restart/recovery;
- deterministic visual matrices across four window sizes, Light/Dark, and
  large macOS text;
- cancellation, checkpoint reuse, and no-content telemetry contracts.

These tests prove contract bounds, not current CPU, memory, energy, or UI
latency.

## Measured artifact snapshots

These are observed isolated working-tree measurements, not signed package or
distribution claims:

| Item | Measured value |
| --- | ---: |
| Foundation Debug executable | 41,110,128 bytes (39.2 MiB) |
| Foundation Release executable | 30,324,592 bytes (28.9 MiB) |
| Earlier functional Debug executable | 45,820,144 bytes (43.7 MiB) |
| Current functional Release executable | 33,814,048 bytes (32.2 MiB) |
| GRDB checkout cache | 154 MiB |
| Entire disposable validation build directory | 1.5 GiB |

No signed/notarized app bundle or optional local model is part of this phase, so
there is not yet a valid public package-size result.

The current functional Release executable SHA-256 is
`50925acfc6bb0a2ef3121d2e40b9725cc259c7e37a2d39a36513f0c0a02817ad`.
It binds only the isolated local scratch build and is not a publication,
signing, notarization, or distribution claim.

## Runtime measurement status

A bounded staged-app smoke was run with a fresh isolated
`CFFIXED_USER_HOME`. The 863×652 main window appeared, the About window showed
the reviewed icon and current release-service state, closing and reopening the
main window reused the same process, and menu Quit ended it cleanly. Initial
idle samples observed 0–0.4 percent CPU and about 49 MiB resident memory; later
Accessibility-driven window interaction samples were about 114–125 MiB. These
short samples are observations, not a stable-memory or leak baseline.

No established TCP connection or UDP socket was observed during the isolated
idle, About, close, reopen, and quit sequence. The isolated home contained no
workspace or intelligence configuration; only the deliberately retained
screenshot and empty stdout/stderr capture remained. Apple Unified Logging
showed only fixed content-free lifecycle codes for application start, window
resolution, close/reopen, and termination. The diagnostics-copy control was
rendered and enabled, but was not clicked during the live smoke so the user's
clipboard was not overwritten; its exact sanitized payload is covered by unit
tests.

Cold/warm time to first usable workspace, five-minute idle
CPU/memory/energy, main-thread hangs, scroll hitches, disk-write
frequency/total, a full outbound-network spy, model load/unload time,
audio-buffer/STT queue depth, and stop-time resource release remain **not yet
measured**. The `open` command's 0.11-second return was deliberately not treated
as launch-to-usable latency. No before/after UI performance conclusion is
claimed.

## Measurements still required

Before Beta closure, capture on the intended minimum and current macOS:

1. cold and warm launch to first usable workspace;
2. idle memory and CPU;
3. 10-minute, one-hour, four-hour, and eight-hour record-only sessions;
4. record plus configured local STT;
5. long transcript at 1k, 10k, and 50k segments;
6. search/outline latency and selection stability;
7. Codex streaming memory, bounded event queue, cancellation, and reconnect;
8. workspace size and I/O during autosave/recovery;
9. active-window resize and Light/Dark switching;
10. staged app size and optional model footprint.

The audio/device matrix must run each applicable duration against microphone,
selected browser/application audio, whole-system audio when implemented, and
external input devices. Local STT, remote STT, Record Only, source switching,
device removal, browser stop, sleep/wake, close-window continuation, and
post-stop release are separate rows rather than one combined pass.

Use Instruments Time Profiler, Allocations/Leaks, Energy Log, SwiftUI hangs,
and `fs_usage` where appropriate. Do not record real meeting content in
profiling artifacts.

## Initial targets

- no MainActor network, database scan, model inference, hashing, or indexing;
- no unbounded app-server or partial-STT event queue;
- visible cancel acknowledgement within one second when the provider responds;
- transcript search interaction remains responsive at 10k segments;
- no growth proportional to total streamed delta history after finalization;
- close/reopen of a window does not restart or duplicate an active meeting.

Measured results will replace targets in this document rather than being
presented as already achieved.

## Candidate bottlenecks to profile, not findings

- long transcript layout/search if visible rows are not sufficiently bounded;
- capture persistence I/O under frequent checkpoints;
- app-server delta buffering and cancellation;
- local model lifetime after meeting stop; and
- scene resize while outline, transcript, and assistant stream concurrently.

These are test hypotheses only. Optimization requires a trace and before/after
evidence.
