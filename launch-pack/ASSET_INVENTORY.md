# Asset inventory

| ID | Asset | Purpose | Source or provenance | Constraints | Output path | Status | Blocker or next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A01 | 1024 px app icon | Embedded Store icon reference and visual handoff | Shipping AppIcon asset, SHA-256 recorded in evidence | Opaque 1024×1024 PNG | outputs/app-store/icon/app-icon-1024.png | Ready | Confirm the selected build displays this icon in App Store Connect |
| A02 | Sorted Activity screenshot | Show the core result | Genuine app capture using synthetic fixtures | 1440×900 opaque JPEG | outputs/app-store/screenshots/01-sorted-activity.jpg | Ready | Upload in position 1 |
| A03 | Plain-language Rules screenshot | Show rule creation and editing | Genuine app capture with no private data | 1440×900 opaque JPEG | outputs/app-store/screenshots/02-plain-language-rules.jpg | Ready | Upload in position 2 |
| A04 | Privacy settings screenshot | Avoid a stale PCC claim | Earlier capture showed a non-shipping setting | Must reflect current product | Not included | Removed | Capture a replacement only after the privacy/provider decision |
