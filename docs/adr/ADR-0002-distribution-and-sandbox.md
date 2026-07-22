# ADR-0002: Distribution and Sandbox Boundary

Status: Accepted
Date: 2026-07-18
Decision owners: User and Codex
Applies from: Task 005A

## Context

MeetingBuddy will need user-selected file access, downloaded local models,
microphone and application-audio permissions, and possibly approved external
executables. These requirements affect Mac App Store eligibility, sandboxing,
bookmarks, signing, updates, and support burden.

Task 005A needs a native application target and a precise authority boundary
for a persistent workspace and transient user-selected sources. The initial
choice must avoid granting future capture, provider, updater, executable, or
telemetry authority merely to make local media intake work.

## Decision: Option A

- The initial distribution direction is an independently distributed,
  Developer ID-signed and notarized macOS application. The accepted Task 011
  audit does not satisfy that direction: the current INTERNAL ALPHA is ad-hoc
  signed and still lacks Developer ID/Team ID, notarization, Gatekeeper,
  clean-machine, and rollback evidence required for distribution.
- The application uses App Sandbox.
- A user-selected MeetingBuddy workspace receives read/write authority. The app
  may persist exactly one app-scoped security-scoped bookmark for that selected
  workspace and releases/replaces it when the workspace changes or fails
  validation.
- A user-selected source file receives only transient read authority. The
  security scope remains active through the Task-Manager-owned streamed copy,
  SHA-256 verification, and managed-source registration, then is released. The
  source URL and source bookmark are not persisted in jobs, checkpoints,
  metadata, logs, or preferences.
- Product media processing uses approved Apple frameworks. No external media
  or model executable is approved.
- Updates are manual for the initial implementation. No automatic updater is
  approved.
- Telemetry and third-party crash reporting remain disabled.
- Any future telemetry is opt-in, fully disableable, compatible with no-
  outbound-network mode, and excludes meeting/transcript/document/derived
  content, credentials, meeting titles, filenames, sensitive paths, and
  identifiable meeting metadata. Organization-controlled or self-hosted
  telemetry requires a later accepted ADR.
- No network-client, microphone, screen-recording, or application-audio capture
  entitlement is approved by Task 005A.
- Task 008B later adds only audio input and network client authority for visible
  audio-only capture and exact-host UN Web TV metadata. Screen recording,
  arbitrary-host networking, automatic media acquisition, and hidden capture
  remain unapproved.
- Domain, application, media, and feature contracts remain independent of
  signing identities and distribution mechanics.

## Development and release evidence

Xcode 26.6 build 17F113 can build the SwiftPM executable, stage a standard
`.app` bundle, apply an ad-hoc signature carrying only the approved sandbox
entitlements, validate that signature, and launch the process. A native run
observed App Sandbox initialization, presented the workspace Open panel,
persisted exactly one app-scoped bookmark for a synthetic workspace, and
restored scoped authority after relaunch. The single purpose-routed importer is
regression-tested for both workspace and approved-media content types.

Task 011 extends this only to verified local internal-alpha evidence: one arm64
bundle with ad-hoc Hardened Runtime, the exact five accepted entitlements,
closed layout, privacy/license resources, coherent hash-bound archive, and a
bounded local launch. It is not Developer ID, provisioning, notarization,
Gatekeeper, or clean-machine distribution evidence and does not justify
weakening the sandbox or adding a broader entitlement.

## Consequences

- The initial app can retain access to its workspace across launches without
  retaining arbitrary source-file authority.
- A source must be selected again after a launch-interrupted intake because its
  authority is deliberately not durable.
- Mac App Store distribution, automatic updates, additional capture
  permissions, external executables, telemetry destinations, and crash-report
  vendors require later explicit ADRs and task authorization if proposed.
- The user accepted Task 005A after the full-Xcode native gate passed.
- Task 011 audited signing and update boundaries but found no valid signing
  identity, Team ID, notarization ticket, affirmative Gatekeeper distribution
  result, clean-machine proof, or approved updater. No publication or
  distribution authority follows from the accepted internal-alpha audit.
