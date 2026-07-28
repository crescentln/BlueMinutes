#!/bin/bash
set -euo pipefail

APP_PRODUCT="MeetingBuddyApp"
PUBLIC_PRODUCT_NAME="BlueMinutes"
COMPATIBILITY_NAME="MeetingBuddy"
EXPECTED_BUNDLE_IDENTIFIER="com.meetingbuddy.desktop"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_INFO_PLIST="$ROOT_DIR/Configuration/MeetingBuddy-Info.plist"
EXPECTED_ENTITLEMENTS="$ROOT_DIR/Configuration/MeetingBuddy.entitlements"
EXPECTED_PRIVACY_MANIFEST="$ROOT_DIR/Configuration/PrivacyInfo.xcprivacy"
EXPECTED_APP_ICON="$ROOT_DIR/Configuration/Branding/BlueMinutes.icns"
EXPECTED_GRDB_LICENSE_SHA256="9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87"
EXPECTED_GRDB_PRIVACY_SHA256="17784da62e51f74c5859df32fe402e01e25cdf6f797a4add06e2a3ce15c911f4"

fail() {
    echo "release verification failed: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ -f "$SOURCE_INFO_PLIST" && ! -L "$SOURCE_INFO_PLIST" ]] \
    || fail "source Info.plist is missing or linked"
/usr/bin/plutil -lint "$SOURCE_INFO_PLIST" >/dev/null
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_INFO_PLIST")"
[[ "$BUNDLE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "source bundle short version is invalid"
[[ "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]] \
    || fail "source bundle build version is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$SOURCE_INFO_PLIST")" \
    == "$PUBLIC_PRODUCT_NAME" ]] || fail "source public display name is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$SOURCE_INFO_PLIST")" \
    == "$PUBLIC_PRODUCT_NAME" ]] || fail "source public bundle name is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_INFO_PLIST")" \
    == "$APP_PRODUCT" ]] || fail "source compatibility executable is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_INFO_PLIST")" \
    == "$EXPECTED_BUNDLE_IDENTIFIER" ]] || fail "source compatibility bundle identifier is invalid"

APP_BUNDLE_NAME="$PUBLIC_PRODUCT_NAME.app"
RELEASE_SET_NAME="$PUBLIC_PRODUCT_NAME-$BUNDLE_VERSION-development"
ARCHIVE_NAME="$RELEASE_SET_NAME.zip"
TARGET="${1:-$ROOT_DIR/dist/$RELEASE_SET_NAME}"
VERIFICATION_MODE="${2:-development}"

case "$VERIFICATION_MODE" in
    development|distribution) ;;
    *) fail "verification mode must be development or distribution" ;;
esac

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/blueminutes-release-verify.XXXXXX")"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

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

