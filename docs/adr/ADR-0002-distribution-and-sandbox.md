# ADR-0002: Distribution and Sandbox Boundary

Status: Proposed
Date: 2026-07-17
Decision owners: User and Codex
Must be resolved before: Task 005A implementation

## Context

MeetingBuddy will need user-selected file access, downloaded local models,
microphone and application-audio permissions, and possibly approved external
executables. These requirements affect Mac App Store eligibility, sandboxing,
bookmarks, signing, updates, and support burden.

The greenfield repository contains no entitlement or distribution evidence.
Task 002 must not manufacture a final choice without implementation and user-
hardware evidence.

## Proposed direction

- Keep domain and application services independent of distribution mechanics.
- Design file access around user intent and security-scoped access rather than
  unrestricted path assumptions.
- Treat independent Developer ID distribution and Mac App Store distribution
  as explicit alternatives until media/provider requirements are validated.
- Keep the app sandbox-compatible where practical, but do not claim a final
  sandbox policy yet.
- Do not approve telemetry, automatic updates, or an external executable in
  this ADR.

## Decision required later

Before Task 005A implementation, select:

1. initial distribution channel;
2. sandbox and security-scoped bookmark policy;
3. external executable allowance, if any;
4. update and crash-reporting path;
5. required microphone, file, and application-audio entitlements.

## Consequences of deferral

Tasks 003A through 004B may proceed because they do not need product file
permissions or distribution entitlements. Task 005A must not finalize media
file ownership or an app target without this decision.
