#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARTIFACT_DIR="${MEETINGBUDDY_VISUAL_ARTIFACT_DIR:-}"
VISUAL_MODE="${MEETINGBUDDY_VISUAL_MODE:-regression}"

fail() {
    echo "visual environment mismatch: $*" >&2
    if [[ -n "${ARTIFACT_DIR:-}" && -d "${ARTIFACT_DIR:-}" ]]; then
        /usr/bin/printf \
            '{\n  "kind": "environment-mismatch",\n  "message": "%s"\n}\n' \
            "$*" \
            >"$ARTIFACT_DIR/environment-failure.json"
    fi
    exit 2
}

[[ -n "$ARTIFACT_DIR" ]] \
    || fail "MEETINGBUDDY_VISUAL_ARTIFACT_DIR is required"
case "$VISUAL_MODE" in
    regression|candidate|calibration)
        ;;
    *)
        fail "MEETINGBUDDY_VISUAL_MODE must be regression, candidate, or calibration"
        ;;
esac

if [[ -e "$ARTIFACT_DIR" ]]; then
    [[ -d "$ARTIFACT_DIR" && ! -L "$ARTIFACT_DIR" ]] \
        || fail "artifact path must be a real directory"
else
    /bin/mkdir -m 0700 "$ARTIFACT_DIR"
fi
ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd -P)"

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "arm64 is required"
[[ "${RUNNER_OS:-}" == "macOS" ]] \
    || fail "GitHub runner OS identity must be macOS"
[[ "${RUNNER_ARCH:-}" == "ARM64" ]] \
    || fail "GitHub runner architecture identity must be ARM64"
[[ "${ImageOS:-}" == "macos26" ]] \
    || fail "runner ImageOS must be macos26"
[[ "${ImageVersion:-}" == "20260720.0258.1" ]] \
    || fail "runner image version must be 20260720.0258.1"
[[ "$(sw_vers -productVersion)" == "26.4" ]] \
    || fail "macOS product version must be 26.4"
[[ "$(sw_vers -buildVersion)" == "25E246" ]] \
    || fail "macOS build must be 25E246"
[[ "$(xcodebuild -version | /usr/bin/sed -n '1p')" == "Xcode 26.6" ]] \
    || fail "Xcode version must be 26.6"
[[ "$(xcodebuild -version | /usr/bin/sed -n '2p')" == "Build version 17F113" ]] \
    || fail "Xcode build must be 17F113"
swift --version \
    | /usr/bin/grep -F \
        "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)" \
        >/dev/null \
    || fail "Apple Swift compiler identity is not pinned"
swift --version \
    | /usr/bin/grep -F \
        "Target: arm64-apple-macosx26.0" \
        >/dev/null \
    || fail "Swift target triple must be arm64-apple-macosx26.0"
[[ "$(xcrun --sdk macosx --show-sdk-version)" == "26.5" ]] \
    || fail "macOS SDK version must be 26.5"
[[ "$(xcrun --sdk macosx --show-sdk-build-version)" == "25F70" ]] \
    || fail "macOS SDK build must be 25F70"

SOURCE_REVISION="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
[[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]] \
    || fail "source revision must be an exact Git commit"
export MEETINGBUDDY_VISUAL_SOURCE_REVISION="$SOURCE_REVISION"
MEETINGBUDDY_VISUAL_ENVIRONMENT_ATTESTATION="macos-26-arm64/20260720.0258.1;26.4/25E246;Xcode-26.6/17F113;Swift-6.3.3;SDK-26.5/25F70"
export MEETINGBUDDY_VISUAL_ENVIRONMENT_ATTESTATION

SCRATCH_ROOT="$(/usr/bin/mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/blueminutes-visual-build.XXXXXX")"
cleanup() {
    case "$SCRATCH_ROOT" in
        "${RUNNER_TEMP:-${TMPDIR:-/tmp}}"/blueminutes-visual-build.*)
            [[ ! -e "$SCRATCH_ROOT" ]] || /bin/rm -rf "$SCRATCH_ROOT"
            ;;
        *)
            echo "refusing unexpected visual scratch cleanup: $SCRATCH_ROOT" >&2
            ;;
    esac
}
trap cleanup EXIT

cd "$ROOT_DIR"
run_harness() {
    TZ=UTC \
    LC_ALL=en_US.UTF-8 \
    MEETINGBUDDY_VISUAL_MODE="$VISUAL_MODE" \
    MEETINGBUDDY_VISUAL_ARTIFACT_DIR="$ARTIFACT_DIR" \
    swift test \
        --scratch-path "$SCRATCH_ROOT" \
        -Xswiftc -warnings-as-errors \
        --filter runPinnedNativeVisualHarness
}

if [[ "$VISUAL_MODE" == "calibration" ]]; then
    for process_index in 1 2 3; do
        export MEETINGBUDDY_VISUAL_PROCESS_INDEX="$process_index"
        run_harness
    done
else
    unset MEETINGBUDDY_VISUAL_PROCESS_INDEX || true
    run_harness
fi
