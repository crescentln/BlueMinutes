#!/bin/bash
set -euo pipefail

RELEASE_SET_NAME="MeetingBuddy-0.1.0-internal-alpha"
APP_BUNDLE_NAME="MeetingBuddy.app"
ARCHIVE_NAME="MeetingBuddy-0.1.0-internal-alpha.zip"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET="${1:-$ROOT_DIR/dist/$RELEASE_SET_NAME}"
VERIFICATION_MODE="${2:-internal-alpha}"
EXPECTED_ENTITLEMENTS="$ROOT_DIR/Configuration/MeetingBuddy.entitlements"
EXPECTED_PRIVACY_MANIFEST="$ROOT_DIR/Configuration/PrivacyInfo.xcprivacy"
EXPECTED_GRDB_LICENSE_SHA256="9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87"
EXPECTED_GRDB_PRIVACY_SHA256="17784da62e51f74c5859df32fe402e01e25cdf6f797a4add06e2a3ce15c911f4"

fail() {
    echo "release verification failed: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
case "$VERIFICATION_MODE" in
    internal-alpha|distribution) ;;
    *) fail "verification mode must be internal-alpha or distribution" ;;
esac

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/meetingbuddy-release-verify.XXXXXX")"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

verify_app() {
    local app_bundle="$1"
    local label="$2"
    [[ -d "$app_bundle" && ! -L "$app_bundle" ]] || fail "$label app bundle is missing or linked"
    app_bundle="$(cd "$(dirname "$app_bundle")" && pwd -P)/$(basename "$app_bundle")"

    local info_plist="$app_bundle/Contents/Info.plist"
    local executable="$app_bundle/Contents/MacOS/MeetingBuddyApp"
    local privacy_manifest="$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
    local grdb_privacy="$app_bundle/Contents/Resources/GRDB_GRDB.bundle/PrivacyInfo.xcprivacy"
    local grdb_license="$app_bundle/Contents/Resources/ThirdPartyNotices/GRDB-LICENSE.txt"
    local required
    for required in "$info_plist" "$executable" "$privacy_manifest" "$grdb_privacy" "$grdb_license"; do
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
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" \
        == "com.meetingbuddy.desktop" ]] || fail "unexpected bundle identifier"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" \
        == "0.1.0" ]] || fail "unexpected short version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" \
        == "1" ]] || fail "unexpected build version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")" \
        == "15.0" ]] || fail "unexpected minimum system version"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")" \
        == "MeetingBuddyApp" ]] || fail "unexpected executable declaration"
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
    if /usr/bin/grep -q '^Signature=adhoc$' "$signature"; then
        [[ "$VERIFICATION_MODE" == "internal-alpha" ]] \
            || fail "distribution verification rejects an ad-hoc signature"
        signature_kind="ad-hoc"
    else
        /usr/bin/grep -q '^Authority=Developer ID Application:' "$signature" \
            || fail "non-ad-hoc signature is not a Developer ID Application identity"
        /usr/bin/grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' "$signature" \
            || fail "Developer ID signature has no valid Team ID"
        /usr/bin/grep -Eq '^Timestamp=.+' "$signature" \
            || fail "Developer ID signature has no secure timestamp"
        signature_kind="developer-id"
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
    APP_ARCHITECTURES="$architectures"
}

if [[ "$TARGET" == *.app ]]; then
    verify_app "$TARGET" "direct"
    echo "release verification: PASS"
    echo "bundle: $TARGET"
    echo "architecture: $APP_ARCHITECTURES"
    echo "signature: $APP_SIGNATURE_KIND with hardened runtime"
    echo "executable bytes: $APP_EXECUTABLE_BYTES"
    echo "executable sha256: $APP_EXECUTABLE_SHA256"
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

(
    cd "$RELEASE_SET"
    /usr/bin/shasum -a 256 -c "$ARCHIVE_NAME.sha256"
)
SOURCE_MANIFEST_SHA256="$(
    /usr/bin/shasum -a 256 "$RELEASE_SET/source-files.sha256" | /usr/bin/awk '{print $1}'
)"
ARCHIVE_SHA256="$(/usr/bin/shasum -a 256 "$RELEASE_SET/$ARCHIVE_NAME" | /usr/bin/awk '{print $1}')"

verify_app "$RELEASE_SET/$APP_BUNDLE_NAME" "release-set"
EXPECTED_CLASSIFICATION="INTERNAL_ALPHA"
EXPECTED_DISTRIBUTION_AUTHORIZATION=false
if [[ "$VERIFICATION_MODE" == "distribution" ]]; then
    EXPECTED_CLASSIFICATION="RELEASE_CANDIDATE"
    EXPECTED_DISTRIBUTION_AUTHORIZATION=true
fi
/usr/bin/jq -e \
    --arg archive_sha "$ARCHIVE_SHA256" \
    --arg executable_sha "$APP_EXECUTABLE_SHA256" \
    --arg source_manifest_sha "$SOURCE_MANIFEST_SHA256" \
    --arg expected_classification "$EXPECTED_CLASSIFICATION" \
    --argjson expected_distribution_authorization "$EXPECTED_DISTRIBUTION_AUTHORIZATION" '
    .schema_version == 1 and
    .classification == $expected_classification and
    .distribution_authorized == $expected_distribution_authorization and
    .artifact.archive_sha256 == $archive_sha and
    .artifact.executable_sha256 == $executable_sha and
    .source.inventory_sha256 == $source_manifest_sha and
    (.source.tree_state == "clean" or .source.tree_state == "dirty")
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

echo "release-set verification: PASS"
echo "release set: $RELEASE_SET"
echo "architecture: $APP_ARCHITECTURES"
echo "signature: $APP_SIGNATURE_KIND with hardened runtime"
echo "executable bytes: $APP_EXECUTABLE_BYTES"
echo "executable sha256: $APP_EXECUTABLE_SHA256"
echo "archive sha256: $ARCHIVE_SHA256"
echo "source inventory sha256: $SOURCE_MANIFEST_SHA256"
