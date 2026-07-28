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

Settings currently contain General, Appearance, and Learned Preferences.
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
| Start New Meeting | Coordinator over existing import/record/UN forms | Review exact snapshot before start |
| Live Meeting | Existing Recording destination/banner | Background lifecycle and honest STT state |
| Processing Queue | Existing Task Manager/store | Real job list; no fabricated static queue |
| Transcript outline/search | Existing transcript split view | Stable filtered navigation |
| Codex Assistant | Inspector tab or independent window | Preserve evidence inspector width |
| About/update | Native Settings/About scene | Version and honest unconfigured update state |
| Billing | No visible surface while disabled | M1 only |

## State and route visibility

Every task detail must show provider, exact model, Local/Codex/User API route,
cost owner, readiness, and a repair action. Starting a meeting records the
resolved snapshot. No control may imply Codex transcribes audio or that an
unconfigured STT route is active.

## UI boundary

Only functional insertion, accessibility, overflow, keyboard, window-size, and
state-feedback changes are in scope. Typography, color, shadows, corner
language, materials, global layout, and broad iconography remain unchanged
until U1.
