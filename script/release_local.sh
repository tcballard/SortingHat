#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CONTRACT_VERSION="$($ROOT_DIR/script/release_identity.sh --version)"
CONTRACT_BUILD="$($ROOT_DIR/script/release_identity.sh --build)"
VERSION="${1:-$CONTRACT_VERSION}"
"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$CONTRACT_BUILD"

NOTARY_PROFILE="${SORTING_HAT_NOTARY_PROFILE:-SortingHat-Notary}"
NOTARY_KEY_PATH="${SORTING_HAT_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${SORTING_HAT_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${SORTING_HAT_NOTARY_ISSUER_ID:-}"
DERIVED_DATA="${SORTING_HAT_RELEASE_DERIVED_DATA:-${TMPDIR%/}/SortingHatReleaseDerivedData}"
OUTPUT_DIR="${SORTING_HAT_RELEASE_OUTPUT:-$ROOT_DIR/dist/releases}"
APP="$ROOT_DIR/dist/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"
ARCHIVE="$OUTPUT_DIR/Sorting-Hat-v$VERSION.zip"
DMG="$OUTPUT_DIR/Sorting-Hat-v$VERSION.dmg"
APPCAST="$OUTPUT_DIR/appcast.xml"
RELEASE_NOTES="$ROOT_DIR/docs/releases/v$VERSION.md"
SUBMISSION="${TMPDIR%/}/Sorting-Hat-v$VERSION-notarization.zip"
DMG_ROOT="$(mktemp -d "${TMPDIR%/}/sorting-hat-dmg.XXXXXX")"
APPCAST_ROOT="$(mktemp -d "${TMPDIR%/}/sorting-hat-appcast.XXXXXX")"
IDENTITY="Developer ID Application: Thomas Ballard (R8HXTBY3NM)"
SPARKLE_ROOT="$ROOT_DIR/.build/sparkle/2.9.2"
GENERATE_APPCAST="$SPARKLE_ROOT/bin/generate_appcast"

cleanup() {
  rm -rf "$DMG_ROOT" "$APPCAST_ROOT"
  rm -f "$SUBMISSION"
}
trap cleanup EXIT

NOTARY_ARGS=()
if [[ -n "$NOTARY_KEY_PATH" || -n "$NOTARY_KEY_ID" || -n "$NOTARY_ISSUER_ID" ]]; then
  if [[ -z "$NOTARY_KEY_PATH" || -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" ]]; then
    echo "Set SORTING_HAT_NOTARY_KEY_PATH, SORTING_HAT_NOTARY_KEY_ID, and SORTING_HAT_NOTARY_ISSUER_ID together." >&2
    exit 2
  fi
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA"
rm -f "$ARCHIVE" "$DMG" "$APPCAST" "$SUBMISSION"
"$ROOT_DIR/script/prepare_sparkle.sh"
test -x "$GENERATE_APPCAST"
test -f "$RELEASE_NOTES"

if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  echo "Missing valid signing identity: $IDENTITY" >&2
  exit 3
fi

BUILD_CONFIGURATION=Release \
SORTING_HAT_DERIVED_DATA="$DERIVED_DATA" \
SORTING_HAT_SIGN_IDENTITY="$IDENTITY" \
  "$ROOT_DIR/script/build_and_run.sh" package

codesign --verify --strict --verbose=2 "$EXTENSION"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
codesign -dvvv "$APP" 2>&1 | grep -Fx "TeamIdentifier=R8HXTBY3NM" >/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$CONTRACT_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" = "$CONTRACT_BUILD"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTENSION/Contents/Info.plist")" = "$CONTRACT_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTENSION/Contents/Info.plist")" = "$CONTRACT_BUILD"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
"$ROOT_DIR/script/verify_release_archive.sh" "$ARCHIVE" "$CONTRACT_VERSION" "$CONTRACT_BUILD"

ditto "$APP" "$DMG_ROOT/Sorting Hat.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Sorting Hat" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
"$ROOT_DIR/script/verify_release_dmg.sh" "$DMG" "$CONTRACT_VERSION" "$CONTRACT_BUILD"

cp "$DMG" "$APPCAST_ROOT/$(basename "$DMG")"
cp "$RELEASE_NOTES" "$APPCAST_ROOT/Sorting-Hat-v$VERSION.md"
"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/tcballard/SortingHat/releases/download/v$VERSION/" \
  --link "https://oss.tcballard.dev/sortinghat" \
  --embed-release-notes \
  "$APPCAST_ROOT"
cp "$APPCAST_ROOT/appcast.xml" "$APPCAST"
grep -Fq "Sorting-Hat-v$VERSION.dmg" "$APPCAST"
grep -Fq "sparkle:edSignature=" "$APPCAST"

echo "Signed, notarized, stapled, and verified for $CONTRACT_VERSION ($CONTRACT_BUILD):"
printf '%s\n' "$ARCHIVE" "$DMG" "$APPCAST"
