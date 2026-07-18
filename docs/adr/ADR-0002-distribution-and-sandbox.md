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
  Developer ID-signed and notarized macOS application. A release still requires
  its separately authorized Task 011 signing, notarization, clean-machine, and
  rollback gates.
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
- No network-client, microphone, screen-recording, or application-audio capture
  entitlement is approved by Task 005A.
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

This is local development evidence only; it is not Developer ID, provisioning,
notarization, Gatekeeper, or clean-machine distribution evidence. Those release
gates remain separately authorized Task 011 work and do not justify weakening
the sandbox or adding a broader file entitlement.

## Consequences

- The initial app can retain access to its workspace across launches without
  retaining arbitrary source-file authority.
- A source must be selected again after a launch-interrupted intake because its
  authority is deliberately not durable.
- Mac App Store distribution, automatic updates, capture permissions, external
  executables, telemetry, and crash-report vendors require later explicit ADRs
  and task authorization if proposed.
- The user accepted Task 005A after the full-Xcode native gate passed.
