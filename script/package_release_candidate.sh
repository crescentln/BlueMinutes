#!/bin/bash
set -euo pipefail

APP_PRODUCT="MeetingBuddyApp"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST="$ROOT_DIR/Configuration/MeetingBuddy-Info.plist"
ENTITLEMENTS="$ROOT_DIR/Configuration/MeetingBuddy.entitlements"
PRIVACY_MANIFEST="$ROOT_DIR/Configuration/PrivacyInfo.xcprivacy"
APP_ICON="$ROOT_DIR/Configuration/Branding/BlueMinutes.icns"
GRDB_LICENSE="$ROOT_DIR/ThirdPartyNotices/GRDB-LICENSE.txt"
PACKAGE_RESOLVED="$ROOT_DIR/Package.resolved"
VERIFY_SCRIPT="$ROOT_DIR/script/verify_release_candidate.sh"
SIGN_IDENTITY="${MEETINGBUDDY_SIGN_IDENTITY:--}"

fail() {
    echo "release packaging failed: $*" >&2
    exit 1
}

verify_release() {
    local target="$1"
    local mode="$2"
    local status
    local attempt
    for attempt in 1 2; do
        if /bin/bash "$VERIFY_SCRIPT" "$target" "$mode"; then
            return 0
        else
            status=$?
        fi
        if [[ "$status" -ne 137 || "$attempt" -eq 2 ]]; then
            return "$status"
        fi
        echo "release verifier was terminated by the host; retrying once" >&2
        /bin/sleep 2
    done
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "the validated development package is Apple Silicon only"
for required in \
    "$INFO_PLIST" "$ENTITLEMENTS" "$PRIVACY_MANIFEST" "$APP_ICON" "$GRDB_LICENSE" \
    "$PACKAGE_RESOLVED" "$VERIFY_SCRIPT"; do
    [[ -f "$required" && ! -L "$required" ]] || fail "missing or linked release input: $required"
done

/usr/bin/plutil -lint "$INFO_PLIST" "$ENTITLEMENTS" "$PRIVACY_MANIFEST" >/dev/null
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PUBLIC_PRODUCT_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")"
[[ "$BUNDLE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "bundle short version must be a three-component semantic version"
[[ "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]] \
    || fail "bundle build version must be a positive integer"
[[ "$PUBLIC_PRODUCT_NAME" == "BlueMinutes" ]] \
    || fail "unexpected public product name: $PUBLIC_PRODUCT_NAME"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")" == "BlueMinutes" ]] \
    || fail "unexpected public bundle name"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")" == "$APP_PRODUCT" ]] \
    || fail "unexpected compatibility executable"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" \
    == "com.meetingbuddy.desktop" ]] || fail "unexpected compatibility bundle identifier"

APP_BUNDLE_NAME="$PUBLIC_PRODUCT_NAME.app"
RELEASE_SET_NAME="$PUBLIC_PRODUCT_NAME-$BUNDLE_VERSION-development"
ARCHIVE_NAME="$RELEASE_SET_NAME.zip"

if [[ -e "$DIST_DIR" || -L "$DIST_DIR" ]]; then
    [[ -d "$DIST_DIR" && ! -L "$DIST_DIR" ]] \
        || fail "dist exists but is not a real directory"
else
    /bin/mkdir -m 0700 "$DIST_DIR"
fi

BUILD_ROOT="$(/usr/bin/mktemp -d "$DIST_DIR/.swiftpm-release.XXXXXX")"
STAGE_ROOT="$(/usr/bin/mktemp -d "$DIST_DIR/.release-stage.XXXXXX")"
EXTRACT_ROOT="$(/usr/bin/mktemp -d "$DIST_DIR/.release-extract.XXXXXX")"

cleanup() {
    local path
    for path in "$BUILD_ROOT" "$STAGE_ROOT" "$EXTRACT_ROOT"; do
        case "$path" in
            "$DIST_DIR"/.swiftpm-release.*|"$DIST_DIR"/.release-stage.*|"$DIST_DIR"/.release-extract.*)
                [[ ! -e "$path" ]] || /bin/rm -rf "$path"
                ;;
            *)
                echo "refusing unexpected cleanup path: $path" >&2
                ;;
        esac
    done
}
trap cleanup EXIT

RELEASE_SET="$STAGE_ROOT/$RELEASE_SET_NAME"
/usr/bin/install -d -m 0700 "$RELEASE_SET"

