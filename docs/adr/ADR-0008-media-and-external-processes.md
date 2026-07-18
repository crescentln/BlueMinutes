# ADR-0008: Media Tooling and External Processes

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 005A

## Context

MeetingBuddy must process long local audio/video while preserving source
provenance and a canonical timeline. Third-party media and model executables
may add format support but increase binary size, licensing, sandbox, signing,
update, and security complexity.

## Decision

- Prefer AVFoundation and other approved Apple APIs for media inspection,
  extraction, normalization, timing, and playback.
- Process long media in stable bounded chunks without loading the entire file
  into memory.
- Preserve the original source and one canonical timeline; user source files
  are never modified.
- Track missing, corrupt, or failed ranges and resume from verified
  checkpoints.
- Temporary chunks are job-owned, rebuildable, bounded, and cleaned according
  to storage policy.
- No external media or model executable is approved by Task 002.
- Any future executable requires a dependency/ADR review and a narrow adapter
  with explicit path, argument arrays, bounded directory/output, timeout,
  cancellation, version validation, signing/quarantine checks, and redacted
  diagnostics.
- User-controlled or source-derived values never enter shell interpolation.

## Consequences

- Task 005A begins with an AVFoundation-only proof using licensed or synthetic
  fixtures.
- Canonical audio representation, timestamp tolerance, chunk duration/overlap,
  and approved formats must be fixed in the Task 005A plan and tests.
- FFmpeg or another external tool cannot be added merely for exploratory
  convenience.
