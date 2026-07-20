# Sorting Hat privacy policy

Last updated: 20 July 2026

Sorting Hat is a macOS file-organising app. It processes files that you explicitly add to its Inbox or Finder Action so it can extract useful context, rename them, apply Finder tags, and move them into folders you choose.

## On-device processing

When Apple Foundation Models is selected, file context is processed on your Mac. Text extraction from supported documents and images also uses Apple frameworks on your Mac. Sorting Hat does not send that content to the developer and the developer does not operate an analytics or tracking service for the app.

The app stores its configuration, rules, recent activity, security-scoped folder bookmarks, and optional provider credentials locally. OpenAI credentials are stored in the macOS Keychain.

## Optional providers

Sorting Hat can be configured to use providers other than Apple's on-device model:

- **Ollama:** extracted file context is sent to the server address you configure. That server may be on your Mac, your local network, or a remote host. Its operator's privacy and retention practices apply.
- **OpenAI:** when you explicitly configure and select OpenAI, extracted file context and your API credential are sent to OpenAI to provide the sorting result. OpenAI's API data-usage and retention terms apply.

These providers are optional. No provider credentials are included with the app, and Sorting Hat does not require an account with the developer.

## Files and Finder access

Sorting Hat's App Sandbox limits it to folders you explicitly select and files you explicitly send through its Finder Action. The Finder Action copies selected items into Sorting Hat's private App Group intake queue; it does not alter the originals.

## Tracking, advertising, and sale of data

Sorting Hat contains no advertising SDK, does not track you across apps or websites, and does not sell personal data.

## Retention and deletion

Sorting Hat's local activity history and settings remain on your Mac until you remove them or uninstall the app. You can remove individual review items in the app. Files already organised by Sorting Hat remain in the output folders you selected.

For optional providers, retention is controlled by the provider or server operator. Consult that provider's current policy before enabling it.

## Contact

For privacy questions, email [tom@armytage.co](mailto:tom@armytage.co).
