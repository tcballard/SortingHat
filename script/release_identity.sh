#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CONFIG="$ROOT_DIR/Configuration/Release.xcconfig"
APP_INFO="$ROOT_DIR/Configuration/SortingHatApp-Info.plist"
EXTENSION_INFO="$ROOT_DIR/Configuration/SendToSortingHatAction-Info.plist"

read_setting() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/\/\/.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$CONFIG"
}

VERSION="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid MARKETING_VERSION in $CONFIG: $VERSION" >&2
  exit 2
fi
if [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid CURRENT_PROJECT_VERSION in $CONFIG: $BUILD" >&2
  exit 2
fi

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")" = '$(MARKETING_VERSION)'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO")" = '$(CURRENT_PROJECT_VERSION)'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTENSION_INFO")" = '$(MARKETING_VERSION)'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTENSION_INFO")" = '$(CURRENT_PROJECT_VERSION)'

case "${1:-}" in
  --version)
    printf '%s\n' "$VERSION"
    ;;
  --build)
    printf '%s\n' "$BUILD"
    ;;
  --verify)
    EXPECTED_VERSION="${2:-}"
    EXPECTED_BUILD="${3:-$BUILD}"
    if [[ "$VERSION" != "$EXPECTED_VERSION" || "$BUILD" != "$EXPECTED_BUILD" ]]; then
      echo "Release identity mismatch: contract is $VERSION ($BUILD), expected $EXPECTED_VERSION ($EXPECTED_BUILD)." >&2
      exit 2
    fi
    printf 'Release identity verified: %s (%s)\n' "$VERSION" "$BUILD"
    ;;
  "")
    printf 'version=%s\nbuild=%s\n' "$VERSION" "$BUILD"
    ;;
  *)
    echo "usage: $0 [--version | --build | --verify VERSION [BUILD]]" >&2
    exit 2
    ;;
esac
