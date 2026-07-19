# iOS client boundary

Sorting Hat's native model contract can be reused on iOS 26 and later: Apple's
`FoundationModels` framework, guided-generation schema, filing rules, `Decision`
shape, rename correction, and deterministic route validation are not inherently
Mac-only.

The current Swift package is still a macOS product. Its watched Inbox,
security-scoped folder bookmarks, Finder tags, AppKit document conversion, and
menu-bar shell are macOS-specific and must not be presented as an iOS build.

An iPhone or iPad client should keep the same product contract while replacing
continuous folder watching with platform-native intake:

- a Files document picker for explicit imports;
- a Share extension for sending documents and screenshots to Sorting Hat;
- drag and drop on iPad;
- an App Group queue shared by the extension and containing app;
- an in-app Inbox and manual-review flow identical in meaning to the Mac app.

iOS does not grant an ordinary app continuous, general-purpose monitoring of
arbitrary Files locations in the background. Sorting must therefore begin from
an explicit import/share action or from work the app has already accepted into
its own container. The model also requires a supported Apple Intelligence
device with the system model available; manual rules and review UI should remain
usable when it is not.

The next cross-platform refactor would split the package into:

1. `SortingHatDecisionCore`: Foundation-only decisions, compiled rules, routing,
   validation, and provider-neutral protocols;
2. `SortingHatAppleModel`: Foundation Models prompts and guided generation,
   accepting already-extracted text plus file metadata;
3. macOS and iOS ingestion targets that own document extraction, permissions,
   intake, and filesystem actions for their platform.

This rewrite establishes the in-process Apple model path needed for that split,
but does not claim that the current macOS package already compiles or ships on
iOS.
