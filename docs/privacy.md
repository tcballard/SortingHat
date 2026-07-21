# Sorting Hat privacy policy

Last updated: 21 July 2026

Sorting Hat is a macOS file-organising app. It processes files that you explicitly add to its Inbox or Finder Action so it can extract useful context, rename them, apply Finder tags, and move them into folders you choose.

## On-device processing

When Apple Foundation Models is selected, file context is processed on your Mac. Text extraction from supported documents and images also uses Apple frameworks on your Mac. Sorting Hat does not send that content to the developer and the developer does not operate an analytics or tracking service for the app.

The app stores its configuration, rules, recent activity, and security-scoped folder bookmarks locally.

## Local model providers

The Mac App Store build can use either Apple's on-device model or Ollama running on the same Mac. Ollama connections are restricted to `localhost`, `127.0.0.1`, and `::1`. Remote, local-network, and OpenAI model routes are unavailable in this build.

Sorting Hat does not require an account with the developer and does not send file context to a service operated by the developer or another remote model provider.

## Files and Finder access

Sorting Hat's App Sandbox limits it to folders you explicitly select and files you explicitly send through its Finder Action. The Finder Action copies selected items into Sorting Hat's private App Group intake queue; it does not alter the originals.

## Tracking, advertising, and sale of data

Sorting Hat contains no advertising SDK, does not track you across apps or websites, and does not sell personal data.

## Retention and deletion

Sorting Hat's local activity history and settings remain on your Mac until you remove them or uninstall the app. You can remove individual review items in the app. Files already organised by Sorting Hat remain in the output folders you selected.

If you run Ollama locally, its model data and processing remain under your control on that Mac.

## Contact

For privacy questions, email [tom@armytage.co](mailto:tom@armytage.co).
