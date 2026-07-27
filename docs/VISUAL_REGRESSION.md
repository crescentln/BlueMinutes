# Native Visual Regression

Status: Future Slice I automated proof in progress
Scope: synthetic application-owned SwiftUI/AppKit content only

## Contract

The harness runs inside `MeetingBuddyFeaturesTests`. Each case is hosted in a
borderless `NSWindow` through `NSHostingView`, rendered at exactly one output
pixel per point, and normalized into opaque 8-bit sRGB. The encoder removes
timestamp, text, EXIF, path, and identifying chunks, embeds the canonical sRGB
ICC profile, and rejects any PNG that is not color type 2 at the declared
dimensions.

`Tests/MeetingBuddyFeaturesTests/VisualRegression/manifest.json` binds every
accepted golden to:

- scenario, state, viewport, inspector state, Light/Dark appearance, and
  accessibility flags;
- POSIX English locale, UTC, system-blue accent, and exact text size;
- macOS 26.4 build 25E246, Xcode 26.6 build 17F113, Apple Swift 6.3.3
  (`swiftlang-6.3.3.1.3`, `clang-2100.1.1.101`), target triple
  `arm64-apple-macosx26.0`, macOS SDK 26.5 build 25F70, and GitHub runner image
  `macos-26-arm64` version `20260720.0258.1`;
- the exact baseline-generation source revision, arm64 architecture,
  one-pixel-per-point capture, fixture seed/version, and
  comparison-algorithm version;
- PNG, decoded-pixel, and ICC-profile SHA-256 values;
- an explicit per-case maximum channel delta, changed-pixel ratio, and minimum
  luminance SSIM.

All initial thresholds are zero. Dimensions, PNG structure, profile, and
environment are hard gates outside perceptual thresholds.

## Matrix

The fixture catalog contains 50 automated Light/Dark descriptors. The accepted
manifest will contain one capture for each descriptor. The catalog covers the
860x600, 1080x720, 1440x1024, and 1728x1024 shell sizes; inspector open and
closed; and representative onboarding, Local Media, Recording, UN Web TV,
Transcript, Analysis, Briefing, History, Storage, and Settings states.
Explicit Recording loading and Storage failure cases close the loading/failure
part of the state matrix; the other cases include empty, blocked, working,
stale, export-blocked, and destructive-disabled reasons. Increase Contrast and
larger text are distributed across constrained cases.

Every automated case renders the real production root or surface view with a
deterministic synthetic `MediaReviewWorkflow`. There is no generic or
fixture-only replacement screen. For the two inspector-open host captures, a
narrow internal initializer seeds the real production review view's own
`.inspector` state and Analysis evidence selection. Runtime AX tests prove the
native inspector appears exactly once with its production role, label, value,
and in-window frame. Hands-on inspector resizing in the complete application
remains separate actual-app evidence.

Reduce Transparency, Differentiate Without Color, and Reduce Motion are
system-owned read-only SwiftUI environment values. Their three descriptors are
recorded separately in `manualSystemCases`; the harness refuses a capture when
the live macOS setting does not exactly match the descriptor. They are not
silently simulated and are not represented as completed actual-application
VoiceOver or motion evidence.

## Modes

The checked-in CI entry point is:

```bash
MEETINGBUDDY_VISUAL_ARTIFACT_DIR=/absolute/empty/directory \
  ./script/run_visual_regression.sh
```

`regression` reads the immutable bundled manifest and goldens. A pixel or
PNG/profile/hash contract mismatch emits exactly expected, actual, diff, and
machine-readable comparison JSON into the supplied artifact directory. When a
corrupt image cannot be decoded for a mathematical diff, the diff file is an
explicit checkerboard contract-failure placeholder and the JSON records that
fact.

`candidate` writes a complete proposed `VisualRegression` tree only to the
supplied artifact directory. It refuses to target the checked-in golden
directory. Candidate output never changes a baseline.

All three modes use the same pinned preflight. The `Native visual regression`
job has a fixed `regression` mode and is the only formal visual-regression
check. Ordinary pull-request synchronize/open/reopen events and main pushes run
that job; candidate or calibration generation can never turn its check context
green.

The distinct `Native visual evidence bootstrap` job is evidence generation,
not a regression gate. After the workflow exists on the default branch, the
workflow-dispatch `visual_mode` choice can request evidence on an exact ref.
For the first Slice I baseline, when manual dispatch is not yet available, a
maintainer applies exactly one of the `visual-candidate` or
`visual-calibration` PR labels. Only that labeled event generates evidence
against the exact PR head SHA. A later `synchronize` event always runs the
formal regression job even if the evidence label remains, and never regenerates
candidate or calibration evidence. Remove `visual-candidate` before applying
`visual-calibration`; if both labels are present, evidence generation fails
closed by not starting.

The script rejects any other mode and fails separately before capture unless
the exact OS/build, Xcode/build, full Swift compiler, target triple, SDK/build,
runner image/version, arm64, UTC, and POSIX English contract above are in
force. A local Mac or a later rolling runner image is therefore expected to
fail closed rather than produce an apparently comparable baseline.

`calibration` takes five captures per case in each of three fresh test
processes and writes one record per process.
Identical encoded hashes prove every pair is exact without repeatedly decoding
the same pixels; any unequal hash triggers full channel, changed-pixel, and
luminance comparisons. Each record includes its process index, exact
environment, five per-case PNG hashes, source revision, committed-manifest
hash, fixture-catalog hash, and GitHub run identity.

The accepted calibration records under
`docs/audits/visual-regression-calibration/` must come from the same exact
runner contract as the accepted candidates. No local or prior 46-case
calibration is valid for this 50-case production-view matrix.

## Baseline governance

A person must inspect candidate images, state the design reason, and review the
manifest/hash/threshold change before mechanically copying a candidate into
the resource directory. CI and calibration never update goldens or thresholds.
Do not mask regions, delete required cases, or loosen a threshold merely to
accept a design change.

The proposed first-baseline reason is: establish the Future Slice I Editorial
Dossier proof matrix after Slices F through H2 stabilize the native surfaces.
At this working-tree checkpoint, no 50-case exact-runner candidate or
calibration record has been accepted. The existing 46-case resource set
predates the final production-view catalog and is intentionally rejected by
the manifest contract. Slice I cannot be accepted until exact-runner candidate
artifacts are inspected, their manifest and hashes are reviewed, three-process
calibration proves the proposed zero thresholds, and the accepted artifacts
replace that obsolete resource set in a separate reviewed change.

## Accessibility boundary

Runtime AX tests remain separate from pixels and verify roles, labels, values,
hints, enabled states, frames, and duplicate identifiers. Slice I directly
hosts both production views with their own `.inspector` state open and verifies
each inspector appears exactly once with its expected native role, label,
value, and in-window frame. A separate open/closed Transcript host test proves
the production inspector changes native layout without overlap. Another
runtime AX test presses the real production toolbar control through its native
AX action, verifies that it toggles the same binding used by the focused
command route, and confirms the control retains focus across both transitions.
Dirty-navigation and data-state command rules remain covered by their owning
feature tests.

Actual-application VoiceOver order/announcements, visible focus, system Reduce
Transparency, Differentiate Without Color, Reduce Motion, and hands-on resize
evidence must be recorded as a separate manual run. The final run must also
exercise the installed scene command shortcuts and focus restoration in the
complete application. Host-view pixels are never presented as that proof.
