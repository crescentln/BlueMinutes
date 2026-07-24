# BlueMinutes UI Migration Plan

Status: Phase 1 design contract; implementation sequence not yet authorized
Owner: Codex, under maintainer authorization
Last updated: 2026-07-24
Tracking: [GitHub Issue #21](https://github.com/crescentln/BlueMinutes/issues/21)

> **Scope and naming.** UI Foundation Phase 1 is Design Contract only. It is
> independent of ADR-0018's completed Meeting/Research Phase 1 and does not
> reopen or extend that initiative. Option 1, Editorial Dossier, is selected;
> white Light Mode is the normative reference and adaptive Dark Mode remains
> mandatory. This phase authorizes exactly the three UI documentation files.
> Every implementation slice below requires separate explicit authorization.

## Purpose

This plan migrates the current native macOS UI toward the selected white
Editorial Dossier direction through small, reviewable, independently reversible
Pull Requests. It preserves accepted Meeting behavior, local-first policy,
evidence lineage, schema v10, and the existing modular-monolith dependency
direction.

This Phase 1 change creates only:

- [`UI_DESIGN_LANGUAGE.md`](UI_DESIGN_LANGUAGE.md);
- [`UI_SCREEN_INVENTORY.md`](UI_SCREEN_INVENTORY.md);
- this migration plan.

No implementation slice below is authorized merely because it appears here.

## Baseline and rollback

- Phase 1 branch point: `d786b3302a250a588e1c98e22a1b23ea3c37fd19`.
- Public remote: [`crescentln/BlueMinutes`](https://github.com/crescentln/BlueMinutes).
- The execution ledger was observed stale after merged PR #20; Phase 1 does
  not repair it.
- Each future slice requires its own Issue, short-lived branch, acceptance
  criteria, focused validation, and Pull Request.
- Each Pull Request parent is its rollback anchor.
- UI work must not share or modify the separate Issue #16 worktree.
- A Pull Request that introduces durable domain, policy, security, provider,
  Meeting, or Setup Guide state is not a UI-only slice and must follow the
  migration/backup/recovery gates below. Harmless reversible UI preferences
  have their own explicit defaults/removal tests.

## Ordering rules

1. Correct state ownership and draft safety before moving editors.
2. Add only design-system primitives consumed by the active slice.
3. Preserve current workflow contracts while changing presentation.
4. Add a control only when its action and state are real.
5. Keep schema, dependencies, entitlements, capabilities, provider routes,
   network behavior, and user-data semantics unchanged unless a separately
   authorized task explicitly changes them.
6. Keep Research capabilities immutable and default-off.
7. Do not raise the macOS 15 deployment target for optional macOS 26 visual
   effects; require availability guards and a complete macOS 15 fallback.
8. Do not combine documentation, state-safety, Settings, shell migration, and
   feature migration into one unreviewable Pull Request.

## Phase 1 — Design contract

**Scope**

- lock the selected white Editorial Dossier direction;
- define semantic tokens and component contracts;
- inventory current screens and states;
- define Settings/Setup Guide ownership;
- define the small-PR sequence and validation matrix.

**Changed files**

- `docs/UI_DESIGN_LANGUAGE.md`
- `docs/UI_SCREEN_INVENTORY.md`
- `docs/UI_MIGRATION_PLAN.md`

**Validation**

- local Markdown links resolve;
- reference screenshot paths and hashes match;
- Issue #21 scope matches the diff;
- only the three declared documentation files change;
- `git diff --check` passes;
- no source, tests, ledger, schema, dependency, configuration, workflow, or
  user-data file changes.

**Rollback**

- discard the three uncommitted files, or revert the future documentation
  commit if separately authorized.

## Future slice A — State and ownership safety

**Objective**

Make UI state safe before structural refactor.

**Candidate work**

- reset workspace-specific selection and drafts when the workspace changes;
- prevent a new workspace from remaining on an unavailable destination;
- add dirty-state tracking and navigation/selection protection for Transcript,
  Analysis, and Briefing editors;
- separate app-wide services from scene-local selection and draft state;
- decide whether the main workspace is a singleton `Window` or a scene-safe
  `WindowGroup`.

**Explicit exclusions**

- no visual redesign;
- no Settings;
- no schema change unless separately authorized after an ADR;
- no new provider, route, or persistence authority.

**Required tests**

- synthetic workspace A → workspace B isolation;
- prerequisite-invalid destination reset;
- dirty segment/position/section navigation;
- cancel/discard/save outcomes;
- multiwindow or singleton-window ownership behavior;
- existing workflow regression suite.

**Rollback**

- revert the slice to its parent; no data migration should be present.

## Future slice B — Consumed design-system primitives

**Objective**

Introduce the smallest token and component set needed by the shell.

**Candidate work**

- semantic colors, typography, spacing, radius, surfaces, motion, and density;
- sidebar row and section header;
- shared initial/loading/empty/blocked/ready/working/success/failure/stale
  states;
- semantic SF Symbol roles and availability fallbacks.

**Explicit exclusions**

- no new package target or dependency;
- no complete speculative component library;
- no workflow behavior change;
- no hard-coded light-only root background.

**Required tests**

- token/source structure tests where useful;
- component state coverage;
- Light/Dark rendering;
- Increase Contrast and Differentiate Without Color review;
- no direct persistence imports in `MeetingBuddyFeatures`.

**Rollback**

- remove only the newly consumed primitives and restore prior view styling.

## Future slice C — Native scene and Settings foundation

**Objective**

Establish explicit scene ownership and a real native Settings destination.

**Candidate work**

- add a SwiftUI `Settings` scene;
- add safe appearance preferences for system/Light/Dark, density, reading
  width, and default inspector presentation;
- use `@AppStorage` only for harmless UI preferences;
- use scene storage or view state only for non-sensitive presentation state as
  appropriate;
- retain meaningful window title, restoration, minimum size, and native
  sidebar commands.

**Initial Settings content**

- General and Appearance may contain real mutable UI preferences;
- Privacy & Storage, Processing & Models, Recording, and Advanced may show only
  real status/actions supplied by application services;
- omit any control whose action is not implemented.

**Explicit exclusions**

- no credentials outside Keychain;
- no provider/external-route authority in `@AppStorage`;
- no remembered recording consent;
- no classification, retention, evidence, citation, or human-confirmation
  policy in UI defaults;
- no reuse of `AutomationSettingsValues` as app preferences;
- no Setup Guide or Meeting-specific persistence;
- no Research capability toggles.
- no workspace paths/bookmarks, Meeting IDs/content, draft text,
  classification, evidence, credentials, or policy values in `@AppStorage` or
  scene storage.

**Required tests**

- Settings scene and Command-Comma presence;
- defaults and preference round trip;
- old-default compatibility;
- independent window/scene state;
- initial or restored selection loads the corresponding application review
  after workspace restoration; if that lifecycle is not implemented, selection
  restoration remains disabled;
- protected-value absence from `UserDefaults`;
- protected/sensitive-value absence from scene restoration;
- Light/Dark and larger-text review.

**Rollback**

- remove the Settings scene and UI-only preference keys. Defaults must make
  removal safe without a data migration.

## Future slice D — Editorial main-window shell

**Objective**

Apply the selected global hierarchy without migrating feature internals.

**Candidate work**

- widen and group the existing sidebar so primary labels remain legible;
- keep workspace and current Meeting context stable when real;
- introduce a focused editorial canvas container;
- add a selection-driven optional inspector shell only with real content;
- add toolbar structure and focused command routing;
- retain the existing eight workflow destinations until replacements are
  backed by application contracts.

**Conceptual controls to omit initially**

- Overview;
- global Meeting list or global search;
- Meeting Setup;
- Add Note;
- generic Open Source;
- commitment checkboxes;
- actions that bypass existing workflow prerequisites.

**Required tests**

- exact current destination availability and order, unless separately
  authorized by the maintainer and reflected in the Issue;
- sidebar labels at 860×600 and 1080×720;
- inspector open/closed resizing;
- toolbar collapse and menu fallback;
- keyboard selection and focus restoration;
- no behavior or evidence-lineage regression.

**Rollback**

- restore the prior root shell while retaining independent state-safety fixes.

## Future slice E — Intake surfaces

Migrate Local Media, Recording, and UN Web TV separately or in tightly bounded
Pull Requests.

### Local Media gates

- all required metadata and track choices remain available;
- preflight validation explains blocked import before activation;
- Task Manager progress/cancel/retry remains intact;
- route and managed-source proof remain inspectable;
- no source path becomes durable or publicly visible.

### Recording gates

- microphone/application-audio checking, denied, unavailable, ready, recording,
  stopping, completed, incomplete, and failed states are distinct;
- persistent Stop remains reachable from every destination;
- recording acknowledgement remains per session;
- crash/recovery semantics do not change.

### UN Web TV gates

- explicit authorization remains mandatory;
- metadata-only boundary remains explicit;
- no download/streaming behavior appears;
- candidate/review/fallback states remain distinct;
- Save/Apply/Discard appears only with a real application contract;
- no affiliation or endorsement implication.

**Rollback**

- revert one intake surface at a time; no semantic or stored data migration.

## Future slice F — Transcript review

**Candidate work**

- preserve list/detail and add the Editorial Dossier visual hierarchy;
- add the consumed evidence badge and anchor presentation without new evidence
  semantics;
- add focused previous/next/save commands;
- integrate an exact-evidence inspector backed by existing evidence contracts;
- provide visible draft and saved state;
- improve route and coverage progressive disclosure.

**Required gates**

- deterministic 100 percent source-segment coverage;
- exact correction provenance;
- dirty-draft protection;
- keyboard-only segment selection/edit/save;
- bounded playback only if a real playback contract is added;
- large transcript performance and selection stability.

**Rollback**

- revert presentation and inspector integration without changing published
  transcript revisions.

## Future slice G — Analysis and Briefing

Analysis and Briefing should be separate Pull Requests when either diff becomes
large.

### Analysis gates

- claims/positions use a readable list/detail structure;
- add evidence badge/anchor components here if they were not already consumed
  by the Transcript slice;
- exact evidence is inspectable;
- confidence and human confirmation remain distinct;
- correction draft safety is proven;
- source/extraction/inference/human-confirmed provenance is preserved.

### Briefing gates

- the white editorial canvas becomes the primary reading/editing surface;
- the dossier read mode renders the real three-section Briefing contract rather
  than the mock's illustrative four headings;
- section drafts are protected;
- stale and validation states explain export eligibility;
- evidence anchors retain exact references;
- Generate Briefing uses existing policy and Task Manager gates;
- contract-backed commitments/decisions may appear as document content, but
  status controls remain noninteractive until an application-owned
  mutation/update action is separately authorized.

The first Briefing visual migration should preserve the existing
confirmation, edit, per-section regeneration, stale warning, and export
actions. A shared evidence inspector is a later slice unless the same Pull
Request adds the required application-owned read projection without expanding
scope beyond review.

**Rollback**

- restore each prior feature view; immutable semantic revisions and exact
  evidence references remain untouched.

## Future slice H — History and Storage

### History gates

- initial/loading/empty/results states are distinct;
- local deterministic filtering and comparison remain unchanged;
- learned presentation preferences retain repository semantics;
- moving their UI to Settings does not change authority or audit history.

### Storage gates

- usage, integrity, Trash, restore, and permanent deletion remain exact;
- permanent deletion keeps explicit confirmation and erasure limitations;
- all writes remain routed through Storage Service;
- no decorative dashboard obscures exact storage state.

**Rollback**

- revert presentation only; no file, Trash, recovery, or database mutation is
  performed by rollback.

## Future slice I — Visual and accessibility closure

This slice adds and verifies the durable proof system after the shell and
feature surfaces stabilize.

### Synthetic screenshot matrix

The matrix scales by the scope of the Pull Request:

- every changed surface: Light and Dark at the canonical 1440×1024 viewport;
- a shell/sidebar/toolbar/inspector change: all minimum viewports below, with
  inspector open and closed where applicable;
- a changed state-bearing surface: every changed representative state below at
  the canonical viewport, plus the narrowest viewport for the most constrained
  state;
- accessibility appearances: representative text-heavy, form, list/detail,
  destructive, and inspector stress surfaces rather than an implied full
  Cartesian product;
- a Pull Request may require a broader matrix in its Issue, but may not silently
  sample less than this mapping.

Minimum viewports for shell-affecting changes:

- 860×600;
- 1080×720;
- 1440×1024;
- one expanded desktop width.

Minimum appearances across the mapped surfaces:

- Light Mode white Editorial Dossier;
- Dark Mode;
- Increase Contrast;
- Reduce Transparency;
- Differentiate Without Color.

Minimum state families when changed:

- onboarding;
- Local Media ready and working;
- Recording ready and active;
- UN Web TV blocked and candidate;
- Transcript selected segment and incomplete coverage;
- Analysis selected claim and stale;
- Briefing selected section and export blocked;
- History empty and results;
- Storage healthy and destructive confirmation;
- Settings General and Appearance;
- Inspector open and closed;
- representative loading, empty, blocked, failure, and disabled-reason states.

All screenshot fixtures must be synthetic, privacy-reviewed, dimension-checked,
and free of credentials, real meetings, private paths, and identifiable user
metadata.

### Visual regression policy

- replace generated concepts with native runtime captures before treating a
  screen as an implementation golden;
- pin and record the capture OS, Xcode, locale, time zone, accent, appearance,
  animation state, text size, and deterministic fixture seed;
- use offline synthetic fixtures with provider/model routes stubbed or
  disabled and without accepting new TCC permissions;
- normalize or explicitly account for Display P3 versus sRGB;
- produce future goldens as fixed-dimension 8-bit sRGB PNGs with an embedded
  profile, no alpha, and no variable timestamps, paths, or identifying
  metadata;
- store viewport, appearance, locale, text size, and data-fixture metadata;
- compare deterministic app content, not variable window shadows or system
  rendering outside the owned surface;
- make dimension/profile mismatch a hard failure;
- have the first visual-harness Pull Request calibrate and record perceptual
  and per-pixel thresholds against repeated native captures; thresholds must
  not be loosened merely to accept a changed design;
- publish expected, actual, and diff artifacts for failures;
- remove fixture nondeterminism rather than masking unstable regions;
- update a baseline only with a stated design reason and reviewer approval;
- never update baselines automatically;
- a file signature or minimum byte count is not pixel or accessibility proof.

### Accessibility closure

- runtime accessibility-tree inspection;
- VoiceOver order, labels, values, hints, and announcements;
- full keyboard traversal and focused command routing;
- visible focus in Light/Dark and Increase Contrast;
- larger-text reflow;
- Reduce Motion behavior;
- no color-only state;
- resized window and inspector behavior.

**Rollback**

- restore the parent visual harness and approved native goldens while
  preserving all previously accepted accessibility and behavior gates;
- do not weaken thresholds, remove tests, delete required states, or mask
  unstable regions merely to make rollback or comparison pass.

## Global validation matrix

Every implementation Pull Request must run the narrowest focused tests plus the
repository-required complete gates appropriate to its behavior.

| Plane | Required proof |
| --- | --- |
| Git/scope | Exact Issue, branch, allowlisted diff, `git diff --check`, no unrelated work |
| Build/test | Swift 6 warning-as-error build and applicable complete tests |
| Architecture | Dependency direction and application-owned mutation paths preserved |
| Behavior | Current workflow acceptance and new regression tests |
| Evidence | Exact evidence lineage and 100 percent coverage rules preserved |
| Privacy | Synthetic fixtures, no paths/content/credentials in logs or screenshots |
| Policy | No visual control weakens classification, provider, retention, network, or confirmation authority |
| Persistence | Schema v10 unchanged unless a separate migration task is explicitly authorized |
| Platform | macOS 15 minimum, availability guards for newer decoration |
| Visual | Target viewports, Light/Dark, inspector, state matrix |
| Accessibility | Keyboard, VoiceOver, focus, contrast, motion, larger text |
| Packaging | No signing, notarization, packaging, installation, upload, or distribution unless separately authorized |

## Persistent-change escalation gate

If a future Settings or Setup Guide slice needs durable non-UI state, stop and
obtain separate authorization for:

- an accepted ADR;
- explicit ownership and authority;
- an ordered backward-compatible migration;
- verified pre-migration backup;
- schema-v10 and declared supported-prior-state tests;
- failure injection and close/reopen recovery;
- unknown-future-schema rejection;
- byte preservation for existing semantic revisions, pointers, dependencies,
  Meetings, managed-file references, recovery records, and files;
- a tested rollback using the supported prior binary and data state.

Do not predeclare a new schema version in a UI Pull Request.

## Completion definition

The UI migration is complete only when:

- the selected Editorial Dossier hierarchy is implemented with real controls;
- every current workflow remains behaviorally accepted;
- evidence and policy boundaries remain exact;
- Settings and Setup Guide ownership are proven;
- the visual and accessibility matrix passes;
- the working tree, Issue, Pull Request, tests, and runtime evidence agree.

Document presence or a visually similar screenshot alone is not completion.
