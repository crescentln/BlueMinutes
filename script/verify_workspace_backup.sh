#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-}"
BACKUP_ROOT="${2:-}"

fail() {
    echo "workspace backup verification failed: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ -n "$SOURCE_ROOT" && -n "$BACKUP_ROOT" ]] \
    || fail "usage: $0 SOURCE_WORKSPACE BACKUP_WORKSPACE"
[[ -d "$SOURCE_ROOT" && ! -L "$SOURCE_ROOT" ]] || fail "source workspace is missing or linked"
[[ -d "$BACKUP_ROOT" && ! -L "$BACKUP_ROOT" ]] || fail "backup workspace is missing or linked"
SOURCE_ROOT="$(cd "$SOURCE_ROOT" && pwd -P)"
BACKUP_ROOT="$(cd "$BACKUP_ROOT" && pwd -P)"
[[ "$SOURCE_ROOT" != "$BACKUP_ROOT" ]] || fail "source and backup resolve to the same directory"
case "$BACKUP_ROOT/" in
    "$SOURCE_ROOT/"*) fail "backup must not be nested inside the source workspace" ;;
esac
case "$SOURCE_ROOT/" in
    "$BACKUP_ROOT/"*) fail "source workspace must not be nested inside the backup" ;;
esac
[[ "$(/usr/bin/stat -f '%d:%i' "$SOURCE_ROOT")" \
    != "$(/usr/bin/stat -f '%d:%i' "$BACKUP_ROOT")" ]] \
    || fail "source and backup share one filesystem identity"

REQUIRED_DIRECTORIES=(
    Meetings Models Database Indexes Backups Logs .tasks .temp .Trash manifests
)
for root in "$SOURCE_ROOT" "$BACKUP_ROOT"; do
    [[ -f "$root/workspace_manifest.json" && ! -L "$root/workspace_manifest.json" ]] \
        || fail "workspace manifest is missing or linked: $root"
    [[ -f "$root/Database/meetingbuddy.sqlite" && ! -L "$root/Database/meetingbuddy.sqlite" ]] \
        || fail "workspace database is missing or linked: $root"
    for directory in "${REQUIRED_DIRECTORIES[@]}"; do
        [[ -d "$root/$directory" && ! -L "$root/$directory" ]] \
            || fail "required workspace directory is missing or linked: $root/$directory"
    done
    [[ -z "$(/usr/bin/find "$root" -type l -print -quit)" ]] \
        || fail "workspace contains a symbolic link: $root"
    [[ -z "$(/usr/bin/find "$root" ! -type f ! -type d -print -quit)" ]] \
        || fail "workspace contains a non-file, non-directory entry: $root"
    [[ -z "$(/usr/bin/find "$root/Database" \
        \( -name '*-wal' -o -name '*-shm' -o -name '*-journal' \) -print -quit)" ]] \
        || fail "workspace has live SQLite sidecars; quit BlueMinutes and retry: $root"
    while IFS= read -r -d '' path; do
        relative="${path#"$root"/}"
        [[ "$relative" != *$'\n'* && "$relative" != *$'\t'* ]] \
            || fail "workspace paths containing tabs or newlines are unsupported: $path"
    done < <(/usr/bin/find "$root" -mindepth 1 -print0)
done

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/meetingbuddy-backup-verify.XXXXXX")"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

content_inventory() {
    local root="$1"
    local output="$2"
    (
        cd "$root"
        /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort | while IFS= read -r relative; do
            /usr/bin/shasum -a 256 "$relative"
        done
    ) > "$output"
}

metadata_inventory() {
    local root="$1"
    local output="$2"
    (
        cd "$root"
        /usr/bin/find . -print | LC_ALL=C /usr/bin/sort | while IFS= read -r relative; do
            metadata="$(/usr/bin/stat -f '%HT\t%Lp\t%u\t%g\t%Sf' "$relative")"
            /usr/bin/printf '%s\t%s\n' "$metadata" "$relative"
        done
    ) > "$output"
}

xattr_inventory() {
    local root="$1"
    local output="$2"
    (
        cd "$root"
        /usr/bin/find . -print | LC_ALL=C /usr/bin/sort | while IFS= read -r relative; do
            /usr/bin/printf '%s\t' "$relative"
            attributes="$(/usr/bin/xattr "$relative" 2>/dev/null | LC_ALL=C /usr/bin/sort)"
            if [[ -z "$attributes" ]]; then
                /usr/bin/printf -- '-\n'
                continue
            fi
            while IFS= read -r attribute; do
                [[ "$attribute" != *$'\n'* && "$attribute" != *$'\t'* ]] \
                    || fail "extended attribute names containing tabs or newlines are unsupported"
                value_digest="$(
                    /usr/bin/xattr -px "$attribute" "$relative" \
                        | /usr/bin/tr -d '[:space:]' \
                        | /usr/bin/shasum -a 256 \
                        | /usr/bin/awk '{print $1}'
                )"
                /usr/bin/printf '%s=%s;' "$attribute" "$value_digest"
            done <<< "$attributes"
            /usr/bin/printf '\n'
        done
    ) > "$output"
}

