# BlueMinutes UI Design Language v1

Status: Phase 1 design contract; selected direction, not runtime implementation
Owner: Codex, under maintainer authorization
Last updated: 2026-07-24
Tracking: [GitHub Issue #21](https://github.com/crescentln/BlueMinutes/issues/21)

> **Scope and naming.** UI Foundation Phase 1 is Design Contract only. It is
> independent of ADR-0018's completed Meeting/Research Phase 1 and does not
> reopen or extend that initiative. The selected direction is Option 1,
> Editorial Dossier. Light/white is the normative reference baseline,
> implemented through semantic system colors and materials; Dark Mode remains
> required. This phase authorizes only this document,
> `UI_SCREEN_INVENTORY.md`, and `UI_MIGRATION_PLAN.md`. Every implementation
> group requires separate explicit authorization.

## Purpose

This document defines the durable visual and interaction contract for the
BlueMinutes native macOS application. It freezes the maintainer-selected
**Editorial Dossier** direction from UI Foundation Phase 0 and records the
boundaries that later implementation Pull Requests must preserve.

The selected direction is:

- a calm white editorial canvas in Light Mode;
- system-adaptive Dark Mode support, rather than a fixed light-only theme;
- stable Meeting context in a native sidebar;
- content-first reading and editing in the primary pane;
- an optional evidence and provenance inspector;
- restrained BlueMinutes blue for selection, focus, action, and evidence links;
- native macOS structure and behavior before custom decoration.

This document does not claim that the selected mockup is implemented. It does
not authorize source, test, schema, dependency, entitlement, provider,
network, persistence, or user-data changes.

## Governing product character

BlueMinutes serves diplomats, multilateral practitioners, and policy
researchers who need to move from source material to reviewable, evidence-linked
meeting outputs. The interface must be:

- **calm**: low visual noise, deliberate spacing, and no decorative dashboard;
- **editorial**: typography and document hierarchy lead the eye;
- **evidence-first**: material claims expose exact source and provenance;
- **professional**: precise labels, restrained motion, and predictable commands;
- **trustworthy**: policy, stale, confirmation, and local-only states are
  visible and never implied by color alone;
- **local-first**: local processing is the baseline and external processing is
  never made to look authorized by a visual selector;
- **native**: SwiftUI and narrow AppKit interop follow macOS conventions.

Public presentation uses **BlueMinutes**. Compatibility-sensitive modules,
executables, bundle identifiers, database names, commands, protocols, and
formats may continue to use **MeetingBuddy**.

[`BRAND.md`](BRAND.md) remains the brand source of truth for the approved
BlueMinutes name, lockup, app icon, compatibility naming, and independence
language. UI work must not imply United Nations, government, OpenAI, or other
institutional affiliation or introduce maps, globes, wreaths, flags, seals,
crests, or UN-emblem motifs.

## Reference evidence

| Reference | Role | Image contract | SHA-256 |
| --- | --- | --- | --- |
| [`assets/screenshots/local-media.png`](assets/screenshots/local-media.png) | Committed synthetic current-state reference, not a target golden | 2384×1664, 8-bit Display P3, alpha | `fc6c06ddbba4e14aadcfe92921719034d281e61848cecf2a1089811e98b6b282` |
| [`assets/screenshots/un-web-tv-metadata.png`](assets/screenshots/un-web-tv-metadata.png) | Committed synthetic current-state reference, not a target golden | 2384×1664, 8-bit Display P3, alpha | `61f86aebf6ee8241182fa66e193aa3c5266519c47df608e195bed2b7056c1266` |
| `option-1-editorial-dossier-1440x1024.png` | Selected Phase 0 visual direction; external design artifact, not committed product evidence | 1440×1024, 8-bit sRGB, no alpha | `38c10b4b95fb0bfff82b7d69691d4a69b1cfc1c1d432ea99d9dc574388d1db9e` |

The two committed screenshots contain synthetic data and establish only
current Light Mode reference evidence. Their Display P3/alpha encoding and
pre-redesign layout mean they are not future visual-regression goldens. The
selected Phase 0 mockup also contains synthetic fictional content and no real
user or Meeting data. It is visual design evidence, not proof of behavior,
accessibility, policy authority, or data support.

## Design principles

### 1. A Meeting is the stable context

The sidebar and toolbar should keep the current workspace and Meeting legible
while the user moves among intake, recording, transcript, analysis, briefing,
history, and storage. Workflow tools must not erase Meeting context.

No Meeting list or current-Meeting control may appear until it is backed by a
real application-owned query and selection contract.

### 2. Evidence is a first-class navigation path

Claims, transcript corrections, analysis positions, and briefing sections
should expose evidence anchors that open an inspector or navigate to the exact
source location. `EvidenceRefV1` remains the typed evidence-locator authority.
The UI must not invent a duplicate citation model.

### 3. Content hierarchy precedes containers

Use headings, readable line length, spacing, separators, and native selection
before adding a container. A `GroupBox`, card, bordered editor, or elevated
surface must represent a real semantic grouping, not compensate for weak
typography.

Nested cards, card grids for ordinary form fields, and a rounded container
around every paragraph are prohibited.

### 4. White means an editorial canvas, not a hard-coded application

The maintainer selected a white visual direction. In Light Mode, the primary
reading and editing canvas should resolve to a quiet white system-appropriate
surface. The sidebar, toolbar, inspector, and secondary regions retain native
system materials and separation.

The whole application must not be painted with a fixed white RGB value. Dark
Mode, Increase Contrast, Reduce Transparency, and system accent choices remain
supported. The white preference controls the Light Mode composition, not the
availability of other system appearances.

### 5. Trust states are exact and redundant

Local-only, external-route eligibility, stale input, incomplete coverage,
machine transcription, human correction, AI extraction, AI inference, and
human-confirmed fact remain distinct. Each state uses:

- a short text label;
- an SF Symbol or other non-color indicator when helpful;
- a semantic color only as reinforcement;
- an accessible label and value;
- a concise explanation or recovery action when blocked.

Confidence must never be styled as confirmation. Human confirmation must not
be inferred from high confidence.

### 6. Advanced detail appears progressively

The primary canvas shows the minimum policy and provenance needed to make the
current decision. Exact time ranges, source revision, provider route,
retention, access-policy revision, and technical proof belong in an inspector,
popover, or disclosure group when they are not the current task.

Progressive disclosure must not hide a required authorization, destructive
effect, data destination, retention consequence, or failure reason.

### 7. Native behavior is part of the design

The visual language includes:

- macOS menu commands and standard shortcuts;
- a resizable main window with a meaningful minimum size;
- sidebar and inspector visibility commands;
- keyboard focus and selection;
- system restoration of non-sensitive presentation state unless a later scene
  contract says otherwise;
- standard Settings presentation;
- native controls, SF Symbols, and semantic materials;
- optional macOS 26 visual enhancements behind availability guards, with a
  complete macOS 15 fallback rather than a raised deployment target.

UI defaults and scene restoration must not contain workspace paths or
bookmarks, Meeting identifiers or content, draft text, classification,
evidence, credentials, or policy values.

### 8. Accessibility is an implementation gate

Every migrated surface must prove keyboard-only operation, VoiceOver labels
and reading order, visible focus, Increase Contrast, Reduce Transparency,
Reduce Motion, Differentiate Without Color, larger text, Light/Dark Mode, and
window resizing. Source-string assertions alone are not accessibility proof.

## Bear inspiration boundary

Bear is a design-language reference, not an implementation source.

| Borrow as a principle | Translate for BlueMinutes | Do not copy |
| --- | --- | --- |
| Stable multi-column hierarchy | Meeting context, editorial canvas, evidence inspector | Notes/tags information architecture or exact column widths |
| Content-first reading | Briefing, transcript, and analysis lead the window | Bear text, screenshots, or pixel-identical layout |
| Calm typography and whitespace | Professional policy-document rhythm | Bear fonts, red palette, icon, or brand personality |
| Restrained accent use | BlueMinutes blue for selection, focus, action, and evidence | Bear colors, proprietary icons, or assets |
| Progressive disclosure | Exact policy and provenance appear when relevant | Bear component code or interaction copies |

All production code and assets must be independently implemented under the
project's reviewed dependencies and licenses.

## Main-window composition

The selected target has four persistent regions:

1. **Toolbar** — workspace/Meeting context, search when real, setup when real,
   primary workflow action, and inspector visibility.
2. **Sidebar** — workspace, Meeting context, workflow groups, and local-only
   status. The initial implementation may preserve the current workflow list
   until a real Meeting query exists.
3. **Editorial canvas** — the primary reading or editing surface. It uses a
   comfortable line length and expands responsibly without leaving arbitrary
   unused desktop space.
4. **Evidence inspector** — optional, selection-driven, and read-only by
   default. Editing actions appear only when application contracts support
   them.

The sidebar, canvas, and inspector form a desktop hierarchy. They are not three
independent card columns.

### Layout targets

These are design targets to validate against native behavior, not hard-coded
window assumptions:

| Region | Minimum | Preferred | Maximum/behavior |
| --- | --- | --- | --- |
| Sidebar | 240 pt | 280 pt | 320 pt; primary labels remain legible |
| Editorial canvas | 560 pt usable detail | 680–760 pt reading measure | center or align within available detail width |
| Inspector | 280 pt | 312 pt | 360 pt; collapse before crushing the canvas |

At the current 860×600 minimum, the inspector should normally be closed or
temporarily presented. At 1440×1024, the selected three-region composition
should fit without horizontal scrolling. Wider windows add breathing room
around the reading measure rather than stretching paragraphs edge to edge.

Use SwiftUI's native inspector presentation when it satisfies the interaction
and resizing contract. Do not paint a third column merely to resemble the
mockup.

## Semantic token taxonomy

The future `Sources/MeetingBuddyFeatures/DesignSystem` directory should remain
inside the existing `MeetingBuddyFeatures` target. It is not a new module or
dependency.

### Color

| Token | Intended use | Native mapping rule |
| --- | --- | --- |
| `color.text.primary` | titles and primary content | `.primary` |
| `color.text.secondary` | metadata and supporting copy | `.secondary` |
| `color.text.tertiary` | low-emphasis timestamps and hints | semantic tertiary style |
| `color.accent` | selection, focus, primary action, evidence link | application accent / BlueMinutes blue |
| `color.surface.window` | main window background | system window background |
| `color.surface.sidebar` | navigation region | native sidebar material/list |
| `color.surface.canvas` | Light Mode white editorial canvas | dynamic text/content background |
| `color.surface.inspector` | evidence inspector | system control/window background |
| `color.surface.raised` | a true elevated semantic group | system material; use sparingly |
| `color.separator` | pane and section separation | system separator |
| `color.state.info` | informative state | semantic system color plus label |
| `color.state.success` | completed/verified state | semantic system color plus label |
| `color.state.warning` | incomplete, stale, or attention state | semantic system color plus label |
| `color.state.error` | failed/unsafe state | semantic system color plus label |
| `color.state.disabled` | unavailable action | native disabled state plus reason |
| `color.provenance.source` | source material | semantic badge style |
| `color.provenance.machine` | machine-produced content | semantic badge style |
| `color.provenance.human` | human correction/confirmation | semantic badge style |

No token may encode policy authority. No semantic state may depend on a raw
brand RGB value.

### Typography

| Token | Role |
| --- | --- |
| `type.windowTitle` | logical window/Meeting title |
| `type.meetingTitle` | primary Meeting heading |
| `type.sectionTitle` | dossier and inspector section heading |
| `type.readingBody` | transcript, briefing, and analysis reading text |
| `type.editorBody` | editable long-form content |
| `type.metadata` | date, language, classification, and source metadata |
| `type.evidenceLabel` | evidence and provenance labels |
| `type.timecode` | exact ranges and media time |
| `type.caption` | concise limitation and recovery guidance |

Use San Francisco through SwiftUI text styles and weight modifiers. Do not
bundle a substitute font. Text must reflow rather than clip at supported
accessibility sizes.

### Spacing and size

The base spacing scale is `4, 8, 12, 16, 24, 32`. Components may combine these
values but should not introduce near-duplicates without measured need.

- `4`: icon-label or tightly related metadata;
- `8`: compact control and row internals;
- `12`: standard row and compact section spacing;
- `16`: form groups and inspector sections;
- `24`: primary canvas sections;
- `32`: major dossier divisions.

Primary interactive targets should provide a practical 44-point hit region
where the control and layout permit it. Dense tables may use native row sizing
if keyboard and accessibility behavior remain clear.

### Radius, border, and elevation

| Token | Use |
| --- | --- |
| `radius.control` | native or compact controls |
| `radius.surface` | one meaningful grouped surface |
| `radius.popover` | popover/temporary presentation |

Default hierarchy uses pane backgrounds and separators, not shadows. Avoid
custom borders around standard `Form`, `List`, `TextEditor`, and selection
controls unless the border communicates focus or validation.

### State

All asynchronous or gated surfaces use this shared vocabulary:

`initial`, `loading`, `empty`, `blocked`, `ready`, `working`, `success`,
`failure`, and `stale`.

`unavailable` means the platform or approved application contract cannot
provide a capability. It must not stand in for “not loaded yet.”

### Icon

Icons are semantic roles mapped centrally to SF Symbols:

| Token | Meaning |
| --- | --- |
| `icon.workspace` | validated workspace context |
| `icon.meeting` | Meeting context |
| `icon.evidence` | exact evidence link or inspector target |
| `icon.localOnly` | local-only route/status |
| `icon.recording` | recording state or action |
| `icon.inspector` | inspector visibility |
| `icon.storage` | storage and Trash context |
| `icon.success` | completed/verified state |
| `icon.warning` | attention, incomplete, or stale state |
| `icon.error` | failed or unsafe state |

One implementation file owns the exact SF Symbol mapping and availability
fallbacks. Feature views request semantic roles rather than scattering symbol
names. An icon reinforces state; it never replaces the state label or
accessible value.

### Motion

Motion communicates state continuity:

- sidebar and inspector disclosure;
- selection movement;
- task progress and completion;
- contextual error/recovery presentation.

No decorative continuous animation is permitted. Reduce Motion replaces
spatial or spring animation with an immediate or cross-fade transition.

### Density

`comfortable` is the default for reading and review. `compact` may be offered
later as a safe presentation preference for lists and metadata-heavy panels.
Density must not hide evidence, status, authorization, or destructive effects.

## Reusable component contracts

The proposed directory is:

```text
Sources/MeetingBuddyFeatures/DesignSystem/
  Tokens/
    BlueMinutesColors.swift
    BlueMinutesTypography.swift
    BlueMinutesLayout.swift
    BlueMinutesIcons.swift
    BlueMinutesMotion.swift
  Components/
    WorkspaceSidebarRow.swift
    MeetingContextHeader.swift
    EditorialSectionHeader.swift
    EvidenceBadge.swift
    EvidenceAnchor.swift
    WorkflowStateView.swift
    FormSection.swift
    EvidenceInspectorPanel.swift
    TaskProgressView.swift
    InlineErrorView.swift
    EditorialToolbarContent.swift
  Environment/
    InterfaceDensity.swift
```

This is a proposed file map, not an instruction to create every type at once.
Each implementation PR should add only the components it consumes.

### Sidebar row

A sidebar row owns icon, full label, selection, optional status, disabled
reason, accessibility label, and help text. It must not truncate the primary
label at the supported default window size.

### Evidence badge and anchor

Evidence badges identify provenance class. Evidence anchors navigate to a
real `EvidenceRefV1` location and update the inspector selection. Badge color
does not imply evidentiary sufficiency or human confirmation.

### Empty, blocked, loading, and failure states

Each state provides:

- a precise title;
- one-sentence explanation;
- a real primary recovery action when available;
- optional technical detail through disclosure;
- accessible progress or error announcement.

### Inspector panel

An inspector panel displays only data available through an application-owned
view model. A control shown in the inspector must call a real application
action. Raw persistence access and decorative action buttons are prohibited.

### Toolbar pattern

The toolbar shows the few actions that apply to the current selection and
workflow. It must not become a duplicate navigation bar. Menu commands and
keyboard shortcuts remain available when toolbar items collapse.

## Selected-mock authenticity boundary

The Phase 0 mock contains conceptual elements. They are not automatically
authorized product behavior:

| Mock element | Current support | Contract |
| --- | --- | --- |
| Current Meeting and All Meetings rows | Partial historical query support, no current shell model | Do not show until a real Meeting selection/query contract exists |
| Global Search | Meeting History has scoped search only | Do not present as global search until results and scope are real |
| Meeting Setup | Not implemented | Belongs to a separately authorized per-Meeting Setup Guide |
| Evidence Inspector | Not implemented as a shared scene surface | Add only after selection and evidence view-model contracts exist |
| Generate Briefing toolbar action | Briefing generation and later review/regeneration are different states | Derive toolbar wording and actions from the real Briefing state; never bypass policy |
| Meeting time range and type | Not current Meeting-profile fields in this form | Omit or replace with contract-backed metadata |
| Global Local only badge | Route proof exists on specific screens, not as one shell summary | Require an application-owned policy projection; never hard-code it |
| Open Source | A source URL may exist, but safe reveal/open semantics vary | Show only after resolving the exact source and a real application action |
| Play segment | Exact time evidence exists in some flows | Require a real bounded playback contract |
| Add Note | No general note model exists | Omit until a separately authorized domain/application contract exists |
| Next Steps checkboxes | Commitment and Decision domain contracts exist, but the Briefing surface has no status-mutation action | A projection may render real content/status; keep checkboxes noninteractive until an application-owned update action is authorized |
| Confidence bar | Exact numeric confidence may exist | Apply an approved deterministic label policy; never invent prose or imply confirmation |
| Four dossier headings | Current Briefing contracts publish three template section types | Treat the mock headings as illustrative; render only contract-backed sections |

The current Briefing review bundle exposes publication and stale-state data,
not a ready-made shared inspector projection. A future inspector therefore
requires an application-owned read projection or resolver before it can ship;
views must not query persistence directly.

## Pull Request design checklist

Every UI Pull Request must answer:

- Which design tokens and shared components does it use?
- What current behavior and evidence lineage remain unchanged?
- Are all visible controls functional and policy-authorized?
- Does the surface pass Light and Dark Mode review?
- Does it pass keyboard-only operation and visible-focus review?
- Does it pass VoiceOver label, value, order, and announcement review?
- Does it remain usable at 860×600, 1080×720, and 1440×1024?
- Does it reflow with larger text without truncating primary labels?
- Does it respect Reduce Motion, Increase Contrast, Reduce Transparency, and
  Differentiate Without Color?
- Are screenshots synthetic, privacy-reviewed, dimension-checked, and
  color-profile-accounted?
- Are loading, empty, blocked, failure, stale, and disabled reasons distinct?
- Did schema, dependencies, entitlements, capabilities, policy authority,
  provider routes, network behavior, and user-data handling remain unchanged?

## Non-goals

This design language does not:

- authorize Research UI or capability toggles;
- authorize external providers, connectors, accounts, or network routes;
- create a second citation/evidence model;
- convert learned presentation preferences into security authority;
- persist full prompts;
- remember recording consent;
- raise the macOS deployment target;
- promise signed, notarized, packaged, installed, or distributed software.
