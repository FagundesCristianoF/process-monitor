import Foundation
import Combine
import Darwin
import os

private let serviceLog = Logger(subsystem: "com.cristianofagundes.ProcessMonitor", category: "monitor")

final class ProcessMonitorService: ObservableObject {
    typealias ProcessEntriesProvider = () -> [RawProcessEntry]
    typealias PollPublisherFactory = (TimeInterval) -> Timer.TimerPublisher

    @Published var processes: [MonitoredProcess] = []
    @Published var totalMemoryMB: Double = 0

    static let historyLength = 60
    static let autoRestartCooldown: TimeInterval = 300 // 5 min between auto-restarts per process
    private var memoryHistory: [String: [Double]] = [:]
    private var cpuHistory: [String: [Double]] = [:]
    private var lastAutoRestartAt: [String: Date] = [:]

    // CPU sampling state for native libproc-based sampling.
    private var previousCPUTotals: [pid_t: UInt64] = [:]
    private var previousSampleTime: TimeInterval = 0

    private var timer: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var configCancellables = Set<AnyCancellable>()
    private let configStore: ProcessConfigStore
    private let notificationService: NotificationService
    private var pollInterval: TimeInterval
    private let processEntriesProvider: ProcessEntriesProvider?
    private let pollPublisherFactory: PollPublisherFactory?

    var isPolling: Bool {
        timer != nil || pollTask != nil
    }

