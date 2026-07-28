# Release Backlog, Acceptance, and Fixes

## Execution order

1. Foundation: live baseline, brand, routing contracts, Sensitive Meeting,
   disabled billing/site/update guards, ADR, and audit evidence.
2. Codex app-server text vertical slice and Intelligence connection state.
3. Independent STT/BYOK settings, runtime readiness, scope, and persisted
   routing snapshots.
4. Active meeting background lifecycle, menu-bar recovery, autosave, and New
   Meeting readiness coordinator.
5. Transcript outline/search and bounded Codex Assistant.
6. UN source distinctions, export expansion, About/update readiness.
7. full functional, accessibility, visual, security, performance, and
   release-gate regression.

## P0 status

| Gate | Status |
| --- | --- |
| Fresh Debug/Release/warnings/full-test baseline | Pass on current branch: the CI-shaped warnings-as-errors gate covers 538 discovered tests and a fresh one-pass warnings-as-errors Release build completes |
| Supplied logo/icon replacement | Implemented and merged in foundation PR #61; the current staged development bundle contains the reviewed ICNS byte-for-byte, while the eventual signed distribution artifact remains a later gate |
| Capability registry and Codex-excluded STT | Implemented contracts, persisted configuration, four-section UI, meeting pickers, and tests |
| Explicit record-only and no silent fallback | Implemented through import, recording, canonical preparation, and transcript execution |
| Sensitive Meeting local-only resolver | Exact policy graph, persisted meeting profile, picker constraints, and central model-policy defense implemented |
| External execution authorization | Exact remote adapter still requires destination, retention, data categories, visible per-meeting authorization, ready provider, and approved execution route |
| Billing disabled, website disconnected, update unconfigured | Composed into About with compile-time guards and no configured service endpoint; a bounded isolated idle/About/close/reopen/quit smoke observed no established TCP or UDP socket, while the full provider/network matrix remains pending |
| Data loss/recovery/version lineage | Existing accepted foundation; real-device matrix pending |
| Codex app-server vertical slice | Implemented with pinned official runtime, isolated home, protocol confinement, login/account/quota, selected-text Assistant, and opt-in live verification |
| Keychain BYOK composition | Implemented for OpenAI speech and text provider profiles without serializing secrets |
| Active meeting/window separation | Implemented for close/reopen/menu stop/true Quit; sleep/wake and long-run hardware proof remain |
| Long transcript search/performance | Five-minute outline and bounded stable search implemented; real-app Instruments/large-document proof remains |
| Basic updater architecture | Safety contract and truthful About state implemented; updater provider remains distribution-gated |
| Dead code/resource audit | Static first pass and bounded staged-app lifecycle/resource smoke complete; Instruments and duration matrices pending |

## P1 status

- three source modes: partial; microphone, selected application, and dual
  capture exist, while whole-system output, source switching, and external
  device management remain incomplete;
- New Meeting coordinator: lightweight reuse-based coordinator implemented;
- outline/search: implemented with five-minute anchors and bounded search;
- resizable/scoped AI Chat: bounded selected-segment Assistant implemented in
  the existing workspace; independent window and broader context remain
  unnecessary for the current slice;
- Codex runtime/login/quota recovery: implemented with strict runtime pin,
  ephemeral private threads, confirmed shutdown/purge, and fresh reconnect;
  adverse live-account matrix remains;
- complete four-section Intelligence UI: implemented;
- UN automatic/official/local source distinction: pending;
- local model manager: implemented for supported Apple Speech assets; macOS
  minimum-version decision remains;
- one supported local STT route: Apple batch exists on macOS 26+, macOS 15 gap;
- optional remote STT: exact OpenAI batch adapter implemented and explicitly
  per-meeting gated;
- complete export: Markdown only;
- Sparkle: distribution-gated;
- performance and accessibility matrix: contract shards and a bounded
  staged-app smoke pass; duration, Instruments, VoiceOver, and intended-device
  matrices remain;
- Beta/1.0 unlocked state: composed and live-observed in About; the bounded
  no-socket smoke passes, while full runtime network-spy proof remains pending.

## U1, M1, and P2

- **U1:** not started; requires separate user approval.
- **M1:** production billing/licensing not enabled; requires post-1.0 go/no-go.
- **P2:** generic web/video ingestion, local text LLM, calendar, watch folder,
  share extension, broader automation, and collaboration remain deferred.

## Foundation fixes

- live `main` was safely fast-forwarded from stale `b651b0b` to
  `b41ae589e40ce9811a64c389899bc9639f8188d2`;
- stale historical H1/H2/I pause evidence was superseded by live merged state;
- v4 tracking Issue #60 and ADR-0019 now define the bounded provider/release
  authority;
