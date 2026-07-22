# Maintenance Guide

Status: active after initial GitHub publication

This guide defines the normal maintenance workflow. `AGENTS.md`, accepted ADRs,
the security and storage policies, and explicit maintainer authorization remain
authoritative when they are more restrictive.

## Issue-first workflow

Every code or behavior change starts with a GitHub Issue. The Issue must state
the background, current and expected behavior, acceptance criteria, excluded
scope, affected data, privacy/security and evidence-traceability impact,
migration impact, rollback method, and test plan.

Before implementation:

1. Reproduce or inspect the current behavior from source, tests, and runtime
   evidence.
2. Read the applicable ADRs and architecture, security, storage, and domain
   contracts.
3. Identify the smallest change that satisfies the Issue.
4. Record unresolved product, data, or architecture decisions instead of
   silently choosing a wider scope.

Architecture, persistent-schema, provider, external-processing, storage,
security-policy, or distribution changes require an accepted ADR before or with
implementation.

## Branches

Never make routine changes directly on `main` after the initial publication.
Create one short-lived branch per Issue:

```text
fix/123-short-description
feat/123-short-description
docs/123-short-description
security/123-short-description
chore/123-short-description
```

Delete the branch after merge. Do not mix unrelated work, rewrite shared
history, or force-push protected branches.

## Commits

Use small, reviewable commits with imperative messages, such as:

```text
fix: reject unconfirmed briefing export
test: cover schema nine rollback failure
docs: clarify local processing boundary
```

A commit must not claim completion unless its required checks passed. Do not
commit real meeting material, user workspaces, generated briefings, credentials,
logs, models, signing material, or local build output.

## Pull Requests

Every future change uses a Pull Request linked to its Issue. Complete the Pull
Request template, include exact test commands and results, describe migration
and rollback behavior, and disclose remaining risk. Visible UI changes need
screenshots made with synthetic data.

CI must pass and conversations must be resolved before merge. Passing CI does
not authorize merge. Only the maintainer may explicitly authorize a merge, and
release authorization is a separate decision.

## Required checks

The baseline local gate is:

```sh
swift package resolve
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

Also run every focused suite relevant to the change. At minimum:

| Change area | Focused evidence |
| --- | --- |
| Persistent schema or repository | `WorkspaceAndMigrationTests`, `RepositoryRoundTripTests` |
| Recovery, Trash, or backups | `RecoveryAndTrashTests` plus the applicable backup verifier |
| Semantic schema or serialization | `CanonicalAndCompatibilityTests` and affected domain tests |
| Transcription coverage | `TranscriptPipelineIntegrationTests` |
| Analysis coverage or review | `AnalysisPipelineIntegrationTests` |
| Briefing or export | `BriefingPipelineIntegrationTests` |
| Provider contracts | `ProviderContractTests` |
| Golden behavior | `GoldenFixtureTests` and affected bounded Golden suite |

Installed-model tests are opt-in and synthetic-only. A skip is not a pass for
the installed-model path.

## Database migrations

Persistent schema changes must:

1. define a new ordered migration without modifying prior migrations;
2. document the source and target schema versions;
3. create and verify a portable pre-migration rollback anchor;
4. preserve accepted prior data byte-for-byte unless an explicit transformation
   is required and tested;
5. test fresh creation and every supported prior schema path;
6. inject a migration failure and prove the logical transaction rolls back;
7. reject unknown future schemas;
8. close and reopen the migrated database and run SQLite integrity and foreign
   key checks;
9. update recovery-manifest coverage and the storage policy; and
10. document why downgrade uses a restored backup rather than the newer live
    workspace.

Never point an older binary at a newer live workspace unless compatibility has
been explicitly designed and tested.

## Rollback

Every change identifies a Git rollback anchor and a user-data rollback plan.
Code rollback never justifies deleting or resetting a user workspace. For an
application or schema rollback, preserve the newer workspace and restore a
verified pre-change cold backup into a distinct empty path. Follow
`docs/BACKUP_AND_RECOVERY.md` and `docs/RELEASE_BACKUP_AND_ROLLBACK.md`.

## Dependency updates

Dependency changes require a documented need, license review, provenance and
maintainer-health review, API and security-impact analysis, exact version or
reviewed range, update/removal plan, and complete regression gate. Review major
versions manually. Dependabot Pull Requests are proposals only and are never
auto-merged.

## Privacy and security review

For every change, determine whether it affects data categories, classification,
network destinations, provider retention, credentials, logs, file authority,
evidence lineage, human-confirmation boundaries, deletion, or recovery. Fail
closed when policy or provenance is missing. Provider output and imported
content remain untrusted data.

Tests, CI, examples, screenshots, and demonstrations may use only synthetic,
anonymized, explicitly licensed, or already-public fixtures. Open source makes
review possible; it is not a security guarantee.

## Emergency hotfixes

For an urgent vulnerability or data-loss risk:

1. open a private Security Advisory when confidentiality is needed;
2. branch from the current protected `main` revision;
3. make the smallest safe fix and add a regression test;
4. run all risk-relevant checks and the full gate;
5. use a Pull Request, even if review is expedited;
6. document rollback and affected versions; and
7. coordinate disclosure through `SECURITY.md`.

Do not bypass data protection, CI, branch protection, or explicit release
authorization because a fix is urgent.

## Versioning and releases

Use Semantic Versioning where it accurately communicates compatibility. Until
the project declares a stable public API, minor versions may include documented
breaking changes, but persistent-data compatibility and migration obligations
still apply.

Source publication, a Git tag, a GitHub Release, a distributable application,
signing, and notarization are separate actions. Follow
`docs/RELEASE_CHECKLIST.md`; none is authorized implicitly by a merged Pull
Request.
