# ADR-0019: v4 Provider Routing, Codex, and Release-Service Gates

Status: Accepted under the user's 2026-07-28 v4 pre-Beta authorization
Date: 2026-07-28
Decision owners: User and Codex
Tracking: GitHub Issue #60

## Context

The accepted MVP is local-first and has production Apple on-device
transcription, translation, analysis, and briefing routes. Its model-policy
router records exact classification, destination, retention, authorization,
and data-category inputs. It has no Codex application provider, general
provider registry, task-routing settings, licensing client, or updater.

The user has adopted the BlueMinutes pre-Beta implementation brief v4 as the
current execution baseline. v4 requires a Codex subscription text-intelligence
vertical slice, independent speech-to-text setup, capability-based BYOK
providers, explicit task routing, deterministic Sensitive Meeting behavior,
and release-service guards. The same authorization explicitly preserves the
current UI language, defers U1 visual redesign, keeps commercial features
disabled, and leaves the separately developed website disconnected until
testing is complete.

ADR-0018 accurately recorded that no Codex/OpenAI application-provider route
existed at the time and kept its Phase 1 capabilities off. Its blanket
no-outbound-provider limitation is superseded only for the bounded,
user-authorized Codex text route described here. Its immutable evidence,
least-context, compatibility, and default-off Research constraints remain
binding.

The same user authorization narrowly supersedes ADR-0002's statement that no
external model executable is approved, solely to allow a compatible
system-installed official `codex app-server` runtime under this ADR's
confinement rules. It does not approve a bundled/downloaded executable,
arbitrary external process, updater, deployment, signing, notarization, or
public binary distribution. If process isolation cannot be proven, the provider
remains unavailable.

## Decision

### 1. Eligibility is declared by an exact provider/model capability

BlueMinutes owns a typed provider registry. Every exact model declares the
tasks it can perform. Task routing uses that metadata and never infers
capability from a provider name or model name.

Speech-to-text execution requests distinguish batch from realtime and require
the matching exact capability; the resolver never chooses one by sorting a
combined capability set. The Codex subscription profile declares neither.
Therefore Codex cannot appear in an STT selector or resolve an STT task.

The current Apple Speech route truthfully declares batch capability only. A
future genuinely streaming backend must prove streaming behavior before it may
declare realtime capability.

### 2. Missing STT is an explicit record-only state

An absent STT selection resolves to `recordOnly`. It is not a model failure,
manual transcript provider, or implicit Codex route. Recording and imported
transcript workflows remain available, while the UI must not claim live or
completed transcription.

Global, workspace, and meeting routing values use an explicit three-state
contract: `inherit`, `disabled`, or one exact selection. Missing entries and
`inherit` continue downward; `disabled` stops resolution. Consequently a
meeting-level Record Only state cannot be confused with an absent override and
cannot inherit global STT.

The scope stack cannot accept independent workspace/meeting IDs and an
unrelated policy snapshot. `TaskRoutingSecurityContext` validates the exact
MeetingProfile, SensitivityLabel, and AccessPolicy graph, derives workspace and
meeting identity from that meeting, and proves the immutable model-policy
snapshot does not widen the graph. Every ready/authorization-required result
records the exact meeting revision and winning global/workspace/meeting profile
origin.

### 3. Fallback never changes provider, destination, or cost silently

A route may record a repair or fallback candidate, but provider failure,
credential failure, quota exhaustion, or model removal does not automatically
activate it. The resolver returns an unavailable state and the user chooses
whether to repair or change the route. The resulting meeting/job snapshot
records the exact provider, model, capability, data route, and cost owner.

Capability and runtime readiness are not external-processing authority. The
foundation resolver may return an external authorization-required candidate,
but never `ready`, until the execution supplies the existing full
`ModelRouteRequest`: exact deployment environment, destination, retention,
data categories, organization policy, visible user authorization, immutable
security-policy snapshot, and an approved concrete adapter.

### 4. Sensitive Meeting is a resolver policy, not a UI filter

The resolver derives Sensitive Meeting restrictions from the exact immutable
`ModelSecurityPolicySnapshot`, including its sensitivity-label revision,
access-policy revision, effective classification, no-outbound mode, and
approved-provider set. It never accepts a free-standing UI Boolean as
authority. Sensitive Meeting permits local providers only. Remote STT, Codex text,
remote BYOK text, external research, and cloud fallback fail closed in the
resolver even if stale settings or a malformed UI attempt to select them. If
no local STT model is ready, STT remains unavailable; recording can continue.

### 5. Codex uses the official system-installed runtime first

The first Codex vertical slice will:

- detect a compatible, user-installed official Codex runtime;
- use the official app-server protocol over a local stdio subprocess;
- pin protocol behavior to an explicitly tested runtime/schema range;
- use official app-server account login/logout APIs;
- leave Codex authentication material under the official runtime's control;
- never read, copy, persist, or log Codex token files;
- create/resume threads, stream turns, interrupt work, surface quota/runtime
  failures, and reconnect without affecting recording or STT;
- send only user-authorized bounded text context; and
- expose only application-owned, bounded, read-only meeting tools.

