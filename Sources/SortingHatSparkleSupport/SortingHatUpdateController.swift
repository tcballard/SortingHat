import Sparkle

/// Direct-download update support. This source is intentionally compiled only
/// into the Developer ID target; Mac App Store builds use Apple's updater.
@MainActor
final class SortingHatUpdateController {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
