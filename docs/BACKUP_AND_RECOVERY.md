# Backup and Recovery

Status: active maintenance guidance

MeetingBuddy source code and a MeetingBuddy user workspace are separate. A Git
clone is not a backup of meeting data, and user data must never be copied into
the source repository.

## Source repository recovery

Use the protected GitHub repository and reviewed Git history to recover source.
Do not commit local build output, signing material, credentials, databases,
workspaces, logs, models, or generated briefings as a backup mechanism.

Before a risky source change, record the current commit and work on a
short-lived branch. Reverting code must preserve newer user data and respect
schema compatibility.

## Cold workspace backup

For a user-selected workspace:

1. Stop recording and wait for visible jobs to reach a terminal state.
2. Quit the application and confirm no `MeetingBuddyApp` process remains.
3. Choose a new backup destination on trusted private storage.
4. Copy the complete workspace without merging into an existing destination.
5. Run `script/verify_workspace_backup.sh` and retain the passing report.

Example with explicit operator-selected paths:

```sh
SOURCE_WORKSPACE="/absolute/path/to/MeetingBuddy Workspace"
BACKUP_WORKSPACE="/absolute/path/to/MeetingBuddy Backup"

test -d "$SOURCE_WORKSPACE"
test ! -e "$BACKUP_WORKSPACE"
pgrep -x MeetingBuddyApp >/dev/null && exit 1
/usr/bin/ditto "$SOURCE_WORKSPACE" "$BACKUP_WORKSPACE"
/absolute/path/to/repository/script/verify_workspace_backup.sh \
  "$SOURCE_WORKSPACE" \
  "$BACKUP_WORKSPACE"
```

A copy is not a verified backup unless the verifier prints
`workspace backup verification: PASS`. Keep the application closed for the
entire copy and verification. Full-disk encryption and secure backup retention
remain operator responsibilities.

## Restore and rollback

Restore into a distinct empty path. Never overwrite or merge into the live
workspace, and never point an older incompatible binary at a newer workspace.

```sh
BACKUP_WORKSPACE="/absolute/path/to/MeetingBuddy Backup"
RESTORED_WORKSPACE="/absolute/path/to/MeetingBuddy Restored Copy"

test -d "$BACKUP_WORKSPACE"
test ! -e "$RESTORED_WORKSPACE"
/usr/bin/ditto "$BACKUP_WORKSPACE" "$RESTORED_WORKSPACE"
/absolute/path/to/repository/script/verify_workspace_backup.sh \
  "$BACKUP_WORKSPACE" \
  "$RESTORED_WORKSPACE"
```

Open the restored copy only after verification and only with a schema-compatible
application. Preserve the newer live workspace unchanged until recovery is
accepted.

## Migration recovery

Every ordered SQLite migration must create and verify its pre-migration backup
before changing persistent data. Migration failure must leave no partial
logical state. Downgrade uses a verified backup in a separate path, not an
in-place reverse migration unless a later ADR explicitly designs and tests one.

Application recovery snapshots under `Backups/` provide bounded point-in-time
recovery evidence. They do not replace a separately stored cold whole-workspace
backup.

## Incident priorities

When corruption, data loss, or an incompatible schema is suspected:

1. stop writes and preserve the affected workspace;
2. record the app version and safe error summary without copying sensitive
   content into a public report;
3. make a cold copy before attempting repair;
4. use SQLite integrity and foreign-key checks on a disposable copy;
5. recover to a new path from the newest verified compatible backup; and
6. report product defects with synthetic reproduction material only.

The detailed internal-alpha procedure and tested limitations are in
`docs/RELEASE_BACKUP_AND_ROLLBACK.md`.
