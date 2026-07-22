# BlueMinutes v0.1.0 — First Public Source Release

- Released: 2026-07-22
- Tag: `v0.1.0`
- Distribution scope: source code only

## Why BlueMinutes

BlueMinutes grew from firsthand experience with the time pressure of UN
conferences and multilateral meetings. It brings local transcription,
translation, evidence-linked position analysis, human review, briefing
preparation, and qualified meeting history into one native macOS workflow.

## Highlights

- Local-first native macOS application built with Swift 6 and SwiftUI.
- Local media intake and visible audio capture with managed storage,
  deterministic canonical audio, checkpoints, retry, and recovery.
- Apple on-device transcription, translation, diplomatic analysis, and
  briefing routes, with explicit review and confirmation boundaries.
- Typed provenance, immutable revisions, exact evidence links, complete source
  accounting, and fail-closed publication gates.
- Independent briefing sections, Markdown export, qualified historical review,
  and visible learned preferences.
- A typed local CLI and a local stdio MCP server with seven bounded read tools;
  no HTTP listener or remote-control surface.
- Apache License 2.0, public contribution and security policies, protected
  `main`, and a synthetic-safe CI suite.

See [CHANGELOG.md](../CHANGELOG.md) for the detailed version history and
[README.md](../README.md) for build and usage instructions.

## Source-release boundary

This GitHub Release identifies the first reviewed public source version.
GitHub provides the standard source archives automatically; no BlueMinutes app
bundle, installer, maintainer-built application ZIP, signing material, or other
binary asset is attached.

Developers and early evaluators can build and run BlueMinutes locally by
following the README. A Developer ID signed, notarized, and clean-machine-tested
app download remains a separate future distribution milestone.

## Compatibility naming

BlueMinutes is the public project and product name. Some internal Swift targets,
executables, bundle and database identifiers, protocol names, and persistent
formats retain the legacy `MeetingBuddy` identifier to preserve compatibility.
Exact legacy command names in the README are intentional implementation
identifiers, not a second brand.

## Known limitations

- Apple Silicon is the currently validated architecture.
- Automatic Apple transcription, translation, analysis, and briefing require
  macOS 26, supported hardware and locales, and installed model assets.
- Briefing currently provides one multilateral template and three sections.
- Historical retrieval is conservative lexical and exact-identity search.
- UN Web TV support is metadata-only; no media acquisition is implemented.
- Native capture remains subject to the intended-OS and physical-device proof
  gaps documented in the repository.
- BlueMinutes supports evidence-linked drafting and review; users must validate
  consequential output against source material and applicable processes.

## Privacy

Meeting content remains local by default. There is no outbound inference
provider, cloud synchronization, remote MCP, HTTP API, telemetry service, or
remote-control path in this version. The only implemented network route is an
explicit, bounded metadata request to an exact `webtv.un.org` asset page, and
offline/no-outbound mode disables it.
