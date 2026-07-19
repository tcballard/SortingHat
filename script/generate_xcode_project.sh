#!/usr/bin/env bash
set -euo pipefail

EXPECTED_XCODEGEN_VERSION="2.44.1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen $EXPECTED_XCODEGEN_VERSION is required to generate SortingHat.xcodeproj." >&2
  exit 2
fi

ACTUAL_XCODEGEN_VERSION="$(xcodegen --version)"
if [[ "$ACTUAL_XCODEGEN_VERSION" != "Version: $EXPECTED_XCODEGEN_VERSION" ]]; then
  echo "Expected XcodeGen $EXPECTED_XCODEGEN_VERSION, found '$ACTUAL_XCODEGEN_VERSION'." >&2
  exit 2
fi

# XcodeGen names local-package navigator references from the checkout's final
# path component. Generate through a canonical logical root so the checked-in
# project remains byte-identical in local clones and GitHub Actions checkouts.
TEMPORARY_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/sortinghat-xcodegen.XXXXXX")"
CANONICAL_ROOT="$TEMPORARY_PARENT/SortingHat"
cleanup() {
  rm -rf "$TEMPORARY_PARENT"
}
trap cleanup EXIT

ln -s "$ROOT_DIR" "$CANONICAL_ROOT"
xcodegen generate \
  --spec "$CANONICAL_ROOT/project.yml" \
  --project "$CANONICAL_ROOT" \
  --project-root "$CANONICAL_ROOT" \
  --cache-path "$TEMPORARY_PARENT/cache.json"