content_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.sha256"
content_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.sha256"
/usr/bin/cmp -s "$TEMP_DIR/source.sha256" "$TEMP_DIR/backup.sha256" \
    || fail "file inventory, paths, or SHA-256 digests differ"

metadata_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.metadata"
metadata_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.metadata"
/usr/bin/cmp -s "$TEMP_DIR/source.metadata" "$TEMP_DIR/backup.metadata" \
    || fail "file types, paths, ownership, or POSIX modes differ"

xattr_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.xattrs"
xattr_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.xattrs"
/usr/bin/cmp -s "$TEMP_DIR/source.xattrs" "$TEMP_DIR/backup.xattrs" \
    || fail "extended attributes differ"

while IFS= read -r -d '' source_path; do
    relative="${source_path#"$SOURCE_ROOT"/}"
    backup_path="$BACKUP_ROOT/$relative"
    [[ "$(/usr/bin/stat -f '%d:%i' "$source_path")" \
        != "$(/usr/bin/stat -f '%d:%i' "$backup_path")" ]] \
        || fail "backup file shares source storage through a hard link: $relative"
    [[ "$(/usr/bin/stat -f '%l' "$backup_path")" == "1" ]] \
        || fail "backup file has multiple hard links: $relative"
done < <(/usr/bin/find "$SOURCE_ROOT" -type f -print0)

for database in \
    "$SOURCE_ROOT/Database/meetingbuddy.sqlite" \
    "$BACKUP_ROOT/Database/meetingbuddy.sqlite"; do
    [[ "$(/usr/bin/sqlite3 -readonly "$database" 'PRAGMA quick_check;')" == "ok" ]] \
        || fail "SQLite quick_check failed: $database"
    [[ -z "$(/usr/bin/sqlite3 -readonly "$database" 'PRAGMA foreign_key_check;')" ]] \
        || fail "SQLite foreign_key_check failed: $database"
done

CURRENT_UID="$(/usr/bin/id -u)"
while IFS= read -r -d '' path; do
    mode="$(/usr/bin/stat -f '%Lp' "$path")"
    uid="$(/usr/bin/stat -f '%u' "$path")"
    permission_token="$(/bin/ls -lde "$path" | /usr/bin/head -n 1 | /usr/bin/awk '{print $1}')"
    [[ "$uid" == "$CURRENT_UID" ]] || fail "backup item is not owned by the current user: $path"
    [[ "$permission_token" != *+* ]] || fail "backup item has an access-control list: $path"
    (( (8#$mode & 8#077) == 0 )) || fail "group/other permissions are present: $path ($mode)"
    if [[ -d "$path" ]]; then
        (( (8#$mode & 8#700) == 8#700 )) \
            || fail "backup directory is not owner-readable, writable, and searchable: $path ($mode)"
    else
        (( (8#$mode & 8#600) == 8#600 )) \
            || fail "backup file is not owner-readable and writable: $path ($mode)"
    fi
done < <(/usr/bin/find "$BACKUP_ROOT" -mindepth 0 -print0)

content_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.final.sha256"
content_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.final.sha256"
metadata_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.final.metadata"
metadata_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.final.metadata"
xattr_inventory "$SOURCE_ROOT" "$TEMP_DIR/source.final.xattrs"
xattr_inventory "$BACKUP_ROOT" "$TEMP_DIR/backup.final.xattrs"
for inventory in sha256 metadata xattrs; do
    /usr/bin/cmp -s "$TEMP_DIR/source.$inventory" "$TEMP_DIR/source.final.$inventory" \
        || fail "source workspace changed during verification; quit BlueMinutes and repeat a cold backup"
    /usr/bin/cmp -s "$TEMP_DIR/backup.$inventory" "$TEMP_DIR/backup.final.$inventory" \
        || fail "backup workspace changed during verification; quit BlueMinutes and repeat a cold backup"
done

FILE_COUNT="$(/usr/bin/wc -l < "$TEMP_DIR/source.sha256" | /usr/bin/tr -d ' ')"
BACKUP_KIB="$(/usr/bin/du -sk "$BACKUP_ROOT" | /usr/bin/awk '{print $1}')"
echo "workspace backup verification: PASS"
echo "source: $SOURCE_ROOT"
echo "backup: $BACKUP_ROOT"
echo "verified independent files: $FILE_COUNT"
echo "backup size KiB: $BACKUP_KIB"
