# UI Functional Structure and Deferred Visual Backlog

## Current regression baseline

`ui-current-baseline/` contains 50 byte-identical PNG copies of the accepted
visual regression goldens plus their manifest. Coverage includes:

- shell at 860×600, 1080×720, 1440×1024, and 1728×1024;
- Light and Dark appearances;
- onboarding, media, recording, UN metadata, transcript, analysis, briefing,
  history, storage, and settings;
- ready, working, selected, stale, blocked, empty, destructive-disabled, and
  failure states.

The canonical executable fixtures remain under
`Tests/MeetingBuddyFeaturesTests/VisualRegression/`. The audit copy is evidence,
not a second source of test truth.

## Existing design to preserve

- native `NavigationSplitView`, `List`, `TabView`, `Form`, `Section`, toolbar,
  inspector, confirmation, and alert patterns;
- Editorial Dossier canvas and evidence-oriented information hierarchy;
- `BlueMinutesColors`, `BlueMinutesLayout`, and semantic icon roles;
- deterministic state text rather than color-only status;
- stable accessibility identifiers and keyboard commands;
- compact/standard density and reading-width preferences.

## Current P0/P1 functional UI status

1. Intelligence now has four ordered Codex, STT, BYOK, and Task Routing
   sections with explicit route, destination, cost owner, readiness, and repair
   controls.
2. Closing the main window leaves the app-owned recording session active. The
   menu-bar item can reopen the meeting or stop and finalize it; true Quit
   retains the existing stop/finalize failure guard.
3. Record-only, unavailable local STT, installed Apple STT, and authorized
   OpenAI remote STT are distinct visible states.
4. Transcript Review now has deterministic five-minute outline anchors plus
   bounded text, translation, speaker, and timestamp search while preserving
   exact selection.
5. Codex Assistant shows runtime/account/quota state and supports selected-text
   authorization, streaming, stop, retry, and isolated thread reset.
6. Start a New Meeting is a lightweight coordinator over the existing import,
   recording, and UN metadata pages. It intentionally does not duplicate their
   exact policy forms.
7. The About window shows the supplied icon, version, unlocked Beta state,
   disconnected website handoff, honest unconfigured updater state, and an
   explicit Copy Sanitized Diagnostics action.
8. The CI-shaped current-tree gate passes 12 isolated native-window tests and
   the 11-test visual-contract shard. A staged-app smoke also verified the
   About surface and close/reopen menu lifecycle. New-control Light/Dark,
   860×600, keyboard, spoken VoiceOver, overflow, resize, and real-device
   performance evidence remains open.

## UI performance comparison status

The current branch adds runtime SwiftUI surfaces and bounded model tests, but a
before/after Instruments, main-thread-hang, hitch, resize, scroll, CPU, and
stable-memory comparison is **not yet run** and must not be inferred from source
assertions or visual fixtures. Intelligence, routing, active-meeting,
outline/search, and Assistant still need the real-app performance and
accessibility matrix before public Beta distribution.

## Integration rules

- Add one Intelligence settings tab with four ordered sections.
- Reuse existing workflow state and evidence components.
- Add only the navigation/inspector space required by the function.
- Keep Task Manager as the source for Processing Queue.
- Never hide data destination or cost behind a generic model label.
- Do not let streaming deltas resize the full window or steal text focus.
- Add new visual fixtures only for new states; do not re-record unrelated
  accepted goldens.

## U1 deferred backlog

The following items are intentionally not implemented now:

- global typography and spacing normalization;
- color, material, shadow, corner, badge, or animation redesign;
- wholesale Home/Meeting/Transcript/Settings relayout;
- imitation of Granola, Codex, Xcode, MacWhisper, or another product;
- global design-token rewrite;
- visual before/after campaign.

U1 starts only after the user separately approves it and the provider,
meeting, transcript, and routing workflows are stable.