verify_app() {
    local app_bundle="$1"
    local label="$2"
    [[ -d "$app_bundle" && ! -L "$app_bundle" ]] || fail "$label app bundle is missing or linked"
    app_bundle="$(cd "$(dirname "$app_bundle")" && pwd -P)/$(basename "$app_bundle")"

    local info_plist="$app_bundle/Contents/Info.plist"
    local executable="$app_bundle/Contents/MacOS/$APP_PRODUCT"
    local app_icon="$app_bundle/Contents/Resources/BlueMinutes.icns"
    local privacy_manifest="$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
    local grdb_privacy="$app_bundle/Contents/Resources/GRDB_GRDB.bundle/PrivacyInfo.xcprivacy"
    local grdb_license="$app_bundle/Contents/Resources/ThirdPartyNotices/GRDB-LICENSE.txt"
    local required
    for required in "$info_plist" "$executable" "$app_icon" "$privacy_manifest" "$grdb_privacy" "$grdb_license"; do
        [[ -f "$required" && ! -L "$required" ]] || fail "missing or linked bundle item: $required"
    done
    [[ -x "$executable" ]] || fail "app executable is not executable"
    [[ -z "$(/usr/bin/find "$app_bundle" -type l -print -quit)" ]] \
        || fail "bundle contains a symbolic link"

    (
        cd "$app_bundle"
        /usr/bin/find . -print | LC_ALL=C /usr/bin/sort
    ) > "$TEMP_DIR/$label.actual-layout"
    /usr/bin/sed 's/^[[:space:]]*//' > "$TEMP_DIR/$label.expected-layout" <<'LAYOUT'
        .
        ./Contents
        ./Contents/Info.plist
        ./Contents/MacOS
        ./Contents/MacOS/MeetingBuddyApp
        ./Contents/Resources
        ./Contents/Resources/BlueMinutes.icns
        ./Contents/Resources/GRDB_GRDB.bundle
        ./Contents/Resources/GRDB_GRDB.bundle/Info.plist
        ./Contents/Resources/GRDB_GRDB.bundle/PrivacyInfo.xcprivacy
        ./Contents/Resources/PrivacyInfo.xcprivacy
        ./Contents/Resources/ThirdPartyNotices
        ./Contents/Resources/ThirdPartyNotices/GRDB-LICENSE.txt
        ./Contents/_CodeSignature
        ./Contents/_CodeSignature/CodeResources
LAYOUT
    /usr/bin/cmp -s "$TEMP_DIR/$label.expected-layout" "$TEMP_DIR/$label.actual-layout" \
        || fail "bundle layout is not the reviewed closed allowlist"

    /usr/bin/plutil -lint "$info_plist" "$privacy_manifest" "$grdb_privacy" >/dev/null
    /usr/bin/cmp -s "$SOURCE_INFO_PLIST" "$info_plist" \
        || fail "bundled Info.plist differs from the reviewed source Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" \
        == "$EXPECTED_BUNDLE_IDENTIFIER" ]] || fail "unexpected bundle identifier"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" \
        == "$BUNDLE_VERSION" ]] || fail "unexpected short version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" \
        == "$BUILD_VERSION" ]] || fail "unexpected build version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")" \
        == "15.0" ]] || fail "unexpected minimum system version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")" \
        == "$APP_PRODUCT" ]] || fail "unexpected executable declaration"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist")" \
        == "$PUBLIC_PRODUCT_NAME" ]] || fail "unexpected public display name"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist")" \
        == "$PUBLIC_PRODUCT_NAME" ]] || fail "unexpected public bundle name"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist")" \
        == "BlueMinutes.icns" ]] || fail "unexpected application icon declaration"
    /usr/bin/cmp -s "$EXPECTED_APP_ICON" "$app_icon" \
        || fail "bundled application icon differs from the reviewed source icon"
    /usr/bin/iconutil -c iconset "$app_icon" -o "$TEMP_DIR/$label.iconset" \
        || fail "bundled application icon is not a valid macOS icon set"
    [[ -f "$TEMP_DIR/$label.iconset/icon_512x512@2x.png" ]] \
        || fail "bundled application icon has no 1024-pixel representation"
    /usr/bin/cmp -s "$EXPECTED_PRIVACY_MANIFEST" "$privacy_manifest" \
        || fail "bundled privacy manifest differs from the reviewed source manifest"

    local privacy_json
    privacy_json="$(/usr/bin/plutil -convert json -o - "$privacy_manifest")"
    echo "$privacy_json" | /usr/bin/jq -e '
        .NSPrivacyTracking == false and
        (.NSPrivacyCollectedDataTypes | length) == 0 and
        (.NSPrivacyTrackingDomains | length) == 0 and
        (.NSPrivacyAccessedAPITypes | length) == 3 and
        ([.NSPrivacyAccessedAPITypes[] |
            select(.NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryDiskSpace") |
            .NSPrivacyAccessedAPITypeReasons[]] == ["E174.1"]) and
        ([.NSPrivacyAccessedAPITypes[] |
            select(.NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryFileTimestamp") |
            .NSPrivacyAccessedAPITypeReasons[]] | sort == ["3B52.1", "C617.1"]) and
        ([.NSPrivacyAccessedAPITypes[] |
            select(.NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryUserDefaults") |
            .NSPrivacyAccessedAPITypeReasons[]] == ["CA92.1"])
    ' >/dev/null || fail "app privacy manifest does not match the reviewed local-use contract"

    [[ "$(/usr/bin/shasum -a 256 "$grdb_license" | /usr/bin/awk '{print $1}')" \
        == "$EXPECTED_GRDB_LICENSE_SHA256" ]] || fail "GRDB license notice changed"
    [[ "$(/usr/bin/shasum -a 256 "$grdb_privacy" | /usr/bin/awk '{print $1}')" \
        == "$EXPECTED_GRDB_PRIVACY_SHA256" ]] || fail "GRDB privacy manifest changed"

    local architectures
    architectures="$(/usr/bin/lipo -archs "$executable")"
    [[ "$architectures" == "arm64" ]] \
        || fail "expected one arm64 release slice, found: $architectures"

    while IFS= read -r dependency; do
        case "$dependency" in
            /System/Library/*|/usr/lib/*) ;;
            *) fail "unexpected non-system dynamic dependency: $dependency" ;;
        esac
    done < <(/usr/bin/otool -L "$executable" | /usr/bin/tail -n +2 | /usr/bin/awk '{print $1}')

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
    local actual_entitlements="$TEMP_DIR/$label.actual-entitlements.plist"
    /usr/bin/codesign -d --entitlements - --xml "$app_bundle" > "$actual_entitlements" 2>/dev/null
    /usr/bin/plutil -lint "$actual_entitlements" >/dev/null
    /usr/bin/plutil -convert json -o - "$EXPECTED_ENTITLEMENTS" | /usr/bin/jq -S -c . \
        > "$TEMP_DIR/$label.expected-entitlements.json"
    /usr/bin/plutil -convert json -o - "$actual_entitlements" | /usr/bin/jq -S -c . \
        > "$TEMP_DIR/$label.actual-entitlements.json"
    /usr/bin/cmp -s "$TEMP_DIR/$label.expected-entitlements.json" \
        "$TEMP_DIR/$label.actual-entitlements.json" \
        || fail "signed entitlements differ from the reviewed entitlement set"

    local signature="$TEMP_DIR/$label.signature.txt"
    /usr/bin/codesign -dv --verbose=4 "$app_bundle" > "$signature" 2>&1
    /usr/bin/grep -Eq 'flags=.*runtime' "$signature" \
        || fail "hardened runtime flag is absent"

    local signature_kind
    local team_identifier
    if /usr/bin/grep -q '^Signature=adhoc$' "$signature"; then
        [[ "$VERIFICATION_MODE" == "development" ]] \
            || fail "distribution verification rejects an ad-hoc signature"
        signature_kind="ad-hoc"
        team_identifier=""
    else
        /usr/bin/grep -q '^Authority=Developer ID Application:' "$signature" \
            || fail "non-ad-hoc signature is not a Developer ID Application identity"
        /usr/bin/grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' "$signature" \
            || fail "Developer ID signature has no valid Team ID"
        /usr/bin/grep -Eq '^Timestamp=.+' "$signature" \
            || fail "Developer ID signature has no secure timestamp"
        signature_kind="developer-id"
        team_identifier="$(
            /usr/bin/sed -n 's/^TeamIdentifier=//p' "$signature" | /usr/bin/head -n 1
        )"
    fi

    if [[ "$VERIFICATION_MODE" == "distribution" ]]; then
        /usr/bin/xcrun stapler validate "$app_bundle" \
            || fail "notarization ticket validation failed"
        /usr/sbin/spctl --assess --type execute --verbose=4 "$app_bundle" \
            || fail "Gatekeeper execution assessment failed"
        /usr/bin/syspolicy_check distribution "$app_bundle" \
            || fail "macOS distribution policy assessment failed"
    fi

    APP_EXECUTABLE_SHA256="$(/usr/bin/shasum -a 256 "$executable" | /usr/bin/awk '{print $1}')"
    APP_EXECUTABLE_BYTES="$(/usr/bin/stat -f '%z' "$executable")"
    APP_SIGNATURE_KIND="$signature_kind"
    APP_TEAM_IDENTIFIER="$team_identifier"
    APP_ARCHITECTURES="$architectures"
    local bundle_inventory="$TEMP_DIR/$label.app-files.sha256"
    write_bundle_inventory "$app_bundle" "$bundle_inventory"
    APP_BUNDLE_SHA256="$(/usr/bin/shasum -a 256 "$bundle_inventory" | /usr/bin/awk '{print $1}')"
}

verify_source_inventory() {
    local release_set="$1"
    local manifest="$2"
    local inventory="$release_set/source-files.sha256"
    local git_head
    local git_tree
    local git_tag
    local exact_tags
    local exact_tag_count
    local line
    local digest
    local relative
    local actual_digest
    local actual_paths="$TEMP_DIR/source-paths.actual"
    local expected_paths="$TEMP_DIR/source-paths.expected"

    [[ -f "$inventory" && ! -L "$inventory" ]] \
        || fail "source inventory is missing or linked"
    SOURCE_MANIFEST_SHA256="$(
        /usr/bin/shasum -a 256 "$inventory" | /usr/bin/awk '{print $1}'
    )"
    SOURCE_FILE_COUNT="$(/usr/bin/wc -l < "$inventory" | /usr/bin/tr -d ' ')"
    [[ "$SOURCE_FILE_COUNT" -gt 0 ]] || fail "source inventory is empty"

    git_head="$(/usr/bin/jq -er '.source.git_head' "$manifest")"
    git_tree="$(/usr/bin/jq -er '.source.git_tree' "$manifest")"
    git_tag="$(/usr/bin/jq -er '.source.git_tag' "$manifest")"
    [[ "$git_head" =~ ^[0-9a-f]{40}$ ]] || fail "manifest Git head is invalid"
    [[ "$git_tree" =~ ^[0-9a-f]{40}$ ]] || fail "manifest Git tree is invalid"
    /usr/bin/git -C "$ROOT_DIR" cat-file -e "$git_head^{commit}" \
        || fail "manifest Git commit is unavailable"
    [[ "$(/usr/bin/git -C "$ROOT_DIR" rev-parse "$git_head^{tree}")" == "$git_tree" ]] \
        || fail "manifest Git tree does not match its commit"
    if /usr/bin/git -C "$ROOT_DIR" ls-tree -r "$git_head" \
        | /usr/bin/awk '$1 == "120000" { found = 1 } END { exit(found ? 0 : 1) }'; then
        fail "manifest source commit contains a symbolic link"
    fi
    exact_tags="$(
        /usr/bin/git -C "$ROOT_DIR" tag --points-at "$git_head" | LC_ALL=C /usr/bin/sort
    )"
    exact_tag_count="$(
        /usr/bin/printf '%s\n' "$exact_tags" \
            | /usr/bin/sed '/^$/d' \
            | /usr/bin/wc -l \
            | /usr/bin/tr -d ' '
    )"
    [[ "$exact_tag_count" -le 1 ]] \
        || fail "manifest source commit has more than one available exact tag"
    [[ "$git_tag" == "$exact_tags" ]] \
        || fail "manifest exact tag differs from the available exact tag"

    : > "$actual_paths"
    while IFS= read -r line; do
        /usr/bin/printf '%s\n' "$line" \
            | /usr/bin/grep -Eq '^[0-9a-f]{64}  [^/].+$' \
            || fail "source inventory line has an invalid format"
        digest="${line%%  *}"
        relative="${line#*  }"
        case "$relative" in
            /*|..|../*|*/../*|*/..) fail "source inventory path escapes the repository" ;;
        esac
        [[ "$relative" != *$'\t'* ]] || fail "source inventory path contains a tab"
        /usr/bin/printf '%s\n' "$relative" >> "$actual_paths"
        actual_digest="$(
            /usr/bin/git -C "$ROOT_DIR" show "$git_head:$relative" \
                | /usr/bin/shasum -a 256 \
                | /usr/bin/awk '{print $1}'
        )"
        [[ "$actual_digest" == "$digest" ]] \
            || fail "source inventory digest mismatch: $relative"
    done < "$inventory"

    : > "$expected_paths"
    while IFS= read -r -d '' relative; do
        [[ "$relative" != *$'\n'* && "$relative" != *$'\t'* ]] \
            || fail "source commit paths containing tabs or newlines are unsupported"
        /usr/bin/printf '%s\n' "$relative" >> "$expected_paths"
    done < <(/usr/bin/git -C "$ROOT_DIR" ls-tree -r -z --name-only "$git_head")
    /usr/bin/cmp -s "$expected_paths" "$actual_paths" \
        || fail "source inventory does not cover the exact tracked tree"

    if [[ -n "$git_tag" ]]; then
        [[ "$git_tag" == "v$BUNDLE_VERSION" ]] \
            || fail "manifest exact tag does not match the bundle version"
        [[ "$(/usr/bin/git -C "$ROOT_DIR" cat-file -t "refs/tags/$git_tag")" == "tag" ]] \
            || fail "manifest exact tag is not annotated"
        [[ "$(/usr/bin/git -C "$ROOT_DIR" rev-parse "refs/tags/$git_tag^{}")" == "$git_head" ]] \
            || fail "manifest exact tag does not peel to its Git head"
    fi

    SOURCE_GIT_HEAD="$git_head"
    SOURCE_GIT_TREE="$git_tree"
    SOURCE_GIT_TAG="$git_tag"
    SOURCE_PACKAGE_RESOLVED_SHA256="$(
        /usr/bin/git -C "$ROOT_DIR" show "$git_head:Package.resolved" \
            | /usr/bin/shasum -a 256 \
            | /usr/bin/awk '{print $1}'
    )"
}

