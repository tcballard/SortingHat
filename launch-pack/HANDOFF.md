# Launch handoff

- Product: Sorting Hat: File Organiser
- Release: First Mac App Store submission
- Version: 0.1.0
- Build: 1
- Pack status: Structurally ready with three explicit submission blockers
- Publication authority: Tom Ballard only
- Exact next action: Resolve version identity and Store-provider privacy, merge PR #30, then enter the supplied metadata

## Included deliverables

| Channel | Output | Status | Claim IDs | Notes |
| --- | --- | --- | --- | --- |
| Mac App Store | outputs/app-store/LISTING.md | Ready | C01-C03 | Copy respects current product behavior |
| Screenshots | outputs/app-store/screenshots | Ready | C01-C03 | Two opaque 1440×900 JPEGs |
| Icon | outputs/app-store/icon/app-icon-1024.png | Ready | None | Reference copy of the icon already embedded in build 1 |
| App Review | outputs/app-store/REVIEW_NOTES.md | Ready | C01-C03 | Phone number must be entered by owner |
| Privacy | outputs/app-store/APP_PRIVACY.md and docs/privacy.md | Blocked | C02, C04, C05 | Choose Store provider scope before attesting |
| Support | docs/support.md | Ready | C01-C03 | Public URL works only after merge |

## Omitted or not-applicable deliverables

- No preview video is required for the first submission.
- No separate icon upload is required because the icon is delivered in the build.
- Developer ID, Homebrew, press, and social delivery are outside this submission pack.

## Claims

- Verified: Core renaming/routing, on-device Apple processing, copy-only Finder intake, and no tracking/advertising.
- Qualified: On-device generation requirements and optional provider behavior.
- Blocked or removed: “Data Not Collected” is blocked while OpenAI remains; PCC is removed from shipping claims.

## Validation performed

- Audited App Store Connect without saving changes.
- Inspected the selected build identity, metadata gaps, included icon, privacy state, release mode, and category state.
- Captured the real app with synthetic files, restored the user's configuration and activity, and removed fixture outputs.
- Adapted screenshots proportionally to an accepted Mac size with provenance evidence.
- Measured and visually reviewed the 1024 px shipping icon.

## Remaining decisions and blockers

- Match App Store version 1.0 to build marketing version 0.1.0.
- Either remove cloud providers from the Store build or disclose OpenAI collection conservatively.
- Merge the support/privacy pages, then verify their public URLs.
- Supply the App Review phone number, choose price, complete age rating/export compliance/content rights, change release mode to manual, and uncheck sign-in required.
