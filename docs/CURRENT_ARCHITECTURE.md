# Current Architecture

Status: Task 002 accepted
Owner: Codex
Last updated: 2026-07-17
Purpose: Record the observed repository state only; target design belongs in
`TARGET_ARCHITECTURE.md`.

## Executive state

MeetingBuddy is a confirmed greenfield project. The user accepted the Task 001
audit on 2026-07-17 and confirmed this directory as the canonical root.

The repository currently contains governance and architecture documentation
only. There is no product implementation and no user meeting data.

## Repository state

- Git repository: initialized locally on an unborn `main` branch during Task
  002; no commit has been authorized or created.
- Product source files: none.
- Xcode projects/workspaces: none.
- Swift Package Manager manifests: none.
- Build targets and application entry points: none.
- Dependencies and lockfiles: none.
- Tests, fixtures, CI, formatter, and linter configuration: none.
- Databases, migrations, media, models, credentials, and runtime workspaces:
  none.

The accepted evidence and original commands are preserved in
`audits/TASK-001_REPOSITORY_AUDIT.md`.

## Implemented layers

| Layer | Current implementation |
| --- | --- |
| Application/UI | None |
| Domain | None |
| Persistence and workspace | None |
| Task execution and recovery | None |
| Media | None |
| Transcription, translation, and AI | None |
| Automation/CLI/MCP | None |
| Historical retrieval | None |

The current executable data flow is therefore empty. The only operational flow
is the user-authorized Codex task protocol defined by the governing documents.

## Governance now present

Task 002 adds:

- repository-local operating instructions;
- current and target architecture boundaries;
- domain, storage, security, acceptance, and implementation-plan documents;
- accepted and proposed ADRs;
- a concise execution-state ledger;
- a persisted copy of the accepted Task 001 audit;
- a local Git repository for working-tree visibility and future rollback.

These artifacts do not implement product behavior.

## Known limitations

- There is no build or test command until Task 003A creates the first approved
  Swift module.
- There is no HEAD commit, so Git can report untracked files but cannot yet
  provide historical rollback.
- Distribution/sandbox details and concrete third-party dependencies remain
  open decisions recorded in the ADR index.
- No product quality gate can be marked as passing solely from this
  documentation baseline.

## Next permitted transition

After Task 002 is accepted, Task 003A may create the foundational domain module
and tests. No other implementation task may start first.
