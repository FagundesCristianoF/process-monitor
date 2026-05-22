import SwiftUI

enum ProcessSortOrder: String, CaseIterable {
    case active = "Active"
    case cpu = "CPU"
    case memory = "Memory"
    case added = "Added"

    var icon: String {
        switch self {
        case .active: return "power"
        case .cpu: return "cpu"
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
    @AppStorage("filterWarningsOnly") private var filterWarningsOnly: Bool = false

    private var selectedSort: ProcessSortOrder {
        ProcessSortOrder(rawValue: sortOrder) ?? .active
    }

    private var sortedProcesses: [MonitoredProcess] {
        let processes = monitorService.processes
        let sorted: [MonitoredProcess]
        switch selectedSort {
        case .active:
            sorted = processes.sorted { a, b in
                let aWeight = a.status == .notRunning ? 0 : 1
                let bWeight = b.status == .notRunning ? 0 : 1
                if aWeight != bWeight { return aWeight > bWeight }
                return a.totalMemoryMB > b.totalMemoryMB
            }
        case .cpu:
            sorted = processes.sorted { $0.totalCPU > $1.totalCPU }
        case .memory:
            sorted = processes.sorted { $0.totalMemoryMB > $1.totalMemoryMB }
        case .added:
            sorted = processes
        }
        if filterWarningsOnly {
            return sorted.filter { $0.status == .overLimit }
        }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            sortBar
            Divider().opacity(0.5)
            processList
            Divider().opacity(0.5)
            footer
        }
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Process Monitor")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }

            Spacer()

            HStack(spacing: 2) {
                toolbarButton(
                    icon: configStore.isPaused ? "play.fill" : "pause.fill",
                    tint: configStore.isPaused ? .orange : .secondary,
                    help: configStore.isPaused
                        ? NSLocalizedString("Resume monitoring", comment: "")
                        : NSLocalizedString("Pause monitoring", comment: ""),
                    action: { configStore.isPaused.toggle() }
                )

                toolbarButton(
                    icon: "arrow.clockwise",
                    tint: .secondary,
                    help: NSLocalizedString("Refresh now", comment: ""),
                    disabled: configStore.isPaused,
                    action: { monitorService.refresh() }
                )

                toolbarButton(
                    icon: "gearshape.fill",
                    tint: .secondary,
                    help: NSLocalizedString("Settings", comment: ""),
                    action: {
                        SettingsWindowController.shared.open(
                            configStore: configStore,
                            launchAtLoginStore: launchAtLoginStore
                        )
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toolbarButton(
        icon: String,
        tint: Color,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 22)
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.quaternary.opacity(0.0001))
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(ProcessSortOrder.allCases, id: \.self) { option in
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            sortOrder = option.rawValue
                        }
                    }) {
                        Label(option.rawValue, systemImage: option.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.background.opacity(selectedSort == option ? 0.9 : 0))
                                    .shadow(
                                        color: .black.opacity(selectedSort == option ? 0.08 : 0),
                                        radius: 2,
                                        y: 1
                                    )
                            )
                            .foregroundStyle(selectedSort == option ? Color.primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )

            Spacer()

            Toggle(isOn: $filterWarningsOnly.animation(.easeOut(duration: 0.15))) {
                Label("Warnings only", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(filterWarningsOnly ? .orange : .secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Process List

    private var processList: some View {
        let sorted = sortedProcesses
        return Group {
            if filterWarningsOnly && sorted.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                    Text("No warnings")
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Everything within limits.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
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
                                Divider()
                                    .opacity(0.4)
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formatMemory(monitorService.totalMemoryMB))
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.quaternary.opacity(0.5))
                    )
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
