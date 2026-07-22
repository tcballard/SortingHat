#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARCHIVE="${1:-}"
VERSION="${2:-$($ROOT_DIR/script/release_identity.sh --version)}"
BUILD="${3:-$($ROOT_DIR/script/release_identity.sh --build)}"
IDENTITY="Developer ID Application: Thomas Ballard (R8HXTBY3NM)"

if [[ -z "$ARCHIVE" ]]; then
  echo "usage: $0 ARCHIVE [VERSION [BUILD]]" >&2
  exit 2
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "Release archive not found: $ARCHIVE" >&2
  exit 2
fi
"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$BUILD"

VERIFY_ROOT="$(mktemp -d "${TMPDIR%/}/sorting-hat-release-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_ROOT"' EXIT
ditto -x -k "$ARCHIVE" "$VERIFY_ROOT"

APP="$VERIFY_ROOT/Sorting Hat.app"
EXTENSION="$APP/Contents/PlugIns/Send to Sorting Hat.appex"
APP_INFO="$APP/Contents/Info.plist"
EXTENSION_INFO="$EXTENSION/Contents/Info.plist"
APP_ENTITLEMENTS="$VERIFY_ROOT/app-entitlements.plist"
EXTENSION_ENTITLEMENTS="$VERIFY_ROOT/extension-entitlements.plist"

test "$(find "$VERIFY_ROOT" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = "1"
test -d "$APP"
test -d "$EXTENSION"
codesign --verify --strict --verbose=2 "$EXTENSION"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$EXTENSION" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
codesign -dvvv "$EXTENSION" 2>&1 | grep -Fx "TeamIdentifier=R8HXTBY3NM" >/dev/null
codesign -dvvv "$APP" 2>&1 | grep -Fx "Authority=$IDENTITY" >/dev/null
codesign -dvvv "$APP" 2>&1 | grep -Fx "TeamIdentifier=R8HXTBY3NM" >/dev/null
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_INFO" | grep -Fx com.tcballard.sortinghat >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$EXTENSION_INFO" | grep -Fx com.tcballard.sortinghat.finder-action >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO" | grep -Fx "$VERSION" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO" | grep -Fx "$BUILD" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXTENSION_INFO" | grep -Fx "$VERSION" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$EXTENSION_INFO" | grep -Fx "$BUILD" >/dev/null

codesign -d --entitlements :- "$APP" > "$APP_ENTITLEMENTS" 2>/dev/null
codesign -d --entitlements :- "$EXTENSION" > "$EXTENSION_ENTITLEMENTS" 2>/dev/null
/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$APP_ENTITLEMENTS" | grep -Fx R8HXTBY3NM.com.tcballard.sortinghat >/dev/null
/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$EXTENSION_ENTITLEMENTS" | grep -Fx R8HXTBY3NM.com.tcballard.sortinghat >/dev/null
/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$EXTENSION_ENTITLEMENTS" | grep -Fx true >/dev/null
/usr/libexec/PlistBuddy -c "Print :com.apple.security.files.user-selected.read-only" "$EXTENSION_ENTITLEMENTS" | grep -Fx true >/dev/null

/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$EXTENSION_INFO" | grep -Fx com.apple.services >/dev/null
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPrincipalClass" "$EXTENSION_INFO" | grep -Fx SendToSortingHatAction.ActionRequestHandler >/dev/null
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:NSExtensionServiceFinderPreviewLabel" "$EXTENSION_INFO" | grep -Fx "Send to Sorting Hat" >/dev/null
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:NSExtensionServiceRoleType" "$EXTENSION_INFO" | grep -Fx NSExtensionServiceRoleTypeEditor >/dev/null
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:NSExtensionServiceAllowsFinderPreviewItem" "$EXTENSION_INFO" | grep -Fx true >/dev/null
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:NSExtensionActivationRule" "$EXTENSION_INFO" | grep -Fx 'SUBQUERY (extensionItems, $extensionItem, SUBQUERY ($extensionItem.attachments, $attachment, ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.item").@count == $extensionItem.attachments.@count).@count == 1' >/dev/null

echo "Developer ID release archive verified: $VERSION ($BUILD)"
shasum -a 256 "$ARCHIVE"
