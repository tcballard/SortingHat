# Xcode packaging

`SortingHat.xcodeproj` is generated from `project.yml` with XcodeGen. The Xcode
target embeds the native Finder Action Extension; SwiftPM remains the authority
for `SortingHatCore`, the CLI, and core tests.

The app and extension share the macOS application group
`R8HXTBY3NM.com.tcballard.sortinghat`. A build signed without Team
`R8HXTBY3NM` can compile and launch the main app, but macOS will not grant the
shared container needed by the Finder action. Product verification therefore
requires a valid certificate for that team.

Regenerate the project with the pinned, checkout-name-stable wrapper after
changing `project.yml`:

```sh
./script/generate_xcode_project.sh
```
