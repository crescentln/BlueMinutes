#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIR="$ROOT_DIR/Configuration/Branding/Sources"
ICON_SOURCE="$SOURCE_DIR/BlueMinutes-AppIcon-Source.png"
LOGO_SOURCE="$SOURCE_DIR/BlueMinutes-Logo-Source.png"
ICON_MASTER="$ROOT_DIR/Configuration/Branding/BlueMinutes-AppIcon-1024.png"
ICON_OUTPUT="$ROOT_DIR/Configuration/Branding/BlueMinutes.icns"
LOGO_OUTPUT="$ROOT_DIR/docs/assets/BlueMinutes-logo.png"
SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

EXPECTED_ICON_SOURCE_SHA256="a36fa53503c95047a04c5e3ba9d5f0e6619789f19eb2bbf1225f61d318cadbd4"
EXPECTED_LOGO_SOURCE_SHA256="d0f0e05164a84b14533e2a3f2f83486baab544f2c6029a14911c5a4ba95fcd39"
EXPECTED_ICON_MASTER_SHA256="6bb1f6f61ea536e83433fe979eb8749b4b3745270ba7b1da6bb08e893bee289a"
EXPECTED_ICON_OUTPUT_SHA256="87459e6a19758af87eb34884b2f06066413000298c7ec6468f6eb0046aa06bca"

fail() {
    echo "brand generation failed: $*" >&2
    exit 1
}

verify_source() {
    local source="$1"
    local expected_sha="$2"
    local actual_sha
    [[ -f "$source" && ! -L "$source" ]] || fail "missing or linked source: $source"
    actual_sha="$(/usr/bin/shasum -a 256 "$source" | /usr/bin/awk '{print $1}')"
    [[ "$actual_sha" == "$expected_sha" ]] || fail "source hash mismatch: $source"
}

verify_source "$ICON_SOURCE" "$EXPECTED_ICON_SOURCE_SHA256"
verify_source "$LOGO_SOURCE" "$EXPECTED_LOGO_SOURCE_SHA256"
[[ -f "$SRGB_PROFILE" ]] || fail "system sRGB profile is unavailable"

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/blueminutes-brand.XXXXXX")"
STAGED_ICON_MASTER=""
STAGED_ICON_OUTPUT=""
STAGED_LOGO_OUTPUT=""

