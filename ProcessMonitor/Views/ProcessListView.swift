import SwiftUI
import AppKit

private struct WindowOpaqueAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            applyOpaque(to: v.window)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyOpaque(to: nsView.window)
        }
    }

    private func applyOpaque(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            disableVibrancy(in: contentView)
        }
    }

    /// Recursively neutralize any NSVisualEffectView so the window no longer
    /// pulls vibrancy from the desktop behind it.
    private func disableVibrancy(in view: NSView) {
        if let visual = view as? NSVisualEffectView {
            visual.material = .windowBackground
            visual.blendingMode = .behindWindow
            visual.state = .inactive
            // Do NOT hide the view — hiding it can leave the popover window
            // with nothing to render on subsequent shows, intermittently
            // breaking menu bar clicks.
        }
        for sub in view.subviews {
            disableVibrancy(in: sub)
        }
    }
}

// MARK: - Disk Volume Row

private struct DiskVolumeRow: View {
    let status: DiskVolumeStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.isWarning ? .orange : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.volume.displayName)
                    .font(.system(.caption, weight: .medium))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor)
                            .frame(width: geo.size.width * usedFraction, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: NSLocalizedString("%@ free", comment: "Disk free space label. %@ = formatted size"), formatDiskGB(status.freeGB)))
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(status.isWarning ? .orange : .primary)
                    .monospacedDigit()
                Text(formatDiskGB(status.totalGB))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if status.isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var usedFraction: Double {
        guard status.totalGB > 0 else { return 0 }
        return min(1, status.usedGB / status.totalGB)
    }

    private var barColor: Color {
        let used = usedFraction
        if used > 0.9 { return .red }
        if used > 0.8 { return .orange }
        return Color.accentColor
    }
}

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

    var localizedLabel: String {
        NSLocalizedString(self.rawValue, comment: "Sort option")
    }
}

struct ProcessListView: View {
    @ObservedObject var monitorService: ProcessMonitorService
    @ObservedObject var diskMonitorService: DiskMonitorService
    @ObservedObject var configStore: ProcessConfigStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @ObservedObject var cleanupStore: CleanupStore
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
            if !diskMonitorService.statuses.isEmpty {
                Divider().opacity(0.5)
                diskSection
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowOpaqueAccessor())
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
                            launchAtLoginStore: launchAtLoginStore,
                            diskMonitorService: diskMonitorService,
                            cleanupStore: cleanupStore
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
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(ProcessSortOrder.allCases, id: \.self) { option in
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            sortOrder = option.rawValue
                        }
                    }) {
                        Label(option.localizedLabel, systemImage: option.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
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

            Toggle(isOn: $filterWarningsOnly.animation(.easeOut(duration: 0.15))) {
                Label("Warnings only", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(filterWarningsOnly ? .orange : .secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(maxWidth: .infinity, alignment: .trailing)
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

    // MARK: - Disk Section

    private var diskSection: some View {
        VStack(spacing: 0) {
            ForEach(diskMonitorService.statuses) { status in
                DiskVolumeRow(status: status)
                if status.id != diskMonitorService.statuses.last?.id {
                    Divider().opacity(0.4).padding(.horizontal, 14)
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

            Text("v\(AppInfo.version)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .help(AppInfo.displayVersion)

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
