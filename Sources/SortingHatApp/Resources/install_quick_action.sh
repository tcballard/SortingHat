#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_NAME="Send to Sorting Hat.workflow"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW="$SERVICES_DIR/$WORKFLOW_NAME"
DOCUMENT="$WORKFLOW/Contents/document.wflow"
INFO="$WORKFLOW/Contents/Info.plist"
TEMPLATE="/System/Library/Services/Show Map.workflow"
CONFIGURED_INBOX="${1:-$HOME/SortingHat/Inbox}"

mkdir -p "$SERVICES_DIR"
rm -rf "$WORKFLOW"
cp -R "$TEMPLATE" "$WORKFLOW"
mv "$WORKFLOW/Contents/Resources/document.wflow" "$DOCUMENT"
rm -rf "$WORKFLOW/Contents/_CodeSignature"

SCRIPT='inbox=__SORTING_HAT_INBOX__
mkdir -p "$inbox"
for source in "$@"; do
  [ -e "$source" ] || continue
  name="$(basename "$source")"
  stem="$name"
  extension=""
  if [[ "$name" == *.* && "$name" != .* ]]; then
    stem="${name%.*}"
    extension=".${name##*.}"
  fi
  destination="$inbox/$name"
  number=2
  while [ -e "$destination" ]; do
    destination="$inbox/$stem-$number$extension"
    number=$((number + 1))
  done
  mv "$source" "$destination"
done'
ESCAPED_INBOX="$(printf '%q' "$CONFIGURED_INBOX")"
SCRIPT="${SCRIPT/__SORTING_HAT_INBOX__/$ESCAPED_INBOX}"

/usr/libexec/PlistBuddy -c "Set :actions:0:action:ActionParameters:COMMAND_STRING $SCRIPT" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :actions:0:action:ActionParameters:inputMethod 1" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :actions:0:action:ActionParameters:shell /bin/bash" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :actions:0:action:AMAccepts:Optional false" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :actions:0:action:AMAccepts:Types:0 com.apple.cocoa.path" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :actions:0:action:AMProvides:Types:0 com.apple.cocoa.path" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :workflowMetaData:serviceApplicationBundleID com.apple.finder" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :workflowMetaData:serviceInputTypeIdentifier com.apple.Automator.fileSystemObject" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :workflowMetaData:serviceOutputTypeIdentifier com.apple.Automator.nothing" "$DOCUMENT"
/usr/libexec/PlistBuddy -c "Set :workflowMetaData:workflowTypeIdentifier com.apple.Automator.servicesMenu" "$DOCUMENT"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.local.SortingHat.quick-action" "$INFO"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Send to Sorting Hat" "$INFO"
/usr/libexec/PlistBuddy -c "Set :NSServices:0:NSMenuItem:default Send to Sorting Hat" "$INFO"
/usr/libexec/PlistBuddy -c "Delete :NSServices:0:NSRequiredContext" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :NSServices:0:NSSendTypes" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSServices:0:NSSendFileTypes array" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSServices:0:NSSendFileTypes:0 string public.item" "$INFO" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :NSServices:0:NSSendFileTypes:0 public.item" "$INFO"

/System/Library/CoreServices/pbs -flush
/System/Library/CoreServices/pbs -update
killall Finder >/dev/null 2>&1 || true

echo "Installed $WORKFLOW"
