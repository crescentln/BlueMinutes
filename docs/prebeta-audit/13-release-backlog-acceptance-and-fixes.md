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
| Fresh Debug/Release/warnings/full-test baseline | Pass at v4 rollback anchor |
| Supplied logo/icon replacement | Implemented in foundation branch; PR gate pending |
| Capability registry and Codex-excluded STT | Implemented contracts/tests; UI/persistence pending |
| Explicit record-only and no silent fallback | Implemented resolver; workflow wiring pending |
| Sensitive Meeting local-only resolver | Contract binds exact security-policy revisions; composition/persistence pending |
| External execution authorization | Foundation never returns ready without the later full ModelRouteRequest/adapter gate |
| Billing disabled, website disconnected, update unconfigured | Compile-gated contracts/tests; composition/network-spy proof pending |
| Data loss/recovery/version lineage | Existing accepted foundation; real-device matrix pending |
| Codex app-server vertical slice | Pending |
| Keychain BYOK composition | Keychain exists; UI/profile wiring pending |
| Active meeting/window separation | Pending; known termination conflict |
| Long transcript search/performance | Pending |
| Basic updater architecture | Safety contract implemented; About/provider pending |
| Dead code/resource audit | Static first pass complete; Instruments pending |

## P1 status

- three source modes: partial;
- New Meeting coordinator: pending;
- outline/search: pending;
- resizable/scoped AI Chat: pending;
- Codex runtime/login/resume/quota recovery: pending;
- complete four-section Intelligence UI: pending;
- UN automatic/official/local source distinction: pending;
- local model manager: platform decision pending;
- one supported local STT route: Apple batch exists on macOS 26+, macOS 15 gap;
- optional remote STT: explicitly gated;
- complete export: Markdown only;
- Sparkle: distribution-gated;
- performance and accessibility matrix: pending after new surfaces;
- Beta/1.0 unlocked state: currently true; composition/network spy proof pending.

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
  exact feed allowlist, and exact equality with the composed update policy;
  app-composition and network-spy proof remain open.

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
- initialize, thread start/resume, stream, cancel, crash/reconnect;
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
- active meeting lifecycle across sleep/wake and process termination;
- remote STT privacy/retention/provider choice;
- intended update/distribution channel and signing ownership;
- real-device performance and accessibility.

These are explicit gates, not claims of completion.
