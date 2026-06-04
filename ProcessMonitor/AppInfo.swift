import Foundation

/// Single source of truth for app identity: version metadata and the
/// destination links surfaced in the UI (bug report, repository).
enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/FagundesCristianoF/process-monitor")!
    private static let newIssueURLString = "https://github.com/FagundesCristianoF/process-monitor/issues/new"

    /// Marketing version, e.g. "1.3.1". Falls back to an em dash when the
    /// Info.plist key is unavailable (e.g. running outside the .app bundle).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Build number, e.g. "5".
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// User-facing version string, e.g. "1.3.1 (5)".
    static var displayVersion: String {
        displayVersion(version: version, build: build)
    }

    static func displayVersion(version: String, build: String) -> String {
        "\(version) (\(build))"
    }

    /// GitHub "new issue" URL with the body prefilled with diagnostics so bug
    /// reports arrive with the app and OS versions already attached.
    static var bugReportURL: URL {
        bugReportURL(
            version: version,
            build: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    static func bugReportURL(version: String, build: String, osVersion: String) -> URL {
        let body = """
        **Version:** \(version) (\(build))
        **macOS:** \(osVersion)

        **Describe the bug:**

        """
        var components = URLComponents(string: newIssueURLString)!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }
}
