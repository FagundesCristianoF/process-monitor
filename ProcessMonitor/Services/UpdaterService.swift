import Foundation
import Sparkle

/// Thin wrapper around Sparkle configured for fully silent automatic updates.
/// There is no user-facing UI: the updater checks on a schedule, downloads, and
/// installs in the background, relaunching the app into the new version. Errors
/// from background checks are suppressed by Sparkle (no dialogs).
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// - Parameter startUpdater: production always passes `true`. Tests pass `false`
    ///   because, under XCTest, there is no valid host bundle / SUFeedURL / SUPublicEDKey,
    ///   so starting the real updater would abort the test process. The config flags
    ///   below are still set, so the silent-update assertions remain meaningful.
    init(startUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
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
