# BlueMinutes 0.4.0 v4 Pre-Beta Audit

Status: Candidate audit complete; source-only `v0.4.0` publication is
authorized only after the exact PR and protected-main gates. Binary
distribution gates remain open
Candidate version: `0.4.0` build `4`
Foundation rollback anchor: `b41ae589e40ce9811a64c389899bc9639f8188d2`
Current functional base: `77a4deca11190587c557e081667fb6c0e64a0f4a`
Tracking: GitHub Issue #60
Started: 2026-07-28

This directory evaluates the user-supplied v4 brief against the live
BlueMinutes repository. Code and accepted ADRs remain authoritative where the
brief offers an illustrative implementation. The current phase preserves the
existing UI visual language and does not start U1.

The numbered documents follow the v4 output list. They cross-reference one
another rather than repeating the same matrix. The 50 PNG files in
`ui-current-baseline/` are byte-identical copies of the earlier accepted visual
regression goldens captured from exact source
`82b1abc1b921b37c730e54c699574272c54e8f0e`. `manifest.json` records their
fixture matrix. Final normal-user layout corrections require a fresh pinned
candidate and calibration before merge; the earlier images are not claimed as
final evidence. They remain a functional UI baseline, not a U1 before/after
proposal.

Current boundaries:

- Codex is a text-intelligence provider and never an STT provider.
- STT is independently local, explicitly configured remote, or record-only.
- Sensitive Meeting permits local providers only.
- Billing, licensing, website services, and updates are disabled/unconfigured.
- No website deployment, production Stripe connection, trial, paywall,
  Developer ID distribution, notarization, or Codex runtime bundling occurs.
- Full visual redesign remains deferred until the user separately approves U1.
