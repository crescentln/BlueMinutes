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

## Current P0/P1 functional UI issues

1. Intelligence/Codex/STT/BYOK/Task Routing surfaces are absent.
2. Closing the main window during recording enters termination rather than
   background continuation.
3. Record-only and unavailable STT are not a first-class setup state.
4. Transcript has no dedicated outline/top search for long meetings.
5. Codex Assistant, connection state, quota, streaming, and cancel UI are absent.
6. Start New Meeting inputs are split across destinations without one readiness
   review.
7. About/update readiness is absent.
8. New surfaces still require Light/Dark, 860×600, keyboard, VoiceOver, Dynamic
   Type, overflow, and resize proof.

## UI performance comparison status

The foundation branch adds contracts, documentation, and reviewed brand assets
but no new runtime SwiftUI feature surface. A before/after Instruments,
main-thread-hang, hitch, resize, scroll, CPU, and stable-memory comparison is
therefore **not yet run** and must not be inferred from the visual fixtures.
Each later Intelligence, routing, active-meeting, outline/search, and Assistant
surface must record its own pre-integration baseline and post-integration result
before the phase can close.

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
