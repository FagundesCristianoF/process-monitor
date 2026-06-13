import Foundation
import Sparkle

/// Thin wrapper around Sparkle configured for fully silent automatic updates.
/// There is no user-facing UI: the updater checks on a schedule, downloads, and
/// installs in the background, relaunching the app into the new version. Errors
/// from background checks are suppressed by Sparkle (no dialogs).
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

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

        Telemetry.breadcrumb("Updater started", category: "update")
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        controller.updater.automaticallyDownloadsUpdates
    }
}
