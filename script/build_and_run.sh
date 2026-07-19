#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
case "$CONFIGURATION" in
  debug|Debug|DEBUG) CONFIGURATION="Debug" ;;
  release|Release|RELEASE) CONFIGURATION="Release" ;;
  *) echo "BUILD_CONFIGURATION must be Debug or Release" >&2; exit 2 ;;
esac

APP_NAME="Sorting Hat"
APP_PROCESS="Sorting Hat"
APP_BUNDLE_ID="com.tcballard.sortinghat"
EXTENSION_NAME="Send to Sorting Hat"
EXTENSION_BUNDLE_ID="com.tcballard.sortinghat.finder-action"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${SORTING_HAT_DERIVED_DATA:-${TMPDIR%/}/SortingHatDerivedData}"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
BUILT_EXTENSION="$BUILT_APP/Contents/PlugIns/$EXTENSION_NAME.appex"
DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALLED_APP="${SORTING_HAT_INSTALL_APP:-/Applications/$APP_NAME.app}"
INSTALLED_EXTENSION="$INSTALLED_APP/Contents/PlugIns/$EXTENSION_NAME.appex"
APP_ENTITLEMENTS="$ROOT_DIR/Configuration/SortingHatApp.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/Configuration/SendToSortingHatAction.entitlements"
PRODUCT_SIGN_IDENTITY="${SORTING_HAT_SIGN_IDENTITY:-Developer ID Application: Thomas Ballard (R8HXTBY3NM)}"
EXPECTED_TEAM_IDENTIFIER="R8HXTBY3NM"
SIGN_IDENTITY="$PRODUCT_SIGN_IDENTITY"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

for process_name in SortingHatApp "Sorting Hat" SortingHat sorting-hat; do
  pkill -x "$process_name" >/dev/null 2>&1 || true
done

if [[ ! -d "$ROOT_DIR/SortingHat.xcodeproj" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "SortingHat.xcodeproj is missing; install XcodeGen 2.44.1 and run './script/generate_xcode_project.sh'." >&2
    exit 2
  fi
  "$ROOT_DIR/script/generate_xcode_project.sh"
fi

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/SortingHat.xcodeproj" \
  -scheme SortingHat \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

test -d "$BUILT_EXTENSION"
/usr/bin/xattr -cr "$BUILT_APP"

if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  PRODUCT_SIGNED=1
  SIGN_TIMESTAMP=(--timestamp=none)
  if [[ "$CONFIGURATION" == "Release" ]]; then SIGN_TIMESTAMP=(--timestamp); fi
else
  if [[ "$CONFIGURATION" == "Release" ]]; then
    echo "A Release build requires '$PRODUCT_SIGN_IDENTITY'; refusing an ad-hoc release." >&2
    exit 3
  fi
  PRODUCT_SIGNED=0
  SIGN_IDENTITY="-"
  SIGN_TIMESTAMP=(--timestamp=none)
  echo "warning: no Sorting Hat Developer ID identity is installed; creating an ad-hoc development build." >&2
  echo "warning: the app can launch, but macOS will not grant the Finder action's shared App Group." >&2
fi

sign_nested_code() {
  local bundle="$1"
  local candidate
  while IFS= read -r -d '' candidate; do
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "${SIGN_TIMESTAMP[@]}" --options runtime "$candidate"
  done < <(/usr/bin/find "$bundle/Contents/MacOS" -type f -name '*.dylib' -print0 2>/dev/null || true)
  while IFS= read -r -d '' candidate; do
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "${SIGN_TIMESTAMP[@]}" --options runtime "$candidate"
  done < <(/usr/bin/find "$bundle/Contents/Frameworks" -type f -name '*.dylib' -print0 2>/dev/null || true)
  while IFS= read -r -d '' candidate; do
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "${SIGN_TIMESTAMP[@]}" --options runtime "$candidate"
  done < <(/usr/bin/find "$bundle/Contents/Frameworks" -type d -name '*.framework' -print0 2>/dev/null || true)
}

# Sign from the innermost code outward. Never use --deep for signing: doing so
# can replace target-specific entitlements on the Finder extension.
sign_nested_code "$BUILT_EXTENSION"
/usr/bin/codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  "${SIGN_TIMESTAMP[@]}" \
  --options runtime \
  --entitlements "$EXTENSION_ENTITLEMENTS" \
  "$BUILT_EXTENSION"
sign_nested_code "$BUILT_APP"
/usr/bin/codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  "${SIGN_TIMESTAMP[@]}" \
  --options runtime \
  --entitlements "$APP_ENTITLEMENTS" \
  "$BUILT_APP"

/usr/bin/codesign --verify --strict --verbose=2 "$BUILT_EXTENSION"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

verify_product_identity() {
  local bundle="$1"
  local details
  details="$(/usr/bin/codesign -dvvv "$bundle" 2>&1)"
  /usr/bin/grep -Fq "Authority=$PRODUCT_SIGN_IDENTITY" <<<"$details"
  /usr/bin/grep -Fq "TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER" <<<"$details"
}

if [[ "$PRODUCT_SIGNED" == 1 ]]; then
  verify_product_identity "$BUILT_EXTENSION"
  verify_product_identity "$BUILT_APP"
fi

rm -rf "$DIST_APP"
mkdir -p "$(dirname "$DIST_APP")"
/usr/bin/ditto "$BUILT_APP" "$DIST_APP"

install_product_build() {
  if [[ "$PRODUCT_SIGNED" != 1 ]]; then
    echo "A valid '$PRODUCT_SIGN_IDENTITY' certificate is required for installed Finder integration verification." >&2
    exit 3
  fi
  rm -rf "$INSTALLED_APP"
  /usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
  /usr/bin/xattr -cr "$INSTALLED_APP"
  /usr/bin/codesign --verify --strict --verbose=2 "$INSTALLED_EXTENSION"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
  verify_product_identity "$INSTALLED_EXTENSION"
  verify_product_identity "$INSTALLED_APP"
  "$LSREGISTER" -f -R -trusted "$INSTALLED_APP"
  /usr/bin/pluginkit -a "$INSTALLED_EXTENSION"
}

open_app() {
  local app="$1"
  /usr/bin/open -n "$app"
}

case "$MODE" in
  package)
    ;;
  run)
    if [[ "$PRODUCT_SIGNED" == 1 ]]; then
      install_product_build
      open_app "$INSTALLED_APP"
    else
      open_app "$DIST_APP"
    fi
    ;;
  --debug|debug)
    lldb -- "$DIST_APP/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app "$DIST_APP"
    /usr/bin/log stream --info --style compact --predicate "process == '$APP_PROCESS'"
    ;;
  --telemetry|telemetry)
    open_app "$DIST_APP"
    /usr/bin/log stream --info --style compact --predicate "subsystem == '$APP_BUNDLE_ID'"
    ;;
  --verify|verify)
    install_product_build
    open_app "$INSTALLED_APP"
    sleep 1
    pgrep -x "$APP_PROCESS" >/dev/null
    PLUGINKIT_OUTPUT="$(/usr/bin/pluginkit -m -A -D -i "$EXTENSION_BUNDLE_ID")"
    printf '%s\n' "$PLUGINKIT_OUTPUT"
    /usr/bin/grep -Fq "$EXTENSION_BUNDLE_ID" <<<"$PLUGINKIT_OUTPUT"
    echo "Finder action is registered. PlugInKit does not expose a reliable enabled-state signal for this Action Extension."
    echo "Confirm enablement in System Settings > General > Login Items & Extensions > Finder, then perform a manual right-click invocation."
    ;;
  *)
    echo "usage: $0 [package|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
