# Sorting Hat support

Sorting Hat requires macOS 14 or later. Apple's on-device Foundation Model requires macOS 26, Apple Intelligence, and a supported Mac. On other supported Macs, you can configure a local Ollama server or an optional OpenAI provider.

## Getting started

1. Open Sorting Hat and choose an Inbox and a filed-output folder.
2. Describe how you want files organised, review the proposed rules, and save them.
3. Add files from the Inbox view or use **Send to Sorting Hat** in Finder's Quick Actions menu.
4. Keep Sorting Hat running and unpaused. The Activity view shows where each file was filed or why it needs attention.

Sorting Hat creates rule-specific directories beneath your filed-output folder. It preserves file extensions, protects existing files from being overwritten, and leaves uncertain or invalid decisions in the Inbox for review.

## Finder Action

Enable **Send to Sorting Hat** in **System Settings → General → Login Items & Extensions → Finder**. If Finder does not show it immediately, relaunch Finder once. Sending a file copies it into Sorting Hat; the original remains untouched.

## Fixing a file that needs review

Open the Activity view and use the item's context menu. You can retry it, correct its filename and destination manually, or remove it from the review list. Removing a review entry does not delete the source file.

## Folder access problems

Open Sorting Hat's settings and choose the Inbox or filed-output folder again. This refreshes the App Sandbox permission stored for that folder.

## Get help or report a bug

- Email: [tom@armytage.co](mailto:tom@armytage.co)
- Public issue tracker: [github.com/tcballard/SortingHat/issues](https://github.com/tcballard/SortingHat/issues)

Please include your macOS version, Sorting Hat version, selected model provider, and the visible error message. Do not attach private files or API keys.
