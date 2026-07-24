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
6. Run the smallest useful focused checks locally. Run the complete required
   gate on GitHub-hosted macOS CI by default, plus any risk-relevant native
   checks that CI cannot prove.
7. Inspect the intended diff, staged files, ignored material, secrets, and large
   files before committing.
8. Create a Pull Request; do not merge without explicit user authorization.
9. Do not tag, publish, sign, notarize, deploy, or release without a separate
   explicit command.

Codex must preserve user data, immutable evidence lineage, backward
compatibility, Storage Service ownership, Task Manager routing, approved AI
provider interfaces, and fail-closed structured-output validation.

## Low-load local execution policy

The required quality gate is unchanged. This policy changes where work runs,
not what must pass. Codex cloud tasks are not used for repository maintenance.
The maintainer Mac is the control, review, and focused-validation surface; it
is not the default full-build machine.

### Default development loop

1. Inspect only the Issue, applicable governance, and the smallest relevant
   source and test paths.
2. Make one bounded, reviewable change.
3. For documentation-only work, run link, status, scope, whitespace, and
   sensitive-content checks; do not run Swift merely because the repository
   contains Swift.
4. For behavior changes, run the smallest affected test target, suite, or case.
   Add an incremental `swift build` only when it provides useful immediate
   cross-module feedback.
5. After separately authorized branch publication, require the exact Pull
   Request head to pass the complete GitHub-hosted macOS CI gate. CodeQL and
   review gates remain unchanged.
6. Iterate from focused evidence or CI failures. Do not expand automatically
   into repeated local full-suite or clean-scratch runs.

| Change type | Local default | Required additional evidence |
| --- | --- | --- |
| Documentation only | Links, status/scope assertions, diff, and sensitive-content checks | Exact-head Pull Request checks when published |
| Focused behavior or regression | Affected `swift test --filter ...` suite or case | Complete GitHub macOS CI |
| Cross-module, schema, recovery, or security | Risk-relevant focused suites; incremental build only when useful | Complete CI plus every Issue-specific migration, recovery, adversarial, or security gate |
| SwiftUI, AppKit, capture, TCC, or accessibility | Focused structural tests where available | Complete CI plus explicit native/manual evidence |
| Signing, notarization, installation, or release | Preparation checks authorized by the Issue | Exact release gate, native tooling, and clean-machine evidence under separate authorization |

### Xcode and native validation

`Package.swift` is the normal package entry point. Focused local work uses
SwiftPM. The Swift command-line tools may use the installed Xcode toolchain
without opening the Xcode application.

Open Xcode only when the Issue requires evidence that command-line or hosted CI
cannot provide, including:

- SwiftUI or AppKit visual debugging;
- microphone, ScreenCaptureKit, application-audio, or TCC behavior;
- real interruption, sleep, device-change, or long-capture behavior;
- VoiceOver, keyboard, contrast, reduced-motion, or other manual accessibility
  review;
- Instruments profiling; or
- signing, Archive, notarization, Gatekeeper, installation, or distribution
  verification.

Hosted build/test success is not native TCC, capture, accessibility, signing,
notarization, or clean-machine proof. Keep those gaps explicit.

### Local artifacts and machine use

- Preserve the ignored `.build` directory and normal SwiftPM package caches for
  incremental reuse. Do not schedule `swift package clean`, fresh scratch
  builds, or broad cache deletion.
- Before any cleanup, measure the exact target, confirm that no build is using
  it, explain the rebuild cost, obtain the required authorization, and use a
  recoverable removal path where practical.
- Never broadly delete Xcode `DerivedData`, Archives, simulator data, or shared
  caches merely because one project needs maintenance.
- GitHub-hosted runner artifacts stay remote unless an Issue explicitly
  requires a reviewed artifact.
- Do not register the maintainer Mac as a self-hosted Actions runner for this
  workflow. After authorized branch publication, GitHub checks continue while
  the Mac sleeps or is offline.

### Exceptions and reporting

An Issue may require a local full suite, fresh scratch path, Xcode, or other
high-load evidence when migration, recovery, capture, performance, signing, or
release risk warrants it. Before running that exception, Codex states why it is
needed, the exact command or tool, the expected local load, and the evidence it
will establish.

Every completion report separates:

- focused checks run locally;
- exact-head GitHub CI and CodeQL results;
- native/manual checks run locally;
- skipped or unverified native paths;
- whether Xcode was opened; and
- material local build, archive, or distribution artifacts created.

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
