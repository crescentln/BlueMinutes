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
| Local batch STT | Apple Speech on macOS 26+ with an honest system-managed model state; record-only/manual fallback otherwise | Implemented; macOS 15 product decision remains |
| Realtime STT | Not implemented | P1 capability gate; do not mislabel batch |
| Translation, analysis, briefing | Apple on-device routes with manual fallback | Preserve and register by capability |
| Provider registry and task routing | Capability-filtered Intelligence UI, persisted non-secret routes, Keychain-backed provider profiles, and exact job snapshots | Implemented for the current global and meeting workflow; post-record profile supersession remains a later immutable-revision design |
| Codex subscription text intelligence | Pinned official runtime, isolated app-server transport/session, login/account/quota state, and bounded transcript-text Assistant | Implemented text-only vertical slice; no audio, shell, arbitrary file, web, plugin, or MCP surface |
| Independent STT / BYOK settings | Separate Apple local, OpenAI remote, record-only, and text-provider setup | Implemented with explicit per-meeting audio-upload authorization and no silent fallback |
| Sensitive Meeting | Resolver and persisted meeting profile deny every remote/Codex route | Implemented; central model-policy defense repeats the denial |
| Start a New Meeting | Lightweight coordinator reuses existing import, recording, and UN metadata pages | Implemented without duplicating forms or starting side effects |
| Active meeting after window close | App-owned store and menu-bar lifecycle preserve one recording session | Implemented for close/reopen/stop/quit; pause, live source switching, sleep/wake, and long-run hardware proof remain |
| Transcript outline/search | Deterministic five-minute outline plus bounded text/time search and stable selection | Implemented; real-device long-document performance proof remains |
| AI Chat | Selected-segment Codex Assistant with visible per-request authorization, streaming, stop, retry, and isolated thread lifecycle | Implemented bounded P1 slice |
| UN Web TV | Exact-host metadata only | Preserve security; additional ingestion remains gated |
| Export | Controlled Markdown briefing | P1 formats and exact-revision archive |
| Update | About surface composes an honest unconfigured update policy and disconnected website handoff | P0 shell implemented; Sparkle remains distribution-gated |
| Billing/licensing | No client or network path | Keep `BillingMode.disabled` through Beta/1.0 |
| Website | Separate project plus app-side typed handoff | Remains disconnected with no configured endpoint or request path |
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
