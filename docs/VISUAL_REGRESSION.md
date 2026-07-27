# Native Visual Regression

Status: Future Slice I first baseline and review-remediation replacement
accepted for pull-request validation; bounded actual-application evidence is
recorded, while the system-owned manual boundary and protected-main gates
remain open
Scope: synthetic application-owned SwiftUI/AppKit content only

## Contract

The harness runs inside `MeetingBuddyFeaturesTests`. Each case is hosted in a
borderless `NSWindow` through `NSHostingView` and given an initial one-second
settle. It then captures normalized probes every 250 milliseconds until two
consecutive encoded frames are byte-identical, with at most 12 probes. Every
recorded frame must still equal that stable reference or capture fails closed.
The exact process-owned desktop-independent window is captured by macOS 26
`SCScreenshotManager` in canonical SDR. The SwiftUI root, hosting layer, and
opaque window share one explicit black or white application-owned underlay, so
native material cannot inherit a desktop or unrelated foreground-window
backdrop. This captures native
compositor-owned Liquid Glass, inspector, list, and button layers that
`NSView.cacheDisplay` does not contain. It includes no cursor, audio, desktop,
or other application window. Shareable content is obtained through the
current-process-only API, which exposes the process's own redacted window list
without user consent through TCC. The harness never requests Screen Recording
permission or changes TCC state; an exact runner that cannot capture the
already-created test window fails closed. No application entitlement,
permission prompt, or production capture path is added.

The composed result is rendered at exactly one output pixel per point and
normalized into opaque 8-bit sRGB. The outermost one-pixel WindowServer frame
is outside the owned content surface, so its variable framing tint is replaced
with the adjacent owned edge pixel before hashing. The full resulting image
still participates in comparison. Representative sidebar, inspector, and
native-action regions must each contain at least 32 distinct RGB colors, so a
blank region fails before candidate, calibration, or regression evidence can
pass. This is an explicit blank-region smoke gate, not proof that every
control is correct; runtime AX contracts and human review of every candidate
image remain independent gates. Content-specific runtime AX tests prove the
exact Local Media and Recording buttons represented by the native-action
regions, including unique AX identifiers, exact labels, native button roles,
and button centers with at least half of each frame inside its shared pixel
region contract. Inspector AX tests separately prove both inspector regions.
The encoder removes timestamp, text, EXIF, path, and identifying chunks,
embeds the canonical sRGB ICC profile, and rejects any PNG that is not color
type 2 at the declared dimensions. The synchronous `NSView.cacheDisplay` path
remains only for isolated PNG encoder and format-contract tests.

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
manifest contains one capture for each descriptor. The catalog covers the
860x600, 1080x720, 1440x1024, and 1728x1024 shell sizes; inspector open and
closed; and representative onboarding, Local Media, Recording, UN Web TV,
Transcript, Analysis, Briefing, History, Storage, and Settings states.
Explicit Recording loading and Storage failure cases close the loading/failure
part of the state matrix; the other cases include empty, blocked, working,
stale, export-blocked, and destructive-disabled reasons. Increase Contrast and
larger text are distributed across constrained cases.

Every automated case renders the real production root or surface view with a
deterministic synthetic `MediaReviewWorkflow`. There is no generic or
fixture-only replacement screen. For the three inspector-open host captures
(Transcript selected, Analysis selected, and Analysis stale), a narrow
internal initializer seeds the real production review view's own `.inspector`
state and Analysis evidence selection. Runtime AX tests prove the native
inspector appears exactly once with its production role, label, value, and
in-window frame. Hands-on inspector resizing in the complete application
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

Every ephemeral GitHub-hosted macOS job first establishes the automated
matrix's standard live accessibility state: Reduce Transparency,
Differentiate Without Color, and Reduce Motion are written as disabled for the
runner user, that runner user's preference daemon is restarted, and a separate
AppKit probe must observe all three as disabled before tests or captures begin.
This step is intentionally confined to the disposable hosted runner; the local
entry point never changes a developer Mac. The three nonstandard descriptors
remain manual-system cases and are not simulated by the automated harness.

`calibration` takes five compositor frames from one continuously hosted
production window per case in each of three fresh test processes and writes
one record per process. Reconstructing the view and window between those five
frames is not capture calibration: it changes the WindowServer history being
measured and can manufacture state drift that a single baseline or regression
capture never exercises. The first process's one-hash-per-case result becomes
the in-job reference for processes two and three.
Identical encoded hashes prove every pair is exact without repeatedly decoding
the same pixels; any unequal hash triggers full channel, changed-pixel, and
luminance comparisons. Each record includes its process index, exact
environment, five per-case PNG hashes, source revision, committed-manifest
hash, fixture-catalog hash, and GitHub run identity.
Any within-process or cross-process hash difference fails the evidence job
after writing the JSON available at that point and retaining only the
synthetic differing frames under `CalibrationDiagnostics`. A successful
evidence job is therefore a hard zero-difference gate, but the downloaded
records and their candidate-hash relationship must still be reviewed before
baseline import.