write_source_inventory() {
    local output="$1"
    local relative
    local digest
    : > "$output"
    while IFS= read -r -d '' relative; do
        [[ "$relative" != *$'\n'* && "$relative" != *$'\t'* ]] \
            || fail "source paths containing tabs or newlines are unsupported"
        [[ -f "$ROOT_DIR/$relative" && ! -L "$ROOT_DIR/$relative" ]] \
            || fail "source inventory input is missing, non-regular, or linked: $relative"
        digest="$(/usr/bin/shasum -a 256 "$ROOT_DIR/$relative" | /usr/bin/awk '{print $1}')"
        /usr/bin/printf '%s  %s\n' "$digest" "$relative" >> "$output"
    done < <(/usr/bin/git -C "$ROOT_DIR" ls-files -z)
    [[ -s "$output" ]] || fail "source inventory is empty"
}

source_status() {
    /usr/bin/git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all
}

exact_git_tag() {
    local revision="$1"
    local tags
    local count
    tags="$(/usr/bin/git -C "$ROOT_DIR" tag --points-at "$revision" | LC_ALL=C /usr/bin/sort)"
    count="$(/usr/bin/printf '%s\n' "$tags" | /usr/bin/sed '/^$/d' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    [[ "$count" -le 1 ]] || fail "release source has more than one exact tag"
    if [[ -n "$tags" ]]; then
        [[ "$(/usr/bin/git -C "$ROOT_DIR" cat-file -t "refs/tags/$tags")" == "tag" ]] \
            || fail "exact release tag must be annotated"
    fi
    /usr/bin/printf '%s' "$tags"
}

write_bundle_inventory() {
    local bundle="$1"
    local output="$2"
    local relative
    local digest
    : > "$output"
    while IFS= read -r relative; do
        relative="${relative#./}"
        [[ -n "$relative" && "$relative" != *$'\t'* ]] \
            || fail "unsupported app-bundle inventory path"
        [[ -f "$bundle/$relative" && ! -L "$bundle/$relative" ]] \
            || fail "app-bundle inventory input is missing, non-regular, or linked: $relative"
        digest="$(/usr/bin/shasum -a 256 "$bundle/$relative" | /usr/bin/awk '{print $1}')"
        /usr/bin/printf '%s  %s\n' "$digest" "$relative" >> "$output"
    done < <(
        cd "$bundle"
        /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort
    )
    [[ -s "$output" ]] || fail "app-bundle inventory is empty"
}

PREBUILD_SOURCE_INVENTORY="$STAGE_ROOT/prebuild-source-files.sha256"
write_source_inventory "$PREBUILD_SOURCE_INVENTORY"
PREBUILD_GIT_HEAD="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
PREBUILD_GIT_TREE="$(/usr/bin/git -C "$ROOT_DIR" rev-parse 'HEAD^{tree}')"
PREBUILD_GIT_TAG="$(exact_git_tag "$PREBUILD_GIT_HEAD")"
PREBUILD_SOURCE_STATUS="$(source_status)"
[[ -z "$PREBUILD_SOURCE_STATUS" ]] \
    || fail "the complete repository must be clean before development packaging"

cd "$ROOT_DIR"
/usr/bin/swift build \
    --configuration release \
    --scratch-path "$BUILD_ROOT" \
    --product "$APP_PRODUCT" \
    -Xswiftc -warnings-as-errors
BIN_DIR="$(/usr/bin/swift build --configuration release --scratch-path "$BUILD_ROOT" --show-bin-path)"
APP_BINARY="$BIN_DIR/$APP_PRODUCT"
GRDB_RESOURCE_BUNDLE="$BIN_DIR/GRDB_GRDB.bundle"
[[ -f "$APP_BINARY" && ! -L "$APP_BINARY" ]] || fail "release executable was not produced"
[[ -d "$GRDB_RESOURCE_BUNDLE" && ! -L "$GRDB_RESOURCE_BUNDLE" ]] \
    || fail "GRDB privacy resource bundle was not produced"

STAGED_APP="$RELEASE_SET/$APP_BUNDLE_NAME"
CONTENTS="$STAGED_APP/Contents"
/usr/bin/install -d -m 0755 \
    "$CONTENTS/MacOS" \
    "$CONTENTS/Resources/ThirdPartyNotices"
/usr/bin/install -m 0755 "$APP_BINARY" "$CONTENTS/MacOS/$APP_PRODUCT"
/usr/bin/install -m 0644 "$INFO_PLIST" "$CONTENTS/Info.plist"
/usr/bin/install -m 0644 "$APP_ICON" "$CONTENTS/Resources/BlueMinutes.icns"
/usr/bin/install -m 0644 "$PRIVACY_MANIFEST" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
/usr/bin/install -m 0644 "$GRDB_LICENSE" \
    "$CONTENTS/Resources/ThirdPartyNotices/GRDB-LICENSE.txt"
