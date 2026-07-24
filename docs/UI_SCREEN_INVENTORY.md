# BlueMinutes UI Screen Inventory

Status: Phase 1 design contract; current-state inventory and target mapping
Owner: Codex, under maintainer authorization
Last updated: 2026-07-24
Tracking: [GitHub Issue #21](https://github.com/crescentln/BlueMinutes/issues/21)

> **Scope and naming.** UI Foundation Phase 1 is Design Contract only. It is
> independent of ADR-0018's completed Meeting/Research Phase 1 and does not
> reopen or extend that initiative. The selected direction is Option 1,
> Editorial Dossier, with a white Light Mode reference and required adaptive
> Dark Mode. Only the three UI contract documents are authorized; current and
> target entries below do not authorize implementation.

## Purpose

This document inventories the current native macOS UI, its meaningful states,
and its mapping to the selected white Editorial Dossier direction. It prevents
visual migration from silently removing accepted behavior or inventing
unsupported controls.

Current runtime truth remains governed by
[`CURRENT_ARCHITECTURE.md`](CURRENT_ARCHITECTURE.md), accepted ADRs, and source.
Target UI principles are defined in
[`UI_DESIGN_LANGUAGE.md`](UI_DESIGN_LANGUAGE.md). Migration order and gates are
defined in [`UI_MIGRATION_PLAN.md`](UI_MIGRATION_PLAN.md).

Each entry distinguishes:

- **Current** — verified source/runtime structure;
- **Contract target** — the selected design direction;
- **Separately gated** — behavior that must not appear until a later explicit
  authorization supplies real application contracts and tests.

## Current scene and window inventory

| Surface | Current implementation | Target direction | Proof gap |
| --- | --- | --- | --- |
| Main application scene | One `WindowGroup`, default 1080×720 | One stable Editorial Dossier main workspace | Multiwindow state ownership is unresolved |
| Main navigation | `NavigationSplitView` sidebar and detail | Sidebar, editorial canvas, optional inspector | Shared inspector is not implemented |
| Window minimum | 860×600 at root view | Preserve a tested practical minimum | Real resizing was not exercised in Phase 0 |
| Toolbar | Global working spinner only | Context, real search/setup actions, primary action, inspector visibility | Commands and collapse behavior are unimplemented |
| Commands | `SidebarCommands`, plus a few view shortcuts | Native app/view/meeting commands with focused routing | No menu/shortcut collision proof |
| Settings | No `Settings` scene | Native six-pane Settings scene | Storage/ownership contracts are unresolved |

The current app-owned `MediaReviewStore` is shared by every `WindowGroup`
instance. Before adding scene-specific selection, Settings, or additional
windows, implementation must choose and test one of:

- a singleton main `Window` with app-owned workflow state; or
- a `WindowGroup` with clearly separated app-wide services and scene-local UI
  selection/drafts.

No migration may accidentally create multiple windows that mutate one shared
draft without visible coordination.

The current app has no `@AppStorage`. Its direct `UserDefaults` use is the
dedicated security-scoped workspace bookmark. That narrow access mechanism is
not precedent for storing policy or general preferences in `UserDefaults`.

## Current sidebar navigation

The implemented workflow order is:

1. Local Media
2. Record Audio
3. UN Web TV Metadata
4. Transcript Review
5. Analysis Review
6. Briefing
7. Meeting History
8. Storage

Transcript, Analysis, and Briefing are disabled until their prerequisites are
available. The current sidebar does not present the disabled reason.

### Target grouping

The selected visual direction uses these conceptual groups:

- **Workspace** — current validated local workspace and a real switch action;
- **Meeting** — current Meeting and, only when backed by a query, recent/all
  Meetings;
- **Workflow** — intake, recording, transcript, analysis, and briefing;
- **Library** — history and storage;
- **Trust footer** — concise local-only and storage status.

Initial shell migration may retain the exact current eight destinations while
improving width, grouping, state explanation, and Meeting context. It must not
invent Overview, current Meeting, recent Meetings, or All Meetings before
application contracts supply those values.

## Screen inventory

### Workspace onboarding

**Current purpose:** select or create a user-authorized local workspace.

**Current states:**

- no workspace selected;
- workspace restore/selection working through the global activity state;
- workspace ready;
- workspace switch blocked while recording;
- global error alert.

**Target requirements:**

- distinguish initial, restoring, ready, and failure;
- keep workspace paths private by default;
- expose a real choose/retry action;
- never fabricate a “recent workspace” list;
- preserve security-scoped bookmark behavior.

### Local Media

**Current purpose:** create a Meeting profile, select audio/video, review
tracks, import managed media, and run canonical processing.

**Current states:**

- meeting/source policy form;
- no source;
- pending source and track selection;
- managed source proof;
- queued/running progress;
- failure;
- cancelled;
- completed;
- retry/cancel availability.

**Target requirements:**

- use an editorial setup flow rather than nested `GroupBox` and grouped `Form`
  surfaces;
- keep Meeting metadata visible without turning every field into a card;
- disable or explain unavailable import actions before validation alerts;
- move exact route/proof detail into progressive disclosure;
- preserve Task Manager cancellation, retry, and publication semantics.

### Recording

**Current purpose:** inspect capture capability, collect Meeting/capture
settings, obtain explicit recording acknowledgement, record, stop, and recover.

**Current states:**

- microphone permission checking/allowed/denied;
- application-audio capability;
- setup ready/blocked;
- recording;
- stopping/finalizing;
- completed;
- incomplete/recoverable;
- failed.

**Target requirements:**

- separate checking from unavailable;
- keep the persistent Stop affordance visible from every workflow;
- use words and iconography in addition to red recording color;
- keep legal acknowledgement session-specific;
- never offer a remember-consent or automatic-permission control.

### UN Web TV Metadata

**Current purpose:** fetch metadata-only information after explicit
authorization, review candidate provenance, and provide manual-fallback
guidance.

**Current states:**

- URL empty/invalid/ready;
- authorization not acknowledged/acknowledged;
- fetching;
- candidate available;
- review draft;
- failure;
- manual-fallback guidance without a manual-create/save action.

**Target requirements:**

- distinguish invalid URL, missing authorization, working, and unavailable;
- keep destination and restriction visible but concise;
- provide Save/Apply/Discard only after a real application action exists;
- do not add media download, streaming, or implied affiliation;
- do not expose an “Open Source” action until the application owns its safe
  semantics.

### Transcript Review

**Current purpose:** choose an eligible route or manual fallback, run
transcription/translation, inspect segments, and publish human corrections.

**Current states:**

- setup;
- route eligible/blocked;
- model availability checking/ready/unavailable;
- manual transcript/translation fallback;
- queued/running progress;
- failure/cancel/retry;
- no segment selected;
- segment selected;
- unprotected local transcript/translation/speaker draft;
- published correction;
- coverage complete/incomplete.

**Target requirements:**

- preserve the existing list/detail strength;
- add explicit dirty state and leave/selection protection before visual
  refactor;
- provide previous/next segment and save commands through focused values;
- use an evidence inspector for exact source, correction provenance, and
  downstream references only when backed by real contracts;
- prove 100 percent source-segment coverage before publication.

### Analysis Review

**Current purpose:** run bounded analysis, review confirmation/coverage, inspect
cards and positions, and publish corrections.

**Current states:**

- setup and route proof;
- queued/running;
- failure/cancel/retry;
- confirmation required/confirmed;
- quarantined or otherwise publication-blocked review;
- coverage complete/incomplete;
- cards displayed; position unselected/selected;
- unprotected local correction draft;
- stale/fresh;
- published correction.

**Target requirements:**

- use list/detail for claims and positions;
- add dirty-draft protection before moving editors;
- expose exact evidence rather than only evidence counts;
- preserve the difference among extraction, inference, correction, and
  human-confirmed fact;
- do not add a general note or task model.

### Briefing

**Current purpose:** run briefing generation, review source and validation
proof, edit sections, preview Markdown, and export accepted output.

**Current states:**

- setup and route proof;
- queued/running;
- failure/cancel/retry;
- no section selected;
- section selected;
- unprotected local section edit draft;
- review required;
- human-confirmed dossier;
- validation incomplete/complete;
- stale/fresh;
- per-section regeneration;
- export blocked/ready/completed.

**Target requirements:**

- make the editorial canvas the primary Briefing surface;
- protect section drafts before selection/navigation changes;
- keep evidence anchors attached to material claims;
- explain stale and export-blocked states at the action;
- route Generate Briefing through existing prerequisites and Task Manager;
- render application-projected commitments/decisions as briefing content when
  available; keep status controls noninteractive until an application-owned
  mutation action is separately authorized.

The current Briefing contract has three template section types. The four
headings shown in the selected mock are illustrative composition, not a new
runtime schema. A shared evidence inspector also needs an application-owned
read projection; the current Briefing review bundle alone is not sufficient.

### Meeting History

**Current purpose:** build/query the local history index, filter published
positions, compare evidence-qualified revisions, and manage learned
presentation preferences.

**Current states:**

- index unavailable/building/ready/failed;
- query initial/loading/empty/results;
- result selected;
- comparison unavailable/qualified;
- preference list empty/populated;
- preference mutation working/failed.

**Target requirements:**

- distinguish initial from empty search results;
- preserve deterministic local filters and evidence qualification;
- move app-wide presentation preferences to an appropriate Settings surface
  only if their repository semantics remain intact;
- do not convert learned preferences into security, policy, provider, or
  instruction authority.

### Storage

**Current purpose:** show workspace usage/integrity and manage recoverable Trash
and confirmed permanent deletion.

**Current states:**

- loading;
- report unavailable;
- report ready;
- integrity healthy/degraded;
- Trash empty/populated;
- restore ready/working/failed;
- permanent delete blocked/confirming/working/completed/failed.

**Target requirements:**

- use a clear ledger/list rather than decorative metric cards;
- keep exact deletion limitations in the confirmation;
- distinguish loading from report-not-loaded;
- explain disabled permanent deletion;
- route every mutation through the Storage Service.

## Shared state vocabulary

Every screen maps its feature states onto:

| Shared state | Meaning | Required presentation |
| --- | --- | --- |
| `initial` | No attempt has started | Neutral explanation and real start action |
| `loading` | Existing state is being obtained | Labeled progress; no false empty state |
| `empty` | A successful query returned no items | Scope-specific explanation and next action |
| `blocked` | A prerequisite or policy denies the action | Exact reason and smallest remedy |
| `ready` | The action can begin | Clear primary action |
| `working` | Task or synchronous work is active | Labeled progress, cancellation when supported |
| `success` | Operation completed | Result and next action |
| `failure` | Operation failed | Contextual error and real recovery action |
| `stale` | Exact upstream input was superseded | Input reason and regeneration/review path |

Disabled controls without a visible or accessible reason fail the contract.

## Evidence inspector inventory

The inspector is selection-driven. Potential sections are included only when
the selected object supplies them:

- Source identity and provenance class;
- exact source revision;
- exact time, page, paragraph, or segment location;
- excerpt and language/translation status;
- machine/human derivation;
- confidence, separately from confirmation;
- human correction and confirmation state;
- stale/dependency status;
- downstream references;
- authorized reveal/playback action.

The initial inspector may be read-only. `Add Note`, generic editing, and source
opening are omitted until real application contracts exist.

The current Briefing review bundle does not supply a complete inspector-ready
projection. A later application-owned resolver must obtain exact
evidence/source/transcript revisions. The view must never query SQLite
directly.

## Settings inventory

Settings is an app-wide native scene. Per-Meeting Setup remains in the main
Meeting workflow.

| Pane | App-wide content | Storage/authority | Initial implementation rule |
| --- | --- | --- | --- |
| General | safe launch and presentation behavior | `@AppStorage` or scene state only when harmless | No workspace path or Meeting policy |
| Appearance | system/Light/Dark choice, density, reading width, default inspector presentation | `@AppStorage` for safe UI preferences | Light Mode defaults to the selected white editorial composition |
| Privacy & Storage | workspace, retention, Trash, telemetry/no-outbound status | application policy/repository services | Read-only status until a real mutation contract exists |
| Processing & Models | installed local capability and policy-eligible route | model-policy router and provider interfaces | No cloud/provider selector without approved adapter and authority |
| Recording | permission/capture status and an optional harmless preferred device | capture/permission services | Effective capture selection, authority, and consent remain session-specific |
| Advanced | redacted diagnostics, maintenance actions, Automation status, reset UI preferences | application services | No fake updater, connector, encryption, distribution, or provider controls |

### Never app preferences

These values must not be stored in `@AppStorage`:

- credentials or tokens;
- workspace bookmarks or raw paths;
- Meeting classification or access policy;
- provider or external-route authority;
- retention or evidence policy;
- recording authorization or remembered consent;
- citation or human-confirmation authority;
- Research capability flags;
- full compiled prompts.

### Per-Meeting Setup Guide

The Setup Guide collects and edits structured input for:

- Meeting title and collection of a per-Meeting classification input through
  application-owned policy services;
- source and language configuration;
- capture sources and transcript preferences;
- briefing template and evidence density;
- structured user instructions beneath protected policy;
- prospective creation of an immutable configuration revision and hash through
  application/compiler/repository services.

The Setup Guide cannot persist, compile, or override classification, access
policy, provider authority, recording authority, retention, evidence, or
outbound-network policy on its own. Effective capture source is chosen per
Meeting/session; an app-wide preferred recording device is only a reversible
hint. Permission, authority, and acknowledgement remain service-governed and
session-specific. Immutable instruction snapshots remain compiler/repository
owned.

The current instruction-profile model has no Meeting-specific scope. A future
Setup Guide implementation needs an explicit compatible design decision; it
must not misuse `researchWorkspace` or hide Meeting configuration in Settings.
Setup changes apply prospectively; existing outputs retain their exact
immutable configuration and instruction snapshots.

## Menu and keyboard target inventory

| Command | Current | Target contract |
| --- | --- | --- |
| Choose Workspace | Command-O | Preserve |
| Choose Media | Command-I | Preserve while Local Media is focused |
| Import/Process | Command-Return | Preserve with focused routing |
| Refresh Storage | Shift-Command-R | Preserve while Storage is focused |
| Toggle Sidebar | Native `SidebarCommands` | Preserve |
| Settings | Absent | Native Settings scene and Command-Comma |
| Toggle Inspector | Absent | Add when inspector exists |
| Find/Search | History-scoped UI only | Add only with explicit scope and results |
| Save Correction | Absent | Add after dirty-draft state exists |
| Previous/Next Segment | Absent | Add for transcript-focused selection |
| Record/Stop | No command | Add only with safe, state-aware command routing |
| Export Briefing | View action | Add only while an eligible Briefing is focused |

Commands must use focused values or equivalent scene-aware routing. A command
must not activate an unrelated workflow or shared-window draft.

## Accessibility and visual proof inventory

Current source includes useful labels, hints, textual status, native controls,
and destructive confirmations. Current automated coverage primarily checks
source strings and structure.

Missing proof includes:

- runtime accessibility tree;
- VoiceOver order, labels, values, and announcements;
- full keyboard traversal and focus restoration;
- visible focus in Light and Dark Mode;
- Increase Contrast and Differentiate Without Color;
- Reduce Transparency and Reduce Motion;
- larger text and primary-label truncation;
- 860×600, 1080×720, 1440×1024, and expanded-window layouts;
- Inspector open/closed resizing;
- deterministic screenshot color profile and pixel comparison.

## Large-file and refactor inventory

The visual migration must avoid expanding current large boundaries:

- `MediaReviewStore.swift` owns state and actions across every workflow;
- `AppMediaReviewWorkflow.swift` combines many application-composition paths;
- `MeetingBuddyRootView.swift` combines shell and Local Media content;
- Analysis, History, Transcript, and Briefing views each contain multiple
  responsibilities.

Refactors must extract by ownership and behavior, not by arbitrary line count.
Dirty-draft and workspace-reset safety should precede moving editors.

## Explicitly absent or conceptual

The selected mock visually suggests capabilities that are not current runtime
truth. Until separately authorized and implemented, the product inventory does
not include:

- an Overview destination;
- a global Meeting list or global search;
- a per-Meeting Setup Guide;
- a shared evidence inspector;
- a general note system;
- a commitment/task tracker;
- unrestricted source opening;
- a cloud provider/account surface;
- visible Research or Conversation routes.
