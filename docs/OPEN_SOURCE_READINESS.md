# Open-Source Readiness Evidence

Status: private-publication evidence map; refresh on the exact public commit
Last verified: 2026-07-22

This document gives reviewers and contributors a short path from project claims
to repository evidence. It is not a certification, adoption claim, release
announcement, or substitute for the final public CI and sensitive-data gates.

## Reviewer quick path

| Question | Repository evidence | What it establishes |
| --- | --- | --- |
| What problem does the project address? | [README](../README.md) and [briefing foundation](BRIEFING_FOUNDATION.md) | A multilateral-meeting workflow extending beyond generic speech-to-text into provenance, position review, evidence-linked briefing, and historical context. |
| Is there a real implementation? | [Current architecture](CURRENT_ARCHITECTURE.md), [domain contracts](DOMAIN_CONTRACTS.md), and [Sources](../Sources/) | A native Swift modular monolith with bounded application, persistence, task, media, AI, feature, and automation layers. |
| Is quality actively maintained? | [CI workflow](../.github/workflows/ci.yml), [execution state](CODEX_EXECUTION_STATE.md), and [Tests](../Tests/) | The local and private-GitHub warning-as-error gates pass a 248-test suite in 43 suites; three installed-model routes remain explicit opt-in checks rather than ordinary-CI claims. |
| How is evidence integrity protected? | [ADR-0017](adr/ADR-0017-evidence-integrity-publication-boundaries.md) and [Task 012 remediation](audits/TASK-012_SECURITY_REMEDIATION.md) | Provider output remains untrusted; source omissions need application-owned proof, and consequential analysis and briefing publication require exact human-confirmation gates. |
| How are privacy and security handled? | [Security policy](../SECURITY.md), [security and privacy architecture](SECURITY_PRIVACY.md), [threat model](THREAT_MODEL.md), and [storage policy](STORAGE_POLICY.md) | Local-first data handling, Keychain-only credentials, bounded providers, strict storage authority, recovery, and explicit residual risk. |
| Can others maintain it responsibly? | [Contributing guide](../CONTRIBUTING.md), [maintenance guide](MAINTENANCE.md), [release checklist](RELEASE_CHECKLIST.md), and [AGENTS.md](../AGENTS.md) | Issue-first development, short-lived branches, Pull Requests, required tests, migrations, rollback, privacy review, and explicit merge/release authority. |
| Is reuse legally clear? | [Apache License 2.0](../LICENSE), [NOTICE](../NOTICE), and [third-party notice](../ThirdPartyNotices/GRDB-LICENSE.txt) | Project-authored work uses Apache-2.0; the exact GRDB dependency retains its MIT notice. |

## Current verification snapshot

- `swift package resolve` completes without `Package.resolved` drift.
- `swift build -Xswiftc -warnings-as-errors` passes.
- `swift test -Xswiftc -warnings-as-errors` reports 248 tests in 43 suites with
  zero failures; three installed Apple-model routes are skipped by explicit
  opt-in gates and are not represented as ordinary-CI passes.
- Focused migration, serialization, recovery, evidence-linked integration, and
  bounded Golden suites are configured in GitHub Actions.
- The private repository's exact `main` commit and its GitHub Actions run are
  recorded in the [execution state](CODEX_EXECUTION_STATE.md); repeat the gate
  after the separately authorized public conversion.
- Tests and examples use project-authored synthetic material or explicitly
  bounded public-source metadata; no real meeting or diplomatic material is
  permitted in the repository or CI.
- Apache License 2.0, contribution, security, support, maintenance, backup,
  release, and community policies are present.

These are local and private-publication results. Replace them with the exact
public commit SHA and successful GitHub Actions run before applying to any
program.

Reachable `main` history completed its private-path sanitization before the
initial publication, which pushed only `refs/heads/main:refs/heads/main`.
Local Codex checkpoint refs and reflogs remain rollback-only state and were not
published. Future publication must never use `--mirror` or share the
repository's `.git` directory. Historical audit documents may retain
pre-sanitization commit IDs where they are explicitly labeled as immutable
snapshots.

## Honest application position

BlueMinutes is pre-release and does not yet claim broad adoption, stars,
downloads, production users, or institutional endorsement. Its application case
rests on clear public-interest and ecosystem importance, active maintenance,
reusable safety and provenance patterns, and a credible solo-maintainer burden.
The [Codex for Open Source form](https://openai.com/form/codex-for-oss/)
expressly permits applicants whose projects do not neatly fit ordinary adoption
signals to explain why the project plays an important role.

## Final public-submission gate

Before a Codex for Open Source application is submitted:

- make the GitHub profile and repository public through separate explicit
  maintainer authorization;
- verify the public repository from a signed-out browser session;
- pass GitHub Actions on the exact `main` commit and record the run URL;
- complete the working-tree and reachable-history sensitive-data review;
- review author and committer email metadata for public exposure, choosing the
  authenticated GitHub noreply identity when privacy is preferred;
- push only the explicit `main` ref, never local Codex refs, reflogs, or a
  mirrored `.git` directory;
- publish only synthetic or already-public screenshots and demonstrations;
- refresh dynamic test counts, project status, repository URL, and application
  character counts; and
- do not manufacture usage metrics, testimonials, affiliations, or security
  guarantees.

Contributor-sized Issues, a short safe demo, and early-user feedback can
strengthen the application after publication, but the official form does not
make them prerequisites. Do not delay a truthful application solely to create
those signals.

Public source publication and public binary distribution remain separate. A
public repository does not authorize a Git tag, GitHub Release, signed build,
notarization, installer, package, or application binary upload.
