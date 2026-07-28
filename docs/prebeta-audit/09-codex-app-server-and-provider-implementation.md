# Codex App-Server and Provider Implementation

## Current status

The current branch implements a bounded Codex text vertical slice:

- exact official runtime discovery pinned by version, build, digest, and
  signing identity;
- an isolated BlueMinutes-owned Codex home and disposable non-workspace cwd;
- app-server initialize, account/login/logout/rate-limit, thread
  start/in-process reuse/delete, turn streaming/interrupt/retry, process-loss,
  and reconnect-to-a-new-thread handling;
- Intelligence Settings connection/account/quota state;
- a selected-transcript-segment Assistant with visible per-request
  authorization; and
- one bounded application-owned current-meeting transcript search tool.

Codex declares no batch or realtime STT, never receives audio, and its
failure/quota state does not affect recording, STT, editing, search, or export.
Sensitive/Restricted meetings deny it in both the resolver and central
model-policy router. Local stdio MCP remains a separate read-only automation
boundary and is not exposed to the Codex subprocess.

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

`CodexRuntimeManager` resolves only the explicit official application/installed
candidates allowed by policy, verifies version/build/digest/signing identity,
and returns typed missing, incompatible, or untrusted states. It does not
search arbitrary writable directories or execute a meeting-provided path.

## Authentication

BlueMinutes calls official app-server account methods and exposes both returned
browser and device-code flows through normal macOS links. Login may be
cancelled. Logout is explicit because the official runtime may have a user-wide
session.

BlueMinutes never reads `~/.codex/auth.json`, browser storage, cookies, OAuth
tokens, refresh tokens, or API keys. It persists only safe account state and
no BlueMinutes-owned account, login, thread, or conversation state. Protocol
identifiers and account/quota projections remain in memory only. The official
runtime retains sole control of authentication through its keyring path.

## Transport and session service

The implementation uses:

- `CodexAppServerTransport` actor for one local stdio process, request IDs,
  bounded event queue, initialize, process exit, cancellation, and redacted
  errors;
- `CodexMeetingSessionService` for meeting/thread mapping, turn lifecycle,
  quota state, ephemeral reconnect, confirmed process shutdown/private-state
  purge, and exact context requests;
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
experimental tools. The sole enabled dynamic surface is the exact
version-pinned `dynamicTools` field used for the bounded transcript reader. Its
schema, opaque identifiers, page limit, result shape, and fail-closed behavior
are covered by transport and contract tests.

`history.persistence` is forced to `none`. The private Codex home, session
directory, and temporary directory are removed before every connection and
after confirmed process exit. Cleanup failure remains a visible failed state
with its retry handle retained; the service cannot report disconnected or
replace an unconfirmed process. A disconnect during runtime discovery or
startup cancels and awaits that attempt before application termination may
complete.

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

BYOK is a separate provider family, not Codex authentication. The implemented
configuration reuses `MacOSKeychainSecretStore` and persists only an opaque
`SecretIdentifier`. Provider/profile state records exact model capabilities,
text-versus-audio data route, destination, retention policy, API cost owner,
readiness, and test timestamp. A text-only key cannot appear in STT.

The OpenAI speech connection test sends only the integrity-bound synthetic
sample and verifies its expected transcript. Actual remote batch STT
additionally requires exact canonical audio, non-sensitive classification, a
ready speech-capable profile, and fresh visible per-meeting audio-egress
authorization. Codex login success cannot satisfy any BYOK gate and BYOK
failure never causes a silent Codex switch.

## Error and quota behavior

Distinguish runtime missing/incompatible, not authenticated, login cancelled,
network unavailable, process exited, protocol mismatch, quota unavailable,
turn interrupted, invalid response, and context denied. Never silently switch
to a paid BYOK API. Recording, local STT, editing, search, and export remain
available.

## Vertical-slice proof

Deterministic tests cover compatible/incompatible runtime detection, the
initialize handshake, browser/device login and cancellation, account/logout,
ephemeral thread start, ordered streaming, interrupt/retry, process loss and
fresh reconnect, connection/disconnect races, rate limits, selected-text
binding, the bounded transcript tool, strict disposable confinement,
prohibited command/file/App/plugin/MCP/web and permission events, and
audio/path/secret absence. Opt-in tests also exercised the installed pinned
official runtime and a no-meeting-data account/session connection on
2026-07-28.

App Sandbox, signing, bundled-runtime, and public-distribution proof remain
separate gates.
