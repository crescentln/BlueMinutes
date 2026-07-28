# Changelog

All notable project changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable.

## [Unreleased]

Target application candidate: `0.4.0` (build `4`). This is not yet a tagged
GitHub Release.

### Added

- Capability-based Intelligence configuration with separate provider profiles,
  task routing, workspace and meeting overrides, explicit Record Only, and
  immutable meeting-route snapshots.
- A bounded Codex subscription text-assistance vertical slice using a
  compatible user-installed official app-server runtime, selected transcript
  text, account/quota state, ephemeral thread lifecycle, and one
  application-owned read-only transcript search tool.
- Independent Apple local and optional OpenAI remote batch STT routes, with
  Keychain-backed BYOK metadata, connection testing, exact capability checks,
  and visible per-meeting audio-egress authorization.
- Recording-to-canonical-audio handoff, app-owned active-session recovery,
  close/reopen and menu-bar controls, a lightweight New Meeting readiness
  coordinator, transcript outline/search, and a truthful About surface.
- The reviewed BlueMinutes logo and application icon supplied for this
  pre-Beta round, with deterministic hash-bound asset generation.

### Changed

- Advanced the local application and Codex client identity to version `0.4.0`
  (build `4`) while retaining compatibility-sensitive executable, bundle,
  database, CLI, MCP, protocol, and serialized identifiers.
- Reused the existing native components and visual language for every new
  surface. The separately gated U1 visual redesign remains unstarted.
- Made missing or disabled STT resolve honestly to Record Only; provider repair
  suggestions never activate a different data route or cost owner silently.

### Fixed

- Closing the main window no longer discards an active recording session;
  supported reopen, stop, quit, retained-track, and restart-recovery states are
  explicit.
- Transcript outline and bounded search preserve stable selection and evidence
  references across long documents.
- Fixed application logs use content-free event codes, and copied diagnostics
  fail closed against meeting content, credentials, URLs, and filesystem paths.
- Persistence test workspaces now receive per-run identities so an interrupted
  test cannot leak prior active-revision pointers into a later run.
- Failed workspace candidates no longer revoke the active workspace scope or
  replace its restorable bookmark before recovery succeeds.
- Persisted queued work no longer replays or strands transient source,
  capture, or outbound authority after restart.

### Security and privacy

- Sensitive Meetings and no-outbound policy reject Codex, remote STT, remote
  BYOK text, external research, and cloud fallback in the central resolver.
- Codex remains text-only, receives no audio or arbitrary path, and runs in an
  isolated app-owned home with shell, file-change, web, Apps, plugins, MCP,
  memory, multi-agent, and permission-escalation surfaces disabled.
- Codex history persistence is disabled; disconnect waits for any in-flight
  connection, requires confirmed process exit, and fails closed until private
  runtime state is purged.
- BYOK secret bytes remain in macOS Keychain. Codex subscription credentials
  remain under the official runtime's control.
- Remote-STT authorization is in-memory, exact-job/plan scoped, expires before
  first processing, is revalidated against current policy before every chunk,
  and cannot be reused by retry or restart.
- Billing/licensing stays disabled, the website handoff stays disconnected,
  and updates stay unconfigured with no production service endpoint.

### Compatibility

- SQLite remains at schema v10, GRDB remains pinned at 7.11.1, and no package
  dependency or migration is included.
- macOS 15 remains the declared minimum, while the implemented Apple Speech
  route requires macOS 26 and installed local assets; that support-policy gap
  remains a formal-test decision.

### Candidate scope

- `BlueMinutes-0.4.0-development` is an ad-hoc, Hardened Runtime local package
  for formal testing on the build Mac only.
- This task does not create a `v0.4.0` tag or GitHub Release, attach a binary,
  merge the Pull Request, deploy the website, notarize, install, or authorize
  public distribution. The latest public source Release remains `v0.3.0`.

## [0.3.0] - 2026-07-28

Native Editorial Dossier and local development-package foundation.

### Added

- A unified native Editorial Dossier shell for local media, visible recording,
  bounded UN Web TV metadata, Transcript, Analysis, Briefing, Meeting History,
  learned preferences, and Storage review.
- Native Settings, exact state ownership, keyboard/focus routing, inspector
  presentation, and accessibility contracts across the migrated surfaces.
- A pinned 50-case native visual baseline with zero-tolerance regression
  comparison and same-runner calibration evidence.
- A coherent local development package containing `BlueMinutes.app`, a
  versioned ZIP, checksum, full tracked-source inventory, and schema-v2
  source/build manifest.

### Changed

- Promoted the BlueMinutes application bundle to version `0.3.0` (build `3`)
  while retaining compatibility-sensitive internal identifiers.
- The release packager now requires a clean complete repository and binds the
  package to its exact Git head, tree, optional annotated tag, source inventory,
  dependency lockfile, toolchain, app digest, archive digest, and signature
  classification.
- The verifier now has explicit `development` and `distribution` modes.
  Development accepts the reviewed local signing boundary; distribution
  continues to require Developer ID, timestamp, notarization/stapling,
  Gatekeeper, and distribution-policy proof.

### Fixed

- Workspace-scoped asynchronous review state can no longer commit stale
  results into a replacement workspace.
- Historical search, pagination, learned-preference, and Storage presentation
  failures retain their exact accepted-state and retry boundaries.
- Intake preflight failures are resolved before persistence or job enqueue, and
  file-import cancellation does not steal editor focus.