    init(
        configStore: ProcessConfigStore = ProcessConfigStore(),
        notificationService: NotificationService = NotificationService(),
        pollInterval: TimeInterval? = nil,
        processEntriesProvider: ProcessEntriesProvider? = nil,
        pollPublisherFactory: PollPublisherFactory? = nil
    ) {
        self.configStore = configStore
        self.notificationService = notificationService
        self.pollInterval = pollInterval ?? configStore.pollIntervalSeconds
        self.processEntriesProvider = processEntriesProvider
        self.pollPublisherFactory = pollPublisherFactory

        configStore.$pollIntervalSeconds
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] interval in
                self?.applyPollInterval(interval)
            }
            .store(in: &configCancellables)

        configStore.$isPaused
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] paused in
                if paused { self?.stopPolling() } else { self?.startPolling() }
            }
            .store(in: &configCancellables)
    }

    func startPolling() {
        guard !isPolling else { return }
        guard !configStore.isPaused else { return }
        serviceLog.info("Polling started, interval=\(self.pollInterval)s")

        if let factory = pollPublisherFactory {
            // Combine-based path retained for tests/injection.
            refresh()
            timer = factory(pollInterval)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
            return
        }

        let interval = pollInterval
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAsync()
                let ns = UInt64(max(0.1, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        serviceLog.info("Polling stopped")
    }

    private func applyPollInterval(_ interval: TimeInterval) {
        pollInterval = interval
        guard isPolling else { return }
        stopPolling()
        startPolling()
    }

    func refresh() {
        if pollPublisherFactory != nil {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let rawEntries = self.processEntriesProvider?() ?? self.fetchProcessEntries()
                let grouped = self.buildGroupedProcesses(from: rawEntries)
                DispatchQueue.main.async {
                    self.processes = grouped
                    self.totalMemoryMB = grouped.reduce(0) { $0 + $1.totalMemoryMB }
                    self.checkMemoryLimits(grouped)
                }
            }
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            await self?.refreshAsync()
        }
    }

    private func refreshAsync() async {
        let rawEntries = self.processEntriesProvider?() ?? self.fetchProcessEntries()
        let grouped = self.buildGroupedProcesses(from: rawEntries)
        await MainActor.run {
            self.processes = grouped
            self.totalMemoryMB = grouped.reduce(0) { $0 + $1.totalMemoryMB }
            self.checkMemoryLimits(grouped)
        }
    }

    func killProcess(pid: pid_t) {
        killProcesses(pids: [pid])
    }

    func killProcesses(pids: [pid_t]) {
        serviceLog.notice("Killing \(pids.count) pids")
        Telemetry.breadcrumb("kill_processes count=\(pids.count)", category: "action")
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
        // 1. Enumerate PIDs via proc_listpids.
        let initialCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard initialCount > 0 else { return [] }
        // Add some headroom in case new processes appeared between calls.
        let capacity = Int(initialCount) / MemoryLayout<pid_t>.stride + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<pid_t>.stride)
        let written = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, byteCount)
        }
        guard written > 0 else { return [] }
        let actualCount = Int(written) / MemoryLayout<pid_t>.stride

        // 2. Sample wallclock for CPU delta.
        let now = ProcessInfo.processInfo.systemUptime
        let wallDelta = previousSampleTime > 0 ? (now - previousSampleTime) : 0
        let wallDeltaNS = wallDelta * 1_000_000_000
        var newCPUTotals: [pid_t: UInt64] = [:]
        newCPUTotals.reserveCapacity(actualCount)

        var entries: [RawProcessEntry] = []
        entries.reserveCapacity(actualCount)

        let pathBufSize = Int(MAXPATHLEN)
        var pathBuf = [CChar](repeating: 0, count: pathBufSize)

        for i in 0..<actualCount {
            let pid = pids[i]
            if pid <= 0 { continue }

            // BSD info: ppid + comm.
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let bsdResult = withUnsafeMutablePointer(to: &bsd) { ptr -> Int32 in
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, bsdSize)
            }
            guard bsdResult == bsdSize else { continue }

            let ppid = pid_t(bsd.pbi_ppid)

            // Task info: CPU times.
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let taskResult = withUnsafeMutablePointer(to: &task) { ptr -> Int32 in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, taskSize)
            }
            var cpuPercent: Double = 0
            if taskResult == taskSize {
                let total = task.pti_total_user &+ task.pti_total_system
                newCPUTotals[pid] = total
                if wallDeltaNS > 0, let prev = previousCPUTotals[pid], total >= prev {
                    let deltaNS = Double(total - prev)
                    cpuPercent = (deltaNS / wallDeltaNS) * 100.0
                }
            }

            // Executable path.
            var command = ""
            let pathLen = pathBuf.withUnsafeMutableBufferPointer { buf -> Int32 in
                proc_pidpath(pid, buf.baseAddress, UInt32(pathBufSize))
            }
            if pathLen > 0 {
                command = String(cString: pathBuf)
            } else {
                var comm = bsd.pbi_comm
                let commSize = MemoryLayout.size(ofValue: comm)
                command = withUnsafePointer(to: &comm) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: commSize) {
                        String(cString: $0)
                    }
                }
            }

            entries.append(RawProcessEntry(
                pid: pid,
                ppid: ppid,
                rssKB: 0,
                cpuPercent: cpuPercent,
                command: command
            ))
        }

        previousCPUTotals = newCPUTotals
        previousSampleTime = now
        return entries
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

        // Every monitored definition is its own top-level group. We never
        // hide one monitored process under another — Java is still shown as
        // "Java" even when its parent (e.g. Warp) is also monitored. The
        // "Started by …" subtitle and the children list expose the
        // relationship without merging the rows.
        var rootPidsPerDef: [String: [pid_t]] = [:]
        for (pid, def) in pidToDefinition {
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
                pushHistory(memorySample: 0, cpuSample: 0, for: def.id)
                return MonitoredProcess(
                    id: def.id,
                    definition: def,
                    status: .notRunning,
                    rootPids: [],
                    totalMemoryMB: 0,
                    totalSwapMB: 0,
                    totalCPU: 0,
                    memoryHistory: memoryHistory[def.id] ?? [],
                    cpuHistory: cpuHistory[def.id] ?? [],
                    children: [],
                    memoryLimitMB: limit,
                    appBundlePath: nil,
                    startedBy: nil
                )
            }

            let rootEntries = roots.compactMap { pidToEntry[$0] }
            let bundlePath = rootEntries.lazy.compactMap {
                Self.appBundlePath(from: $0.command)
            }.first
            let startedBy = Self.resolveStarter(
                rootEntries: rootEntries,
                pidToEntry: pidToEntry
            )

            let descendants = allDescendants(of: roots)
            let rootSet = Set(roots)
            let uniqueDescendants = descendants.filter { !rootSet.contains($0.pid) }

            var rootMemMB = 0.0
            var rootSwapMB = 0.0
            var rootCPU = 0.0
            for entry in rootEntries {
                let usage = processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB)
                rootMemMB += usage.footprintMB
                rootSwapMB += usage.swapMB
                rootCPU += entry.cpuPercent
            }

            var childMemMB = 0.0
            var childSwapMB = 0.0
            var childCPU = 0.0
            var childItems: [ProcessChild] = []
            for entry in uniqueDescendants {
                let usage = processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB)
                childMemMB += usage.footprintMB
                childSwapMB += usage.swapMB
                childCPU += entry.cpuPercent
                if usage.footprintMB > 1 {
                    let baseName = URL(fileURLWithPath: entry.command).lastPathComponent
                    childItems.append(ProcessChild(
                        id: entry.pid,
                        parentPid: entry.ppid,
                        command: baseName,
                        memoryMB: usage.footprintMB,
                        swapMB: usage.swapMB,
                        cpuPercent: entry.cpuPercent
                    ))
                }
            }
            childItems.sort { $0.memoryMB > $1.memoryMB }

            let totalMB = rootMemMB + childMemMB
            let totalSwapMB = rootSwapMB + childSwapMB
            let totalCPU = rootCPU + childCPU
            let status: ProcessStatus = totalMB > Double(limit) ? .overLimit : .running

            pushHistory(memorySample: totalMB, cpuSample: totalCPU, for: def.id)

            return MonitoredProcess(
                id: def.id,
                definition: def,
                status: status,
                rootPids: roots,
                totalMemoryMB: totalMB,
                totalSwapMB: totalSwapMB,
                totalCPU: totalCPU,
                memoryHistory: memoryHistory[def.id] ?? [],
                cpuHistory: cpuHistory[def.id] ?? [],
                children: childItems,
                memoryLimitMB: limit,
                appBundlePath: bundlePath,
                startedBy: startedBy
            )
        }
    }

    /// Find a human-friendly name for what spawned this process.
    /// Walks up the ppid chain skipping shell wrappers until it hits
    /// a meaningful command, then returns its basename. Returns nil if
    /// the parent is launchd/init (pid 1) or unknown.
    private static func resolveStarter(
        rootEntries: [RawProcessEntry],
        pidToEntry: [pid_t: RawProcessEntry]
    ) -> String? {
        let shellWrappers: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh", "env", "xargs"]
        for rootEntry in rootEntries {
            var current = rootEntry.ppid
            var hops = 0
            while current > 1, hops < 12 {
                guard let parent = pidToEntry[current] else { break }
                let baseName = (parent.command as NSString).lastPathComponent
                if !shellWrappers.contains(baseName.lowercased()) {
                    return Self.friendlyStarterName(from: parent.command)
                }
                current = parent.ppid
                hops += 1
            }
        }
        return nil
    }

    /// Convert a raw command path into a user-friendly app name.
    /// e.g. "/Applications/Cursor.app/Contents/MacOS/Cursor" -> "Cursor"
    static func friendlyStarterName(from command: String) -> String {
        if let appPath = Self.appBundlePath(from: command) {
            return (appPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
        }
        return (command as NSString).lastPathComponent
    }

    private func pushHistory(memorySample: Double, cpuSample: Double, for id: String) {
        var mem = memoryHistory[id] ?? []
        mem.append(memorySample)
        if mem.count > Self.historyLength { mem.removeFirst(mem.count - Self.historyLength) }
        memoryHistory[id] = mem

        var cpu = cpuHistory[id] ?? []
        cpu.append(cpuSample)
        if cpu.count > Self.historyLength { cpu.removeFirst(cpu.count - Self.historyLength) }
        cpuHistory[id] = cpu
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
        let now = Date()
        for process in processes where process.status == .overLimit {
            notificationService.notifyIfNeeded(
                processName: process.definition.displayName,
                memoryMB: process.totalMemoryMB,
                limitMB: process.memoryLimitMB
            )

            // Auto-restart check
            guard let autoLimit = configStore.autoRestartLimit(for: process.definition.id),
                  process.totalMemoryMB > Double(autoLimit),
                  process.appBundlePath != nil
            else { continue }

            let last = lastAutoRestartAt[process.definition.id]
            if let last, now.timeIntervalSince(last) < Self.autoRestartCooldown {
                continue
            }
            lastAutoRestartAt[process.definition.id] = now
            serviceLog.notice("Auto-restart: \(process.definition.displayName) at \(process.totalMemoryMB)MB exceeds limit \(autoLimit)MB")
            Telemetry.breadcrumb("auto_restart \(process.definition.id) mem=\(Int(process.totalMemoryMB))MB limit=\(autoLimit)MB", category: "auto_restart")
            notificationService.notifyAutoRestart(
                processName: process.definition.displayName,
                memoryMB: process.totalMemoryMB,
                limitMB: autoLimit
            )
            DispatchQueue.main.async { [weak self] in
                self?.restartGroup(process)
            }
        }
    }
}
