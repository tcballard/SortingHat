# Distribution channels

Sorting Hat is preparing two macOS distribution channels. They share the same
product code but have different signing and sandbox contracts.

## Developer ID and Homebrew — Issue #24

The tag-triggered release workflow already fails closed while it:

1. imports a Developer ID Application certificate into an ephemeral keychain;
2. builds with hardened runtime and signs the Finder Action before the app;
3. verifies identities, App Group entitlements, bundle identifiers, and the
   extension contract;
4. notarizes, staples, and validates with Gatekeeper;
5. extracts and re-verifies the final ZIP before publishing it;
6. updates the Homebrew cask with the final archive checksum.

The repository currently lacks the credential secrets required to exercise that
workflow. Add these through GitHub repository secrets, never through source,
issues, workflow logs, or pull requests:

- `DEVELOPER_ID_APPLICATION_P12`
- `DEVELOPER_ID_APPLICATION_PASSWORD`
- `BUILD_KEYCHAIN_PASSWORD`
- `NOTARY_APPLE_ID`
- `NOTARY_PASSWORD`

`HOMEBREW_TAP_TOKEN` is already configured. A successful signed release and a
fresh downloaded-artifact verification remain required before closing Issue #24.

The local Mac already has the Developer ID Application identity. Store reusable
notarization credentials once in the login Keychain (the password is requested
interactively and is not written to the repository):

```sh
xcrun notarytool store-credentials SortingHat-Notary \
  --apple-id YOUR_APPLE_ID \
  --team-id R8HXTBY3NM
```

Then produce and verify a local release candidate with:

```sh
./script/release_local.sh 0.2.0
```

The script requires the real Developer ID identity, submits through the named
Keychain profile, staples and assesses the app, creates the final ZIP, extracts
that ZIP, and repeats signature, stapler, and Gatekeeper validation against the
actual distributable artifact. It does not tag, publish, or update Homebrew.

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

To create a submission build, the owner must first register both bundle IDs and
the App Group in the Apple Developer portal, attach the App Group to both IDs,
install or allow Xcode to obtain matching Mac App Store profiles, and create an
App Store Connect record for `com.tcballard.sortinghat`. Then archive the
`SortingHatAppStore` scheme in Xcode and choose **Distribute App → App Store
Connect**, or export a correctly signed archive with
`Configuration/AppStoreExportOptions.plist`.

App Store Connect build **0.1.0 (2)** passed Apple validation, processed as
`VALID`, and is selected for version 0.1.0. The listing, screenshots,
categories, age rating, review contact, and review notes are saved. Before
submission, choose pricing, attest **Data Not Collected**, complete export
compliance and content rights, and run the installed-build smoke test. The
submission pack under [`launch-pack/`](../launch-pack/) contains the verified
copy, genuine screenshots, icon evidence, review instructions, and remaining
blocker checklist.

An App Store/TestFlight build must still be manually verified for first-run
setup, persisted folder access across relaunch, on-device sorting, manual review,
Finder Action intake, and launch at login before Issue #29 can close.
