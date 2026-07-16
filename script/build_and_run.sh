#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
APP_NAME="SortingHatApp"
BUNDLE_ID="com.local.SortingHat"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Sorting Hat.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

for process_name in "$APP_NAME" "Sorting Hat" SortingHat sorting-hat; do
  pkill -x "$process_name" >/dev/null 2>&1 || true
done
env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swift-cache" swift build --disable-sandbox -c "$CONFIGURATION" --product "$APP_NAME"
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/script/install_quick_action.sh" "$APP_RESOURCES/install_quick_action.sh"
chmod +x "$APP_BINARY"
chmod +x "$APP_RESOURCES/install_quick_action.sh"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Sorting Hat</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

case "$MODE" in
  package) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'" ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'" ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [package|run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
