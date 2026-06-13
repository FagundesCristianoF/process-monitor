import Foundation
import Combine
import Sparkle

/// Thin wrapper around Sparkle configured for fully silent automatic updates.
/// Owns the updater lifecycle; exposes a manual check for the "Check for Updates" UI.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's `canCheckForUpdates`, used to enable/disable the menu item.
    @Published var canCheckForUpdates = false

    init() {
        // Test-only escape hatch: under XCTest there is no valid host bundle and no
        // SUFeedURL/SUPublicEDKey Info.plist keys, so starting the real updater would
        // abort the test process. When PM_TESTING=1 we construct the controller without
        // starting the updater; the property flags below are still settable and the
        // assertions remain meaningful. Production always starts the updater.
        let testing = ProcessInfo.processInfo.environment["PM_TESTING"] == "1"

        controller = SPUStandardUpdaterController(
            startingUpdater: !testing,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        Telemetry.breadcrumb("Updater started", category: "update")
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        controller.updater.automaticallyDownloadsUpdates
    }

    /// Triggers a user-initiated check.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
