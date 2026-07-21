# Release checklist

| Gate | Requirement | Evidence or observation | Result | Owner | Next action |
| --- | --- | --- | --- | --- | --- |
| Release identity | Version, build, date, and availability agree | App Store record is 0.1.0; local-only build 2 is prepared | Blocked | Tom Ballard | Upload and select build 0.1.0 (2) |
| Claims | Every used claim is verified or visibly qualified | Claims ledger removes PCC and blocks no-data claim | Ready | Tom Ballard | Preserve qualifications when entering copy |
| Assets | Required outputs exist and open correctly | Icon plus two real screenshots prepared | Ready | Tom Ballard | Upload screenshots and visually confirm the embedded icon |
| Technical | Channel and submission constraints pass | Local-only build 2 structural preflight passes; installed-build Store smoke test remains | Blocked | Tom Ballard | Upload, install, and smoke-test build 2 |
| Accessibility | Captions, contrast, text alternatives, and readability pass | Screens are legible at 1440×900; copy explains outcomes | Ready | Tom Ballard | Review App Store preview at normal scale |
| Privacy | No secrets, private data, or embargoed details leak | Store runtime neutralizes OpenAI and non-loopback Ollama; privacy manifest declares no collection | Ready | Tom Ballard | Select Data Not Collected after build 2 is processed and verified |
| Links | Destinations and calls to action work | Repository links exist; support/privacy pages become public after merge | Blocked | Tom Ballard | Merge PR #30, then verify both public URLs anonymously |
| Provenance | Required source and model contribution records exist | Per-asset JSON records source hashes and transformations | Ready | Tom Ballard | Retain evidence with the pack |
| Authority | Publisher and manual action are explicit | No App Store Connect fields were changed during preparation | Ready | Tom Ballard | Owner enters metadata, answers declarations, and submits |
