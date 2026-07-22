# Roadmap

This roadmap describes maintenance priorities, not delivery promises. Scope and
timing are decided through Issues, ADRs, Pull Requests, passing gates, and
explicit maintainer authorization.

## Completed milestone: private source-publication foundation

- Completed the evidence-integrity remediation and warning-as-error test gate.
- Adopted the maintainer-selected `BlueMinutes` public brand while preserving
  compatibility-sensitive internal identifiers.
- Published source first to a private GitHub repository with Apache License 2.0,
  maintenance policies, synthetic-safe CI, and an Issue/short-branch/Pull
  Request workflow.
- Verified secrets, reachable history, generated files, private repository
  access, and GitHub Actions before any public-conversion decision.

No public repository, Git tag, GitHub Release, distributable binary, signing,
notarization, package, or deployment is part of this milestone unless separately
authorized.

## Candidate milestone: public open-source readiness

- Perform a final professional name and trademark review before distribution;
  the current repository, app-store, package-registry, domain, and web screen is
  preliminary and not legal clearance.
- Add a short demonstration and screenshots using synthetic or already-public
  material only.
- Open several well-scoped Issues for contributor-sized work.
- Run public CI and document the exact supported toolchain.
- Conduct a follow-up security review and publish only safe, bounded findings.
- Make the repository public only after an explicit maintainer command and
  final sensitive-data/history review.

## Candidate milestone: contributor hardening

- Exercise the Issue/branch/Pull Request workflow with real maintenance work.
- Expand synthetic Golden coverage for multilingual uncertainty, negation,
  reservations, and evidence-linked review.
- Review accessibility structure and contributor documentation.
- Evaluate dependency updates individually; do not auto-merge them.

## Candidate milestone: policy-reviewed public data integrations

- Inventory only documented public UN data APIs with stable terms, provenance,
  rate limits, and an identified public-interest use case.
- Require a separate Issue and ADR for each integration, including licensing,
  privacy, security, retention, caching, failure, and rollback analysis.
- Treat every remote payload as untrusted data, bind imported facts to exact
  source provenance, and preserve local/manual fallbacks.
- Keep integrations optional and never present API access as United Nations
  affiliation, authorization, or endorsement.

## Separate future milestone: macOS distribution readiness

This is intentionally separate from source publication. It would require a
selected distribution policy, verified Developer ID identity, signing,
notarization/stapling, Gatekeeper and clean-machine tests, intended-OS TCC and
capture tests, update/rollback proof, icon/localization review, manual
accessibility review, and separate release authorization.

## Persistent priorities

- Diplomatic accuracy and restrained claims.
- Exact evidence traceability and immutable revisions.
- Local-first privacy, bounded providers, and explicit user control.
- Recoverable storage and backward-compatible migrations.
- Modular AI workflows with application-owned validation.
- No real diplomatic or user material in the public repository or CI.
