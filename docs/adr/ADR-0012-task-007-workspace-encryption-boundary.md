# ADR-0012: Task 007 Workspace Encryption Boundary

Status: Accepted for Task 007 implementation; task acceptance remains user-gated
Date: 2026-07-18
Decision owners: Codex under the user's Task 007 authorization
Applies from: Task 007

## Context

MeetingBuddy stores source media, transcripts, semantic revisions, task state,
logs, exports, backups, and recovery evidence in a user-selected local
workspace. Task 007 must decide whether to introduce application-level
workspace encryption and, if so, prove key recovery, rotation, backup,
corruption, migration, and rollback behavior.

The implemented product path is a single-user local macOS application. Its
secrets use macOS Keychain, managed workspace directories and files use private
POSIX permissions, no meeting-data network adapter is authorized, and the
existing recovery contract depends on readable SQLite backups and hash-verified
workspace files. The application cannot truthfully claim that application-level
encryption protects data while the user is signed in and the process holds an
unlocked key. It also cannot assume that FileVault is enabled on every host.

## Decision

- Do not add application-level workspace encryption in Task 007.
- Keep credentials and provider secrets exclusively in macOS Keychain. Never
  derive a workspace-data key from a user password or store a recovery key in
  the workspace.
- Keep workspace roots and directories at mode `0700`; keep managed files,
  SQLite database/WAL/SHM files, logs, exports, manifests, and recovery
  artifacts at mode `0600`. Treat a broader mode as a visible storage-report
  finding.
- Rely on the operator's macOS account controls and volume encryption, such as
  FileVault when enabled, for data-at-rest protection below the application
  boundary. MeetingBuddy does not label a workspace encrypted merely because
  the host may support FileVault.
- Preserve the existing readable format: SQLite schema v6 plus hashed managed
  files and versioned recovery artifacts. Fresh and v1-v5 workspaces migrate
  without keys, and the pre-migration online backup remains readable by the
  prior application version.
- Keep no-outbound mode independent from disk encryption. Disabling providers
  and telemetry must leave all supported local review, recovery, and export
  paths usable.
- Revisit this decision before supporting shared/multi-user workspaces,
  removable-media guarantees, cloud synchronization, organization-managed
  escrow, regulated tenant keys, or an explicit user requirement for a locked
  workspace while signed in.

## Key, backup, corruption, and migration consequences

- There is no application data-encryption key to lose, rotate, escrow, or
  recover in Task 007. Keychain loss can affect future provider credentials but
  cannot make existing workspace content unreadable.
- SQLite online backups and recovery exports remain independently verifiable
  and readable. No backup silently depends on a key stored only on the source
  Mac.
- Corruption detection continues to use SQLite integrity checks, immutable
  semantic hashes, managed-file SHA-256 values, migration checksums, and
  recovery-manifest hashes. Encryption is not substituted for integrity.
- Migration 006 is additive and byte-preserving for accepted v5 semantic rows.
  Rollback restores the verified pre-migration schema-v5 backup; it does not
  discard keys or transform user data.

## Rejected alternatives

- SQLCipher or another encrypted SQLite build is rejected for this task. It
  would add a native dependency and address only metadata, not managed media,
  exports, logs, indexes, or recovery files.
- A custom encrypted workspace container is rejected because it would require
  a complete authenticated format, streaming large-file I/O, key rotation,
  crash-safe rekeying, backup/restore, corruption isolation, migration, and
  recovery design that Task 007 cannot safely infer.
- A password-derived key is rejected because forgotten passwords would create
  an unrecoverable data-loss path and weak passwords would create misleading
  security.
- Deleting a key as a substitute for deleting files is rejected. APFS clones,
  snapshots, backups, exported plaintext, and unlocked process memory remain
  separate boundaries.

## Residual risk

- A workspace on an unencrypted volume is readable to an actor who obtains
  sufficient filesystem or account authority. Private POSIX modes do not
  protect against a compromised user session, root, malware running as the
  user, or copied backups.
- Local exports and backups are intentionally readable to the authorized user
  and require the same host/volume protection as the primary workspace.
- File unlink does not guarantee forensic erasure on APFS, SSD wear leveling,
  snapshots, clones, or backups.

## Validation required before Task 007 completion

- Fresh and v1-v5 migration, failure rollback, backup readability, and
  byte-preservation tests.
- Private-mode checks for workspace directories, database sidecars, managed
  files, logs, exports, and recovery artifacts.
- Keychain round-trip, invalid identifier, empty/oversized value, log, source,
  and workspace-secret scans.
- Explicit storage UI wording for Trash retention and unlink semantics.
- Dependency inventory proving no encryption library or custom native binary
  was added.
