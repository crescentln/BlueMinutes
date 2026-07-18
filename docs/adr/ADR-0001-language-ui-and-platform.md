# ADR-0001: Language, UI, and Initial Platform Baseline

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 003A

## Context

MeetingBuddy is a greenfield professional macOS application. Its media,
permission, accessibility, file-access, and long-form review requirements favor
native platform APIs. No legacy code constrains the language or UI stack.

## Decision

- Use Swift 6 language mode for production code.
- Use SwiftUI for primary application structure and AppKit bridges only where
  required for native macOS behavior.
- Use Xcode and Swift Package Manager; do not introduce another package manager
  without a new dependency decision.
- Build a modular monolith and create modules only as authorized tasks need
  them.
- Use a narrow `MeetingBuddyApplication` module to own use-case APIs and the
  ports implemented by persistence, task, media, and inference adapters.
- Use `MeetingBuddyApp` as the sole composition root that wires concrete
  adapters without exposing them to features or automation.
- Use macOS 15 or later and Apple Silicon as the initial implementation and
  test baseline.
- Do not ship a Python, Node.js, Electron, Tauri, or browser-shell runtime.
- Permit Rust/C/C++ only behind a narrow, separately reviewed adapter when a
  mature native or model library makes it necessary.

## Consequences

- Task 003A can create a Swift package/domain module without a language
  migration.
- `MeetingBuddyApplication` is created only when an authorized task first needs
  application orchestration or adapter ports; Task 003A remains domain-only.
- A native app target is introduced only when its owning task needs it; Task
  002 does not create an empty target.
- Release compatibility beyond the initial baseline requires evidence from
  actual user hardware, capture APIs, model support, and distribution testing.
- Accessibility, keyboard navigation, permissions, signing, and notarization
  remain native macOS responsibilities.

## Open follow-up

Before a release scope is fixed, validate the deployment target against actual
supported user hardware and the approved distribution/capture design. This
does not block Task 003A.
