#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 VERSION" >&2
  echo "example: $0 0.2.0" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must be a semantic version without a leading v" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NOTARY_PROFILE="${SORTING_HAT_NOTARY_PROFILE:-SortingHat-Notary}"
DERIVED_DATA="${SORTING_HAT_RELEASE_DERIVED_DATA:-${TMPDIR%/}/SortingHatReleaseDerivedData}"
OUTPUT_DIR="${SORTING_HAT_RELEASE_OUTPUT:-$ROOT_DIR/dist/releases}"
APP="$ROOT_DIR/dist/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"
ARCHIVE="$OUTPUT_DIR/Sorting-Hat-v$VERSION.zip"
SUBMISSION="${TMPDIR%/}/Sorting-Hat-v$VERSION-notarization.zip"
VERIFY_ROOT="${TMPDIR%/}/Sorting-Hat-v$VERSION-verification"
IDENTITY="Developer ID Application: Thomas Ballard (R8HXTBY3NM)"

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

ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
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

echo "Signed, notarized, stapled, and extracted-archive verified:"
echo "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