/usr/bin/ditto "$GRDB_RESOURCE_BUNDLE" "$CONTENTS/Resources/GRDB_GRDB.bundle"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "$ENTITLEMENTS" \
        --sign - \
        "$STAGED_APP"
else
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$STAGED_APP"
fi

verify_release "$STAGED_APP" development

STAGED_ARCHIVE="$RELEASE_SET/$ARCHIVE_NAME"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGED_ARCHIVE"
(
    cd "$RELEASE_SET"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME"
) > "$RELEASE_SET/$ARCHIVE_NAME.sha256"
/usr/bin/ditto -x -k "$STAGED_ARCHIVE" "$EXTRACT_ROOT"
verify_release "$EXTRACT_ROOT/$APP_BUNDLE_NAME" development

SOURCE_INVENTORY="$RELEASE_SET/source-files.sha256"
write_source_inventory "$SOURCE_INVENTORY"
/usr/bin/cmp -s "$PREBUILD_SOURCE_INVENTORY" "$SOURCE_INVENTORY" \
    || fail "build/test/configuration/script source changed during the release build"

GIT_HEAD="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
[[ "$GIT_HEAD" == "$PREBUILD_GIT_HEAD" ]] \
    || fail "Git HEAD changed during the release build"
GIT_TREE="$(/usr/bin/git -C "$ROOT_DIR" rev-parse 'HEAD^{tree}')"
[[ "$GIT_TREE" == "$PREBUILD_GIT_TREE" ]] \
    || fail "Git tree changed during the release build"
GIT_TAG="$(exact_git_tag "$GIT_HEAD")"
[[ "$GIT_TAG" == "$PREBUILD_GIT_TAG" ]] \
    || fail "exact Git tag changed during the release build"
[[ "$(source_status)" == "$PREBUILD_SOURCE_STATUS" ]] \
    || fail "repository status changed during the release build"
SOURCE_INVENTORY_SHA256="$(/usr/bin/shasum -a 256 "$SOURCE_INVENTORY" | /usr/bin/awk '{print $1}')"
SOURCE_FILE_COUNT="$(/usr/bin/wc -l < "$SOURCE_INVENTORY" | /usr/bin/tr -d ' ')"
PACKAGE_RESOLVED_SHA256="$(/usr/bin/shasum -a 256 "$PACKAGE_RESOLVED" | /usr/bin/awk '{print $1}')"
ARCHIVE_SHA256="$(/usr/bin/shasum -a 256 "$STAGED_ARCHIVE" | /usr/bin/awk '{print $1}')"
EXECUTABLE_SHA256="$(/usr/bin/shasum -a 256 "$CONTENTS/MacOS/$APP_PRODUCT" | /usr/bin/awk '{print $1}')"
APP_BUNDLE_INVENTORY="$STAGE_ROOT/app-files.sha256"
write_bundle_inventory "$STAGED_APP" "$APP_BUNDLE_INVENTORY"
APP_BUNDLE_SHA256="$(/usr/bin/shasum -a 256 "$APP_BUNDLE_INVENTORY" | /usr/bin/awk '{print $1}')"
BUILT_AT_UTC="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
SWIFT_VERSION="$(/usr/bin/swift --version 2>&1 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/[[:space:]]*$//')"
XCODE_VERSION="$(/usr/bin/xcodebuild -version | /usr/bin/paste -sd ' ' -)"
HOST_OS_VERSION="$(/usr/bin/sw_vers -productVersion)"

SIGNATURE_REPORT="$STAGE_ROOT/signature.txt"
/usr/bin/codesign -dv --verbose=4 "$STAGED_APP" > "$SIGNATURE_REPORT" 2>&1
SIGNATURE_KIND="developer-id"
TEAM_IDENTIFIER="$(/usr/bin/sed -n 's/^TeamIdentifier=//p' "$SIGNATURE_REPORT" | /usr/bin/head -n 1)"
if /usr/bin/grep -q '^Signature=adhoc$' "$SIGNATURE_REPORT"; then
    SIGNATURE_KIND="ad-hoc"
    TEAM_IDENTIFIER=""
fi

