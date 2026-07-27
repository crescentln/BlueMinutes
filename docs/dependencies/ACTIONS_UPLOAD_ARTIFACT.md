# actions/upload-artifact Dependency Note

Status: Accepted for Future Slice I
Owner: Codex
Decision date: 2026-07-26
Pinned version: 7.0.1
Pinned commit: `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`

## Purpose

The dedicated `Native visual regression` CI job uses the official
`actions/upload-artifact` action to preserve expected, actual, diff, and
machine-readable comparison files when an ordinary regression job fails. The
separate `Native visual evidence bootstrap` job uploads requested candidate or
calibration evidence after an explicit workflow dispatch or its
maintainer-labeled first-PR bootstrap equivalent, so evidence can be reviewed
without changing the repository or impersonating the regression check.

## Native and existing alternatives

GitHub Actions logs cannot represent the three PNG files or preserve them as
one bounded diagnostic set. Implementing the runner artifact protocol directly
with shell and HTTP would add unaudited authentication, retry, serialization,
and endpoint behavior. The official GitHub-maintained action is the narrow
existing mechanism for this CI-only transfer.

## Size and distribution impact

- The action is downloaded only by the GitHub-hosted CI runner.
- It is not linked into `MeetingBuddyApp`, copied into the application bundle,
  installed on a user Mac, or present at runtime.
- Exact runner download/cache size varies with GitHub's action packaging and
  was not measured as shipped-product evidence.
- Successful ordinary regression jobs upload nothing. Failed regression jobs
  and explicit candidate or calibration evidence jobs retain only bounded
  synthetic visual evidence for seven days.

## Maintenance and security history

Version 7.0.1 was published by the official `actions/upload-artifact`
repository on 2026-04-10. The exact tag resolves to the commit pinned above.
The repository's published security-advisory endpoint returned no advisories
at review time. That point-in-time negative result is not proof that no defect
exists; the exact pin remains subject to future authorized dependency review.

## License

The repository declares the MIT license. The action is a CI tool and adds no
copyleft condition to BlueMinutes application code or distribution.

## Sandbox and signing impact

- The action receives the workflow's read-only repository token context and
  the exact failure-artifact directory.
- It does not receive meeting data, credentials supplied by BlueMinutes,
  workspaces, logs, user paths, or successful-run screenshots.
- It adds no application entitlement, helper executable, code-signing input,
  runtime network path, provider/model route, or notarization impact.

## Update strategy

Keep the full immutable commit SHA in the workflow. Upgrade only in a separately
reviewed change that rechecks release provenance, license, advisories, runner
compatibility, regression-failure and explicit-dispatch conditions, retention,
distinct regression/evidence check contexts, single-label fail-closed bootstrap
behavior, and the closed artifact paths.

## Removal strategy

Remove the upload step and this note. The visual test still fails correctly and
prints its case identifier; only hosted failure diagnostics and explicit
candidate/calibration evidence transfer are lost.

## Sources reviewed

- <https://github.com/actions/upload-artifact/releases/tag/v7.0.1>
- <https://github.com/actions/upload-artifact/commit/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a>
- <https://github.com/actions/upload-artifact/blob/main/LICENSE>
