# BlueMinutes v4 Pre-Beta Audit

Status: Active implementation evidence
Baseline: `b41ae589e40ce9811a64c389899bc9639f8188d2`
Tracking: GitHub Issue #60
Started: 2026-07-28

This directory evaluates the user-supplied v4 brief against the live
BlueMinutes repository. Code and accepted ADRs remain authoritative where the
brief offers an illustrative implementation. The current phase preserves the
existing UI visual language and does not start U1.

The numbered documents follow the v4 output list. They cross-reference one
another rather than repeating the same matrix. The 50 PNG files in
`ui-current-baseline/` are byte-identical copies of the accepted visual
regression goldens at the rollback anchor. `manifest.json` records their
fixture matrix. They are a current functional UI baseline, not a U1
before/after proposal.

Current boundaries:

- Codex is a text-intelligence provider and never an STT provider.
- STT is independently local, explicitly configured remote, or record-only.
- Sensitive Meeting permits local providers only.
- Billing, licensing, website services, and updates are disabled/unconfigured.
- No website deployment, production Stripe connection, trial, paywall,
  Developer ID distribution, notarization, or Codex runtime bundling occurs.
- Full visual redesign remains deferred until the user separately approves U1.
