# Product and Feature Audit

## Current product

BlueMinutes is a Swift 6 native macOS modular monolith. The accepted workflow
opens a user-controlled local workspace, imports or records audio, produces a
coverage-proven transcript through an installed Apple model when available,
supports human review, creates evidence-linked analysis and briefing
revisions, and exposes history, storage, local CLI, and seven read-only local
MCP tools.

The code paths are composed in
`Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`; the visible workflow
tree is in
`Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift`.

## v4 feature matrix

| Area | Current truth | v4 disposition |
| --- | --- | --- |
| Local workspace, immutable revisions, stale propagation | Implemented and accepted | Preserve |
| Segmented recording, task checkpoints, startup recovery | Implemented and accepted | Preserve; add real-device fault matrix |
| Local batch STT | Apple Speech on macOS 26+; manual fallback otherwise | Adapt; expose honest installed/not-ready state |
| Realtime STT | Not implemented | P1 capability gate; do not mislabel batch |
| Translation, analysis, briefing | Apple on-device routes with manual fallback | Preserve and register by capability |
| Provider registry and task routing | Foundation contracts added in Issue #60 slice | Implement UI, scope precedence, persistence, and snapshots |
| Codex subscription text intelligence | Not present at rollback anchor | P0 app-server vertical slice |
| Independent STT / BYOK settings | Not present at rollback anchor | P0/P1 |
| Sensitive Meeting | New resolver contract; no persisted profile yet | P0/P1 |
| Start a New Meeting | Inputs are separate pages | P1 functional coordinator using existing pages |
| Active meeting after window close | Closing during recording currently terminates | P0 bug |
| Transcript outline/search | Stable list exists; dedicated search/outline absent | P0/P1 |
| AI Chat | Absent | P1 after Codex context bridge |
| UN Web TV | Exact-host metadata only | Preserve security; additional ingestion remains gated |
| Export | Controlled Markdown briefing | P1 formats and exact-revision archive |
| Update | Manual/unconfigured policy only | P0 shell; Sparkle remains distribution-gated |
| Billing/licensing | No client or network path | Keep `BillingMode.disabled` through Beta/1.0 |
| Website | Separate UI-only prototype; no desktop contract | App-side disconnected interface only |
| Visual system | Accepted Editorial Dossier foundation and 50 goldens | Preserve; U1 deferred |

## Conflict and duplication findings

- `AIProcessingCapability` models execution contracts for the accepted
  transcript/translation/analysis jobs. The new `ProviderCapability` models
  product eligibility for routing. They serve different layers; they must be
  bridged in composition rather than merged mechanically.
- `.manualFallback` is an execution outcome. It must not be shown as the v4
  `None / Record only` STT choice.
- `meetingbuddy-mcp` is an automation boundary, not a Codex inference transport.
- Website ChatGPT-hosting headers are not desktop Codex authentication.

## Release phases

- **P0/P1 now:** functional readiness, routing, Codex text slice, independent
  STT/BYOK, background reliability, long transcript usability, disabled release
  services, tests, and audit closure.
- **Beta/1.0:** all local features remain unlocked; no trial, paywall, license
  dependency, production billing, or silent cloud fallback.
- **U1:** visual refinement only after separate user approval.
- **M1:** production commercialization only after a separate go/no-go.
- **P2:** broader integrations and collaboration after 1.0 feedback.

The execution order and remaining acceptance gates are in
[`13-release-backlog-acceptance-and-fixes.md`](13-release-backlog-acceptance-and-fixes.md).