- uploaded brand sources are retained with fixed SHA-256 values;
- the old lossy README logo path is replaced by the approved PNG;
- a deterministic sRGB/iconset/ICNS generation script replaces manual asset
  derivation;
- Codex cannot acquire STT eligibility by name;
- Apple Speech is truthfully registered as batch, not realtime;
- meeting/workspace/global routes use explicit inherit/disabled/selection
  semantics, so meeting Record Only cannot inherit global STT;
- persisted workspace profiles carry their exact workspace owner and meeting
  profiles carry their exact immutable meeting revision; the route stack
  rejects cross-owner, cross-revision, and wrong-scope cache entries;
- missing or explicitly disabled STT resolves to record-only;
- fallback is a repair suggestion, not an automatic route;
- external capability/readiness produces an authorization-required candidate,
  never an executable-ready route, until destination, retention, deployment,
  data categories, visible authorization, and adapter approval are bound;
- Sensitive Meeting is derived from an exact immutable security-policy snapshot
  and rejects non-local providers in the resolver;
- the routing stack derives workspace/meeting identity from a validated exact
  Meeting/SensitivityLabel/AccessPolicy graph and rejects an unrelated or
  unscoped snapshot;
- Beta billing and service endpoints have an unforgeable-constructor contract
  and fail closed by default;
- a website update feed additionally requires updater approval, the dedicated
  exact feed and service-endpoint allowlists, exact equality with the composed
  update policy, and a complete release configuration at every update action;
  app composition is now visible in About while runtime network-spy proof
  remains open;
- the official Codex runtime is pinned by version, build, digest, and signing
  identity before app-server execution, receives only bounded authorized text,
  and runs with an isolated BlueMinutes-owned Codex home;
- OpenAI remote STT is separate from Codex, stores its API key in Keychain,
  uploads only exact canonical audio after visible per-meeting authorization,
  and has no silent fallback;
- a stopped recording publishes verified retained tracks, requires exact track
  selection for dual capture, enters the existing canonical-audio workflow,
  and can be recovered after restart without inventing coverage;
- main-window close preserves the app-owned recording session and the menu-bar
  item exposes only supported lifecycle actions;
- transcript review supplies deterministic five-minute anchors and bounded
  text/time search while preserving exact evidence selection;
- the lightweight New Meeting coordinator and About window reuse the accepted
  visual language and do not start U1;
- fixed Apple Unified Logging event codes cover core request/window lifecycle
  without accepting content or arbitrary text, and About can copy a
  fail-closed sanitized build/release report without exposing meeting data,
  credentials, URLs, or paths;
- same-suffix persistence test workspaces now receive a per-run UUID, so an
  interrupted test cannot leak old active-revision pointers into a later run
  while production optimistic locking remains unchanged.

## Acceptance criteria for phase closure

### Routing

- every task filters by exact model capability;
- batch and realtime STT requests remain distinct, so a dual-capability model
  never resolves by string-sort accident;
- Codex can never be selected/resolved for STT;
- local/remote/record-only STT states are truthful;
- no provider/data/cost fallback is silent;
- global/workspace/meeting precedence and immutable snapshots survive reopen;
- exact workspace/meeting/revision owner, validated policy graph, and winning
  route origin survive reopen;
- provider deletion produces repair state rather than crash.

### Codex

- compatible runtime detection and explicit incompatibility;
- official login/cancel/logout and account/quota state;
- initialize, ephemeral thread start, stream, cancel, crash/fresh reconnect;
- bounded selected-text context and one read-only transcript tool;
- no raw audio, arbitrary path, secret, or unbounded workspace access;
- no shell, command, file-change, patch, Apps/plugin/MCP, web-search, or
  permission-escalation surface survives the process confinement gate;
- failure never blocks recording, local STT, editing, search, or export.

### Meeting and transcript

- record-only works without fake transcript;
- closing/reopening the window preserves one active session;
- true Quit finalizes or visibly preserves recoverable state;
- source/device/TCC/disk failures retain honest provenance;
- long transcript outline/search remains responsive and selection-stable;
- partial streaming does not force scroll or rebuild the entire document.

### Release

- all focused and full SwiftPM tests pass with warnings as errors;
- new UI states pass Light/Dark, 860×600, keyboard, VoiceOver, and resize gates;
- no unauthorized billing, licensing, update, telemetry, remote STT, or website
  request occurs;
- staged bundle contains the reviewed ICNS byte-for-byte;
- docs, ADR index, execution ledger, branch/PR/CI/review state, and rollback
  anchors agree.

## Residual risks

