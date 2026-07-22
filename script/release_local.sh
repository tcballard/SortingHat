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
SUBMISSION="${TMPDIR%/}/Sorting-Hat-v$VERSION-notarization.zip"
VERIFY_ROOT="${TMPDIR%/}/Sorting-Hat-v$VERSION-verification"
IDENTITY="Developer ID Application: Thomas Ballard (R8HXTBY3NM)"

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
rm -rf "$DERIVED_DATA" "$VERIFY_ROOT"
rm -f "$ARCHIVE" "$SUBMISSION"

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
mkdir -p "$VERIFY_ROOT"
ditto -x -k "$ARCHIVE" "$VERIFY_ROOT"
FINAL_APP="$VERIFY_ROOT/Sorting Hat.app"
FINAL_EXTENSION="$FINAL_APP/Contents/PlugIns/Send to Sorting Hat.appex"
codesign --verify --strict --verbose=2 "$FINAL_EXTENSION"
codesign --verify --deep --strict --verbose=2 "$FINAL_APP"
xcrun stapler validate "$FINAL_APP"
spctl --assess --type execute --verbose=2 "$FINAL_APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FINAL_APP/Contents/Info.plist")" = "$CONTRACT_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FINAL_APP/Contents/Info.plist")" = "$CONTRACT_BUILD"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FINAL_EXTENSION/Contents/Info.plist")" = "$CONTRACT_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FINAL_EXTENSION/Contents/Info.plist")" = "$CONTRACT_BUILD"

echo "Signed, notarized, stapled, and extracted-archive verified for $CONTRACT_VERSION ($CONTRACT_BUILD):"
echo "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