if [[ "$TARGET" == *.app ]]; then
    verify_app "$TARGET" "direct"
    echo "release verification: PASS"
    echo "bundle: $TARGET"
    echo "architecture: $APP_ARCHITECTURES"
    echo "signature: $APP_SIGNATURE_KIND with hardened runtime"
    echo "executable bytes: $APP_EXECUTABLE_BYTES"
    echo "executable sha256: $APP_EXECUTABLE_SHA256"
    echo "app bundle sha256: $APP_BUNDLE_SHA256"
    exit 0
fi

[[ -d "$TARGET" && ! -L "$TARGET" ]] || fail "release set is missing or linked"
RELEASE_SET="$(cd "$(dirname "$TARGET")" && pwd -P)/$(basename "$TARGET")"
[[ -z "$(/usr/bin/find "$RELEASE_SET" -type l -print -quit)" ]] \
    || fail "release set contains a symbolic link"
(
    cd "$RELEASE_SET"
    /usr/bin/find . -mindepth 1 -maxdepth 1 -print | LC_ALL=C /usr/bin/sort
) > "$TEMP_DIR/release-set.actual-layout"
/usr/bin/sed 's/^[[:space:]]*//' > "$TEMP_DIR/release-set.expected-layout" <<LAYOUT
    ./$ARCHIVE_NAME
    ./$ARCHIVE_NAME.sha256
    ./$APP_BUNDLE_NAME
    ./release-manifest.json
    ./source-files.sha256
