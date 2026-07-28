# User Flow and UI Map

## Current navigation

`MeetingBuddyRootView` uses one native `NavigationSplitView` and eight
destinations:

1. Local Media
2. Record Audio
3. UN Web TV Metadata
4. Transcript Review
5. Analysis Review
6. Briefing
7. Meeting History
8. Storage

Settings contain General, Appearance, Intelligence, and Learned Preferences.
The Intelligence tab owns the four ordered Codex, speech-to-text, BYOK, and
Task Routing sections.
The existing editor canvas, evidence inspector, state views, sidebar rows,
toolbars, confirmation dialogs, and visual tokens remain the integration
language.

## Target functional flow

```text
Onboarding
  -> Choose/create local workspace
  -> Intelligence settings
       1. Codex with ChatGPT Subscription
       2. Speech-to-Text Setup
       3. Bring Your Own API Key
       4. Task Routing
  -> Start a New Meeting
       source + languages + routing readiness + Sensitive Meeting
  -> Live Meeting
       recording state + exact STT state + autosave/recovery + assistant entry
  -> Transcript
       outline + search + review + evidence + scoped assistant
  -> Analysis / Briefing / Export
  -> History / Storage
```

## Surface mapping

| v4 surface | Current insertion point | Functional change |
| --- | --- | --- |
| Onboarding | Existing no-workspace `ContentUnavailableView` | Add readiness link after workspace |
| Codex connection | New Intelligence settings tab | Runtime/account state, text-only disclosure |
| Local/remote/no STT | Same tab, second section | Capability-filtered options; Codex excluded |
| BYOK | Same tab, third section | Keychain-backed profiles |
| Task Routing | Same tab, fourth section | Task/provider/data/cost/readiness |
| Start New Meeting | Lightweight coordinator over existing import/record/UN forms | Choose a workflow without duplicating forms or starting work; exact policy and route review remains in the selected page |
| Live Meeting | Existing Recording destination, banner, and app-owned menu-bar item | Background close/reopen lifecycle, durable stop/finalize, honest STT state, and later canonical preparation |
| Processing Queue | Existing Task Manager/store | Real job list; no fabricated static queue |
| Transcript outline/search | Existing transcript split view | Deterministic five-minute outline, bounded text/time search, and stable filtered navigation |
| Codex Assistant | Existing transcript workspace assistant tab | Selected-segment text only, per-request authorization, streaming/stop/retry, and no audio |
| About/update | Independent native About scene | Icon/version plus honest unlocked, website-disconnected, and update-unconfigured state |
| Billing | No visible surface while disabled | M1 only |

## State and route visibility

Every task detail must show provider, exact model, Local/Codex/User API route,
cost owner, readiness, and a repair action. Import and recording starts persist
the selected STT intent; transcript jobs bind the exact execution snapshot.
Changing the picker after recording affects later transcript execution but does
not rewrite the immutable meeting-start profile. No control may imply Codex
transcribes audio or that an unconfigured STT route is active.

## UI boundary

Only functional insertion, accessibility, overflow, keyboard, window-size, and
state-feedback changes are in scope. Typography, color, shadows, corner
language, materials, global layout, and broad iconography remain unchanged
until U1.
