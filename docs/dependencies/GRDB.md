# GRDB Dependency Note

Status: Approved for Task 004A
Owner: Codex
Decision date: 2026-07-18
Pinned version: 7.11.1

## Purpose

GRDB supplies the narrow Swift adapter over the system SQLite library for
ordered migrations, transactions, foreign-key enforcement, safe statement
binding, database backup, and serialized/concurrent database access. It is
used only by `MeetingBuddyPersistence`; domain and application contracts do
not import GRDB types.

## Native and existing alternatives

The active macOS SDK exposes SQLite 3.51.0 through `SQLite3`, so a native C API
adapter is technically possible and would add no source dependency. It would,
however, require MeetingBuddy to own statement lifetime, value binding,
transaction nesting, migration bookkeeping, backup integration, error
translation, and Swift 6 concurrency isolation. Those are correctness-critical
storage mechanisms rather than product-specific behavior.

GRDB is preferred because it supplies those mechanisms while retaining SQLite
as the database engine and keeping the adapter replaceable. No ORM record type
is exposed outside the concrete persistence module.

## Size and distribution impact

- Swift Package Manager fetches the tagged GRDB source, increasing dependency
  checkout and build-cache storage. Transfer and cache size vary by SwiftPM/Git
  state and are not treated as shipped-size evidence.
- The package links GRDB into the eventual application and uses the operating
  system SQLite library. No app bundle exists yet, so shipped binary and bundle
  size impact cannot be measured truthfully and remains unverified until an
  application target exists.
- GRDB 7.11.1 declares Swift tools 6.1 and macOS 10.15 or later. Task 004A
  raises MeetingBuddy's package manifest from tools 6.0 to 6.1 so its declared
  minimum matches the dependency; the current Swift 6.3.3 toolchain and
  macOS 15 package baseline satisfy those requirements.
- GRDB includes an Apple privacy manifest. It adds no network service, model,
  executable, or credential handling.

## Sandbox, signing, and build-network impact

- GRDB is compiled source linked into the future app; it adds no helper
  executable, runtime-loaded unsigned code, entitlement, daemon, or separate
  signing identity.
- It uses Apple's system SQLite library and does not itself broaden sandbox
  filesystem authority. MeetingBuddy's eventual container/bookmark policy
  remains the separate Task 005A decision.
- SwiftPM requires network access to resolve/fetch the exact source pin during
  dependency acquisition. The built library performs no runtime network call.
- Final code-signing, hardened-runtime, notarization, privacy-manifest merge,
  license-notice packaging, and shipped-size results remain unverified until
  an application bundle exists.

## Maintenance and security history

The project has been maintained since 2015. Version 7.11.1 is the current
official release as of this decision and was released on 2026-06-18. The
official repository showed active releases and no published repository
security advisory at review time. Absence of a published advisory is not a
guarantee that no vulnerability exists; dependency review remains part of
Task 007 and release review.

## License

GRDB is MIT licensed. Distribution must preserve the license notice in the
eventual application notices. There is no copyleft requirement.

## Update strategy

- Pin the exact reviewed release in `Package.swift` and commit
  `Package.resolved` when the task is later accepted and committed.
- Upgrade only in an authorized task with migration, repository, build, and
  dependency review.
- Do not enable SQLCipher, custom SQLite builds, or GRDB optional features
  without a separate dependency and distribution decision.

## Removal strategy

`MeetingBuddyApplication` owns repository and storage ports. GRDB remains an
implementation detail of `MeetingBuddyPersistence`, so another SQLite adapter
can replace it without changing domain objects, provider boundaries, or UI
contracts. SQL and migration behavior still require an explicit data migration
and cannot be swapped by merely changing imports.

## Validation plan

- debug and release builds with Swift warnings treated as errors;
- package dependency graph and exact resolved revision inspection;
- clean database creation and idempotent reopen;
- disposable prior-state and failed-migration rollback tests;
- immutable revision, active-pointer, dependency, and stale-state integrity
  tests;
- backup open/restore verification;
- scan that GRDB imports remain confined to the persistence module and its
  tests.

## Task 007 re-review

Reviewed: 2026-07-18

- `Package.swift` and `Package.resolved` still resolve exactly GRDB 7.11.1 at
  revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`; the package graph has no
  transitive source dependency.
- The official v7.11.1 GitHub release identifies the same abbreviated commit
  `b83108d` and a 2026-06-18 release date.
- The checked-out license is MIT, SHA-256
  `9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87`.
  Its notice must ship in eventual application notices.
- The checkout contains `GRDB/PrivacyInfo.xcprivacy`. GRDB imports remain
  confined to `MeetingBuddyPersistence` and persistence/task tests.
- GitHub's repository advisory page showed no published GRDB security advisory,
  and a GitHub Advisory Database search for `GRDB.swift` returned zero results
  at review time. This is a point-in-time negative result, not proof that no
  vulnerability exists.
- No SQLCipher, custom SQLite build, encryption library, executable, network
  service, entitlement, or optional GRDB product was added. ADR-0012 separately
  rejects application-level encryption for the current product boundary.

## Sources reviewed

- <https://github.com/groue/GRDB.swift/releases/tag/v7.11.1>
- <https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift>
- <https://github.com/groue/GRDB.swift/blob/v7.11.1/LICENSE>

## Task 011 release re-review

Reviewed: 2026-07-21

- A new-scratch release build resolves the single exact source dependency as
  GRDB 7.11.1 and produces no additional transitive source dependency.
- The final `MeetingBuddy.app` has no non-system dynamic library dependency;
  GRDB is linked into the 25,170,800-byte arm64 executable.
- `GRDB_GRDB.bundle` now ships in `Contents/Resources` with the upstream
  `PrivacyInfo.xcprivacy` SHA-256
  `17784da62e51f74c5859df32fe402e01e25cdf6f797a4add06e2a3ce15c911f4`.
- `ThirdPartyNotices/GRDB-LICENSE.txt` ships with the previously reviewed exact
  MIT notice SHA-256
  `9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87`.
- The verified internal-alpha app occupies 24,608 KiB and its update archive
  6,704,678 bytes (6,547 KiB rounded down) on the audit host. These values
  include the whole product rather
  than an isolated GRDB size delta.
- The upstream release/tag, manifest, license, and privacy resource were
  rechecked; no dependency upgrade, SQLCipher/custom SQLite, optional GRDB
  product, entitlement, executable, network route, or credential behavior was
  added.