LAYOUT
/usr/bin/cmp -s "$TEMP_DIR/release-set.expected-layout" "$TEMP_DIR/release-set.actual-layout" \
    || fail "release-set layout is not the reviewed closed allowlist"

ARCHIVE_SHA256="$(/usr/bin/shasum -a 256 "$RELEASE_SET/$ARCHIVE_NAME" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE_NAME" \
    > "$TEMP_DIR/archive-checksum.expected"
/usr/bin/cmp -s "$TEMP_DIR/archive-checksum.expected" \
    "$RELEASE_SET/$ARCHIVE_NAME.sha256" \
    || fail "archive checksum file is not the exact reviewed record"

verify_app "$RELEASE_SET/$APP_BUNDLE_NAME" "release-set"
verify_source_inventory "$RELEASE_SET" "$RELEASE_SET/release-manifest.json"
EXPECTED_CLASSIFICATION="DEVELOPMENT"
EXPECTED_DISTRIBUTION_AUTHORIZATION=false
EXPECTED_NOTARIZATION="not_submitted"
if [[ "$VERIFICATION_MODE" == "distribution" ]]; then
    EXPECTED_CLASSIFICATION="DISTRIBUTION"
    EXPECTED_DISTRIBUTION_AUTHORIZATION=true
    EXPECTED_NOTARIZATION="stapled"
