import Foundation

struct ProcessChild: Identifiable, Equatable {
    let id: pid_t
    let parentPid: pid_t
    let command: String
    let memoryMB: Double
    let swapMB: Double

    var formattedMemory: String {
        formatMemory(memoryMB)
    }

    var formattedSwap: String {
        formatMemory(swapMB)
    }
}

struct ProcessChildGroup: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let children: [ProcessChild]

    var totalMemoryMB: Double { children.reduce(0) { $0 + $1.memoryMB } }
    var totalSwapMB: Double { children.reduce(0) { $0 + $1.swapMB } }
    var pids: [pid_t] { children.map(\.id) }
    var count: Int { children.count }

    var formattedMemory: String { formatMemory(totalMemoryMB) }
    var formattedSwap: String { formatMemory(totalSwapMB) }
}

struct RawProcessEntry {
    let pid: pid_t
    let ppid: pid_t
    let rssKB: Int
    let command: String
}

func formatMemory(_ mb: Double) -> String {
    if mb >= 1024 {
        return String(format: "%.1f GB", mb / 1024)
    }
    return String(format: "%.0f MB", mb)
}
