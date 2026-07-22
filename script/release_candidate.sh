#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="${1:-$($ROOT_DIR/script/release_identity.sh --version)}"
BUILD="${2:-$($ROOT_DIR/script/release_identity.sh --build)}"
OUTPUT_DIR="${SORTING_HAT_RELEASE_OUTPUT:-$ROOT_DIR/dist/releases}"
MANIFEST="$OUTPUT_DIR/Sorting-Hat-$VERSION-$BUILD.manifest.txt"

"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$BUILD"
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
  echo "Release candidates must be built from a clean committed worktree." >&2
  exit 2
fi
"$ROOT_DIR/script/generate_xcode_project.sh"
git -C "$ROOT_DIR" diff --exit-code -- \
  SortingHat.xcodeproj \
  Configuration/SortingHatApp-Info.plist \
  Configuration/SendToSortingHatAction-Info.plist
swift test
"$ROOT_DIR/script/release_local.sh" "$VERSION"
SORTING_HAT_APP_STORE_OUTPUT="$OUTPUT_DIR/AppStore" \
  "$ROOT_DIR/script/archive_app_store.sh"

DIRECT_ARCHIVE="$OUTPUT_DIR/Sorting-Hat-v$VERSION.zip"
STORE_PACKAGE="$(find "$OUTPUT_DIR/AppStore/Export" -maxdepth 1 -type f -name '*.pkg' -print -quit)"
test -f "$DIRECT_ARCHIVE"
test -n "$STORE_PACKAGE"

COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
DIRECT_SHA="$(shasum -a 256 "$DIRECT_ARCHIVE" | awk '{print $1}')"
STORE_SHA="$(shasum -a 256 "$STORE_PACKAGE" | awk '{print $1}')"
mkdir -p "$OUTPUT_DIR"
printf '%s\n' \
  "Sorting Hat release candidate" \
  "version=$VERSION" \
  "build=$BUILD" \
  "commit=$COMMIT" \
  "developer_id_archive=$DIRECT_ARCHIVE" \
  "developer_id_sha256=$DIRECT_SHA" \
  "app_store_package=$STORE_PACKAGE" \
  "app_store_sha256=$STORE_SHA" \
  "published=false" \
  "app_store_uploaded=false" > "$MANIFEST"

echo "Unified release candidate verified: $VERSION ($BUILD) at $COMMIT"
echo "Manifest: $MANIFEST"
echo "Neither channel has been published or uploaded."