The accepted calibration records under
`docs/audits/visual-regression-calibration/` come from the same exact runner
contract as the accepted candidates. No local or prior 46-case calibration is
valid for this 50-case production-view matrix.

## Baseline governance

A person must inspect candidate images, state the design reason, and review the
manifest/hash/threshold change before mechanically copying a candidate into
the resource directory. CI and calibration never update goldens or thresholds.
Do not mask regions, delete required cases, or loosen a threshold merely to
accept a design change.

The first-baseline design reason is: establish the Future Slice I Editorial
Dossier proof matrix after Slices F through H2 stabilize the native surfaces.

The first accepted candidate was generated by GitHub Actions run
`30306957209`, evidence job `90113453412`, from source revision
`f203010c3a645d11ccdb97538d6baf9af9a94b04`. All 50 images were reviewed in
Light and Dark contact sheets, and representative full-resolution images were
inspected for the narrow shell, Transcript and Analysis inspector states,
Storage failure, and Recording loading. The review found no blank capture,
overlap, clipping, missing primary action, or privacy-bearing content. The
manifest contains 50 unique identifiers, files, and PNG hashes; every PNG
matched its declared dimensions and SHA-256 values, used opaque 8-bit RGB
without identifying metadata chunks, and shared the declared canonical sRGB
profile. Every accepted comparison threshold remains exact:
`maximumChannelDelta = 0`, `maximumChangedPixelRatio = 0`, and
`minimumLuminanceSSIM = 1`. This remains the historical first-baseline
acceptance record rather than a claim that those exact four superseded
Analysis images remain current.

The first-baseline calibration was generated by GitHub Actions run
`30307533539`, evidence job `90115266147`, at that same source revision and
exact environment.
Three fresh processes each captured five frames for every one of the 50 cases:
750 recorded frames and 1,500 within-process pair relationships in total.
Every per-case hash was identical within and across processes, every hash
matched the corresponding first-baseline candidate PNG hash, and all measured
differences were zero.

Review remediation then changed the Analysis coverage presentation to fail
closed for incomplete, missing, or failed terminal coverage and made the stale
Analysis inspector's unresolved exact evidence visible. The candidate from
GitHub Actions run `30313002869`, evidence job `90132570916`, at source
`c477cc4` is intentionally rejected: manual full-resolution review found a
published-ledger fixture referencing an intervention card that was not
present. Its images and manifest were not imported, and no threshold was
changed to accept it.

The accepted remediation candidate was generated by GitHub Actions run
`30313447482`, evidence job `90133908047`, from exact source revision
`b86264d6d207ed8c2c96b3a87c5cfdfa4a49cdaa`. Its manifest SHA-256 is
`63fac4d34e01baa4e48b30e9420c313066fe2e6b21f237defa2d5ef3ba2e561c`.
Forty-six of the 50 PNGs were byte-identical to the first baseline. The four
changed images (`analysis-selected-{light,dark}` and
`analysis-stale-{light,dark}`) were inspected at full resolution. Selected
Analysis now shows `0 / 1 terminal results`, one missing result, an incomplete
ledger, and an exact resolved `EvidenceRef`; stale Analysis shows the same
non-green coverage truth, the stale delegation, and a fail-closed unresolved
evidence inspector. Light and Dark layouts, wrapping, contrast, and
non-color-only state remained coherent. The candidate retained 50 unique
identifiers, files, and PNG hashes, and every threshold remained zero.

The current accepted calibration was generated by GitHub Actions run
`30313797786`, evidence job `90134932100`, at that same exact source and
environment. Three fresh processes each captured five continuously hosted
frames for all 50 cases: 750 frames and 1,500 within-process pair relationships.
Every per-case hash was identical within and across processes, every hash
matched the corresponding remediation-candidate PNG hash, and every measured
difference was zero. These current immutable records replace the superseded
first-baseline calibration records under
`docs/audits/visual-regression-calibration/calibration-1.json` through
`calibration-3.json`.

Calibration run `30301841698` is intentionally rejected. It reconstructed the
production view and compositor window between samples and exposed measurable
WindowServer-history perturbation rather than the continuously hosted capture
contract used by candidate and regression modes. Its output was not imported
or used to loosen a threshold.

The accepted manifest's `baselineSourceRevision` is the exact remediation
capture source above and intentionally precedes the resource-import carrier
commit. The current calibration records' `manifestSHA256`
(`d558e643f5a33b6f0109f188a6d376e8ce1631e5ec8a0fefaca23a848320ee9f`)
records the pre-import committed 50-case manifest that existed at that capture
source; the imported candidate manifest itself hashes to
`63fac4d34e01baa4e48b30e9420c313066fe2e6b21f237defa2d5ef3ba2e561c`.
Acceptance is bound to the matching source revision, exact environment,
fixture-catalog hash
(`115715977aa7e2bf2ad01324cd7015104d45ff505a0f39c1a5ca49c652074156`),
and the verified one-to-one candidate PNG hashes. The pre-import manifest field
is preserved rather than rewritten after the fact.

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
