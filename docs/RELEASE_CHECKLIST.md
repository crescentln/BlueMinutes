# Release Checklist

Status: policy only; no release is authorized by this document

Initial source publication is not an application release. Creating a Git tag,
GitHub Release, archive, installer, package, signed build, notarized build, or
deployment requires separate explicit maintainer authorization.

A source-only GitHub Release and a downloadable macOS application are distinct
distribution scopes. A source release may proceed after the source gate passes
even when the binary-distribution gate remains incomplete, provided that it
attaches no application binary and states that boundary clearly.

## Versioning and changelog policy

- Use Semantic Versioning for public releases.
- During `0.x`, substantial user-visible capabilities or compatibility changes
  normally increment the minor version; focused fixes normally increment the
  patch version.
- Record every notable user-visible change under `Unreleased` in
  `CHANGELOG.md` as part of the same Pull Request.
- For each substantial milestone, move those entries into a dated version and
  publish matching release notes after protected-`main` CI passes and the
  maintainer authorizes the exact release.
- Do not treat a source release as authorization for a signed app, installer,
  updater, deployment, or other binary distribution.

## Release decision

- [ ] The maintainer explicitly authorized this exact version and distribution
      scope.
- [ ] The release milestone and included Issues are closed or deliberately
      deferred with documented risk.
- [ ] The public project name, ownership, license, trademarks, and third-party
      notices were reviewed.
- [ ] Release notes distinguish implemented behavior from plans.
- [ ] Supported macOS versions, architectures, update path, and rollback path
      are documented.

## Source and data safety

- [ ] The release commit is on protected `main`, has a clean working tree, and
      matches the reviewed Pull Requests.
- [ ] Reliable secret scanning covered the working tree and reachable history,
      or layered fallback scans and their limitations are documented.
- [ ] Author and committer email metadata is intentionally suitable for public
      exposure; use the authenticated GitHub noreply identity when required.
- [ ] Initial source publication pushes only
      `refs/heads/main:refs/heads/main`; never mirror local Codex refs, reflogs,
      or the repository's `.git` directory.
- [ ] No credential, signing material, real meeting content, diplomatic record,
      user workspace, database, log, model, private fixture, or generated
      briefing is included.
- [ ] Large files, archives, media, databases, generated output, and test
      fixtures were individually reviewed.
- [ ] Tests and demonstrations use only synthetic, anonymized, licensed, or
      already-public material.

## Engineering gate

```sh
swift package resolve
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

- [ ] Migration, schema/serialization, recovery, provider, evidence coverage,
      integration, and bounded Golden suites pass.
- [ ] GitHub Actions passes on the exact release commit.
- [ ] Dependency licenses, resolved versions, security advisories, and update
      notes were reviewed.
- [ ] A verified cold backup and rollback rehearsal used a disposable synthetic
      workspace.
- [ ] P0/P1 security, privacy, evidence-integrity, or data-loss findings are
      closed. Accepted lower-priority risk is explicit.

## Local development-package gate

This gate is separate from public binary distribution. Passing it authorizes
only a package retained in the ignored local `dist/` directory when the
maintainer has explicitly approved that exact scope.

- [ ] `CFBundleShortVersionString`, `CFBundleVersion`, public bundle/package
      names, and compatibility-sensitive executable/bundle identifiers match
      the reviewed release contract.
- [ ] The repository is clean and the package manifest binds the exact Git
      head, tree, optional annotated release tag, complete tracked-source
      inventory, `Package.resolved`, and build toolchain.
- [ ] The development release set has the exact reviewed top-level layout and
      contains no symbolic link, credential, signing material, workspace,
      database, log, model, real meeting content, or generated briefing.
- [ ] The direct app, coherent release set, and fresh ZIP extraction pass
      `script/verify_release_candidate.sh ... development`.
- [ ] App/executable/archive/source-inventory digests and the ad-hoc Hardened
      Runtime signature match the schema-v2 manifest.
- [ ] `distribution` verification rejects the ad-hoc package; no check is
      bypassed or weakened to make it pass.
- [ ] The local app/ZIP is not installed, uploaded, attached to a GitHub
      Release, advertised as a supported download, or used as an update.

## Binary-distribution gate

- [ ] A reproducible build procedure records the full Xcode/Swift/macOS
      toolchain and target architecture.
- [ ] Entitlements and sandbox authority match the documented policy.
- [ ] The BlueMinutes display name and reviewed icon are present in the bundle;
      icon legibility and appearance are checked at Finder, Dock, Spotlight,
      and small accessibility-relevant sizes.
- [ ] Developer ID identity and Team ID are verified without exposing signing
      material.
- [ ] Hardened Runtime, code signing, notarization, stapling, and Gatekeeper
      checks pass when distribution requires them.
- [ ] Clean-machine installation, first launch, permissions, update, rollback,
      VoiceOver, keyboard, contrast, and reduced-motion checks pass on intended
      macOS versions.
- [ ] No signing, notarization, upload, publishing, or deployment credential is
      stored in the repository.

Until this gate passes, public releases must remain source-only and must not
attach or imply a supported BlueMinutes application download.

## Authorized publication steps

Perform these only after the exact release authorization is recorded:

1. Re-run the complete gate on the intended commit.
2. Create the approved annotated tag without rewriting history.
3. Build and verify only the authorized local artifacts, keeping them local
   unless binary publication was separately approved.
4. Publish source release notes. Attach artifacts or checksums only when their
   exact public distribution was separately approved.
5. Verify repository visibility, tag, release record, and attached files.
6. Monitor the supported update and rollback path.

Stop immediately if the source commit, signatures, checksums, visibility,
artifact contents, or remote state differ from the approved plan.

## Post-release

- [ ] Record the exact tag, commit, artifact checksums, CI run, toolchain, and
      verification results.
- [ ] Confirm no unexpected package, deployment, Pages site, or release asset
      exists.
- [ ] Keep rollback artifacts and compatibility notes for the supported period.
- [ ] Update `CHANGELOG.md` and the support/security version policy.
