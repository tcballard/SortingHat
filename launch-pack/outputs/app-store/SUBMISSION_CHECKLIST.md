# App Store Connect entry checklist

## Product page

- Confirm the saved copy matches `LISTING.md`.
- Confirm the two screenshots remain in numbered order.
- Confirm selected build 2 displays the embedded wizard-hat icon.
- Confirm Productivity remains primary and Utilities secondary.
- Confirm copyright is `2026 Tom Ballard`.

## Required corrections

- Local-only build `0.1.0 (2)` is uploaded, valid, and selected.
- **Sign-in required** is disabled; Sorting Hat has no developer account system.
- Release mode is manual.
- Choose pricing. Free is recommended for the first submission; any paid price requires an active Paid Apps agreement.

## Declarations

- Select **Data Not Collected** using `APP_PRIVACY.md` as the evidence note.
- The age-rating questionnaire is complete and currently resolves to 4+; confirm it remains unchanged before submission.
- Content rights recommendation: select **No** when asked whether the app contains, shows, or accesses third-party content supplied by the developer. User-selected files are processed as a utility function.
- Complete export-compliance questions based on Apple's standard HTTPS/system-cryptography exemption path and the final binary.

## Review

- Confirm the saved review notes and contact details match `REVIEW_NOTES.md`.
- Keep build 0.1.0 (2) selected.
- Public support and privacy URLs returned HTTP 200 on 22 July 2026; recheck them in the final preview.
- Run an installed-build smoke test for first setup, persisted folder access, Apple on-device sorting, manual review, Finder intake, pause/resume, and launch at login.
- Submit only after every blocker in `RELEASE_CHECKLIST.md` is resolved by the owner.
