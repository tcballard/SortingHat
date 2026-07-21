#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DERIVED_DATA="${SORTING_HAT_APP_STORE_DERIVED_DATA:-${TMPDIR%/}/SortingHatAppStoreDerivedData}"
ARCHIVE_PATH="${SORTING_HAT_APP_STORE_ARCHIVE:-${TMPDIR%/}/SortingHat-AppStore-Preflight.xcarchive}"
APP="$ARCHIVE_PATH/Products/Applications/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"
APP_ENTITLEMENTS="$ROOT_DIR/Configuration/SortingHatApp-AppStore.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/Configuration/SendToSortingHatAction.entitlements"
APP_BINARY="$APP/Contents/MacOS/Sorting Hat"
PRIVACY_MANIFEST="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
APP_ICON="$APP/Contents/Resources/AppIcon.icns"
ASSET_CATALOG="$APP/Contents/Resources/Assets.car"
APP_ICON_SOURCE="$ROOT_DIR/Sources/SortingHatApp/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"

rm -rf "$DERIVED_DATA" "$ARCHIVE_PATH"
xcodebuild \
  -quiet \
  -project "$ROOT_DIR/SortingHat.xcodeproj" \
  -scheme SortingHatAppStore \
  -configuration AppStore \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  archive

test -d "$APP"
test -d "$EXTENSION"
test -x "$APP_BINARY"
test -f "$PRIVACY_MANIFEST"
test -f "$APP_ICON"
test -f "$ASSET_CATALOG"
test -f "$APP_ICON_SOURCE"
test "$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = "1"
plutil -lint "$APP/Contents/Info.plist" "$EXTENSION/Contents/Info.plist" "$PRIVACY_MANIFEST" >/dev/null

test "$(sips -g pixelWidth "$APP_ICON_SOURCE" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')" = "1024"
test "$(sips -g pixelHeight "$APP_ICON_SOURCE" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')" = "1024"

ASSET_INFO="$DERIVED_DATA/app-store-assets.json"
xcrun assetutil --info "$ASSET_CATALOG" > "$ASSET_INFO"
/usr/bin/python3 - "$ASSET_INFO" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    renditions = json.load(handle)

if not any(
    rendition.get("Name") == "AppIcon"
    and rendition.get("PixelWidth") == 1024
    and rendition.get("PixelHeight") == 1024
    and rendition.get("Scale") == 2
    for rendition in renditions
):
    raise SystemExit("Compiled asset catalog is missing the 512pt @2x AppIcon rendition.")
PY

if strings "$APP_BINARY" | grep -Fq "/usr/bin/fm"; then
  echo "App Store binary unexpectedly contains the legacy fm executable path." >&2
  exit 1
fi

if ! strings "$APP_BINARY" | grep -Fq "The Mac App Store build can connect only to Ollama running on this Mac"; then
  echo "App Store binary is missing the local-only provider policy." >&2
  exit 1
fi

# Ad-hoc signing is only for structural entitlement inspection. App Store
# submission still requires Apple Distribution identities and matching profiles.
xattr -cr "$APP"
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$EXTENSION_ENTITLEMENTS" "$EXTENSION"
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$APP_ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$EXTENSION"
codesign --verify --deep --strict --verbose=2 "$APP"

APP_ACTUAL="$DERIVED_DATA/app-store-app-entitlements.plist"
EXTENSION_ACTUAL="$DERIVED_DATA/app-store-extension-entitlements.plist"
codesign -d --entitlements :- "$APP" > "$APP_ACTUAL" 2>/dev/null
codesign -d --entitlements :- "$EXTENSION" > "$EXTENSION_ACTUAL" 2>/dev/null

assert_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" | grep -Fx "$expected" >/dev/null
}

assert_plist_value "$APP_ACTUAL" "com.apple.security.app-sandbox" true
assert_plist_value "$APP_ACTUAL" "com.apple.security.application-groups:0" R8HXTBY3NM.com.tcballard.sortinghat
assert_plist_value "$APP_ACTUAL" "com.apple.security.files.bookmarks.app-scope" true
assert_plist_value "$APP_ACTUAL" "com.apple.security.files.user-selected.read-write" true
assert_plist_value "$APP_ACTUAL" "com.apple.security.network.client" true
assert_plist_value "$EXTENSION_ACTUAL" "com.apple.security.app-sandbox" true
assert_plist_value "$EXTENSION_ACTUAL" "com.apple.security.application-groups:0" R8HXTBY3NM.com.tcballard.sortinghat
assert_plist_value "$EXTENSION_ACTUAL" "com.apple.security.files.user-selected.read-only" true
assert_plist_value "$APP/Contents/Info.plist" ITSAppUsesNonExemptEncryption false
assert_plist_value "$APP/Contents/Info.plist" SortingHatLocalOnlyDistribution YES

echo "App Store structural preflight passed."
echo "Archive: $ARCHIVE_PATH"
echo "A submission archive still requires Apple Distribution signing and matching App Store profiles."
