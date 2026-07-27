# Slice I Actual-App Accessibility Evidence

Status: Current exact-source import/AX evidence with bounded earlier unchanged
Transcript interaction; manual system-integration boundary remains
Date: 2026-07-27
Application: staged `dist/MeetingBuddy.app`

## Environment and boundary

- macOS 26.5.2 (25F84) on Apple M4 arm64, Xcode 26.6 (17F113), and
  Apple Swift 6.3.3.
- Application source revision:
  `90fc6c6911bed80d2c0e3ddd222a92dbc1d3e8a1`.
- Staged executable SHA-256:
  `399596f84c93783c6ce3d1fd7589ab14462d3c88cb795964fedcde4d0587ffaf`.
- The arm64 application used ad-hoc signing. `codesign --verify --deep
  --strict` passed; this record does not claim Developer ID signing,
  notarization, or distribution authorization.
- The run used a temporary private workspace and a generated two-second,
  mono, 48 kHz WAV containing only a 440 Hz tone. Its SHA-256 was
  `aac5dc69dd34403e505f80abf52836101dc986195d45f8d8db34e84e0048d0c7`.
- No real meeting content, credentials, provider or model access, outbound
  processing route, or new TCC permission was used.
- This is hands-on actual-application evidence. Native host-view goldens and
  automated AX tests are separate gates and are not substituted for this run.

## Results

### Runtime accessibility tree

- The actual-app AX tree exposed one `SidebarNavigationSplitView`, contained
  110 nodes without an accessibility cycle, and preserved this sidebar order:
  Workspace, Synthetic Workspace, Choose Workspace, Workflow, Local Media,
  Record Audio, UN Web TV Metadata, Transcript Review, Analysis Review,
  Briefing, Library, Meeting History, and Storage.
- Sidebar destinations exposed distinct labels and selection state. The
  workspace toolbar controls exposed `Hide Sidebar` and the current-workspace
  menu with separate descriptions.
- The main window was observed at approximately 863 by 652 points. The
  sidebar, selected destination, editorial canvas, setup fields, and primary
  actions remained represented in the ordered AX hierarchy at that size.

### Import focus and local processing

- With the language field focused and set to `en`, Command-O opened the native
  file importer. Cancelling with Escape restored AX focus to that same field
  with its `en` value intact.
- Importing the generated WAV copied and hash-verified the managed object.
  The staged app then reported `Succeeded`, `3 of 3 verified stages`,
  `chunk-0`, and `local_only`.
- Two independent empty workspaces on the preceding `b86264d` executable
  completed that same import:
  one retained the domain-supported `unknown` speech provenance and one
  explicitly selected `original speaker audio`. This confirms that the latter
  was not required merely to make the writer succeed.
- After the pre-persistence hardening described below, a third empty workspace
  on the current exact-source executable completed with `unknown` provenance
  and the same managed-source, canonical-audio, and `local_only` success proof.
- Every observed SQLite database, WAL/SHM file, task log, managed WAV, and
  canonical CAF was mode `0600`. Both successful workspaces contained exactly
  two succeeded jobs (`media-local-intake-v1` and
  `media-canonical-audio-v1`), two completed managed-asset import operations,
  and two registered managed assets.
- An earlier source-row selection attempt in a separate empty workspace
  returned the generic pre-intake failure before creating a job, managed asset,
  or managed-asset operation, but it had already inserted the meeting and its
  two security-policy revisions. It was not counted as success evidence. The
  same input then succeeded through three exact-path selections, including
  twice with `unknown` provenance. The isolated selection failure was not
  reproduced or assigned an unproved product cause.
- The current implementation constructs the meeting and security policy,
  validates the selected track and source byte size, constructs the intake plan
  and request, and registers the reversible process-local source capability
  before its first persistent write. A source-order contract test prevents a
  future preflight regression from reintroducing the observed orphaned
  pre-task metadata sequence.
- The earlier exact-app processing run exposed an
  `AVAssetWriter.startWriting()` failure when the Task Manager had already
  created a zero-byte, mode-0600 writer lease. The implementation now removes
  only a verified ordinary, non-symlink, zero-byte lease immediately before
  creating the writer, then verifies an ordinary non-symlink mode-0600
  destination before starting the media session or appending samples.
  Non-empty destinations still fail closed. The current staged executable
  produced the two successful results above.

### Transcript keyboard and evidence surface

- The hands-on transcript sequence below was captured on source
  `31bd311b27a13444fa778abc75f5df47c9bbb5b2`, executable SHA-256
  `503e15f89c6d86f2ab0d3276e80f1a937e8b405d079e87bfd8af4d9d8cb9d712`.
  The exact diff from that source to the current executable changes only
  Analysis coverage presentation, AVFoundation writer validation, local-media
  pre-persistence ordering, their regression tests, the visual fixture catalog,
  and this audit; it does not change the Transcript view, scene state, or
  focused-command implementation.
- Keyboard traversal reached the source-language field, target-language
  field, and manual transcript text area in order. The text area accepted
  `Synthetic 440 hertz tone no speech.` through the real app.
- The complete-timeline-coverage checkbox changed from unchecked to checked,
  which enabled `Publish Manual Transcript`. Publishing created one
  human-correction, human-confirmed segment covering the two-second source.
- Command-Option-I opened the transcript evidence inspector. Native AX exposed:
  - label: `Transcript evidence inspector`;
  - identifier: `BlueMinutes.Transcript.EvidenceInspector`;
  - value: `Exact source, coverage, and evidence for the selected transcript
    segment`.
- Pressing Command-Option-I again removed that AX element and restored the
  toggle value to `Closed`.
- On the single-segment transcript, the Transcript menu correctly exposed
  Previous Segment, Next Segment, and Save Focused Transcript Draft as
  disabled, while Toggle Evidence Inspector remained enabled.
- A current-executable repeat reached a fresh succeeded canonical-audio state,
  but the desktop-control bridge closed while reading the Transcript
  destination transition. BlueMinutes stayed running and its succeeded
  workspace files remained intact. This audit therefore does not relabel the
  earlier transcript interaction as a new exact-current-build hands-on run;
  exact-current production-view AX and command behavior remains covered by the
  deterministic runtime AX suite.

## System-owned accessibility settings

- Before and after this run, VoiceOver was off. Reduce Transparency,
  Differentiate Without Color, and Reduce Motion remained at their original
  false or unset values; this run did not change those settings.
- The desktop-control bridge terminated while reading the complex System
  Settings Display accessibility page. BlueMinutes remained healthy and its
  native AX tree remained readable. Because a reliable toggle-and-restore
  cycle was not available, this record does not claim hands-on passes for
  those three system-owned settings.
- Automated fixtures separately exercise Increase Contrast, larger text, and
  the application-owned non-color-only and reduced-environment contracts.
  Those fixtures do not impersonate system-owned settings.

## Residual manual boundary

Exact spoken VoiceOver announcement wording and live toggle-and-restore checks
for Reduce Transparency, Differentiate Without Color, and Reduce Motion remain
manual system-integration observations. They are not represented as captured
golden pixels or as completed by the deterministic application-owned gate.