cleanup() {
    [[ -z "$STAGED_ICON_MASTER" || ! -e "$STAGED_ICON_MASTER" ]] \
        || /bin/rm -f -- "$STAGED_ICON_MASTER"
    [[ -z "$STAGED_ICON_OUTPUT" || ! -e "$STAGED_ICON_OUTPUT" ]] \
        || /bin/rm -f -- "$STAGED_ICON_OUTPUT"
    [[ -z "$STAGED_LOGO_OUTPUT" || ! -e "$STAGED_LOGO_OUTPUT" ]] \
        || /bin/rm -f -- "$STAGED_LOGO_OUTPUT"
    /bin/rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

ICONSET_DIR="$TEMP_DIR/BlueMinutes.iconset"
EXPANDED_ICONSET_DIR="$TEMP_DIR/Expanded.iconset"
TEMP_ICON_MASTER="$TEMP_DIR/BlueMinutes-AppIcon-1024.png"
TEMP_ICON_OUTPUT="$TEMP_DIR/BlueMinutes.icns"
TEMP_LOGO_OUTPUT="$TEMP_DIR/BlueMinutes-logo.png"
/bin/mkdir -p "$ICONSET_DIR"

/usr/bin/sips \
    --matchTo "$SRGB_PROFILE" \
    --resampleHeightWidth 1024 1024 \
    "$ICON_SOURCE" \
    --out "$TEMP_ICON_MASTER" >/dev/null
/usr/bin/install -m 0644 "$LOGO_SOURCE" "$TEMP_LOGO_OUTPUT"

generate_icon_representation() {
    local pixels="$1"
    local name="$2"
    /usr/bin/sips \
        --resampleHeightWidth "$pixels" "$pixels" \
        "$TEMP_ICON_MASTER" \
        --out "$ICONSET_DIR/$name" >/dev/null
}

generate_icon_representation 16 "icon_16x16.png"
generate_icon_representation 32 "icon_16x16@2x.png"
generate_icon_representation 32 "icon_32x32.png"
generate_icon_representation 64 "icon_32x32@2x.png"
generate_icon_representation 128 "icon_128x128.png"
generate_icon_representation 256 "icon_128x128@2x.png"
generate_icon_representation 256 "icon_256x256.png"
generate_icon_representation 512 "icon_256x256@2x.png"
generate_icon_representation 512 "icon_512x512.png"
generate_icon_representation 1024 "icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$TEMP_ICON_OUTPUT"

[[ "$(/usr/bin/sips -g pixelWidth "$TEMP_ICON_MASTER" | /usr/bin/awk '/pixelWidth/ {print $2}')" == "1024" ]] \
    || fail "generated icon master width is not 1024"
[[ "$(/usr/bin/sips -g pixelHeight "$TEMP_ICON_MASTER" | /usr/bin/awk '/pixelHeight/ {print $2}')" == "1024" ]] \
    || fail "generated icon master height is not 1024"
[[ "$(/usr/bin/sips -g profile "$TEMP_ICON_MASTER" | /usr/bin/awk -F': ' '/profile/ {print $2}')" == *"sRGB"* ]] \
    || fail "generated icon master is not tagged sRGB"
[[ -s "$TEMP_ICON_OUTPUT" ]] || fail "generated ICNS is empty"
[[ -s "$TEMP_LOGO_OUTPUT" ]] || fail "generated logo is empty"

verify_source "$TEMP_ICON_MASTER" "$EXPECTED_ICON_MASTER_SHA256"
verify_source "$TEMP_ICON_OUTPUT" "$EXPECTED_ICON_OUTPUT_SHA256"
verify_source "$TEMP_LOGO_OUTPUT" "$EXPECTED_LOGO_SOURCE_SHA256"
/usr/bin/iconutil -c iconset "$TEMP_ICON_OUTPUT" -o "$EXPANDED_ICONSET_DIR"
[[ -s "$EXPANDED_ICONSET_DIR/icon_512x512@2x.png" ]] \
    || fail "generated ICNS cannot be expanded to its 1024-pixel representation"

stage_output() {
    local source="$1"
    local destination="$2"
    local directory
    local staged
    [[ ! -L "$destination" ]] || fail "refusing linked output: $destination"
    directory="$(/usr/bin/dirname "$destination")"
    staged="$(/usr/bin/mktemp "$directory/.blueminutes-brand.XXXXXX")"
    /usr/bin/install -m 0644 "$source" "$staged"
    echo "$staged"
}

# No tracked output changes until every derived artifact has passed validation.
STAGED_ICON_MASTER="$(stage_output "$TEMP_ICON_MASTER" "$ICON_MASTER")"
STAGED_ICON_OUTPUT="$(stage_output "$TEMP_ICON_OUTPUT" "$ICON_OUTPUT")"
STAGED_LOGO_OUTPUT="$(stage_output "$TEMP_LOGO_OUTPUT" "$LOGO_OUTPUT")"

/bin/mv -f -- "$STAGED_ICON_MASTER" "$ICON_MASTER"
STAGED_ICON_MASTER=""
/bin/mv -f -- "$STAGED_ICON_OUTPUT" "$ICON_OUTPUT"
STAGED_ICON_OUTPUT=""
/bin/mv -f -- "$STAGED_LOGO_OUTPUT" "$LOGO_OUTPUT"
STAGED_LOGO_OUTPUT=""

echo "Generated reviewed BlueMinutes logo and macOS icon assets."
