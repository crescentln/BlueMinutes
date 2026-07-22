# BlueMinutes 0.1.0 Internal Validation Snapshot

Build: 1
Platform: Apple Silicon, macOS 15 or later
Status: local internal evaluation only; not distributed

## Included

This historical internal snapshot includes the accepted BlueMinutes work
through Task 010:
local workspace/persistence, managed media intake and canonical audio,
on-device transcription/translation/analysis/briefing routes with manual
fallbacks, evidence-linked review, retention/recovery controls, bounded
recording capture, local automation/stdio MCP developer surfaces, and
historical comparison/preferences.

The selected historical artifact contains only the legacy-compatible
`MeetingBuddy.app` bundle. The CLI and MCP executables remain local
developer/operator tools and are not bundled.

## Task 011 changes

- Added a three-hour canonical planning limit and exact boundary tests.
- Added a 32-audio-track inspection limit before expensive track processing.
- Enforced the inspected source byte ceiling during streamed managed intake.
- Reworked UN Web TV blocked-element cleanup to make monotonic progress.
- Blocked recording restore while recovery reconciliation remains required.
- Added a macOS privacy manifest with reviewed required-reason declarations.
- Bundled GRDB's privacy resource and exact MIT license notice.
- Added clean-scratch release packaging, app/archive verification, and cold
  workspace-backup verification scripts. The app, archive, digest,
  source-file inventory, and build manifest now form one coherently staged and
  recoverably replaced local release set.

## Privacy and data handling

Meeting audio, transcripts, metadata, and derived intelligence remain local by
default. No meeting content is sent to a provider or destination unless an
approved route and visible authorization permit it. The only application
network implementation is the explicit exact-host UN Web TV metadata request;
it does not acquire media. Telemetry is default-off and content-free. Secrets
use macOS Keychain. Application-level workspace encryption is not included;
use trusted account and volume protection.

## Known limitations

- Four medium evidence-integrity findings remain: generated analysis and
  briefing claims lack application-owned semantic entailment, and provider-only
  `nonSubstantive`/`noSpeech` classifications can close published coverage.
  Treat every derived result as requiring human review.
- The package is ad-hoc signed with Hardened Runtime. It has no Developer ID,
  Team ID, notarization ticket, or Gatekeeper distribution approval.
- Clean-machine install/update/rollback and manual VoiceOver/Full Keyboard
  Access/contrast/reduced-motion review are not complete.
- Live TCC behavior, long physical capture, sleep, sudden power loss, and
  device/source changes are not fully validated on the intended OS range.
- The UI is English-only and no approved app icon exists.
- The artifact contains one arm64 slice; Intel/universal distribution is not
  selected.
- Automatic updates are not implemented or approved.
- Release-set replacement uses a recoverable two-rename operation rather than
  a strict atomic directory exchange; an interrupted replacement fails closed
  for operator inspection.
- Cold-backup verification detects initial/final inventory drift but does not
  take an OS-level lock; MeetingBuddy must remain quit throughout the copy and
  verification.
- UN Web TV media/player acquisition and automatic audio-track mapping remain
  outside scope.

## Artifact identity

Local ignored output:

- `dist/MeetingBuddy-0.1.0-internal-alpha/`
- `MeetingBuddy-0.1.0-internal-alpha.zip` inside that release set
- SHA-256:
  `2ae023748b20f0bcf3c5dba87a839948248ff5edc914015020ade5ee50b12f44`

`release-manifest.json` explicitly records the dirty/uncommitted source state
at build time, toolchain, artifact hashes, ad-hoc identity, and
non-distribution status. Its `source-files.sha256` inventory digest is
`ed9983486f217bd6274ceb97dc324d7b9547ffae2daba32ef44e8942ff059e5b`.

The current archive was made before acceptance from an uncommitted Task 011
working tree. Task 011 is now accepted locally, but this archive is not a
publication artifact. Rebuild from the accepted revision with Developer
ID/notarization only after separate authorization.

## Backup and rollback

Before any application change, quit MeetingBuddy, make a cold whole-workspace
copy, and run `script/verify_workspace_backup.sh`. Never open a newer-schema
live workspace in an older binary; restore a verified pre-upgrade copy into a
new directory. See `RELEASE_BACKUP_AND_ROLLBACK.md`.
