# Codex Maintenance Workflow

Status: active after initial GitHub publication

Codex is a maintenance assistant, not an authority to widen scope, merge, or
release. Every session follows `AGENTS.md`, the active Issue, applicable ADRs,
current repository evidence, and the user's explicit authorization.

## Standard sequence

1. Read the Issue, acceptance criteria, excluded scope, and relevant ADRs.
2. Inspect the current branch, commit, working tree, tests, and implementation.
3. Report material drift, sensitive-data concerns, or unresolved architecture
   decisions before editing.
4. Create or use the Issue's short-lived branch; never work directly on `main`.
5. Make the smallest compatible change and add regression tests.
6. Run focused checks, then the complete required gate.
7. Inspect the intended diff, staged files, ignored material, secrets, and large
   files before committing.
8. Create a Pull Request; do not merge without explicit user authorization.
9. Do not tag, publish, sign, notarize, deploy, or release without a separate
   explicit command.

Codex must preserve user data, immutable evidence lineage, backward
compatibility, Storage Service ownership, Task Manager routing, approved AI
provider interfaces, and fail-closed structured-output validation.

## Standard prompts

### Analyze an Issue without changing files

```text
Analyze GitHub Issue #<number>. Read AGENTS.md, the Issue, relevant ADRs,
architecture, security, storage, implementation, and tests. Reproduce or trace
the current behavior using read-only checks. Return the smallest proposed
change, affected files, data/privacy/evidence impact, migration and rollback
needs, exact test plan, and unresolved decisions. Do not edit, commit, push,
merge, or release.
```

### Implement an approved Issue

```text
Implement GitHub Issue #<number> on a short-lived branch. Follow AGENTS.md and
the accepted analysis. Keep scope to the acceptance criteria, preserve user
data and compatibility, add regression tests, and run focused plus full gates.
Inspect the final diff and sensitive-data boundary. Commit only the intended
change and open a Pull Request. Do not merge or release without separate
explicit authorization.
```

### Review a Pull Request

```text
Review Pull Request #<number> against its Issue, AGENTS.md, relevant ADRs, and
current source. Prioritize correctness, data loss, privacy/security,
evidence-traceability, migration compatibility, rollback, and missing tests.
Run safe read-only validation where useful. Report findings with file/line
evidence. Do not edit, merge, push, or release.
```

### Update a dependency

```text
Analyze dependency update <package/version>. Verify the need, official source,
license, release notes, compatibility, security advisories, transitive changes,
and removal plan. Propose the smallest version change and exact regression
gate. Do not update until the maintainer explicitly authorizes implementation;
never auto-merge a Dependabot Pull Request.
```

### Change a persistent schema

```text
Analyze schema change <description>. Require an ADR, ordered migration,
pre-migration backup, supported-prior-state tests, failure rollback, reopen and
integrity checks, recovery-manifest coverage, downgrade procedure, and updated
storage documentation. Do not modify an accepted migration or reset user data.
```

### Prepare—but do not publish—a release

```text
Prepare release candidate <version> using docs/RELEASE_CHECKLIST.md. Audit the
exact source commit, tests, secrets, history, large files, licenses, toolchain,
signing/notarization status, backup, and rollback evidence. Produce a readiness
report only. Do not create a tag, GitHub Release, binary, package, signature,
notarization submission, deployment, or upload.
```

## Completion report

Every Codex implementation report states:

- Issue and branch;
- files changed and why;
- exact commands and results;
- migration, privacy/security, evidence, and rollback impact;
- commit and Pull Request identifiers, if authorized;
- skipped or unverified checks;
- remaining risks; and
- confirmation that no sensitive data or unauthorized release action occurred.
