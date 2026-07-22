# Release checklist

| Gate | Requirement | Evidence or observation | Result | Owner | Next action |
| --- | --- | --- | --- | --- | --- |
| Release identity | Version, build, date, and availability agree | App Store record is 0.1.0; local-only build 2 is valid and selected | Ready | Tom Ballard | Preserve build 2 through submission |
| Claims | Every used claim is verified or visibly qualified | Claims ledger removes PCC and verifies the Store-only no-data claim | Ready | Tom Ballard | Preserve channel qualifications in public copy |
| Assets | Required outputs exist and open correctly | Icon plus two real screenshots are present in App Store Connect | Ready | Tom Ballard | Visually confirm the final product-page preview |
| Technical | Channel and submission constraints pass | Local-only build 2 passed structural preflight and Apple validation; installed-build Store smoke test remains | Blocked | Tom Ballard | Install and smoke-test build 2 |
| Accessibility | Captions, contrast, text alternatives, and readability pass | Screens are legible at 1440×900; copy explains outcomes | Ready | Tom Ballard | Review App Store preview at normal scale |
| Privacy | No secrets, private data, or embargoed details leak | Store runtime neutralizes OpenAI and non-loopback Ollama; privacy manifest declares no collection | Ready | Tom Ballard | Select Data Not Collected |
| Links | Destinations and calls to action work | Support and privacy URLs return HTTP 200 from merged `main` | Ready | Tom Ballard | Recheck in the final App Store preview |
| Provenance | Required source and model contribution records exist | Per-asset JSON records source hashes and transformations | Ready | Tom Ballard | Retain evidence with the pack |
| Authority | Publisher and manual action are explicit | Metadata and build are prepared; App Review submission remains owner-controlled | Ready | Tom Ballard | Owner answers remaining declarations and submits |
