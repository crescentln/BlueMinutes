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

- The approved Task 005A local formats are MOV, MP4, M4A, MP3, and WAV. The
  filename extension selects the candidate format and AVFoundation must still
  confirm a positive duration and at least one readable audio track.
- One audio track is processed. A single track may be selected automatically;
  multiple tracks require an explicit user selection. Track count, language,
  or channel metadata never infers original speech, interpretation, or
  translated-audio provenance; the user records that choice separately.
- Product media inspection and conversion use `AVURLAsset`, `AVAssetReader`,
  `AVAssetWriter`, Core Media, and AudioToolbox. Product code does not use an
  export preset or external executable.
- Canonical audio v1 is CAF containing signed 16-bit little-endian interleaved
  linear PCM, mono, at exactly 16,000 Hz. Its stable identifier is
  `meetingbuddy.canonical-audio.v1` and codec label is `lpcm_s16le`.
- The canonical timeline is zero-based, uses half-open integer frame ranges at
  16 kHz, and remains anchored to source-asset time zero. Timestamp gaps are
  not collapsed. Missing, corrupt, and decode-failed ranges retain exact
  half-open frame coordinates and bounded safe summaries.
- Source-asset duration is the expected canonical timeline. Canonical output
  may differ by at most 800 frames, equal to 50 ms at 16 kHz; a shorter result
  records the exact trailing missing range. A larger difference fails before
  publication.
- Each deterministic chunk has a 480,000-frame (30-second) core and up to
  16,000 frames (one second) of physical context on each side. Adjacent
  interior physical chunks therefore overlap by two seconds; edge and final
  ranges clamp exactly to the canonical timeline.
- Long operations stream data and use the one Task Manager. Local source
  authority is process-local and absent from durable job payloads. A cancelled
  intake removes its partial staging copy, and an interrupted intake requires
  source reselection.
- The untouched managed original and the generated canonical CAF are persistent
  hash-bound `SourceAsset.v1` revisions. Canonical audio has one explicit
  generated owner/lifecycle. Chunks are job-owned, rebuildable task artifacts;
  verified chunks remain only for an eligible checkpoint retry and are cleaned
  after success, cancellation, or a non-retained failure.
- Processing resumes only from hash- and size-reverified canonical/chunk
  descriptors. Completed chunks are not regenerated unnecessarily.
- Downstream transcription owns each core range exactly once. Physical context
  overlap is bounded and documented, never counted as additional source
  coverage. A coverage manifest records every core range as transcribed,
  verified no-speech, missing, failed, or retried and must prove a 100 percent
  eligible-range union before transcript publication.
- No external media or model executable is approved.
- Any future executable requires a dependency/ADR review and a narrow adapter
  with explicit path, argument arrays, bounded directory/output, timeout,
  cancellation, version validation, signing/quarantine checks, and redacted
  diagnostics.
- User-controlled or source-derived values never enter shell interpolation.

## Consequences

- Task 005A uses project-authored synthetic fixtures, including native fixtures
  for all five formats, and tests canonical format, duration tolerance,
  deterministic ranges, three-hour checkpoint size, cancellation, retry, and
  cleanup.
- Downstream transcription must use exact core/physical mappings and must not
  infer that a missing range contains silence or speech.
- Accepted Tasks 006A/006B carry exact source segment IDs through hierarchical
  processing and fail when complete segment coverage cannot be proven.
- Task 011 additionally fails canonical planning above the tested three-hour
  release bound, caps audio-track enumeration at 32, and enforces the inspected
  byte ceiling inside streamed managed intake before a crossing write.
- FFmpeg or another external tool cannot be added merely for exploratory
  convenience.
