import Foundation
import Sparkle

/// A discovered Sparkle update, decoupled from SUAppcastItem so presentation
/// logic stays pure and unit-testable.
struct AvailableUpdate: Equatable {
    let version: String
    let isCritical: Bool
}

/// What the app should present for a discovered update.
///
/// - `.none`: nothing to show (no update, or the user deferred a normal one).
/// - `.suggest`: normal release — a dismissible banner in the popover.
/// - `.forced`: critical release — a blocking window that ignores dismissal.
enum UpdatePresentation: Equatable {
    case none
    case suggest(AvailableUpdate)
    case forced(AvailableUpdate)

    /// Critical releases force the blocking window regardless of dismissal;
    /// normal releases can be hidden for the session.
    static func resolve(available: AvailableUpdate?, dismissedThisSession: Bool) -> UpdatePresentation {
        guard let available else { return .none }
        if available.isCritical { return .forced(available) }
        return dismissedThisSession ? .none : .suggest(available)
    }
}

/// Wraps Sparkle with a two-tier update presentation:
///
/// - Normal releases are suggested, not silent: the updater no longer downloads
///   automatically. A banner in the popover offers "Update" (which opens
///   Sparkle's standard install UI) or "Later" (hides it for this session).
/// - Critical releases (appcast item flagged via generate_appcast's
///   `--critical-update-version`) force a blocking window; polling services
///   are stopped by the app while it is up.
///
/// Sparkle's scheduled checks stay UI-silent (`standardUserDriverShouldHandleShowingScheduledUpdate`
/// returns false) so only the app's own banner/window surfaces updates.
/// Installing always goes through Sparkle's standard UI via `checkForUpdates`.
@MainActor
final class UpdaterService: NSObject, ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var suggestionDismissed = false
    /// True while Sparkle's own install window is up (after `installUpdate()`),
    /// so the app can step aside instead of covering it.
    @Published private(set) var installInProgress = false

    /// What the UI should currently present for updates.
    var presentation: UpdatePresentation {
        UpdatePresentation.resolve(available: availableUpdate, dismissedThisSession: suggestionDismissed)
    }

    private var controller: SPUStandardUpdaterController?
    private let startUpdater: Bool
    /// Whether the current update cycle found an update, so a finished cycle
    /// without a find can clear stale availability.
    private var foundUpdateThisCycle = false

    /// - Parameter startUpdater: production always passes `true`. Tests pass `false`
    ///   because, under XCTest, there is no valid host bundle / SUFeedURL / SUPublicEDKey,
    ///   so starting the real updater would abort the test process. The config flags
    ///   below are still set, so the update-policy assertions remain meaningful.
    init(startUpdater: Bool = true) {
        self.startUpdater = startUpdater
        super.init()

        let controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        // Updates are no longer silent: Sparkle never downloads on its own.
        updater.automaticallyDownloadsUpdates = false
        self.controller = controller

        if startUpdater {
            // In addition to the schedule: re-surface the update right after
            // launch so the blocking window reappears every launch while outdated.
            updater.checkForUpdatesInBackground()
        }

        Telemetry.breadcrumb("Updater started", category: "update")
    }

    var automaticallyChecksForUpdates: Bool {
        controller?.updater.automaticallyChecksForUpdates ?? false
    }

    var automaticallyDownloadsUpdates: Bool {
        controller?.updater.automaticallyDownloadsUpdates ?? false
    }

    /// Starts the found update through Sparkle's standard UI (download + install).
    func installUpdate() {
        guard startUpdater else { return }
        Telemetry.breadcrumb("Update install requested", category: "update")
        installInProgress = true
        controller?.updater.checkForUpdates()
    }

    /// Hides the normal-update banner until the next discovered update.
    /// Critical updates ignore this and stay forced.
    func dismissSuggestion() {
        suggestionDismissed = true
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterService: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = AvailableUpdate(
            version: item.displayVersionString,
            isCritical: item.isCriticalUpdate
        )
        Task { @MainActor [weak self] in
            self?.handleFoundUpdate(update)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor [weak self] in
            self?.handleNoUpdate()
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.handleFinishedUpdateCycle(hadError: error != nil)
        }
    }

    @MainActor
    private func handleFoundUpdate(_ update: AvailableUpdate) {
        foundUpdateThisCycle = true
        availableUpdate = update
    }

    @MainActor
    private func handleNoUpdate() {
        availableUpdate = nil
    }

    @MainActor
    private func handleFinishedUpdateCycle(hadError: Bool) {
        defer { foundUpdateThisCycle = false }
        installInProgress = false
        guard !foundUpdateThisCycle, !hadError else { return }
        availableUpdate = nil
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdaterService: SPUStandardUserDriverDelegate {
    /// Keep scheduled reminders gentle; the app surfaces updates itself.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled/background checks stay silent — the banner or the blocking
    /// window is shown by the app instead of Sparkle's driver.
    /// User-invoked checks (`installUpdate` → `checkForUpdates`) still show
    /// the standard Sparkle update window.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool { false }
}