### Security and privacy

- Meeting data remains local by default. This release adds no provider, model,
  credential flow, telemetry destination, remote control, or network route.
- Actual-app evidence used a fresh synthetic local WAV and verified private
  workspace file modes; no real meeting or user material enters the repository
  or package.

### Compatibility

- SQLite remains at schema v10, GRDB remains pinned at 7.11.1, and no migration
  or dependency change is included.
- `MeetingBuddyApp`, `com.meetingbuddy.desktop`, Swift target, database, CLI,
  MCP, protocol, and serialized compatibility identifiers remain unchanged.

### Release scope

- The GitHub `v0.3.0` Release is source-only with zero uploaded assets.
- The ad-hoc `BlueMinutes-0.3.0-development` app/ZIP stays in the ignored local
  `dist/` directory for testing on the build Mac. It is not notarized,
  installed, uploaded, or authorized for public binary distribution.

## [0.2.0] - 2026-07-23

Source-only compatibility and safety foundation for future Meeting / Research
work.

### Added

- Provider-neutral, versioned contracts for logical Research workspaces,
  shared-source references, exact-version artifacts, citation associations,
  append-only Conversation histories, instruction profiles and snapshots, and
  transcript-source discovery and resolution.
- Read-only adapters that project existing Meeting sources, briefings,
  historical comparisons, and evidence without replacing their authoritative
  revisions.
- An immutable, composition-owned capability snapshot whose four Research
  integration capabilities are all disabled by default.

### Changed

- Reorganized CI so resource-bound coverage and historical-scale checks run
  once in isolated or focused steps; product behavior and validation thresholds
  are unchanged.

### Fixed

- Retried bounded cancellation transitions when concurrent checkpoint
  persistence advances the optimistic record version, while preserving
  temporary-data cleanup and propagating unrelated repository failures.

### Security

- The new transcript-source contract rejects external primary or authoritative
  selections whenever application policy denies external source use.
- Canonical-audio coverage eligibility requires exact source binding,
  application-owned proof, and zero-based, contiguous, gap-free,
  chronological, non-overlapping timing.
- Conversation histories remain bound to one logical Meeting identity or one
  Research workspace identity while exact revision references may evolve
  within that identity.

### Compatibility

- SQLite schema remains v10. This release adds no visible Research surface,
  connector, external provider, persistence, migration, backfill, dependency,
  entitlement, CLI command, MCP tool, network destination, user-data behavior,
  or file-layout change.
- Existing Meeting workflows remain unchanged with the default capability
  snapshot.
- The GitHub source version advances independently of the separately gated
  `0.1.0` internal-alpha application-bundle metadata and packaging evidence.

### Release scope

- Distribution is source code only. No app bundle, installer, archive, signing
  material, or other binary asset is attached.
- A Developer ID signed and notarized macOS download remains a separate future
  distribution milestone.

## [0.1.0] - 2026-07-22

First public source release.

### Added

- The maintainer-selected BlueMinutes public brand, horizontal project lockup,
  and text-free macOS application icon, while retaining internal MeetingBuddy
  compatibility identifiers.
- Apache License 2.0, contribution and security policies, maintenance and
  recovery documentation, GitHub templates, and conservative CI metadata.
- Explicit human confirmation for the exact analysis ledger before briefing,
  position correction, or other consequential downstream use.
- Explicit confirmation of every briefing section before Markdown export.
- Application-owned exact-digital-silence verification for `noSpeech` coverage.
- Application-owned closed-marker verification, exact transcript and optional
  translation text digests, and a safe reason code for `nonSubstantive`
  analysis omissions.
- A public-facing README introduction explaining the project's firsthand
  diplomatic motivation, solo-maintainer scope, and review-first workflow.
- Public release notes and a documented Semantic Versioning and changelog
  cadence for future substantial milestones.

### Changed

- Standardized reader-facing documentation on the BlueMinutes name and moved
  legacy `MeetingBuddy` identifiers into clearly labeled compatibility and
  developer-command contexts.
- Replaced the prominent internal-status warning with precise source-release,
  distribution, and human-review boundaries in the sections where readers need
  them.

### Security

- Closed the four medium evidence-integrity findings recorded in the Task 011
  security scan. Provider-only classifications and structurally valid text no
  longer authorize omission or consequential publication by themselves.
- Added focused fail-closed regression tests and production verifier tests.

### Release scope

- Published `v0.1.0` as a source release from protected `main`.
- No app bundle, installer, archive, signing material, or other binary asset is
  attached. Signed and notarized macOS distribution remains a separate future
  milestone.

## [0.1.0-internal-alpha] - 2026-07-21

Internal validation milestone only; no Git tag or GitHub Release was created.

### Added

- Native macOS modular-monolith foundation.
- Local media intake, recording, canonical audio, transcription, translation,
  analysis, briefing, historical review, local automation, and recovery flows.
- Immutable semantic revisions, exact evidence traceability, deterministic
  coverage ledgers, synthetic Golden Tests, and migration tests through schema
  version 10.

### Known limitations

- No Developer ID signature, notarization, clean-machine distribution proof,
  final distribution icon review, or localization package.
- Installed Apple-model tests remain opt-in and synthetic-only.
- The internal alpha is not authorized for public binary distribution.

[Unreleased]: https://github.com/crescentln/BlueMinutes/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/crescentln/BlueMinutes/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/crescentln/BlueMinutes/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/crescentln/BlueMinutes/releases/tag/v0.1.0
