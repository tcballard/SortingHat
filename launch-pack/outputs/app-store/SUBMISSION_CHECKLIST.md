# App Store Connect entry checklist

## Product page

- Paste the copy from `LISTING.md`.
- Upload the two screenshots in the numbered order.
- Confirm the build's embedded wizard-hat icon is displayed.
- Select Productivity as primary category and Utilities as secondary.
- Set copyright to `2026 Tom Ballard`.

## Required corrections

- Upload and select local-only build `0.1.0 (2)`.
- Uncheck **Sign-in required**; Sorting Hat has no developer account system.
- Change release mode from automatic to manual release.
- Choose pricing. Free is recommended for the first submission; any paid price requires an active Paid Apps agreement.

## Declarations

- After build 2 verification, select **Data Not Collected** using `APP_PRIVACY.md` as the evidence note.
- Complete the age-rating questionnaire. The product contains no ads, social features, web browser, gambling, user-to-user communication, or user-generated-content sharing; answer from the shipping binary rather than this recommendation.
- Content rights recommendation: select **No** when asked whether the app contains, shows, or accesses third-party content supplied by the developer. User-selected files are processed as a utility function.
- Complete export-compliance questions based on Apple's standard HTTPS/system-cryptography exemption path and the final binary.

## Review

- Paste `REVIEW_NOTES.md` and enter the owner's phone number.
- Select build 0.1.0 (1) after the version identity is resolved.
- Verify the public support and privacy URLs anonymously after PR #30 merges.
- Run an installed-build smoke test for first setup, persisted folder access, Apple on-device sorting, manual review, Finder intake, pause/resume, and launch at login.
- Submit only after every blocker in `RELEASE_CHECKLIST.md` is resolved by the owner.
