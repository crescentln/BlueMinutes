# Open-Source Readiness Evidence

Status: public-source evidence map; verified on `v0.1.0` release baseline `b45b38a`
Last verified: 2026-07-22

This document gives reviewers and contributors a short path from project claims
to repository evidence. It is not a certification, adoption claim, release
announcement, or substitute for the final public CI and sensitive-data gates.

## Reviewer quick path

| Question | Repository evidence | What it establishes |
| --- | --- | --- |
| What problem does the project address? | [README](../README.md) and [briefing foundation](BRIEFING_FOUNDATION.md) | A multilateral-meeting workflow extending beyond generic speech-to-text into provenance, position review, evidence-linked briefing, and historical context. |
| Is there a real implementation? | [Current architecture](CURRENT_ARCHITECTURE.md), [domain contracts](DOMAIN_CONTRACTS.md), and [Sources](../Sources/) | A native Swift modular monolith with bounded application, persistence, task, media, AI, feature, and automation layers. |
| Is quality actively maintained? | [CI workflow](../.github/workflows/ci.yml), [execution state](CODEX_EXECUTION_STATE.md), and [Tests](../Tests/) | The local and public-GitHub warning-as-error gates pass a 248-test suite in 43 suites; three installed-model routes remain explicit opt-in checks rather than ordinary-CI claims. |
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
- The `v0.1.0` release baseline
  `b45b38abc68739d008bad733479286438a4b4bc8` passes
  [exact-main GitHub Actions run 29969615653](https://github.com/crescentln/BlueMinutes/actions/runs/29969615653).
  Attempt 2 succeeded on the unchanged SHA after attempt 1 hit the documented
  shared-runner wall-clock performance fluctuation.
- Signed-out repository and raw README requests return HTTP 200, the
  unauthenticated API reports public visibility, and anonymous Git resolves the
  peeled `v0.1.0` tag to the same exact source-release baseline.
- `main` requires Pull Requests and the strict `Swift build and test` check,
  applies protection to administrators, requires linear history and resolved
  conversations, and rejects force-push and deletion. Dependabot security
  updates, secret scanning/push protection, private vulnerability reporting,
  and CodeQL default setup are enabled.
- Tests and examples use project-authored synthetic material or explicitly
  bounded public-source metadata; no real meeting or diplomatic material is
  permitted in the repository or CI.
- Apache License 2.0, contribution, security, support, maintenance, backup,
  release, and community policies are present.

These are local and public-source results. The exact `v0.1.0` source-release
baseline and its successful GitHub Actions run are recorded above; later source
releases must record their own protected-`main` evidence.

Reachable `main` history completed its private-path sanitization before the
initial publication, which pushed only `refs/heads/main:refs/heads/main`.
Local Codex checkpoint refs and reflogs remain rollback-only state and were not
published. Future publication must never use `--mirror` or share the
repository's `.git` directory. Historical audit documents may retain
pre-sanitization commit IDs where they are explicitly labeled as immutable
snapshots.

## Honest application position

BlueMinutes has an early-stage `v0.1.0` source release and does not claim broad
adoption, production users, or institutional endorsement. Its application case
rests on clear public-interest and ecosystem importance, active maintenance,
reusable safety and provenance patterns, and a credible solo-maintainer burden.
The [Codex for Open Source form](https://openai.com/form/codex-for-oss/)
expressly permits applicants whose projects do not neatly fit ordinary adoption
signals to explain why the project plays an important role.

## Public-submission gate

The repository-side publication gates are complete:

- the GitHub profile and repository are public;
- signed-out HTTP, unauthenticated API, and anonymous Git checks pass;
- GitHub Actions passes on the exact public baseline;
- working-tree and reachable-history sensitive-data checks pass;
- reachable author and committer identities use GitHub noreply/system
  identities; and
- the protected `main` branch, annotated `v0.1.0` tag, and regular
  [GitHub source Release](https://github.com/crescentln/BlueMinutes/releases/tag/v0.1.0)
  are public; the Release has no uploaded binary asset, deployment, or Codex
  rollback ref.

Immediately before submitting an application, the maintainer must still:

- enter and verify the private account-associated email and OpenAI Organization
  ID directly in the form;
- recount the live form fields and confirm every factual statement;
- use only synthetic or already-public screenshots and demonstrations; and
- avoid manufactured usage metrics, testimonials, affiliations, or security
  guarantees.

Contributor-sized Issues, a short safe demo, and early-user feedback can
strengthen the application after publication, but the official form does not
make them prerequisites. Do not delay a truthful application solely to create
those signals.

Public source publication and public binary distribution remain separate. The
explicitly authorized `v0.1.0` tag and GitHub source Release contain no uploaded
app bundle, installer, or maintainer-built ZIP and do not authorize a signed
build, notarization, installer, or future application-binary upload.
