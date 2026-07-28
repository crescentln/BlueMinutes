# Codex App-Server and Provider Implementation

## Current status

At rollback anchor `b41ae589`, BlueMinutes has no Codex application provider,
runtime locator, app-server transport, subscription login, conversation
persistence, or AI Chat surface. Local stdio MCP is a separate read-only
automation boundary.

The foundation slice adds only Codex capability metadata and safety rules:

- Codex supports selected text tasks;
- Codex declares no batch or realtime STT;
- its data route is authorized text through the user's Codex subscription;
- its failure/quota state does not affect STT; and
- Sensitive Meeting denies it.

## Verified official protocol baseline

Verified on 2026-07-28 against official Codex App Server documentation and the
installed `codex-cli 0.146.0-alpha.3.1`:

- default transport is newline-delimited JSON-RPC-like messages over stdio;
- a client sends `initialize`, then `initialized`;
- account APIs include login start/cancel, account read, logout, and rate
  limits;
- thread APIs include start, resume, list, and fork;
- turn APIs include start, streamed notifications, steer, and interrupt;
- CLI-generated JSON schema is version-specific;
- WebSocket mode is experimental and unnecessary for the local app.

Primary references:

- <https://developers.openai.com/codex/app-server/>
- <https://github.com/openai/codex/tree/main/codex-rs/app-server>

Implementation must generate/review schema from the exact supported runtime
version rather than copying illustrative JSON from this audit.

## Runtime strategy

Phase 1 uses a compatible official system-installed `codex` executable.
BlueMinutes does not bundle, download, overwrite, or auto-update it.

`CodexRuntimeLocator` must resolve an explicit trusted candidate, obtain its
version, compare a supported schema range, and present install/upgrade guidance.
It must not search arbitrary writable directories or execute a meeting-provided
path.

## Authentication

BlueMinutes calls official app-server account methods and opens the returned
browser/device URL through the normal macOS path. Login may be cancelled.
Logout consequences must be visible because the official runtime may have a
user-wide session.

BlueMinutes never reads `~/.codex/auth.json`, browser storage, cookies, OAuth
tokens, refresh tokens, or API keys. It persists only safe account state and
opaque login/thread identifiers required by the protocol.

## Transport and session service

The implementation uses:

- `CodexAppServerTransport` actor for one local stdio process, request IDs,
  bounded event queue, initialize, process exit, cancellation, and redacted
  errors;
- `CodexMeetingSessionService` for meeting/thread mapping, turn lifecycle,
  quota state, reconnect, and exact context requests;
- fake transport tests before any live/synthetic gate.

No SwiftUI view directly starts or owns the subprocess.

### Execution confinement

The official runtime is an agentic executable, so a read-only BlueMinutes
dynamic tool is not sufficient isolation. Every `thread/start` and
`turn/start` must use one empty, disposable, app-owned working directory that
is outside every user workspace and contains no meeting data. The request must
set `sandbox: "read-only"` and `approvalPolicy: "never"` rather than inheriting
the user's defaults.

The per-thread config overlay must disable the shell tool, unified execution,
web search, Apps/connectors, plugins, multi-agent, memories, hooks, and login
shells; it must not load user MCP servers, skills, workspace configuration, or
experimental tools. The sole possible experimental exception is the exact
version-pinned `dynamicTools` field needed for the bounded transcript reader,
and it remains disabled until its schema and fail-closed behavior are tested.

The client must reject and terminate the thread on every command-execution,
file-change, patch/diff, filesystem-path, MCP/app/plugin, shell-command, or
permission-escalation request/notification. It never approves
`commandExecution`, `fileChange`, `execCommand`, or
`item/permissions/requestApproval`. A path outside the disposable directory in
any event is a protocol violation even if no write occurred.

No real meeting text may enter a live runtime until fake-transport tests and a
synthetic empty-workspace process test prove those controls. If the supported
app-server version cannot disable the built-in execution/file surfaces, the
Codex provider remains unavailable; BlueMinutes does not rely on prompt text as
a security boundary.

## Context bridge

Permitted inputs are explicit user prompts plus bounded selected transcript
segments, timestamps, evidence identifiers, and user-selected document
snippets. Raw audio, arbitrary workspace paths, entire databases, secrets,
unrelated meeting history, and hidden logs are prohibited.

The first read-only tool returns a bounded page of exact transcript segments
through an application service. It accepts opaque meeting/revision identifiers,
enforces classification and workspace authority, and returns no path or write
capability.

## Text-only provider boundary

Codex may assist with selected-text analysis, meeting chat, summary/minutes,
translation, document query, external research, and structured output. Every
consequential result still passes schema validation, exact evidence binding,
and human confirmation. Codex never receives audio and never becomes an STT
option.

## Independent BYOK path

BYOK is a separate provider family, not Codex authentication. The repository
already has `MacOSKeychainSecretStore`; the v4 path must reuse it and persist
only an opaque `SecretIdentifier`. Provider/profile state records exact model
capabilities, text-versus-audio data route, destination, retention/training
policy, API cost owner, readiness, and visible authorization. A text-only key
cannot appear in STT, and an audio-capable remote STT model requires the
separate audio-egress approval described in the audio audit.

No new BYOK profile UI, remote adapter, credential-validation PoC, or network
request has run in the foundation slice. Those remain explicit implementation
and test gates; Codex login success cannot satisfy them and BYOK failure never
causes a silent Codex switch.

## Error and quota behavior

Distinguish runtime missing/incompatible, not authenticated, login cancelled,
network unavailable, process exited, protocol mismatch, quota unavailable,
turn interrupted, invalid response, and context denied. Never silently switch
to a paid BYOK API. Recording, local STT, editing, search, and export remain
available.

## Required vertical-slice proof

- compatible and incompatible runtime detection;
- initialize/initialized handshake;
- browser/device login start, cancel, completion, account read, and logout;
- thread start/resume;
- ordered agent-message streaming;
- turn interrupt;
- process loss and explicit reconnect;
- rate-limit/quota presentation;
- selected-text context bound;
- one bounded read-only transcript tool;
- disposable non-workspace cwd plus explicit read-only/never policy;
- shell, file-change, command, Apps/plugins/MCP, web, and permission-denial
  tests;
- audio/path/secret absence tests;
- synthetic opt-in live test with no user data.

App Sandbox, signing, bundled-runtime, and public-distribution proof remain
separate gates.
