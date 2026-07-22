# App Privacy submission guidance

This note describes the Mac App Store build only.

## Verified Store behavior

- Apple Foundation Models and document/image extraction operate on the Mac.
- Optional Ollama connections are restricted to loopback addresses on the same Mac.
- OpenAI, LAN Ollama, remote Ollama, Private Cloud Compute, advertising, analytics, and tracking are unavailable.
- The developer does not receive file content, account data, analytics, or diagnostics from the app.
- The Store privacy manifest declares no collected data types and no tracking domains.

## App Store Connect answer

Build `0.1.0 (2)` is uploaded, processed, selected, and verified. Choose **Data Not Collected** in App Store Connect.

Do not apply this answer to Developer ID, source, or CLI distributions without separately evaluating their configured provider behavior.

## Privacy policy URL

https://github.com/tcballard/SortingHat/blob/main/docs/privacy.md
