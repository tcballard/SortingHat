# Launch brief

- Product: Sorting Hat: File Organiser
- Release: First Mac App Store submission
- Version: 0.1.0
- Build: 2
- Release state: Local-only build uploaded, processed, and selected; owner declarations and installed verification remain
- Release date or window: After App Review approval
- Authoritative source: merged PR #30 at commit 7dcc9ef plus App Store Connect build 0.1.0 (2)

## Audience and outcome

- Primary audience: Mac users who want files renamed and organised without writing automation
- User outcome: Describe a filing plan once, then send files to one Inbox and see them renamed and routed into useful folders
- Launch objective: Submit an accurate, reviewable first Mac App Store version
- Primary call to action: At launch, download Sorting Hat from the Mac App Store; before launch, complete the owner submission gates
- Canonical destination: App Store Connect record 6792563259

## Availability and boundaries

- Platforms and minimum versions: macOS 14 or later; Apple on-device generation requires macOS 26, Apple Intelligence, and a supported Mac
- Rollout or eligibility: Public Mac App Store after manual release and review approval
- Pricing: Owner decision required; free is recommended for the first submission
- Material limitations: Model availability affects sorting; uncertain items require review; Store Ollama connections are restricted to the same Mac
- Required disclosures: same-Mac model boundary, folder access, no developer account, and Finder Action copy-only intake

## Delivery contract

- Included channels: repository front door, Mac App Store product page, screenshots, icon handoff, privacy policy, support page, App Review notes, submission checklist
- Deliberately omitted channels: Homebrew, Developer ID release, press, social, and demo video
- Format or submission constraints: 1-10 opaque 16:10 Mac screenshots; icon embedded in the uploaded build; App Store field limits
- Accessibility requirements: Screenshots remain legible at product-page scale and listing copy describes the visual outcome
- Publication authority: Tom Ballard controls App Review submission and public release

## Evidence summary

- Release artifact or verified build: App Store Connect build 0.1.0 (2) passed Apple validation, processed as `VALID`, and is selected with an included App Icon
- Tests and measurements: PR #30 CI is green; Store structural preflight, archive validation, and selected-build verification passed
- Specification and acceptance criteria: Issue #29 and docs/distribution.md
- Build logs and decisions: merged PR #30 history and App Store Connect API verification on 21 July 2026
- Existing assets and copy: Shipping app icon plus two genuine, sanitised application captures