fi
/usr/bin/jq -e \
    --arg public_name "$PUBLIC_PRODUCT_NAME" \
    --arg compatibility_name "$COMPATIBILITY_NAME" \
    --arg version "$BUNDLE_VERSION" \
    --arg build "$BUILD_VERSION" \
    --arg bundle_identifier "$EXPECTED_BUNDLE_IDENTIFIER" \
    --arg executable "$APP_PRODUCT" \
    --arg git_head "$SOURCE_GIT_HEAD" \
    --arg git_tree "$SOURCE_GIT_TREE" \
    --arg git_tag "$SOURCE_GIT_TAG" \
    --arg app_bundle "$APP_BUNDLE_NAME" \
    --arg app_bundle_sha "$APP_BUNDLE_SHA256" \
    --arg archive "$ARCHIVE_NAME" \
    --arg archive_sha "$ARCHIVE_SHA256" \
    --arg executable_sha "$APP_EXECUTABLE_SHA256" \
    --arg source_manifest_sha "$SOURCE_MANIFEST_SHA256" \
    --arg package_resolved_sha "$SOURCE_PACKAGE_RESOLVED_SHA256" \
    --argjson source_file_count "$SOURCE_FILE_COUNT" \
    --arg signature_kind "$APP_SIGNATURE_KIND" \
    --arg team_identifier "$APP_TEAM_IDENTIFIER" \
    --arg expected_notarization "$EXPECTED_NOTARIZATION" \
    --arg expected_classification "$EXPECTED_CLASSIFICATION" \
    --argjson expected_distribution_authorization "$EXPECTED_DISTRIBUTION_AUTHORIZATION" '
    .schema_version == 2 and
    .classification == $expected_classification and
    .distribution_authorized == $expected_distribution_authorization and
    (.built_at_utc | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    .product.public_name == $public_name and
    .product.compatibility_name == $compatibility_name and
    .product.version == $version and
    .product.build == $build and
    .product.bundle_identifier == $bundle_identifier and
    .product.executable == $executable and
    .source.git_head == $git_head and
    .source.git_tree == $git_tree and
    .source.git_tag == $git_tag and
    .source.tree_state == "clean" and
    .source.inventory == "source-files.sha256" and
    .source.file_count == $source_file_count and
    .source.package_resolved_sha256 == $package_resolved_sha and
    .artifact.app_bundle == $app_bundle and
    .artifact.app_bundle_sha256 == $app_bundle_sha and
    .artifact.app_bundle_digest_kind == "sha256_of_sorted_file_sha256_inventory_v1" and
    .artifact.archive == $archive and
    .artifact.archive_sha256 == $archive_sha and
    .artifact.executable_sha256 == $executable_sha and
    .source.inventory_sha256 == $source_manifest_sha and
    .signing.kind == $signature_kind and
    .signing.team_identifier == $team_identifier and
    .signing.hardened_runtime == true and
    .signing.notarization == $expected_notarization and
    (.toolchain.swift | type == "string" and length > 0) and
    (.toolchain.xcode | type == "string" and length > 0) and
    (.toolchain.macos | type == "string" and length > 0) and
    .toolchain.architecture == "arm64"
' "$RELEASE_SET/release-manifest.json" >/dev/null \
    || fail "release manifest does not bind the verified artifact and source inventory"

EXTRACT_ROOT="$TEMP_DIR/extracted"
/bin/mkdir "$EXTRACT_ROOT"
/usr/bin/ditto -x -k "$RELEASE_SET/$ARCHIVE_NAME" "$EXTRACT_ROOT"
(
    cd "$EXTRACT_ROOT"
    /usr/bin/find . -mindepth 1 -maxdepth 1 -print | LC_ALL=C /usr/bin/sort
) > "$TEMP_DIR/archive-root.actual-layout"
/usr/bin/printf './%s\n' "$APP_BUNDLE_NAME" > "$TEMP_DIR/archive-root.expected-layout"
/usr/bin/cmp -s "$TEMP_DIR/archive-root.expected-layout" \
    "$TEMP_DIR/archive-root.actual-layout" \
    || fail "archive extraction root contains an unexpected sibling"
verify_app "$EXTRACT_ROOT/$APP_BUNDLE_NAME" "extracted"
[[ "$APP_EXECUTABLE_SHA256" \
    == "$(/usr/bin/jq -r '.artifact.executable_sha256' "$RELEASE_SET/release-manifest.json")" ]] \
    || fail "extracted executable differs from the release manifest"
[[ "$APP_BUNDLE_SHA256" \
    == "$(/usr/bin/jq -r '.artifact.app_bundle_sha256' "$RELEASE_SET/release-manifest.json")" ]] \
    || fail "extracted app bundle differs from the release manifest"

echo "release-set verification: PASS"
echo "release set: $RELEASE_SET"
echo "architecture: $APP_ARCHITECTURES"
echo "signature: $APP_SIGNATURE_KIND with hardened runtime"
echo "executable bytes: $APP_EXECUTABLE_BYTES"
echo "executable sha256: $APP_EXECUTABLE_SHA256"
echo "app bundle sha256: $APP_BUNDLE_SHA256"
echo "archive sha256: $ARCHIVE_SHA256"
echo "source inventory sha256: $SOURCE_MANIFEST_SHA256"
echo "source git head: $SOURCE_GIT_HEAD"
echo "source git tree: $SOURCE_GIT_TREE"
echo "source exact tag: ${SOURCE_GIT_TAG:-none}"
