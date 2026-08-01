#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="2.9.2"
EXPECTED_SHA256="b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
CACHE_DIR="${SORTING_HAT_SPARKLE_DIR:-$ROOT_DIR/.build/sparkle/$VERSION}"

if [[ -d "$CACHE_DIR/Sparkle.xcframework" \
   && -x "$CACHE_DIR/bin/generate_keys" \
   && -x "$CACHE_DIR/bin/generate_appcast" ]]; then
  echo "Sparkle $VERSION is ready at $CACHE_DIR"
  exit 0
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/sortinghat-sparkle.XXXXXX")"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

curl -fL "$URL" -o "$STAGING/Sparkle.zip"
ACTUAL_SHA256="$(shasum -a 256 "$STAGING/Sparkle.zip" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Sparkle archive checksum mismatch: expected $EXPECTED_SHA256, got $ACTUAL_SHA256" >&2
  exit 3
fi

mkdir -p "$STAGING/extracted"
ditto -x -k "$STAGING/Sparkle.zip" "$STAGING/extracted"
test -d "$STAGING/extracted/Sparkle.xcframework"
test -x "$STAGING/extracted/bin/generate_keys"
test -x "$STAGING/extracted/bin/generate_appcast"

rm -rf "$CACHE_DIR"
mkdir -p "$(dirname "$CACHE_DIR")"
mv "$STAGING/extracted" "$CACHE_DIR"
echo "Sparkle $VERSION verified and prepared at $CACHE_DIR"
