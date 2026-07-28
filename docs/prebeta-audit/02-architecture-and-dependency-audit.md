# Architecture and Dependency Audit

## Module boundary

| Target | Current responsibility |
| --- | --- |
| `MeetingBuddyDomain` | Provider-neutral semantic values, immutable revisions, evidence, validation |
| `MeetingBuddyApplication` | Use-case contracts, security/routing policy, recovery and task interfaces |
| `MeetingBuddyPersistence` | GRDB repositories, workspace files, migration, recovery, export |
| `MeetingBuddyTasks` | Single task manager, checkpoints, cancellation, retry |
| `MeetingBuddyMedia` | Native import, capture, canonical audio, exact-host UN metadata |
| `MeetingBuddyAI` | Apple providers, OpenAI batch STT, Codex app-server transport/session, pipeline jobs, validation, Keychain secret store |
| `MeetingBuddyFeatures` | SwiftUI presentation, scene state, provider/Codex stores, existing design system |
| `MeetingBuddyAutomation` | Typed local command boundary, CLI/MCP adapters |
| `MeetingBuddyApp` | Composition root and application lifecycle |

The boundaries match the modular-monolith invariant. New provider profiles,
release gates, and routing resolution belong in `MeetingBuddyApplication`.
Codex transport remains behind application contracts with its concrete process
implementation in `MeetingBuddyAI`. The composition root owns the service;
SwiftUI observes bounded stores and does not start `Process`, query SQLite, or
handle credential bytes.

## Dependency inventory

`Package.swift` has one external dependency:

- GRDB 7.11.1, exact pinned, used for SQLite repositories and migrations.

Local measurement on the 2026-07-28 audit host:

| Item | Size | Interpretation |
| --- | ---: | --- |
| GRDB Git checkout under `.build/checkouts` | 154 MiB | Build/cache input; not copied wholesale into the app |
| Foundation-tree Release `MeetingBuddyApp` | 30,324,592 bytes (28.9 MiB) | Fresh warnings-as-errors output in the isolated validation root; not a signed/notarized app-package size |
| Foundation validation build directory | 1.5 GiB | Disposable dependencies, build products, tests, and debug symbols; not distribution payload |

The measured Release executable SHA-256 is
`5ec67b02181f7182d5cd68a963f9253e521e97d014290bd416b41741f35fd6d4`.
It binds only that isolated working-tree build output; it is not a source
commit, package, signing, notarization, or distribution claim.

GRDB is actively used across repositories, migrations, recovery, and search;
removing it would create high correctness/migration risk for little demonstrated
runtime benefit. Its checked-in license text is MIT. The current conclusion is
to retain the exact pin, review updates deliberately, and measure the eventual
signed app bundle rather than treating checkout/cache size as shipped size.
No duplicate database, HTTP, JSON, audio, or logging package is present.

The Codex vertical slice does not need a new Swift package: Foundation
`Process`, pipes, actors, `JSONSerialization`/`Codable`, and the official local
app-server protocol are sufficient. A new dependency requires the controller's
license, privacy, size, update, removal, and rollback note.

## Local diagnostics boundary

The current functional tree uses Apple's existing Unified Logging framework;
it adds no dependency or outbound telemetry service. Eight fixed categories
cover Audio Capture, STT, Import, Storage, AI Provider, Licensing, Update, and
Windowing. Callers can emit only a closed enum of fixed event codes: the logger
API accepts no meeting title, transcript, identifier, path, URL, credential,
provider output, or arbitrary text field.

The About window's user-initiated diagnostic copy is a separate bounded report.
It accepts only length- and character-constrained build/OS metadata plus the
validated release modes, states explicitly that content, audio metadata,
credentials, URLs, and paths are absent, and fails closed on unsafe metadata.
The existing local telemetry policy remains disabled and no-outbound; local
content-free lifecycle logs do not create a network route.

## Dead code and duplication

No tracked production target is proven dead by the current static pass.
The four `AppCapabilities` Research flags remain deliberately default-off and
must not be deleted as dead code because ADR-0018 preserves their compatibility
role. The stale execution-ledger and UI-migration wording is documentation
drift, not runtime dead code.

Potential duplication to avoid:

- do not create a second Keychain implementation;
- do not create a second task scheduler for Codex or STT;
- do not create a second cloud-policy router;
- do not treat local MCP tools as a second application service layer;
- do not duplicate website or payment schemas in the app.

## Resource and lifecycle findings

- Recording persistence and recovery are strong and extensively tested.
- Active recording now belongs to the app-scoped store. Closing the main window
  preserves it, and the menu-bar item can reopen or stop/finalize the same
  session.
- Verified completed recording tracks can enter the existing canonical-audio
  and transcript workflow; dual tracks require exact selection.
- Apple Speech and the optional OpenAI adapter consume verified chunks after
  capture; neither is labelled realtime STT.
- Codex and provider streams use bounded queues, cancellation, typed process
  loss, and actor isolation.
- Core request and window lifecycle boundaries now emit fixed content-free
  local diagnostics, and the staged-app smoke confirmed the expected
  start/window/quit events without opening a socket.

## Refactoring guidance

1. Keep product routing bridged to existing execution contracts in composition.
2. Preserve the revisioned non-secret configuration repository and Keychain
   separation; do not move provider secrets into workspace schema.
3. Keep Codex transport behind its fakeable protocol and process lifecycle out
   of SwiftUI.
4. Extend the app-owned recording lifecycle only with explicit source-epoch and
   recovery contracts.
5. Measure before splitting modules or introducing dependencies.

No external dependency was added by either the foundation or current functional
slice.
