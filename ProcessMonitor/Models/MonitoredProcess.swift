import Foundation

struct ProcessDefinition: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var displayName: String
    var patterns: [String]
    var defaultLimitMB: Int

    func matches(command: String) -> Bool {
        let lowered = command.lowercased()
        return patterns.contains { lowered.contains($0.lowercased()) }
    }

    var isRestartable: Bool {
        patterns.contains { $0.lowercased().contains(".app") }
    }
}

extension ProcessDefinition {
    static let builtInDefaults: [ProcessDefinition] = [
        ProcessDefinition(
            id: "cursor",
            displayName: "Cursor",
            patterns: ["Cursor.app"],
            defaultLimitMB: 4096
        ),
        ProcessDefinition(
            id: "proxyman",
            displayName: "Proxyman",
            patterns: ["Proxyman.app"],
            defaultLimitMB: 1024
        ),
        ProcessDefinition(
            id: "java",
            displayName: "Java",
            patterns: ["java"],
            defaultLimitMB: 4096
        ),
        ProcessDefinition(
            id: "gradle",
            displayName: "Gradle",
            patterns: ["gradlew", "GradleDaemon", "gradle-launcher"],
            defaultLimitMB: 2048
        ),
        ProcessDefinition(
            id: "vscode",
            displayName: "VS Code",
            patterns: ["Visual Studio Code.app"],
            defaultLimitMB: 4096
        ),
        ProcessDefinition(
            id: "android_studio",
            displayName: "Android Studio",
            patterns: ["Android Studio.app"],
            defaultLimitMB: 6144
        ),
        ProcessDefinition(
            id: "xcode",
            displayName: "Xcode",
            patterns: ["Xcode.app/Contents/MacOS"],
            defaultLimitMB: 8192
        )
    ]
}

enum ProcessStatus: Equatable {
    case notRunning
    case running
    case overLimit
}

struct MonitoredProcess: Identifiable, Equatable {
    let id: String
    let definition: ProcessDefinition
    let status: ProcessStatus
    let rootPids: [pid_t]
    let totalMemoryMB: Double
    let totalSwapMB: Double
    let totalCPU: Double
    let memoryHistory: [Double]
    let cpuHistory: [Double]
    let children: [ProcessChild]
    let memoryLimitMB: Int
    let appBundlePath: String?
    let startedBy: String?

    var formattedMemory: String {
        guard status != .notRunning else { return "--" }
        return formatMemory(totalMemoryMB)
    }

    var formattedSwap: String {
        guard status != .notRunning else { return "--" }
        return formatMemory(totalSwapMB)
    }

    var formattedCPU: String {
        guard status != .notRunning else { return "--" }
        return String(format: "%.0f%%", totalCPU)
    }

    var formattedLimit: String {
        formatMemory(Double(memoryLimitMB))
    }

    /// Whether a manual restart can be performed. True when a bundle path was
    /// resolved from the actual running command — the precondition
    /// `restartGroup` relies on to relaunch via `open`. This is runtime truth,
    /// independent of whether the definition's patterns literally contain
    /// ".app" (a user may monitor a bundle app by a plain name).
    var canRestart: Bool {
        appBundlePath != nil
    }

    var childGroups: [ProcessChildGroup] {
        let grouped = Dictionary(grouping: children, by: \.command)
        return grouped.map { ProcessChildGroup(name: $0.key, children: $0.value) }
            .sorted { $0.totalMemoryMB > $1.totalMemoryMB }
    }
}
