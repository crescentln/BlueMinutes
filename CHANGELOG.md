# Changelog

All notable project changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable.

## [Unreleased]

No notable changes yet.

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

[Unreleased]: https://github.com/crescentln/BlueMinutes/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/crescentln/BlueMinutes/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/crescentln/BlueMinutes/releases/tag/v0.1.0
