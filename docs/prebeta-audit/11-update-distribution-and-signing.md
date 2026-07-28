# Update, Distribution, and Signing

## Current truth

BlueMinutes v0.3.0 is a source-only release with zero maintainer-uploaded app
assets. The local staging path produces an ad-hoc-signed development bundle.
Developer ID, Team ID, hardened-runtime distribution signature,
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
- `UpdateSafetyGate`;
- default public-Beta `unconfigured` state with no feed or request; and
- a block on download/install during an active meeting.

This is an architecture shell, not an updater. The About/Settings UI must show
the honest unavailable reason until a feed is configured. Actual enablement
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

The functional About surface should show:

- BlueMinutes icon and product name;
- app version/build;
- release channel and classification;
- current update policy;
- last checked/result when a provider exists;
- website/support/privacy links only when configured; and
- independence/not-affiliation statement.

It must not imply a signed/notarized public build when running from SwiftPM or
the development staging script.

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
