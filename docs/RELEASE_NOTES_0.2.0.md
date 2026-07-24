# BlueMinutes v0.2.0 — Default-Off Meeting / Research Foundation

- Released: 2026-07-23
- Tag: `v0.2.0`
- Distribution scope: source code only

BlueMinutes v0.2.0 is a source-only developer milestone. It adds contract,
compatibility, and fail-closed validation foundations for possible future
Meeting / Research workflows while deliberately leaving every Research
capability disabled.

## Highlights

- Provider-neutral, versioned identities and contracts for logical Research
  workspaces, shared-source references, exact-version artifacts, citation
  associations, append-only Conversation histories, structured instruction
  profiles and snapshots, and transcript-source discovery and resolution.
- Read-only compatibility adapters preserve the exact authoritative Meeting
  source, briefing, historical-comparison, and evidence revisions.
- Transcript-source resolution rejects disallowed external selections and
  requires application-owned, exact-source proof before text can qualify for
  canonical-audio coverage.
- Timed transcript-source segments must be zero-based, contiguous,
  chronological, gap-free, and non-overlapping; an untimed segment cannot hide
  overlap between surrounding timed segments.
- Conversation histories remain bound to one logical Meeting identity or one
  Research workspace identity while exact revision references may evolve
  within that identity.
- A composition-owned capability snapshot keeps `research`,
  `transcriptSourceResolution`, `sharedObjectStore`, and
  `conversationPersistence` disabled by default.
- Resource-bound coverage and historical-scale tests are isolated in CI so
  their validation thresholds are exercised once without changing product
  behavior.
- Task cancellation re-reads and retries bounded optimistic-lock conflicts
  caused by concurrent checkpoint persistence; unrelated repository failures
  still surface and job-owned temporary data is still cleaned.

## What this release does not add

This release does not add a Research navigation item or interface, Conversation
or Chat interface, external transcript connector, Codex/OpenAI or other
external model provider, credential or login flow, persistent Research data,
database migration, backfill, second data root, new task executor, CLI command,
MCP tool, entitlement, network destination, or changed Meeting workflow.

SQLite remains at schema v10. GRDB 7.11.1 remains the only external package
dependency. Existing user workspaces, semantic payloads, managed files, and
compatibility identifiers are unchanged.

## Source-release boundary

GitHub provides the standard source archives automatically. No BlueMinutes app
bundle, installer, maintainer-built archive, signing material, or other binary
asset is attached.

The `v0.2.0` tag identifies the reviewed source tree. The development app bundle
retains its separately gated `0.1.0` internal-alpha version and packaging
evidence. Advancing that bundle, signing it with Developer ID, notarizing it,
and proving clean-machine installation remain a separate future distribution
milestone.

Developers and early evaluators can build and stage BlueMinutes locally by
following the README. The default launch path and visible Meeting workflow are
unchanged from the preceding public source release.

## Privacy and security

Meeting content remains local by default. No new provider, connector, network
route, telemetry service, remote MCP, HTTP API, cloud synchronization, or
remote-control path is introduced.

The contract foundation fails closed when external transcript use is denied,
source identity or content binding is incomplete, canonical-audio alignment is
unproved, timing is incomplete or contradictory, or a Conversation crosses its
logical Meeting or Research workspace boundary.

## Compatibility naming

BlueMinutes remains the public project and product name. Compatibility-sensitive
Swift targets, executables, bundle and database identifiers, protocol names,
commands, and persistent formats continue to use the legacy `MeetingBuddy`
identifier.

## Known limitations

- Every Meeting / Research integration capability added in this release is
  disabled by default and has no visible product surface.
- Apple Silicon is the currently validated architecture.
- Automatic Apple transcription, translation, analysis, and briefing require
  macOS 26, supported hardware and locales, and installed model assets.
- Briefing currently provides one multilateral template and three sections.
- Historical retrieval remains conservative lexical and exact-identity search.
- UN Web TV support remains metadata-only; no media acquisition is
  implemented.
- Native capture still has the intended-OS and physical-device proof gaps
  documented in the repository.
- BlueMinutes supports evidence-linked drafting and review; users must validate
  consequential output against source material and applicable processes.

See [CHANGELOG.md](../CHANGELOG.md) for the detailed version history and
[README.md](../README.md) for build and usage instructions.