/usr/bin/jq -n \
    --arg built_at_utc "$BUILT_AT_UTC" \
    --arg git_head "$GIT_HEAD" \
    --arg git_tree "$GIT_TREE" \
    --arg git_tag "$GIT_TAG" \
    --arg source_inventory_sha "$SOURCE_INVENTORY_SHA256" \
    --argjson source_file_count "$SOURCE_FILE_COUNT" \
    --arg package_resolved_sha "$PACKAGE_RESOLVED_SHA256" \
    --arg swift_version "$SWIFT_VERSION" \
    --arg xcode_version "$XCODE_VERSION" \
    --arg host_os_version "$HOST_OS_VERSION" \
    --arg host_architecture "$(uname -m)" \
    --arg public_product_name "$PUBLIC_PRODUCT_NAME" \
    --arg bundle_version "$BUNDLE_VERSION" \
    --arg build_version "$BUILD_VERSION" \
    --arg app_bundle "$APP_BUNDLE_NAME" \
    --arg archive "$ARCHIVE_NAME" \
    --arg archive_sha "$ARCHIVE_SHA256" \
    --arg app_bundle_sha "$APP_BUNDLE_SHA256" \
    --arg executable_sha "$EXECUTABLE_SHA256" \
    --arg signature_kind "$SIGNATURE_KIND" \
    --arg team_identifier "$TEAM_IDENTIFIER" '
    {
      schema_version: 2,
      classification: "DEVELOPMENT",
      distribution_authorized: false,
      built_at_utc: $built_at_utc,
      product: {
        public_name: $public_product_name,
        compatibility_name: "MeetingBuddy",
        version: $bundle_version,
        build: $build_version,
        bundle_identifier: "com.meetingbuddy.desktop",
        executable: "MeetingBuddyApp"
      },
      source: {
        git_head: $git_head,
        git_tree: $git_tree,
        git_tag: $git_tag,
        tree_state: "clean",
        inventory: "source-files.sha256",
        inventory_sha256: $source_inventory_sha,
        file_count: $source_file_count,
        package_resolved_sha256: $package_resolved_sha
      },
      toolchain: {
        swift: $swift_version,
        xcode: $xcode_version,
        macos: $host_os_version,
        architecture: $host_architecture
      },
      artifact: {
        app_bundle: $app_bundle,
        app_bundle_sha256: $app_bundle_sha,
        app_bundle_digest_kind: "sha256_of_sorted_file_sha256_inventory_v1",
        archive: $archive,
        archive_sha256: $archive_sha,
        executable_sha256: $executable_sha
      },
      signing: {
        kind: $signature_kind,
        team_identifier: $team_identifier,
        hardened_runtime: true,
        notarization: "not_submitted"
      }
    }
' > "$RELEASE_SET/release-manifest.json"

verify_release "$RELEASE_SET" development

FINAL_RELEASE_SET="$DIST_DIR/$RELEASE_SET_NAME"
PREVIOUS_RELEASE_SET="$DIST_DIR/.previous-$RELEASE_SET_NAME"
[[ ! -e "$PREVIOUS_RELEASE_SET" && ! -L "$PREVIOUS_RELEASE_SET" ]] \
    || fail "a prior interrupted release-set replacement needs manual inspection in dist"
if [[ -e "$FINAL_RELEASE_SET" || -L "$FINAL_RELEASE_SET" ]]; then
    [[ -d "$FINAL_RELEASE_SET" && ! -L "$FINAL_RELEASE_SET" ]] \
        || fail "existing release-set path is not a real directory"
    /bin/mv "$FINAL_RELEASE_SET" "$PREVIOUS_RELEASE_SET"
fi
if ! /bin/mv "$RELEASE_SET" "$FINAL_RELEASE_SET"; then
    [[ ! -e "$FINAL_RELEASE_SET" && ! -L "$FINAL_RELEASE_SET" ]] \
        || /bin/rm -rf "$FINAL_RELEASE_SET"
    [[ ! -e "$PREVIOUS_RELEASE_SET" ]] \
        || /bin/mv "$PREVIOUS_RELEASE_SET" "$FINAL_RELEASE_SET"
    fail "could not publish the verified release set"
fi
if ! verify_release "$FINAL_RELEASE_SET" development; then
    /bin/rm -rf "$FINAL_RELEASE_SET"
    [[ ! -e "$PREVIOUS_RELEASE_SET" ]] \
        || /bin/mv "$PREVIOUS_RELEASE_SET" "$FINAL_RELEASE_SET"
    fail "final release-set verification failed; prior set was restored"
fi
[[ ! -e "$PREVIOUS_RELEASE_SET" ]] || /bin/rm -rf "$PREVIOUS_RELEASE_SET"

echo "release set: $FINAL_RELEASE_SET"
echo "release bundle: $FINAL_RELEASE_SET/$APP_BUNDLE_NAME"
echo "verified development archive: $FINAL_RELEASE_SET/$ARCHIVE_NAME"
echo "archive digest: $FINAL_RELEASE_SET/$ARCHIVE_NAME.sha256"
echo "source/build manifest: $FINAL_RELEASE_SET/release-manifest.json"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "classification constraint: ad-hoc hardened-runtime signature; not notarized or distributable"
fi
