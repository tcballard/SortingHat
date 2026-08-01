#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DMG="${1:-}"
VERSION="${2:-$($ROOT_DIR/script/release_identity.sh --version)}"
BUILD="${3:-$($ROOT_DIR/script/release_identity.sh --build)}"
IDENTITY="Developer ID Application: Thomas Ballard (R8HXTBY3NM)"

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "usage: $0 DMG [VERSION [BUILD]]" >&2
  exit 2
fi
"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$BUILD"

MOUNT_ROOT="$(mktemp -d "${TMPDIR%/}/sorting-hat-dmg-verify.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNT_ROOT" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_ROOT"
}
trap cleanup EXIT

codesign --verify --strict --verbose=2 "$DMG"
codesign -dvvv "$DMG" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_ROOT" -quiet

APP="$MOUNT_ROOT/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"
INFO="$APP/Contents/Info.plist"
test -d "$APP"
test -d "$EXTENSION"
test -L "$MOUNT_ROOT/Applications"
test "$(readlink "$MOUNT_ROOT/Applications")" = "/Applications"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
codesign --verify --strict --verbose=2 "$EXTENSION"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
for item in \
  "$SPARKLE/Autoupdate" \
  "$SPARKLE/Updater.app" \
  "$SPARKLE/XPCServices/Downloader.xpc" \
  "$SPARKLE/XPCServices/Installer.xpc"; do
  codesign --verify --strict --verbose=2 "$item"
  codesign -dvvv "$item" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
  codesign -dvvv "$item" 2>&1 | grep -Fx "TeamIdentifier=R8HXTBY3NM" >/dev/null
  details="$(codesign -dvvv "$item" 2>&1)"
  grep -Fq "Timestamp=" <<<"$details"
done
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO" | grep -Fx "$VERSION" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO" | grep -Fx "$BUILD" >/dev/null
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO" | grep -Fx "https://github.com/tcballard/SortingHat/releases/latest/download/appcast.xml" >/dev/null
test -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO")"

echo "Developer ID release DMG verified: $VERSION ($BUILD)"
shasum -a 256 "$DMG"