Every thread uses an empty disposable non-workspace cwd, explicit read-only
sandbox, `approvalPolicy: never`, and a config overlay disabling shell/unified
execution, web search, Apps/connectors, plugins, multi-agent, memories, hooks,
login shells, and inherited user workspace tools. The client denies and
terminates on command, shell, file-change, patch/diff, arbitrary-path, external
tool, or permission-escalation events. The only potential experimental API is
the exact version-pinned bounded `dynamicTools` transcript reader. No real
meeting context may enter the process until fake and synthetic tests prove this
boundary; inability to disable built-in execution keeps the provider
unavailable.

The first slice does not bundle, download, replace, or update a Codex runtime.
It does not use an OpenAI API key and does not treat local MCP as an inference
provider. App Sandbox/process feasibility and exact runtime compatibility must
be proven before public binary distribution.

### 6. Codex is text-only and never receives raw audio

Codex may perform meeting chat, selected-transcript analysis, document query,
external research, summary/minutes, translation, and structured output when
the exact task and policy authorize text egress. It never receives canonical
audio, recording chunks, microphone input, system audio, or an audio file
path. Codex failure and quota state are independent from STT readiness.

### 7. BYOK secrets and Codex subscription authentication stay separate

BYOK provider metadata may reference an opaque `SecretIdentifier`; secret
bytes use macOS Keychain and are never persisted in routing settings or shown
again. A remote provider is eligible for STT only after its exact model
declares and verifies a speech capability. A real remote-STT adapter still
requires a separate provider/data-route decision naming endpoint, retention,
audio categories, user authorization, billing owner, and offline alternative.

### 8. Beta release services fail closed

`BillingMode` has `disabled`, `sandbox`, and `production` vocabulary, but this
codebase exposes only the public-Beta disabled gate and an explicitly
build-authorized internal sandbox constructor. There is no production
constructor, licensing client, trial, paywall, device limit, or licensing
network dependency in this phase.

The app-side website contract defaults to `.disconnected` with no URL.
`.publicLinksOnly` may later expose ordinary website/support/privacy links but
no update-feed or billing API endpoint. `.services` remains unwired. Browser
checkout success is never entitlement proof.

The update policy defaults to unconfigured and performs no request. A future
configured feed requires the dedicated unforgeable updater approval, membership
in the exact update-feed allowlist, and equality between the website handoff and
`UpdatePolicy`. A configured updater must not download or install during an
active meeting.
Sparkle/appcast keys, Developer ID, notarization, and public distribution remain
separately gated.

### 9. Existing UI language remains the integration surface

New Intelligence, STT, BYOK, Task Routing, readiness, and later Codex Assistant
surfaces reuse the existing native `TabView`, `Form`, `Section`, editor,
inspector, state, accessibility, and visual-regression patterns. This ADR does
not authorize U1, a global restyle, or a broad design-token rewrite.

## Compatibility and migration

The new registry and release-service values are application contracts only in
the foundation slice; they do not alter SQLite schema or accepted job payloads.
Existing `ModelPolicyRouter`, transcript coverage, immutable revisions,
provider metadata, and local production jobs remain unchanged.

When routing preferences or conversation metadata become persistent, they
require an ordered backward-compatible schema migration, supported-prior-state
tests, an exact rollback anchor, and fail-closed decoding of unknown values.
Existing transcript job format version 1 must not be widened in place to admit
remote audio routes.

## Rejected alternatives

- **One generic model picker:** rejected because it hides task capability,
  destination, privacy, and cost.
- **Codex as STT or a wrapper around another STT executable:** rejected because
  it misstates the actual provider and subscription boundary.
- **Silent provider fallback:** rejected because it may change data egress or
  cost without authorization.
- **Reading Codex auth files directly:** rejected because BlueMinutes does not
  own those credentials.
- **Bundling or downloading Codex in this phase:** rejected pending licensing,
  signing, notarization, compatibility, size, update, and rollback proof.
- **Connecting the website or sandbox billing now:** rejected because testing
  precedes integration and success redirects are not authorization.
- **Starting U1 while functional architecture is moving:** rejected by the
  user's explicit phase boundary.

## Verification

The foundation gate requires tests proving:

- Codex has text capabilities and no STT capability;
- STT eligibility is capability-filtered;
- no STT resolves honestly to record-only;
- fallback is surfaced for repair and never selected silently;
- external candidates cannot become ready without the full existing model-route
  policy and adapter authorization;
- Sensitive Meeting rejects every non-local route;
- meeting-level disabled/Record Only masks less-specific STT selections;
- batch and realtime STT resolve only their exact capability;
- disabled billing keeps features unlocked and permits no licensing request;
- disconnected website/update configuration has no service endpoint; and
- the supplied brand sources and deterministic derived icon remain
  hash/size-bound.

The Codex implementation slice adds fake-transport tests for runtime/version
mismatch, initialize, login cancel/logout, thread start/resume, ordered
streaming, interrupt, process loss, quota errors, context bounds, read-only
tool bounds, disposable cwd, disabled shell/file/external tools, denied
permission requests, log redaction, and the absence of every audio path.
