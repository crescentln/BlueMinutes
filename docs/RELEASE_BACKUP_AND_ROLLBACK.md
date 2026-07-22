# Release Backup and Rollback

Status: Task 011 internal-alpha procedure
Applies to: a user-selected MeetingBuddy workspace
Safety rule: preserve the newer workspace; restore into a distinct empty path

## Before changing the application

1. Stop recording and wait for all visible jobs to reach a terminal state.
2. Quit MeetingBuddy normally.
3. Confirm that no `MeetingBuddyApp` process remains.
4. Keep the source workspace and backup destination on trusted, private
   storage. Full-disk encryption is an operator control; MeetingBuddy does not
   add application-level workspace encryption under ADR-0012.
5. Use a new backup destination. Do not merge into or overwrite an existing
   backup.

Example, with explicit absolute paths chosen by the operator:

```bash
SOURCE_WORKSPACE="/absolute/path/to/MeetingBuddy Workspace"
BACKUP_WORKSPACE="/absolute/path/to/MeetingBuddy Backup 2026-07-21"

test -d "$SOURCE_WORKSPACE"
test ! -e "$BACKUP_WORKSPACE"
pgrep -x MeetingBuddyApp >/dev/null && {
  echo "Quit MeetingBuddy before backup" >&2
  exit 1
}

/usr/bin/ditto "$SOURCE_WORKSPACE" "$BACKUP_WORKSPACE"
/absolute/path/to/MeetingBuddy/script/verify_workspace_backup.sh \
  "$SOURCE_WORKSPACE" \
  "$BACKUP_WORKSPACE"
```

The verifier fails if the paths resolve to one directory, a required workspace
directory is absent, either workspace is nested inside the other, any symbolic
link or special file is present, or live SQLite `-wal`/`-shm`/`-journal`
sidecars remain. It also requires matching complete content, type, mode,
ownership, BSD-flag, and extended-attribute inventories; distinct
source/backup inode identity for every file; one link per backup file; clean
SQLite `quick_check` and `foreign_key_check` results; current-user ownership;
no ACL; owner-usable files/directories; and no group/other permissions. It
recomputes content, metadata, and extended-attribute inventories at the end
and fails if either tree changed during verification.

The verifier does not take an OS-level filesystem or application lock. Keep
MeetingBuddy quit throughout the copy and verification; an inventory-stable
pass detects observed mutation but cannot make a live copy safe.

Do not treat a copy as a backup until the verifier prints
`workspace backup verification: PASS`.

## Application update

The initial update policy is manual. Automatic updates are unapproved.

For the Task 011 local internal-alpha release set:

1. Run `script/verify_release_candidate.sh` against
   `dist/MeetingBuddy-0.1.0-internal-alpha/`.
2. Retain `release-manifest.json`, `source-files.sha256`, and the ZIP digest
   together with the app and archive.
3. Expand the ZIP into a new temporary directory and verify the extracted app
   if performing an independent manual inspection; the release-set verifier
   already performs this step.
4. Do not replace an installed application unless the signature identity,
   notarization ticket, Gatekeeper result, version, and rollback plan meet the
   intended distribution policy.

The current archive is ad-hoc signed and not notarized. It is not approved for
installation or distribution outside this development Mac.

## Safe application rollback

Schema v10 is intentionally rejected by older binaries that understand only a
prior schema. An older app must never be pointed at the newer live workspace.

To roll back:

1. Quit MeetingBuddy and preserve the entire newer workspace unchanged.
2. Select the verified cold backup made before the application change.
3. Restore that backup into a new, empty directory; do not copy over the live
   workspace.
4. Verify the restored copy against the backup.
5. Open the restored copy with the older application only after verification.

Example:

```bash
BACKUP_WORKSPACE="/absolute/path/to/MeetingBuddy Backup 2026-07-21"
RESTORED_WORKSPACE="/absolute/path/to/MeetingBuddy Rollback Copy"

test -d "$BACKUP_WORKSPACE"
test ! -e "$RESTORED_WORKSPACE"
/usr/bin/ditto "$BACKUP_WORKSPACE" "$RESTORED_WORKSPACE"
/absolute/path/to/MeetingBuddy/script/verify_workspace_backup.sh \
  "$BACKUP_WORKSPACE" \
  "$RESTORED_WORKSPACE"
```

If no verified pre-upgrade backup exists, do not downgrade the live workspace.
Continue with the current compatible binary, preserve recovery snapshots, and
request a specific migration/export recovery plan. A recovery snapshot inside
`Backups/` proves an application recovery anchor; it is not a substitute for a
cold whole-workspace backup stored separately.

## Tested evidence

Task 011 exercised this procedure only on a disposable synthetic workspace:

- source and copied backup had three files and a 20 KiB allocated footprint;
- both SQLite databases passed `quick_check` and `foreign_key_check`;
- the complete content, metadata, BSD-flag, extended-attribute, ownership,
  permission, and independent-file inventories matched, and final inventories
  still matched their initial values;
- a hard-linked backup file and a read-only backup file were each rejected;
- a separate full-suite regression copied an application-created schema-v10
  workspace, reopened it through `LocalWorkspaceService` and
  `SQLitePersistenceStore`, and verified schema, SQLite integrity, and a
  distinct database file identity; and
- the disposable fixture was moved to macOS Trash after the test, so it remains
  recoverable until Trash is emptied.

No real user workspace or real meeting data was read, copied, restored, or
deleted by Task 011.
