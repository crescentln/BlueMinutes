# Changelog

All notable project changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable.

## [Unreleased]

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

### Security

- Closed the four medium evidence-integrity findings recorded in the Task 011
  security scan. Provider-only classifications and structurally valid text no
  longer authorize omission or consequential publication by themselves.
- Added focused fail-closed regression tests and production verifier tests.

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
