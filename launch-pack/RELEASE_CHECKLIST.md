# Release checklist

| Gate | Requirement | Evidence or observation | Result | Owner | Next action |
| --- | --- | --- | --- | --- | --- |
| Release identity | Version, build, date, and availability agree | Build is 0.1.0 (1); App Store version page currently says 1.0 | Blocked | Tom Ballard | Change the record to 0.1.0 or upload a build whose marketing version matches 1.0 |
| Claims | Every used claim is verified or visibly qualified | Claims ledger removes PCC and blocks no-data claim | Ready | Tom Ballard | Preserve qualifications when entering copy |
| Assets | Required outputs exist and open correctly | Icon plus two real screenshots prepared | Ready | Tom Ballard | Upload screenshots and visually confirm the embedded icon |
| Technical | Channel and submission constraints pass | Selectable build and green CI; installed-build Store smoke test remains | Blocked | Tom Ballard | Test the Store-signed installed build after TestFlight/App Store availability |
| Accessibility | Captions, contrast, text alternatives, and readability pass | Screens are legible at 1440×900; copy explains outcomes | Ready | Tom Ballard | Review App Store preview at normal scale |
| Privacy | No secrets, private data, or embargoed details leak | Assets are sanitised; optional OpenAI requires disclosure or removal | Blocked | Tom Ballard | Make provider decision and complete App Privacy accordingly |
| Links | Destinations and calls to action work | Repository links exist; support/privacy pages become public after merge | Blocked | Tom Ballard | Merge PR #30, then verify both public URLs anonymously |
| Provenance | Required source and model contribution records exist | Per-asset JSON records source hashes and transformations | Ready | Tom Ballard | Retain evidence with the pack |
| Authority | Publisher and manual action are explicit | No App Store Connect fields were changed during preparation | Ready | Tom Ballard | Owner enters metadata, answers declarations, and submits |
