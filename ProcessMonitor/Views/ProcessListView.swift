import SwiftUI

enum ProcessSortOrder: String, CaseIterable {
    case active = "Active"
    case memory = "Memory"
    case added = "Added"

    var icon: String {
        switch self {
        case .active: return "power"
        case .memory: return "memorychip"
        case .added: return "list.number"
        }
    }
}

struct ProcessListView: View {
    @ObservedObject var monitorService: ProcessMonitorService
    @ObservedObject var configStore: ProcessConfigStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @AppStorage("processSortOrder") private var sortOrder: String = ProcessSortOrder.active.rawValue

    private var selectedSort: ProcessSortOrder {
        ProcessSortOrder(rawValue: sortOrder) ?? .active
    }

    private var sortedProcesses: [MonitoredProcess] {
        let processes = monitorService.processes
        switch selectedSort {
        case .active:
            return processes.sorted { a, b in
                let aWeight = a.status == .notRunning ? 0 : 1
                let bWeight = b.status == .notRunning ? 0 : 1
                if aWeight != bWeight { return aWeight > bWeight }
                return a.totalMemoryMB > b.totalMemoryMB
            }
        case .memory:
            return processes.sorted { $0.totalMemoryMB > $1.totalMemoryMB }
        case .added:
            return processes
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sortBar
            Divider()
            processList
            Divider()
            footer
        }
        .onAppear { monitorService.startPolling() }
        .onDisappear { monitorService.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Process Monitor", systemImage: "cpu")
                .font(.headline)

            Spacer()

            Button(action: { monitorService.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            Button(action: {
                SettingsWindowController.shared.open(
                    configStore: configStore,
                    launchAtLoginStore: launchAtLoginStore
                )
            }) {
                Image(systemName: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 2) {
            ForEach(ProcessSortOrder.allCases, id: \.self) { option in
                Button(action: { sortOrder = option.rawValue }) {
                    Label(option.rawValue, systemImage: option.icon)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedSort == option ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedSort == option ? Color.accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Process List

    private var processList: some View {
        let sorted = sortedProcesses
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sorted) { process in
                    ProcessRowView(
                        process: process,
                        onKillGroup: { monitorService.killGroup(process) },
                        onRestart: { monitorService.restartGroup(process) },
                        onKillChildGroup: { pids in monitorService.killProcesses(pids: pids) },
                        onKillChild: { pid in monitorService.killProcess(pid: pid) }
                    )
                    if process.id != sorted.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Total: \(formatMemory(monitorService.totalMemoryMB))")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
