import Foundation
import Combine
import Darwin

final class ProcessMonitorService: ObservableObject {
    @Published var processes: [MonitoredProcess] = []
    @Published var totalMemoryMB: Double = 0

    private var timer: AnyCancellable?
    private let configStore: ProcessConfigStore
    private let notificationService: NotificationService
    private let pollInterval: TimeInterval

    init(
        configStore: ProcessConfigStore = ProcessConfigStore(),
        notificationService: NotificationService = NotificationService(),
        pollInterval: TimeInterval = 5
    ) {
        self.configStore = configStore
        self.notificationService = notificationService
        self.pollInterval = pollInterval
    }

    func startPolling() {
        refresh()
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rawEntries = self.fetchProcessEntries()
            let grouped = self.buildGroupedProcesses(from: rawEntries)
            DispatchQueue.main.async {
                self.processes = grouped
                self.totalMemoryMB = grouped.reduce(0) { $0 + $1.totalMemoryMB }
                self.checkMemoryLimits(grouped)
            }
        }
    }

    func killProcess(pid: pid_t) {
        killProcesses(pids: [pid])
    }

    func killProcesses(pids: [pid_t]) {
        for pid in pids {
            kill(pid, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            for pid in pids {
                kill(pid, SIGKILL)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    func killGroup(_ process: MonitoredProcess) {
        let allPids = process.children.map(\.id) + process.rootPids

        for pid in allPids {
            kill(pid, SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            for pid in allPids {
                kill(pid, SIGKILL)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    func restartGroup(_ process: MonitoredProcess) {
        guard let bundlePath = process.appBundlePath else { return }

        let allPids = process.children.map(\.id) + process.rootPids
        for pid in allPids {
            kill(pid, SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            for pid in allPids {
                kill(pid, SIGKILL)
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [bundlePath]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.refresh()
            }
        }
    }

    // MARK: - Private

    private func fetchProcessEntries() -> [RawProcessEntry] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,ppid,rss,comm"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .components(separatedBy: "\n")
            .dropFirst() // header
            .compactMap { parseLine($0) }
    }

    private func parseLine(_ line: String) -> RawProcessEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(
            separator: " ",
            maxSplits: 3,
            omittingEmptySubsequences: true
        )
        guard parts.count >= 4,
              let pid = pid_t(parts[0]),
              let ppid = pid_t(parts[1]),
              let rss = Int(parts[2])
        else { return nil }

        let command = String(parts[3])
        return RawProcessEntry(pid: pid, ppid: ppid, rssKB: rss, command: command)
    }

    private func buildGroupedProcesses(from entries: [RawProcessEntry]) -> [MonitoredProcess] {
        let pidToEntry = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) })
        let childrenMap = Dictionary(grouping: entries, by: \.ppid)
        let monitoredDefinitions = configStore.definitions

        var pidToDefinition: [pid_t: ProcessDefinition] = [:]
        for entry in entries {
            for def in monitoredDefinitions where def.matches(command: entry.command) {
                pidToDefinition[entry.pid] = def
            }
        }

        // Walk ancestor chain to group children under their parent definition
        var claimedByParent: [pid_t: ProcessDefinition] = [:]
        for (pid, def) in pidToDefinition {
            var current = pid
            while let entry = pidToEntry[current] {
                let parent = entry.ppid
                if parent == current || parent <= 1 { break }
                if let parentDef = pidToDefinition[parent], parentDef.id != def.id {
                    claimedByParent[pid] = parentDef
                    break
                }
                current = parent
            }
        }

        var rootPidsPerDef: [String: [pid_t]] = [:]
        for (pid, def) in pidToDefinition where claimedByParent[pid] == nil {
            rootPidsPerDef[def.id, default: []].append(pid)
        }

        func allDescendants(of roots: [pid_t]) -> [RawProcessEntry] {
            var result: [RawProcessEntry] = []
            var visited = Set(roots)
            var queue = roots
            while !queue.isEmpty {
                let current = queue.removeFirst()
                if let children = childrenMap[current] {
                    for child in children where !visited.contains(child.pid) {
                        visited.insert(child.pid)
                        result.append(child)
                        queue.append(child.pid)
                    }
                }
            }
            return result
        }

        return monitoredDefinitions.map { def in
            let limit = configStore.limit(for: def.id)
            guard let roots = rootPidsPerDef[def.id], !roots.isEmpty else {
                return MonitoredProcess(
                    id: def.id,
                    definition: def,
                    status: .notRunning,
                    rootPids: [],
                    totalMemoryMB: 0,
                    totalSwapMB: 0,
                    children: [],
                    memoryLimitMB: limit,
                    appBundlePath: nil
                )
            }

            let rootEntries = roots.compactMap { pidToEntry[$0] }
            let bundlePath = rootEntries.lazy.compactMap {
                Self.appBundlePath(from: $0.command)
            }.first

            let descendants = allDescendants(of: roots)
            let rootSet = Set(roots)
            let uniqueDescendants = descendants.filter { !rootSet.contains($0.pid) }

            var rootMemMB = 0.0
            var rootSwapMB = 0.0
            for entry in rootEntries {
                let usage = processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB)
                rootMemMB += usage.footprintMB
                rootSwapMB += usage.swapMB
            }

            var childMemMB = 0.0
            var childSwapMB = 0.0
            var childItems: [ProcessChild] = []
            for entry in uniqueDescendants {
                let usage = processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB)
                childMemMB += usage.footprintMB
                childSwapMB += usage.swapMB
                if usage.footprintMB > 1 {
                    let baseName = URL(fileURLWithPath: entry.command).lastPathComponent
                    childItems.append(ProcessChild(
                        id: entry.pid,
                        parentPid: entry.ppid,
                        command: baseName,
                        memoryMB: usage.footprintMB,
                        swapMB: usage.swapMB
                    ))
                }
            }
            childItems.sort { $0.memoryMB > $1.memoryMB }

            let totalMB = rootMemMB + childMemMB
            let totalSwapMB = rootSwapMB + childSwapMB
            let status: ProcessStatus = totalMB > Double(limit) ? .overLimit : .running

            return MonitoredProcess(
                id: def.id,
                definition: def,
                status: status,
                rootPids: roots,
                totalMemoryMB: totalMB,
                totalSwapMB: totalSwapMB,
                children: childItems,
                memoryLimitMB: limit,
                appBundlePath: bundlePath
            )
        }
    }

    struct MemoryUsage {
        let footprintMB: Double
        let swapMB: Double
    }

    /// Physical memory footprint (same metric as Activity Monitor) and estimated swap.
    /// Swap is approximated as max(0, footprint - RSS): the portion of the
    /// footprint backed by compressed or swapped-out pages rather than
    /// plain resident pages.
    private func processMemoryUsage(for pid: pid_t, fallbackRssKB: Int) -> MemoryUsage {
        var usage = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &usage) { usagePtr in
            usagePtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { bufferPtr in
                proc_pid_rusage(pid, Int32(RUSAGE_INFO_V4), bufferPtr)
            }
        }
        if result == 0 {
            let footprintMB = Double(usage.ri_phys_footprint) / (1024.0 * 1024.0)
            let rssMB = Double(fallbackRssKB) / 1024.0
            let swapMB = max(0, footprintMB - rssMB)
            return MemoryUsage(footprintMB: footprintMB, swapMB: swapMB)
        }
        let rssMB = Double(fallbackRssKB) / 1024.0
        return MemoryUsage(footprintMB: rssMB, swapMB: 0)
    }

    static func appBundlePath(from command: String) -> String? {
        guard let range = command.range(of: ".app", options: .caseInsensitive) else { return nil }
        return String(command[command.startIndex..<range.upperBound])
    }

    private func checkMemoryLimits(_ processes: [MonitoredProcess]) {
        for process in processes where process.status == .overLimit {
            notificationService.notifyIfNeeded(
                processName: process.definition.displayName,
                memoryMB: process.totalMemoryMB,
                limitMB: process.memoryLimitMB
            )
        }
    }
}
