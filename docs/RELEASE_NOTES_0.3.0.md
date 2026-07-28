# BlueMinutes v0.3.0 — Editorial Dossier Foundation

- Released: 2026-07-28
- Tag: `v0.3.0`
- Distribution scope: source code only; zero uploaded assets
- Local package: ad-hoc development build for testing on the build Mac

BlueMinutes v0.3.0 completes the native Editorial Dossier foundation. The
review-first workflow now presents intake, Transcript, Analysis, Briefing,
Meeting History, learned preferences, Storage, and Settings through one
coherent macOS interface while preserving exact evidence, workspace, and
human-confirmation boundaries.

## Highlights

- A native three-column Editorial Dossier shell keeps workspace navigation,
  the active review canvas, and evidence inspector aligned without transferring
  state ownership into views.
- Local Media, visible Record Audio, and bounded UN Web TV Metadata intake use
  consistent native forms and fail before persistence or job enqueue when
  preflight validation is incomplete.
- Transcript and Analysis review expose exact current revisions, evidence, and
  stale reasons. Consequential actions remain disabled when the accepted state
  cannot be proved current.
- Briefing sections remain independently editable, lockable, regenerable,
  confirmable, and exportable only from exact confirmed inputs.
- Meeting History, pagination, comparison, learned preferences, and Storage
  preserve accepted-state and retry boundaries across asynchronous failures and
  workspace changes.
- Native Settings, keyboard commands, visible focus, inspector presentation,
  compact layout, and runtime accessibility contracts cover the migrated
  surfaces.

## Visual and actual-app evidence

The pinned native visual catalog contains 50 reviewed cases. Four remediated
reference images received full-resolution semantic review and the other 46
remained byte-identical. Same-runner calibration captured 750 frames across
three fresh processes and compared 1,500 pairs; all hashes matched with maximum
channel delta `0`, changed-pixel ratio `0`, and luminance SSIM `1`.

A fresh synthetic local WAV was imported through the staged application. The
managed copy, hash verification, canonical audio task, and all three progress
units completed locally, and the inspected workspace database, sidecars, logs,
managed WAV, and canonical CAF used owner-only file modes.

This evidence does not claim complete system-integration coverage. Current-build
VoiceOver spoken wording, live toggle-and-restore checks for Reduce
Transparency, Differentiate Without Color, and Reduce Motion, and a
current-build automated Transcript transition remain unverified. The existing
structural/runtime accessibility tests and earlier bounded hands-on sequence do
not replace those future manual gates.

## Local development package

From a clean checkout of the release source:

```sh
MEETINGBUDDY_SIGN_IDENTITY=- ./script/package_release_candidate.sh
./script/verify_release_candidate.sh \
  dist/BlueMinutes-0.3.0-development \
  development
```

The ignored local release set contains:

- `BlueMinutes.app`
- `BlueMinutes-0.3.0-development.zip`
- `BlueMinutes-0.3.0-development.zip.sha256`
- `source-files.sha256`
- `release-manifest.json`

The schema-v2 manifest records version `0.3.0` (build `3`), the exact Git
head/tree/tag, a full tracked-source inventory and digest, the resolved
dependency digest, Swift/Xcode/macOS/architecture, app and archive digests,
signature kind, Hardened Runtime, and notarization state. The verifier checks
the direct app, coherent release set, exact source commit, and a fresh ZIP
extraction. Its classification is `DEVELOPMENT` and
`distribution_authorized: false`; `distribution` mode rejects the ad-hoc
package.

The app and ZIP stay only in the ignored local `dist/` directory. They are not
installed, uploaded, or attached to this GitHub Release.

## Source-release boundary

GitHub supplies standard source archives automatically. The release contains
zero maintainer-uploaded assets: no app bundle, ZIP, installer, signing
material, model, workspace, meeting content, or generated briefing is attached.

Developer ID and Team ID signing, notarization and stapling, Gatekeeper
distribution approval, clean-machine installation, automatic update/Sparkle,
public binary upload, and deployment remain separate future milestones.

## Privacy, architecture, and compatibility

Meeting content remains local by default. This release adds no external
provider or model, credential flow, telemetry destination, remote control,
cloud synchronization, HTTP API, or network route. UN Web TV support remains a
single explicit metadata-only request to the exact supported host.

SQLite remains at schema v10 and GRDB remains pinned at 7.11.1. There is no
migration or dependency change.

BlueMinutes is the public project, product, app-bundle, and package name.
Compatibility-sensitive `MeetingBuddyApp`, `com.meetingbuddy.desktop`, Swift
targets, database paths, CLI/MCP commands, protocol identifiers, and serialized
formats remain unchanged.

## Known limitations

- Apple Silicon is the currently validated architecture.
- Automatic transcription, translation, analysis, and briefing require macOS
  26, supported hardware/locales, and installed Apple model assets.
- Briefing currently provides one multilateral template and three sections.
- Historical retrieval remains conservative lexical and exact-identity search.
- UN Web TV support remains metadata-only; no media acquisition is implemented.
- Intended-identity TCC behavior, long physical capture, sleep/force-quit/power
  interruption, clean-machine distribution, localization, and complete manual
  assistive-technology review remain future evidence gates.
- BlueMinutes supports evidence-linked drafting and review; users must validate
  consequential output against source material and applicable processes.

See [CHANGELOG.md](../CHANGELOG.md) for the detailed version history and
[README.md](../README.md) for build, package, and usage instructions.
