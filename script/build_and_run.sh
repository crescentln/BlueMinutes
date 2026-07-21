#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MeetingBuddyApp"
BUNDLE_ID="com.meetingbuddy.desktop"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/MeetingBuddy.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST_SOURCE="$ROOT_DIR/Configuration/MeetingBuddy-Info.plist"
ENTITLEMENTS_SOURCE="$ROOT_DIR/Configuration/MeetingBuddy.entitlements"
MEETINGBUDDY_SIGN_IDENTITY="${MEETINGBUDDY_SIGN_IDENTITY:--}"

cd "$ROOT_DIR"

swift build --configuration debug --product "$APP_NAME" -Xswiftc -warnings-as-errors
BUILD_DIRECTORY="$(swift build --configuration debug --show-bin-path)"
BUILD_BINARY="$BUILD_DIRECTORY/$APP_NAME"

/usr/bin/install -d -m 0755 "$APP_MACOS"
/usr/bin/install -m 0755 "$BUILD_BINARY" "$APP_BINARY"
/usr/bin/install -m 0644 "$INFO_PLIST_SOURCE" "$APP_CONTENTS/Info.plist"
/usr/bin/codesign \
  --force \
  --sign "$MEETINGBUDDY_SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS_SOURCE" \
  "$APP_BUNDLE"

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --stage-only|stage-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    # This is a local unified-log stream only; MeetingBuddy sends no telemetry.
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--stage-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
