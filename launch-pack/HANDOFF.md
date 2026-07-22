# Launch handoff

- Product: Sorting Hat: File Organiser
- Release: First Mac App Store submission
- Version: 0.1.0
- Build: 2
- Pack status: Local-only build 2 uploaded, processed, and selected; URL publication and installed verification remain
- Publication authority: Tom Ballard only
- Exact next action: Merge PR #30, verify the public support/privacy URLs, then complete the remaining owner declarations

## Included deliverables

| Channel | Output | Status | Claim IDs | Notes |
| --- | --- | --- | --- | --- |
| Mac App Store | outputs/app-store/LISTING.md | Ready | C01-C03 | Copy respects current product behavior |
| Screenshots | outputs/app-store/screenshots | Ready | C01-C03 | Two opaque 1440×900 JPEGs |
| Icon | outputs/app-store/icon/app-icon-1024.png | Ready | None | Reference copy of the icon embedded in selected build 2 |
| App Review | outputs/app-store/REVIEW_NOTES.md | Ready | C01-C03 | Notes and review contact are saved in App Store Connect |
| Privacy | outputs/app-store/APP_PRIVACY.md and docs/privacy.md | Ready | C02, C04, C05 | Build 2 is verified; select Data Not Collected |
| Support | docs/support.md | Ready | C01-C03 | Public URL works only after merge |

## Omitted or not-applicable deliverables

- No preview video is required for the first submission.
- No separate icon upload is required because the icon is delivered in the build.
- Developer ID, Homebrew, press, and social delivery are outside this submission pack.

## Claims

- Verified: Core renaming/routing, on-device Apple processing, copy-only Finder intake, and no tracking/advertising.
- Qualified: On-device generation requirements and optional provider behavior.
- Blocked or removed: PCC, OpenAI, LAN Ollama, and remote Ollama are removed from Store shipping claims.

## Validation performed

- Uploaded build 2, confirmed Apple processing state `VALID`, and selected it for version 0.1.0.
- Saved the local-only listing, categories, age rating, review contact, and review notes in App Store Connect.
- Captured the real app with synthetic files, restored the user's configuration and activity, and removed fixture outputs.
- Adapted screenshots proportionally to an accepted Mac size with provenance evidence.
- Measured and visually reviewed the 1024 px shipping icon.

## Remaining decisions and blockers

- Merge the support/privacy pages, then verify their public URLs.
- Choose price, complete App Privacy, export compliance, and content rights, then run installed-build verification.
