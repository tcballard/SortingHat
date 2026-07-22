#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$($ROOT_DIR/script/release_identity.sh --version)"
BUILD="$($ROOT_DIR/script/release_identity.sh --build)"
TAG="v$VERSION"
ARCHIVE="$ROOT_DIR/dist/releases/Sorting-Hat-$TAG.zip"
CREATE=false

if [[ "${1:-}" == "--create" ]]; then
  CREATE=true
  shift
fi
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [--create] [ARCHIVE]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  ARCHIVE="$1"
fi

"$ROOT_DIR/script/release_identity.sh" --verify "$VERSION" "$BUILD"
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
  echo "Release drafts must be created from a clean committed worktree." >&2
  exit 2
fi
if ! git -C "$ROOT_DIR" show-ref --verify --quiet refs/remotes/origin/main; then
  echo "Missing origin/main. Fetch the current default branch before continuing." >&2
  exit 2
fi
if [[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" != "$(git -C "$ROOT_DIR" rev-parse refs/remotes/origin/main)" ]]; then
  echo "Release drafts must be created from the exact origin/main commit." >&2
  exit 2
fi

NOTES="$ROOT_DIR/docs/releases/$TAG.md"
test -f "$NOTES"
"$ROOT_DIR/script/verify_release_archive.sh" "$ARCHIVE" "$VERSION" "$BUILD"
gh auth status >/dev/null

if [[ "$CREATE" != true ]]; then
  echo "Release draft preflight passed for $TAG."
  echo "Run '$0 --create "$ARCHIVE"' to create the owner-reviewable draft."
  exit 0
fi

gh release create "$TAG" "$ARCHIVE" \
  --repo tcballard/SortingHat \
  --target "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
  --draft \
  --prerelease \
  --title "Sorting Hat $TAG" \
  --notes-file "$NOTES"

echo "Draft GitHub release created for $TAG."
echo "Publishing it remains a separate maintainer action."
