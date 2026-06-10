import Foundation

struct ProcessChild: Identifiable, Equatable {
    let id: pid_t
    let parentPid: pid_t
    let command: String
    let memoryMB: Double
    let swapMB: Double
    let cpuPercent: Double

    var formattedMemory: String {
        formatMemory(memoryMB)
    }

    var formattedSwap: String {
        formatMemory(swapMB)
    }

    var formattedCPU: String {
        String(format: "%.0f%%", cpuPercent)
    }
}

struct ProcessChildGroup: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let children: [ProcessChild]

    var totalMemoryMB: Double { children.reduce(0) { $0 + $1.memoryMB } }
    var totalSwapMB: Double { children.reduce(0) { $0 + $1.swapMB } }
    var totalCPU: Double { children.reduce(0) { $0 + $1.cpuPercent } }
    var pids: [pid_t] { children.map(\.id) }
    var count: Int { children.count }

    var formattedMemory: String { formatMemory(totalMemoryMB) }
    var formattedSwap: String { formatMemory(totalSwapMB) }
    var formattedCPU: String { String(format: "%.0f%%", totalCPU) }
}

struct RawProcessEntry {
    let pid: pid_t
    let ppid: pid_t
    let rssKB: Int
    let cpuPercent: Double
    let command: String
}

func formatMemory(_ mb: Double) -> String {
    if mb >= 1024 {
        return String(format: "%.1f GB", mb / 1024)
    }
    return String(format: "%.0f MB", mb)
}

func formatDiskGB(_ gb: Double) -> String {
    if gb >= 1000 {
        return String(format: "%.1f TB", gb / 1000)
    }
    return String(format: "%.1f GB", gb)
}
