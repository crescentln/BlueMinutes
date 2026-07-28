# Architecture and Dependency Audit

## Module boundary

| Target | Current responsibility |
| --- | --- |
| `MeetingBuddyDomain` | Provider-neutral semantic values, immutable revisions, evidence, validation |
| `MeetingBuddyApplication` | Use-case contracts, security/routing policy, recovery and task interfaces |
| `MeetingBuddyPersistence` | GRDB repositories, workspace files, migration, recovery, export |
| `MeetingBuddyTasks` | Single task manager, checkpoints, cancellation, retry |
| `MeetingBuddyMedia` | Native import, capture, canonical audio, exact-host UN metadata |
| `MeetingBuddyAI` | Apple providers, pipeline jobs, validation, Keychain secret store |
| `MeetingBuddyFeatures` | SwiftUI presentation, scene state, stores, existing design system |
| `MeetingBuddyAutomation` | Typed local command boundary, CLI/MCP adapters |
| `MeetingBuddyApp` | Composition root and application lifecycle |

The boundaries match the modular-monolith invariant. New provider profiles,
release gates, and routing resolution belong in `MeetingBuddyApplication`.
Codex transport belongs behind a new application protocol with its concrete
process implementation in `MeetingBuddyAI`. UI must not start `Process`, query
SQLite, or handle credentials.

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
- Closing the only main window during active recording currently enters
  termination, conflicting with v4 background-meeting behavior.
- Apple Speech consumes verified chunks after capture; it is not realtime STT.
- Provider and long-running work already use async/task boundaries; new process
  streams require bounded buffering, cancellation, and actor isolation.

## Refactoring guidance

1. Bridge product routing to existing execution contracts in composition.
2. Add persistence only after the routing value model is frozen.
3. Implement Codex transport behind a fakeable protocol and keep process
   lifecycle out of SwiftUI.
4. Move active meeting lifetime to an app-owned controller before adding a
   menu-bar surface.
5. Measure before splitting modules or introducing dependencies.

No dependency was added by the foundation slice.
