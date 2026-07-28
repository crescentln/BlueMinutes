# BlueMinutes 0.4.0 — v4 Formal Software-Test Candidate

- Candidate prepared: 2026-07-28
- Application version: `0.4.0` (build `4`)
- Source state: untagged branch and draft Pull Request candidate
- Distribution scope: local ad-hoc DEVELOPMENT package for testing on the
  build Mac only

BlueMinutes 0.4.0 closes the bounded functional implementation round defined by
the v4 pre-Beta brief. It preserves the existing native UI language while
adding the routing, provider, lifecycle, transcript, diagnostics, and brand
work needed to begin structured software testing.

This is not a public-Beta distribution claim. The latest public GitHub source
Release remains `v0.3.0`; this phase creates no `v0.4.0` tag, GitHub Release,
uploaded binary, deployment, installation channel, or update feed.

## Functional highlights

- Intelligence Settings now separates provider profiles, speech-to-text, task
  routing, and Sensitive Meeting policy instead of presenting one generic
  model choice.
- Speech-to-text has explicit Record Only, Apple local batch, and optional
  OpenAI remote batch routes. Missing, disabled, deleted, or unready providers
  produce visible repair state and never silently change destination or cost.
- OpenAI BYOK secret bytes stay in macOS Keychain. Remote audio execution
  additionally requires exact canonical audio, a ready speech-capable profile,
  non-sensitive current policy, and fresh visible per-meeting authorization.
  That transient authority cannot survive restart or retry and is rechecked
  before every remote chunk.
- Codex subscription support is a separate text-only route through a compatible
  user-installed official app-server runtime. It supports account/quota state,
  ephemeral thread lifecycle, streaming, interruption, selected-transcript
  context, and one bounded application-owned read-only search tool. Disconnect
  purges private session state; reconnect starts a new thread.
- Closing the main window preserves an active app-owned recording. Reopen,
  menu-bar stop, true Quit, retained-track publication, and restart recovery
  now have explicit states.
- Recording output enters the existing canonical-audio workflow with exact
  source and track provenance. Dual capture requires an exact track choice.
- Transcript Review adds deterministic five-minute outline anchors and bounded
  text/time search without replacing immutable evidence selection.
- A lightweight New Meeting readiness coordinator and an independent About
  surface reuse the accepted components and visual language.
- The supplied BlueMinutes logo and icon are integrated through deterministic,
  hash-bound source and derived assets.

## Privacy and safety boundaries

- Sensitive Meetings and no-outbound policy permit local providers only.
- Codex never receives raw audio, canonical-audio paths, arbitrary files,
  credentials, or the whole workspace. Shell, file-change, patch, web-search,
  Apps, plugins, MCP, memories, multi-agent, and permission-escalation surfaces
  are disabled in its isolated runtime configuration.
- Codex authentication remains under the official runtime's control and is
  never copied into BlueMinutes storage.
- Remote STT and Codex are independent; failure or quota state in one never
  activates the other.
- Persisted queued jobs are finalized safely after restart instead of replaying
  transient file, capture, or outbound authority. The user must explicitly
  restart the operation and reselect any required source.
- Workspace switching commits its security-scoped bookmark only after the new
  workspace passes recovery; a failed candidate leaves the prior workspace and
  restorable bookmark active.
- Billing and licensing remain disabled. The typed website handoff remains
  disconnected with no endpoint, and updates remain unconfigured.
- Fixed Apple Unified Logging events accept no meeting content. The About
  diagnostic copy is bounded to sanitized build, operating-system, and
  release-mode facts.

## Local development package

From the clean committed candidate source:

```sh
MEETINGBUDDY_SIGN_IDENTITY=- ./script/package_release_candidate.sh
./script/verify_release_candidate.sh \
  dist/BlueMinutes-0.4.0-development \
  development
```

The ignored local release set contains:

- `BlueMinutes.app`
- `BlueMinutes-0.4.0-development.zip`
- `BlueMinutes-0.4.0-development.zip.sha256`
- `source-files.sha256`
- `release-manifest.json`

The schema-v2 manifest binds version `0.4.0` build `4` to the exact clean Git
head and tree, the absent optional exact tag, complete tracked-source inventory,
resolved dependency digest, toolchain, app/archive digests, and signature
classification. It records `classification: DEVELOPMENT` and
`distribution_authorized: false`; `distribution` verification must reject this
ad-hoc package.

The package is retained only under ignored local `dist/`. It is not installed,
uploaded, attached to a GitHub Release, advertised as a supported download, or
authorized for public distribution.

## Verification baseline

The candidate gate includes warning-as-error SwiftPM build/test shards covering
538 discovered tests, an independent warnings-as-errors Release build,
brand/plist/signature/source checks, and an isolated staged-app close/reopen,
About, clean-quit, content-free-log, and idle no-socket smoke. Installed Apple
model probes remain opt-in and use only project-authored synthetic input.

These bounded checks establish entry into formal software testing; they do not
close the intended-device, duration, accessibility, performance, outbound
network, signing, or distribution matrices.

The non-blocking implementation follow-ups retained for testing are a rare
notification-first Codex completion ordering, bounded request-cancellation
latency, a narrow remote-STT reauthorization-to-upload timing window,
non-atomic cancellation-versus-transcript publication, and a real
workspace-bookmark fault-injection scenario. None grants broader authority,
silent fallback, or persistent outbound authorization.

## Compatibility

- SQLite remains at schema v10 and GRDB remains pinned at 7.11.1.
- There is no schema migration or package-dependency change.
- `MeetingBuddyApp`, `com.meetingbuddy.desktop`, Swift targets, database paths,
  CLI/MCP commands, protocol identifiers, and serialized formats retain their
  compatibility names.
- macOS 15 remains the declared minimum, but automatic Apple Speech requires
  macOS 26 and installed local assets.

## Formal-test priorities

- microphone, selected-application, and dual-capture behavior on intended
  devices, including permissions, sleep/wake, source loss, force quit, and
  4/8-hour runs;
- macOS 15 versus macOS 26 local-STT support policy;
- large-transcript performance, energy, memory, I/O, resize, keyboard,
  VoiceOver, contrast, and reduced-motion behavior;
- complete proof that no unauthorized network route occurs;
- Codex runtime/login/quota/protocol-drift and remote-STT policy matrices; and
- immutable UN/official-record provenance, complete export formats, App
  Sandbox, bundled-runtime feasibility, Developer ID, notarization, updater,
  and clean-machine rollback as separate later gates.

Full U1 visual redesign, production billing/licensing, website connection or
deployment, a bundled Codex runtime, public binary distribution, and release
publication remain outside this candidate.

See [CHANGELOG.md](../CHANGELOG.md), the
[v4 pre-Beta audit](prebeta-audit/README.md), and
[release backup and rollback](RELEASE_BACKUP_AND_ROLLBACK.md).
