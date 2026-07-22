#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$($ROOT_DIR/script/release_identity.sh --version)"
BUILD="$($ROOT_DIR/script/release_identity.sh --build)"
OUTPUT_DIR="${SORTING_HAT_APP_STORE_OUTPUT:-$ROOT_DIR/dist/releases/AppStore}"
DERIVED_DATA="${SORTING_HAT_APP_STORE_DERIVED_DATA:-${TMPDIR%/}/SortingHatAppStoreReleaseDerivedData}"
ARCHIVE_PATH="${SORTING_HAT_APP_STORE_ARCHIVE:-$OUTPUT_DIR/Sorting-Hat-$VERSION-$BUILD.xcarchive}"
EXPORT_PATH="${SORTING_HAT_APP_STORE_EXPORT:-$OUTPUT_DIR/Export}"
EXPORT_OPTIONS="$ROOT_DIR/Configuration/AppStoreExportOptions.plist"
APP="$ARCHIVE_PATH/Products/Applications/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"

ASC_KEY_PATH="${SORTING_HAT_ASC_KEY_PATH:-}"
ASC_KEY_ID="${SORTING_HAT_ASC_KEY_ID:-}"
ASC_ISSUER_ID="${SORTING_HAT_ASC_ISSUER_ID:-}"
AUTH_ARGS=(-allowProvisioningUpdates)

if [[ -n "$ASC_KEY_PATH" || -n "$ASC_KEY_ID" || -n "$ASC_ISSUER_ID" ]]; then
  if [[ -z "$ASC_KEY_PATH" || -z "$ASC_KEY_ID" || -z "$ASC_ISSUER_ID" ]]; then
    echo "Set SORTING_HAT_ASC_KEY_PATH, SORTING_HAT_ASC_KEY_ID, and SORTING_HAT_ASC_ISSUER_ID together." >&2
    exit 2
  fi
  AUTH_ARGS+=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$BUILD"
mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA" "$ARCHIVE_PATH" "$EXPORT_PATH"

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/SortingHat.xcodeproj" \
  -scheme SortingHatAppStore \
  -configuration AppStore \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
  -archivePath "$ARCHIVE_PATH" \
  "${AUTH_ARGS[@]}" \
  archive

test -d "$APP"
test -d "$EXTENSION"
codesign --verify --strict --verbose=2 "$EXTENSION"
codesign --verify --deep --strict --verbose=2 "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" = "$BUILD"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTENSION/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTENSION/Contents/Info.plist")" = "$BUILD"

xcodebuild \
  -quiet \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${AUTH_ARGS[@]}"

PACKAGE="$(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.pkg' -print -quit)"
if [[ -z "$PACKAGE" ]]; then
  echo "App Store export did not produce a .pkg in $EXPORT_PATH." >&2
  exit 3
fi
SUMMARY="$EXPORT_PATH/DistributionSummary.plist"
test -f "$SUMMARY"
/usr/bin/python3 - "$SUMMARY" "$VERSION" "$BUILD" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    summary = plistlib.load(handle)

entries = [entry for package in summary.values() for entry in package]
if len(entries) != 1:
    raise SystemExit("Expected one application in DistributionSummary.plist.")

app = entries[0]
binaries = [app, *app.get("embeddedBinaries", [])]
for binary in binaries:
    if binary.get("versionNumber") != sys.argv[2]:
        raise SystemExit(f"Exported version mismatch for {binary.get('name')}.")
    if binary.get("buildNumber") != sys.argv[3]:
        raise SystemExit(f"Exported build mismatch for {binary.get('name')}.")
    if binary.get("certificate", {}).get("type") != "Apple Distribution":
        raise SystemExit(f"Unexpected certificate for {binary.get('name')}.")
PY

echo "Apple Distribution archive and upload package verified for $VERSION ($BUILD)."
echo "Archive: $ARCHIVE_PATH"
echo "Package: $PACKAGE"
shasum -a 256 "$PACKAGE"
echo "The package has not been uploaded or submitted."
