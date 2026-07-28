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
| Provider-routing focus | 12 tests pass |
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

## Current measured artifact values

These are observed isolated working-tree measurements, not signed package or
distribution claims:

| Item | Measured value |
| --- | ---: |
| Debug executable | 41,110,128 bytes (39.2 MiB) |
| Release executable | 30,324,592 bytes (28.9 MiB) |
| GRDB checkout cache | 154 MiB |
| Entire disposable validation build directory | 1.5 GiB |

No signed/notarized app bundle or optional local model is part of this phase, so
there is not yet a valid public package-size result.

## Runtime measurement status

The following v4-required observations are explicitly **not yet run** on this
branch: cold/warm launch, five-minute idle CPU/memory/energy, main-thread hangs,
scroll hitches, disk-write frequency/total, network request count, model
load/unload time, audio-buffer/STT queue depth, and stop-time resource release.
No before/after UI performance conclusion is claimed.

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
