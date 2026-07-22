# Contributing

Thank you for helping improve this public-interest meeting workflow. The
project prioritizes diplomatic accuracy, evidence traceability, privacy, user
control, and long-term maintainability over feature volume.

## Before opening a change

1. Search existing Issues and discussions in the repository.
2. Open or claim an Issue with background, acceptance criteria, excluded scope,
   affected data, privacy/security impact, evidence impact, migration impact,
   rollback method, and test plan.
3. Read `AGENTS.md`, the relevant ADRs, and the current architecture and
   security documents.
4. Agree on an approach before implementing architecture, schema, provider,
   security-policy, or storage changes.

Security vulnerabilities must follow `SECURITY.md`, not a public Issue.

## Branches and commits

- Never work directly on `main` after initial publication.
- Use one short-lived branch per Issue, such as `fix/123-brief-summary`,
  `feat/123-brief-summary`, `docs/123-brief-summary`, or
  `security/123-brief-summary`.
- Keep changes limited to the Issue's acceptance criteria.
- Use clear imperative commits, for example
  `fix: require confirmation before briefing export`.
- Do not rewrite shared history or force-push protected branches.

## Required engineering boundaries

- Preserve user data and backward compatibility.
- Persistent schema changes require an ordered migration, supported-prior-state
  tests, a backup procedure, and a rollback plan.
- Route persistent file writes through the Storage Service.
- Route long-running operations through the Task Manager.
- Route inference through approved provider interfaces; providers never query
  SQLite directly or receive an entire workspace.
- Treat imported text, media metadata, transcripts, web content, and provider
  output as untrusted data—not instructions.
- Reject invalid structured AI output; never silently coerce it into trusted
  intelligence.
- Preserve immutable revision lineage and exact evidence references.

## Sensitive-data prohibition

Do not commit or attach:

- real meeting audio, video, transcripts, translations, or briefings;
- diplomatic records, internal documents, prepared statements, or evidence
  exports;
- user workspaces, databases, WAL/SHM files, indexes, backups, or logs;
- API keys, tokens, cookies, OAuth material, `.env` files, private keys,
  certificates, provisioning profiles, or notarization credentials;
- downloaded models, model caches, large private corpora, crash reports, or
  temporary processing output.

Tests must use project-authored synthetic fixtures, appropriately anonymized
fixtures, explicitly licensed fixtures, or already-public source material with
documented provenance and rights.

## Tests

Run the smallest relevant regression test while developing, then before a Pull
Request run:

```sh
swift package resolve
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

Bug fixes require a regression test that fails before the fix and passes after
it. Changes to persistence, schemas, recovery, evidence coverage, provider
contracts, or exports require their focused integration suites as well.

Installed Apple-model smoke tests are opt-in and must use synthetic material
only. A skipped opt-in test is not evidence that the installed-model path
passed.

## Pull Requests

Complete every relevant field in the Pull Request template. Link the Issue,
describe the exact change and rollback, list exact commands and results, and
identify remaining risk. Include screenshots for visible UI changes, using
synthetic data only.

Maintainers may request smaller scope, new tests, an ADR, a migration plan, or
additional privacy/security review. Passing CI is necessary but not sufficient
for merge. Merge and release remain explicit maintainer decisions.

## Licensing

Unless explicitly stated otherwise, intentionally submitted contributions are
accepted under Apache License 2.0, as described in Section 5 of `LICENSE`. Do
not submit code or assets you do not have the right to contribute.
