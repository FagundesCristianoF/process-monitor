import Foundation

struct DiskUsageEntry: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let bytes: Int64

    var displayName: String {
        friendlyDisplayName ?? (path as NSString).lastPathComponent
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Maps a scanned folder path to a built-in cleanup command name, if one exists.
    var suggestedCleanupCommandName: String? {
        let lower = path.lowercased()
        if lower.contains("coresimulator/devices") { return "iOS Simulators" }
        if lower.contains("ios devicesupport") { return "Xcode Device Support" }
        if lower.contains("xcode/deriveddata") { return "Xcode DerivedData" }
        if lower.contains("xcode/archives") { return "Scan: Large Build Folders" }
        if lower.contains("org.swift.swiftpm") { return "Swift Package Manager Cache" }
        if lower.contains("/caches/google") || lower.hasSuffix("/google") { return "Chrome Cache" }
        if lower.contains("/caches/jetbrains") { return "JetBrains Caches" }
        if lower.contains("/caches") && !lower.contains("org.swift.swiftpm") { return nil }
        if lower.contains("application support/cursor") { return "Cursor Cache" }
        if lower.contains("application support/google") { return "Android Studio" }
        if lower.contains("application support/claude") { return "Claude VM Bundles" }
        if lower.contains(".gradle/caches") || lower.hasSuffix("/.gradle") { return "Gradle Caches" }
        if lower.contains(".npm") { return "npm cache" }
        if lower.contains(".docker") { return "Docker" }
        if lower.contains("homebrew") || lower.contains("/cache") && lower.contains("brew") { return "Homebrew" }
        return nil
    }

    private var friendlyDisplayName: String? {
        guard let name = suggestedCleanupCommandName else { return nil }
        if name == "iOS Simulators" { return "iOS Simulators" }
        if name == "Xcode Device Support" { return "iOS Device Support" }
        if name == "Xcode DerivedData" { return "DerivedData" }
        if name == "Swift Package Manager Cache" { return "SwiftPM Cache" }
        if name == "Cursor Cache" { return "Cursor" }
        if name == "Android Studio" { return "Android Studio" }
        if name == "Gradle Caches" { return "Gradle" }
        if name == "npm cache" { return "npm" }
        if name == "Docker" { return "Docker" }
        if name == "Homebrew" { return "Homebrew" }
        if name == "Chrome Cache" { return "Google Chrome" }
        if name == "JetBrains Caches" { return "JetBrains" }
        return (path as NSString).lastPathComponent
    }
}
