# Distribution channels

Sorting Hat has one release train and two signed macOS delivery channels. Every
candidate is built from one source commit with the same marketing version and
build number from `Configuration/Release.xcconfig`. The channels retain the
different signing, sandbox, and provider contracts required by their delivery
mechanisms.

Run the complete local candidate gate with:

```sh
./script/release_candidate.sh
```

It tests the code, rejects generated-project or version drift, builds and
verifies the Developer ID ZIP, builds and verifies the Apple Distribution
archive and package, and records their checksums and source commit in one
manifest. It does not tag, publish, upload, or submit either artifact.

The current unified release target is **0.1.1 (3)**. The candidate must come
from the eventual release commit; the existing GitHub `v0.1.0` artifact and
App Store Connect build `0.1.0 (2)` remain historical channel artifacts until
their replacements are independently verified.

## Developer ID and Homebrew — Issue #24

The tag-triggered release workflow already fails closed while it:

1. imports a Developer ID Application certificate into an ephemeral keychain;
2. builds with hardened runtime and signs the Finder Action before the app;
3. verifies identities, App Group entitlements, bundle identifiers, and the
   extension contract;
4. notarizes, staples, and validates with Gatekeeper;
5. extracts and re-verifies the final ZIP before publishing it;
6. updates the Homebrew cask with the final archive checksum.

The GitHub workflow expects these repository secrets. Store them only as
GitHub repository secrets, never in source, issues, workflow logs, or pull
requests:

- `DEVELOPER_ID_APPLICATION_P12`
- `DEVELOPER_ID_APPLICATION_PASSWORD`
- `BUILD_KEYCHAIN_PASSWORD`
- `NOTARY_APPLE_ID`
- `NOTARY_PASSWORD`

`HOMEBREW_TAP_TOKEN` is already configured. A successful signed release and a
fresh downloaded-artifact verification remain required before closing Issue #24.
Create the `v0.1.1` tag only after all certificate and notarization secrets are
confirmed; otherwise the workflow intentionally fails closed rather than
publishing an unsigned artifact.

The local Mac already has the Developer ID Application identity. Store reusable
notarization credentials once in the login Keychain (the password is requested
interactively and is not written to the repository):

```sh
xcrun notarytool store-credentials SortingHat-Notary \
  --apple-id YOUR_APPLE_ID \
  --team-id R8HXTBY3NM
```

Then produce and verify only the Developer ID channel with:

```sh
./script/release_local.sh
```

The script requires the real Developer ID identity, submits through the named
Keychain profile, staples and assesses the app, creates the final ZIP, extracts
that ZIP, and repeats signature, stapler, and Gatekeeper validation against the
actual distributable artifact. It does not tag, publish, or update Homebrew.
The script also accepts an App Store Connect API key through the
`SORTING_HAT_NOTARY_KEY_PATH`, `SORTING_HAT_NOTARY_KEY_ID`, and
`SORTING_HAT_NOTARY_ISSUER_ID` environment variables instead of a Keychain
profile. Credentials are never read from the repository.

## Mac App Store — Issue #29

The `SortingHatAppStore` scheme uses the release-like `AppStore` configuration.
Unlike the Developer ID build, its main app enables App Sandbox with only:

- the shared App Group used by the Finder Action queue;
- app-scoped security bookmarks;
- read/write access to folders the person explicitly selects;
- outgoing client connections solely for Ollama restricted to loopback on the
  same Mac. OpenAI, LAN, and remote Ollama routes are unavailable in this build.

The Finder Action stays sandboxed and read-only for selected Finder items. It
copies accepted input into the App Group queue; it does not receive broad write
access. The process-backed PCC research adapter is a separate Swift package
target used by the CLI and tests, and is not linked into the app.

Run the unsigned structural preflight with:

```sh
./script/generate_xcode_project.sh
./script/preflight_app_store.sh
```

The preflight archives the actual Store scheme, checks that there is one app,
verifies the nested extension and privacy manifest, confirms that the legacy
`/usr/bin/fm` path is absent from the app binary, ad-hoc signs solely for local
entitlement inspection, and checks the minimum sandbox contract. It does not
produce an uploadable archive.

Create and verify the Apple Distribution archive and upload package with:

```sh
./script/archive_app_store.sh
```

The script uses Xcode's installed account by default. For API-key authentication,
set `SORTING_HAT_ASC_KEY_PATH`, `SORTING_HAT_ASC_KEY_ID`, and
`SORTING_HAT_ASC_ISSUER_ID` together. It archives the `SortingHatAppStore`
scheme, checks the nested signatures and shared release identity, and exports
with `Configuration/AppStoreExportOptions.plist`. It does not upload or submit.

App Store Connect build **0.1.0 (2)** passed Apple validation, processed as
`VALID`, and remains selected for version 0.1.0. The matching **0.1.1 (3)**
candidate has not been uploaded. The listing, screenshots,
categories, age rating, review contact, and review notes are saved. Before
submission, choose pricing, attest **Data Not Collected**, complete export
compliance and content rights, and run the installed-build smoke test. The
submission pack under [`launch-pack/`](../launch-pack/) contains the verified
copy, genuine screenshots, icon evidence, review instructions, and remaining
blocker checklist.

An App Store/TestFlight build must still be manually verified for first-run
setup, persisted folder access across relaunch, on-device sorting, manual review,
Finder Action intake, and launch at login before Issue #29 can close.
