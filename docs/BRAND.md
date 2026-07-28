# BlueMinutes Brand

BlueMinutes is the public project and product name. The tagline is
“Multilateral Meeting Briefing and Documentation Tool.” Compatibility-sensitive
Swift modules, executable names, bundle identifiers, persistence names, command
names, protocol identifiers, and data formats continue to use `MeetingBuddy`.
That boundary avoids unnecessary migrations and preserves existing local user
authority and data compatibility.

## Assets

- `Configuration/Branding/Sources/BlueMinutes-Logo-Source.png` and
  `Configuration/Branding/Sources/BlueMinutes-AppIcon-Source.png` preserve the
  exact maintainer-supplied source files and their reviewed SHA-256 identities.
- `docs/assets/BlueMinutes-logo.png` is the lossless public horizontal lockup
  copied from the reviewed source.
- `Configuration/Branding/BlueMinutes-AppIcon-1024.png` is the deterministic
  sRGB 1024-pixel application-icon master generated from the reviewed square
  source.
- `Configuration/Branding/BlueMinutes.icns` is the generated macOS icon resource
  installed in local application bundles.
- `script/generate_brand_assets.sh` verifies the two source hashes before
  regenerating every derived asset with the macOS system image tools.

The application icon uses the approved blue rounded square with the white
BlueMinutes “B”, conversation bubble, and minute lines. It intentionally
contains no words, map, globe, olive branches, wreath, flag, seal,
institutional crest, or United Nations emblem.

## Independence and use boundary

BlueMinutes is an independent personal open-source project. It is not
affiliated with, sponsored by, or endorsed by the United Nations, any United
Nations entity, any government, or OpenAI. The project name, logo, and icon
must not be presented in a way that implies such affiliation or endorsement.

Project-authored brand asset files are included with the Work under Apache
License 2.0. Its Section 6 does not grant permission to use project trademarks
except as needed for reasonable and customary description of the origin of the
work. No claim is made here that `BlueMinutes` is a registered trademark, and
the current collision screen is not a substitute for professional trademark
advice.