- macOS 15 versus Apple Speech macOS 26 support;
- App Sandbox and trusted Codex subprocess discovery;
- app-server protocol/runtime version drift;
- active meeting lifecycle across sleep/wake, device loss, true pause/source
  switching, process termination, and 4/8-hour real-device runs;
- remote STT privacy/retention/provider choice;
- intended update/distribution channel and signing ownership;
- immutable post-record meeting-profile route supersession;
- complete export formats beyond controlled briefing Markdown;
- an ultra-fast Codex notification-first completion can outrun the matching
  `turn/start` response, and cancellation may wait for the bounded active
  request timeout;
- transcript cancellation and persistence publication are not one atomic
  transaction, and remote STT has a narrow reauthorization-to-upload timing
  window after the last policy check;
- the transactional workspace-scope implementation has structural and unit
  coverage, but a real A-to-failing-B-to-A bookmark/read/write/restart
  fault-injection test remains;
- real-device performance and accessibility.

These are explicit gates, not claims of completion.

## Phase closure verdict

The current candidate tree is ready to enter formal software testing: its
bounded P0 implementation, functional UI integration, Codex/STT separation,
recording-to-transcript path, recovery, configuration persistence,
content-free diagnostics, staged-app lifecycle smoke, 538-test CI-shaped Debug
gate, and fresh Release build are in place. It is **not** a public-Beta or 1.0
distribution candidate. Hardware-duration, accessibility, performance,
full outbound-network, signing/notarization, updater, complete export, and
UN/official-record ingestion gates remain open.

The ten most serious remaining risks are:

1. the package still supports macOS 15 while the approved Apple Speech route
   requires macOS 26;
2. whole-system audio, external-device management, live source switching,
   sleep/wake, device loss, and 4/8-hour runs lack intended-device proof;
3. a post-record route change needs an immutable meeting-profile supersession
   graph and backward-compatible migration;
4. UN automatic transcripts and later official PV/SR records need distinct
   immutable provenance, rights checks, and an approved network/API contract;
5. export is not yet a complete TXT/DOCX/PDF/SRT/VTT/JSON/archive portability
   surface;
6. updater ownership, Developer ID, notarization, appcast signing, rollback,
   and clean-machine evidence are unresolved;
7. App Sandbox and a distributable trusted Codex subprocess/runtime path are
   not proven;
8. Codex app-server drift and the adverse login/quota/rate-limit/network matrix
   require live regression;
9. remote STT destination, retention, provider policy, cost, and per-meeting
   authorization need release-policy review; and
10. short isolated CPU/memory/lifecycle/no-socket observations now exist, but
    sustained energy, I/O, long-transcript UI, VoiceOver, keyboard, contrast,
    resize, and complete no-unauthorized-network evidence is incomplete.

## Deviations and Better Alternatives

- The suggested eight-step New Meeting wizard was reduced to a readiness
  coordinator that reuses the accepted import, recording, UN metadata, and
  routing surfaces. This avoids duplicating provider setup or prematurely
  freezing meeting-profile schema and visual hierarchy.
- The Assistant is a bounded selected-segment panel in the existing workspace,
  rather than a new detachable/dockable layout system. It proves the Codex
  vertical slice without starting U1 or introducing unvalidated window state.
- Selected-application capture is labelled exactly as such. It is not presented
  as whole-system audio, and external-device/source-switching work is held for
  the intended-device lifecycle design and tests.
- Apple Speech is used only where the operating system actually exposes the
  required asset APIs. The project does not silently raise the minimum OS or
  bundle an unapproved local STT backend to make macOS 15 look complete.
- UN Web TV remains an exact-host metadata path. Automatic transcript, media
  download, and official-record ingestion are not simulated because they
  require approved endpoints, rights, immutable source kinds, and migration.
- Export remains the existing controlled Markdown path. The project does not
  relabel plain text as DOCX/PDF/SRT/VTT/JSON or create an archive format before
  its provenance and round-trip contract is defined.
- Sparkle is not added merely to populate an Update button. A fail-closed
  update/service contract and truthful unconfigured About state are used until
  distribution identity, channel, appcast ownership, and rollback are decided.
- Codex uses a separately installed, pinned official runtime and an isolated
  app-owned home. It is not bundled, is never granted audio, and cannot become
  an STT provider.
- The supplied brand is integrated through deterministic assets while the
  existing UI language is preserved. Full visual normalization remains U1.
- Provider retention promises are treated as external policy, not a guarantee
  the macOS client can enforce; release configuration must bind the reviewed
  destination and policy before remote execution.

## Next smallest change set

Run the formal-test candidate on the intended minimum/current macOS and devices
using the matrix in the performance, audio, UI, and release documents. Record
measured results without changing architecture. Each unresolved product choice
above should then become its own ADR-backed slice; none should be folded into a
single release or visual-refactor change.
