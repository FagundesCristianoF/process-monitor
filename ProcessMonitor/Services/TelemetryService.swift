import Foundation
import Sentry
import os

enum Telemetry {
    static let log = Logger(subsystem: "com.cristianofagundes.ProcessMonitor", category: "telemetry")

    private static let dsn = "https://fecdd638e46f0ab0962704af702ef004@o4511023893774336.ingest.us.sentry.io/4511431257554944"
    private static var started = false

    static func start(enabled: Bool) {
        guard enabled, !started else { return }
        started = true

        let releaseName: String = {
            let bundle = Bundle.main
            let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
            let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            return "ProcessMonitor@\(version)+\(build)"
        }()

        SentrySDK.start { opts in
            opts.dsn = dsn
            opts.releaseName = releaseName
            opts.environment = isDebugBuild ? "debug" : "release"
            opts.attachStacktrace = true
            opts.enableAutoPerformanceTracing = false
            opts.enableNetworkTracking = false
            opts.enableAppHangTracking = true
            opts.tracesSampleRate = 0.0
            opts.beforeSend = { event in
                scrub(event)
                return event
            }
            opts.beforeBreadcrumb = { crumb in
                scrub(crumb)
                return crumb
            }
        }
        log.info("Sentry started: \(releaseName, privacy: .public)")
    }

    static func stop() {
        guard started else { return }
        SentrySDK.close()
        started = false
        log.info("Sentry stopped")
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            start(enabled: true)
        } else {
            stop()
        }
    }

    static func capture(_ error: Error, context: String? = nil) {
        log.error("\(context ?? "error", privacy: .public): \(error.localizedDescription, privacy: .public)")
        guard started else { return }
        SentrySDK.capture(error: error) { scope in
            if let context { scope.setTag(value: context, key: "context") }
        }
    }

    static func captureMessage(_ message: String, level: SentryLevel = .info) {
        log.info("\(message, privacy: .public)")
        guard started else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
        }
    }

    static func breadcrumb(_ message: String, category: String = "app", level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Privacy scrubbing

    /// Strip process names from event payloads so user PII never leaves the device.
    private static func scrub(_ event: Event) {
        if var extra = event.extra {
            extra.removeValue(forKey: "process")
            extra.removeValue(forKey: "command")
            extra.removeValue(forKey: "processName")
            event.extra = extra
        }
        if let breadcrumbs = event.breadcrumbs {
            for crumb in breadcrumbs { scrub(crumb) }
        }
    }

    private static func scrub(_ crumb: Breadcrumb) {
        crumb.data?.removeValue(forKey: "process")
        crumb.data?.removeValue(forKey: "command")
        crumb.data?.removeValue(forKey: "processName")
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
