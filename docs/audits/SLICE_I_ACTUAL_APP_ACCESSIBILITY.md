# Slice I Actual-App Accessibility Evidence

Status: Partial local evidence; final Future Slice I acceptance pending
Date: 2026-07-26
Application: staged `MeetingBuddy.app` built from the Slice I working tree

## Environment and boundary

- macOS 26.5.2 (25F84) on Apple M4 arm64, Xcode 26.6 (17F113), and
  Apple Swift 6.3.3.
- The staged application was launched from
  `/private/tmp/blueminutes-slice-i-proof/dist/MeetingBuddy.app`.
- This record predates the final Slice I source commit and does not bind an
  exact source revision or executable hash. It must be repeated against the
  final staged application before acceptance.
- No workspace was selected. The run used no meeting content, credentials,
  provider or model access, network path, or new TCC permission.
- This is separate hands-on actual-application evidence. The native host-view
  goldens and automated AX tests are not substituted for this run.

## Results

### Runtime accessibility tree and VoiceOver

- The actual-app AX tree exposed one `SidebarNavigationSplitView` and the
  stable sidebar order: Workspace, No workspace open, Choose Workspace,
  Workflow, Local Media, Record Audio, UN Web TV Metadata, Transcript Review,
  Analysis Review, Briefing, Meeting History, and Storage.
- Sidebar destinations exposed distinct labels and selection state. The
  workspace toolbar controls exposed `Hide Sidebar` and the workspace menu
  with their descriptions and keyboard hints.
- VoiceOver was enabled through System Settings for the run. With the
  VoiceOver service active, the actual-app AX tree retained the same ordered
  labels, roles, and selected state; no duplicate destination label or
  inaccessible control was observed.
- The VoiceOver caption panel setting was confirmed enabled in VoiceOver
  Utility. This run verified navigable order and labels but did not retain a
  machine-readable transcript of the spoken announcements, so it does not
  claim byte-for-byte announcement wording.
- VoiceOver was turned off after the check. System Settings showed the switch
  off and `launchctl` reported `com.apple.VoiceOver` as `state = not running`.

### Keyboard focus and command surface

- Keyboard traversal placed a clearly visible focus ring on the toolbar
  `Hide Sidebar` control.
- The toolbar workspace menu remained separately labeled and reachable.
- Selecting Transcript and then Storage updated both sidebar selection and
  editorial-canvas title without stale or duplicate focus targets.

### Resize and reflow

- The main window was narrowed from its initial larger layout to approximately
  860 by 650 points.
- At the narrow size, the sidebar, selected destination, editorial canvas,
  empty-state copy, and primary `Choose Workspace` action remained visible and
  readable without overlap or clipping.
- The AX hierarchy remained ordered after the resize and after destination
  changes.
- The staged application exited normally with Command-Q after the run; no
  test application or VoiceOver process remained active.

### System-owned accessibility settings

- Automated fixtures distribute Increase Contrast and larger text, while the
  manifest records Reduce Transparency, Differentiate Without Color, and
  Reduce Motion as system-owned manual descriptors that cannot be simulated by
  the host-view harness.
- No system-owned display or motion preference was changed during this
  actual-app run. A late Computer Use native-pipe failure prevented a reliable
  toggle-and-restore cycle, so this record does not overstate those three
  hands-on checks.
- The product surfaces use semantic text, icons plus labels or disabled
  reasons, and explicit status copy; the automated visual/AX matrix separately
  verifies the corresponding non-color-only and reduced-environment contracts.

## Residual manual boundary

Exact spoken VoiceOver announcement wording and live toggles for Reduce
Transparency, Differentiate Without Color, and Reduce Motion remain manual
system-integration observations. The deterministic application-owned visual
gate does not substitute for them. Final Slice I acceptance also requires a
repeat run tied to the exact source revision and staged executable hash; none
of these gaps is represented as captured golden pixels.
