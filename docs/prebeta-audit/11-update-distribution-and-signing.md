# Update, Distribution, and Signing

## Current truth

BlueMinutes `v0.3.0` remains the latest source-only GitHub Release with zero
maintainer-uploaded app assets. Application version `0.4.0` build `4` is the
current local formal-test candidate, and the staging path produces only an
ad-hoc-signed DEVELOPMENT bundle. No `v0.4.0` tag or GitHub Release is created
by this phase. Developer ID, Team ID, hardened-runtime distribution signature,
notarization/stapling, Gatekeeper, clean-machine installation, and public
binary distribution are not closed.

ADR-0002 selects an eventual independent Developer ID direction but keeps
updates manual until the distribution path is proven.

## Foundation update contract

`ReleaseIntegrationContracts.swift` adds:

- `UpdatePolicyMode.unconfigured | manual | automatic`;
- a syntactically constrained HTTPS feed requirement for configured modes;
- an unforgeable updater approval plus exact update-feed allowlist shared by the
  website handoff and update policy;
- an exact composite invariant: the website feed and `UpdatePolicy.feedURL`
  either are both absent or are the same approved URL;
- `UpdateSafetyGate`, which accepts only the validated composite release
  configuration rather than a standalone update policy;
- default public-Beta `unconfigured` state with no feed or request; and
- a block on download/install during an active meeting.

This is an architecture shell, not an updater. The independent About window now
composes the public-Beta configuration and shows the honest unconfigured reason,
disabled billing state, and disconnected website handoff. Actual enablement
still requires controlled origins, redirect/DNS policy, signed appcast and
artifact verification; HTTPS syntax alone is not a trust decision.

## Channel decision

The current intended direction is website distribution, which makes Sparkle 2
a reasonable candidate. It is not yet approved because a real integration
requires:

- Developer ID application signing;
- hardened runtime and entitlements review;
- notarized/stapled release artifacts;
- Sparkle license/dependency/privacy/size/removal note;
- EdDSA update key ownership and secure CI secret handling;
- HTTPS appcast ownership and rollback;
- version monotonicity and minimum-OS rules;
- delta/full package validation;
- active-meeting deferral; and
- clean-machine update and downgrade recovery tests.

Mac App Store distribution would use App Store updates instead; the mechanisms
must not be mixed.

## About surface

The functional About surface now shows:

- the reviewed BlueMinutes icon and product name;
- app version/build;
- Beta classification and all-features-unlocked state;
- the honest unconfigured update policy;
- the disconnected typed website handoff with no endpoint; and
- a user-initiated sanitized diagnostic copy containing only bounded
  build/OS/release-mode facts, with no content, credential, URL, or path; and
- no contact/support link while none is configured.

It does not imply a signed/notarized public build when running from SwiftPM or
the development staging script. Last-check state, website/support/privacy
links, and affiliation text remain absent until corresponding reviewed
configuration and product copy exist. A bounded isolated staged-app smoke
rendered this surface and observed no established TCP or UDP socket; that is
not a substitute for the complete release-network matrix.

## CI/release gate

Before public binary publication:

1. pin source tag, Git tree, toolchain, dependencies, assets, entitlements, and
   privacy manifests;
2. archive with exact Developer ID identity;
3. notarize and staple;
4. verify signature/team/hardened runtime/Gatekeeper;
5. verify appcast signature and artifact digest;
6. install/update on clean supported machines;
7. prove recording-safe deferral and rollback;
8. publish only the exact verified artifact.

No signing identity, key, appcast, deployment, or release upload is authorized
by the current phase.
