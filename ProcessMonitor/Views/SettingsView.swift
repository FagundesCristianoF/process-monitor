import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case processes, disk, preferences, privacy, about

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .processes:  return NSLocalizedString("Processes", comment: "")
        case .disk:       return NSLocalizedString("Disk", comment: "")
        case .preferences:return NSLocalizedString("Preferences", comment: "")
        case .privacy:    return NSLocalizedString("Privacy", comment: "")
        case .about:      return NSLocalizedString("About", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .processes:   return "list.bullet.rectangle.fill"
        case .disk:        return "internaldrive.fill"
        case .preferences: return "gearshape.fill"
        case .privacy:     return "lock.shield.fill"
        case .about:       return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .processes:   return Color(red: 0.20, green: 0.47, blue: 0.97)
        case .disk:        return Color(red: 0.94, green: 0.58, blue: 0.14)
        case .preferences: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .privacy:     return Color(red: 0.13, green: 0.78, blue: 0.40)
        case .about:       return Color(red: 0.56, green: 0.36, blue: 0.97)
        }
    }
}

// MARK: - Reusable Style Components

struct SettingsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            configuration.title
                .font(.system(.callout))
        }
    }
}

private struct SidebarItemView: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tab.iconColor.gradient)
                        .frame(width: 28, height: 28)
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.monochrome)
                }
                Text(tab.localizedLabel)
                    .font(.system(.callout))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct DetailHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

private let supportedLanguages: [(id: String, label: String)] = [
    ("system",  "System default"),
    ("en",      "English"),
    ("pt-BR",   "Português (Brasil)"),
    ("es",      "Español"),
    ("fr",      "Français"),
    ("de",      "Deutsch"),
]

struct SettingsView: View {
    @ObservedObject var configStore: ProcessConfigStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @ObservedObject var diskMonitorService: DiskMonitorService

    @State private var selectedTab: SettingsTab = .processes
    @State private var showAddForm = false
    @State private var showAddDiskForm = false
    @State private var showRestartAlert = false
    @State private var pollIntervalDraft: Double = ProcessConfigStore.defaultPollInterval
    @State private var notifAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(minWidth: 680, idealWidth: 700, minHeight: 460)
        .onAppear {
            pollIntervalDraft = configStore.pollIntervalSeconds
            refreshNotifStatus()
        }
        .sheet(isPresented: $showAddForm) {
            AddProcessView { configStore.addDefinition($0) }
        }
        .sheet(isPresented: $showAddDiskForm) {
            AddDiskVolumeView { configStore.addDiskVolume($0) }
        }
        .alert("Restart required", isPresented: $showRestartAlert, actions: {
            Button("Restart now", role: .destructive) { Self.relaunch() }
            Button("Later", role: .cancel) {}
        }, message: {
            Text("Process Monitor needs to restart to apply the new language.")
        })
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SidebarItemView(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.easeOut(duration: 0.12)) { selectedTab = tab }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(minWidth: 190, idealWidth: 190, maxWidth: 190)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedTab {
                case .processes:   processesDetail
                case .disk:        diskDetail
                case .preferences: preferencesDetail
                case .privacy:     privacyDetail
                case .about:       aboutDetail
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .id(selectedTab)
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Processes Detail

    private var processesDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(
                title: NSLocalizedString("Monitored Processes", comment: ""),
                trailing: AnyView(addButton { showAddForm = true })
            )

            if configStore.definitions.isEmpty {
                emptyState(
                    icon: "list.bullet.rectangle",
                    message: "No processes monitored.",
                    detail: "Tap + to add a process."
                )
            } else {
                DetailCard {
                    ForEach(configStore.definitions) { def in
                        DefinitionRow(
                            definition: def,
                            currentLimit: configStore.limit(for: def.id),
                            autoRestartLimit: configStore.autoRestartLimit(for: def.id),
                            onLimitChanged: { configStore.setLimit($0, for: def.id) },
                            onAutoRestartChanged: { configStore.setAutoRestartLimit($0, for: def.id) },
                            onRemove: { configStore.removeDefinition(id: def.id) }
                        )
                        if def.id != configStore.definitions.last?.id {
                            Divider().opacity(0.4).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Disk Detail

    private var diskDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(
                title: NSLocalizedString("Disk Monitoring", comment: ""),
                trailing: AnyView(addButton { showAddDiskForm = true })
            )

            if configStore.diskVolumes.isEmpty {
                emptyState(
                    icon: "internaldrive",
                    message: "No volumes monitored.",
                    detail: "Tap + to add a volume."
                )
            } else {
                DetailCard {
                    ForEach(configStore.diskVolumes) { volume in
                        DiskVolumeSettingsRow(
                            volume: volume,
                            onUpdate: { configStore.updateDiskVolume($0) },
                            onRemove: { configStore.removeDiskVolume(id: volume.id) }
                        )
                        if volume.id != configStore.diskVolumes.last?.id {
                            Divider().opacity(0.4).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preferences Detail

    private var preferencesDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(title: NSLocalizedString("Preferences", comment: ""))

            DetailCard {
                settingsRow {
                    HStack {
                        Label("Language", systemImage: "globe")
                            .labelStyle(SettingsLabelStyle())
                        Spacer()
                        Picker("", selection: languageBinding) {
                            ForEach(supportedLanguages, id: \.id) { lang in
                                Text(lang.label).tag(lang.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                Divider().opacity(0.4).padding(.horizontal, 14)
                settingsRow {
                    HStack {
                        Label("Launch at login", systemImage: "power.circle")
                            .labelStyle(SettingsLabelStyle())
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { launchAtLoginStore.isEnabled },
                            set: { launchAtLoginStore.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                if let statusMessage = launchAtLoginStore.statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                Divider().opacity(0.4).padding(.horizontal, 14)
                settingsRow {
                    HStack {
                        Label(NSLocalizedString("Notifications", comment: ""), systemImage: "bell.badge")
                            .labelStyle(SettingsLabelStyle())
                        Spacer()
                        notifStatusBadge
                        Button(NSLocalizedString("Open Settings", comment: "")) {
                            openNotificationSettings()
                        }
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.4).padding(.horizontal, 14)
                settingsRow {
                    HStack(spacing: 12) {
                        Label("Refresh every", systemImage: "clock.arrow.circlepath")
                            .labelStyle(SettingsLabelStyle())
                            .layoutPriority(1)
                        Slider(
                            value: $pollIntervalDraft,
                            in: ProcessConfigStore.minPollInterval...ProcessConfigStore.maxPollInterval,
                            step: 1
                        ) { editing in
                            if !editing { configStore.pollIntervalSeconds = pollIntervalDraft }
                        }
                        Text("\(Int(pollIntervalDraft))s")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Privacy Detail

    private var privacyDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(title: NSLocalizedString("Privacy", comment: ""))

            DetailCard {
                settingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Send crash reports & diagnostics", systemImage: "ladybug")
                                .labelStyle(SettingsLabelStyle())
                            Spacer()
                            Toggle("", isOn: $configStore.telemetryEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        Text("Anonymous crash/error reports help fix bugs. Process names are stripped before sending.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 22)
                    }
                }
                Divider().opacity(0.4).padding(.horizontal, 14)
                settingsRow {
                    HStack {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise.circle")
                            .labelStyle(SettingsLabelStyle())
                        Spacer()
                        Button(action: { configStore.resetToDefaults() }) {
                            Text("Reset")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.quaternary.opacity(0.6)))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - About Detail

    private var aboutDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(title: NSLocalizedString("About", comment: ""))

            HStack(spacing: 16) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Process Monitor")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Text(String(
                        format: NSLocalizedString("Version %@", comment: ""),
                        AppInfo.displayVersion
                    ))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            .padding(.bottom, 4)

            DetailCard {
                settingsRow {
                    HStack(spacing: 8) {
                        Link(destination: AppInfo.bugReportURL) {
                            Label(NSLocalizedString("Report a bug", comment: ""), systemImage: "ladybug")
                                .font(.system(.callout, design: .rounded, weight: .medium))
                        }
                        Spacer()
                        Link(destination: AppInfo.repositoryURL) {
                            Label(NSLocalizedString("View on GitHub", comment: ""), systemImage: "arrow.up.right.square")
                                .font(.system(.callout, design: .rounded, weight: .medium))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .foregroundStyle(.white)
            .shadow(color: .accentColor.opacity(0.3), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func emptyState(icon: String, message: String, detail: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }

    private func settingsRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var notifStatusBadge: some View {
        switch notifAuthStatus {
        case .authorized, .provisional:
            Label(NSLocalizedString("Allowed", comment: ""), systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .denied:
            Label(NSLocalizedString("Denied", comment: ""), systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        default:
            Label(NSLocalizedString("Not set", comment: ""), systemImage: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    private func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notifAuthStatus = settings.authorizationStatus }
        }
    }

    private func openNotificationSettings() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Enable Notifications", comment: "")
        alert.informativeText = NSLocalizedString(
            "Process Monitor needs notification permission to alert you about memory and disk usage. You can enable it in System Settings → Notifications → Process Monitor.",
            comment: ""
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { configStore.preferredLanguage ?? "system" },
            set: { newValue in
                let newCode = newValue == "system" ? nil : newValue
                guard newCode != configStore.preferredLanguage else { return }
                configStore.preferredLanguage = newCode
                showRestartAlert = true
            }
        )
    }

    private static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}

// MARK: - Definition Row

private struct DefinitionRow: View {
    let definition: ProcessDefinition
    let currentLimit: Int
    let autoRestartLimit: Int?
    let onLimitChanged: (Int) -> Void
    let onAutoRestartChanged: (Int?) -> Void
    let onRemove: () -> Void

    @State private var showConfirmRemove = false
    @State private var limitMB: Double = 0
    @State private var autoRestartEnabled: Bool = false
    @State private var autoRestartMB: Double = 0

    private static let minMB: Double = 64
    private static let maxMB: Double = 32768
    private static let stepMB: Double = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBadge(definition: definition, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.displayName)
                        .font(.system(.callout, weight: .semibold))
                    Text(definition.patterns.joined(separator: " · "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(formatMemory(Double(currentLimit)))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                    .foregroundStyle(.secondary)

                Button(action: { showConfirmRemove = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Remove from monitoring")
                .alert(
                    String(format: NSLocalizedString("Remove %@?", comment: ""), definition.displayName),
                    isPresented: $showConfirmRemove,
                    actions: {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive, action: onRemove)
                    },
                    message: { Text("This process will no longer be monitored.") }
                )
            }

            VStack(spacing: 6) {
                limitSliderRow(
                    iconColor: .orange,
                    icon: "exclamationmark.triangle.fill",
                    label: NSLocalizedString("Warn at", comment: ""),
                    value: $limitMB,
                    onChange: { onLimitChanged(Int($0)) }
                )

                if definition.isRestartable {
                    HStack(spacing: 8) {
                        Label(NSLocalizedString("Auto-restart", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(SettingsLabelStyle())
                            .font(.caption)
                        Spacer()
                        if autoRestartEnabled {
                            Text(formatMemory(autoRestartMB))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.red.opacity(0.12)))
                                .foregroundStyle(.red)
                        }
                        Toggle("", isOn: $autoRestartEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: autoRestartEnabled) { enabled in
                                if enabled {
                                    if autoRestartMB < limitMB { autoRestartMB = min(Self.maxMB, limitMB * 1.5) }
                                    onAutoRestartChanged(Int(autoRestartMB))
                                } else {
                                    onAutoRestartChanged(nil)
                                }
                            }
                    }

                    if autoRestartEnabled {
                        limitSliderRow(
                            iconColor: .red,
                            icon: "arrow.triangle.2.circlepath",
                            label: NSLocalizedString("Restart at", comment: ""),
                            value: $autoRestartMB,
                            onChange: { onAutoRestartChanged(Int($0)) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: autoRestartEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear {
            limitMB = Double(currentLimit)
            if let auto = autoRestartLimit {
                autoRestartEnabled = true
                autoRestartMB = Double(auto)
            } else {
                autoRestartMB = Double(currentLimit) * 1.5
            }
        }
    }

    private func limitSliderRow(
        iconColor: Color,
        icon: String,
        label: String,
        value: Binding<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: Self.minMB...Self.maxMB, step: Self.stepMB) { editing in
                if !editing { onChange(value.wrappedValue) }
            }
            .controlSize(.small)
            Stepper("", value: value, in: Self.minMB...Self.maxMB, step: Self.stepMB)
                .labelsHidden()
                .controlSize(.mini)
                .onChange(of: value.wrappedValue) { newValue in onChange(newValue) }
        }
    }
}

// MARK: - Disk Volume Settings Row

private struct DiskVolumeSettingsRow: View {
    let volume: DiskVolume
    let onUpdate: (DiskVolume) -> Void
    let onRemove: () -> Void

    @State private var showConfirmRemove = false
    @State private var thresholdPercent: Double = 10
    @State private var thresholdGB: Double = 5
    @State private var percentEnabled: Bool = true
    @State private var gbEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.displayName)
                        .font(.system(.callout, weight: .semibold))
                    Text(volume.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: { showConfirmRemove = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("Remove volume", comment: ""))
                .alert(
                    String(format: NSLocalizedString("Remove %@?", comment: ""), volume.displayName),
                    isPresented: $showConfirmRemove,
                    actions: {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive, action: onRemove)
                    },
                    message: { Text(NSLocalizedString("This volume will no longer be monitored.", comment: "")) }
                )
            }

            thresholdRow(
                enabled: $percentEnabled,
                icon: "percent",
                label: NSLocalizedString("Warn below", comment: ""),
                value: $thresholdPercent,
                range: 1...50,
                step: 1,
                format: { "\(Int($0))%" },
                onToggle: { commitUpdate() },
                onChange: { commitUpdate() }
            )

            thresholdRow(
                enabled: $gbEnabled,
                icon: "internaldrive",
                label: NSLocalizedString("Warn below", comment: ""),
                value: $thresholdGB,
                range: 1...500,
                step: 1,
                format: { formatDiskGB($0) },
                onToggle: { commitUpdate() },
                onChange: { commitUpdate() }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear {
            thresholdPercent = volume.thresholdPercent ?? 10
            thresholdGB = volume.thresholdGB ?? 5
            percentEnabled = volume.thresholdPercent != nil
            gbEnabled = volume.thresholdGB != nil
        }
    }

    private func thresholdRow(
        enabled: Binding<Bool>,
        icon: String,
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        onToggle: @escaping () -> Void,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: enabled.wrappedValue) { _ in onToggle() }
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in
                if !editing, enabled.wrappedValue { onChange() }
            }
            .controlSize(.small)
            .disabled(!enabled.wrappedValue)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.mini)
                .disabled(!enabled.wrappedValue)
                .onChange(of: value.wrappedValue) { _ in if enabled.wrappedValue { onChange() } }
            Text(format(value.wrappedValue))
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(enabled.wrappedValue ? .primary : .tertiary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func commitUpdate() {
        var updated = volume
        updated.thresholdPercent = percentEnabled ? thresholdPercent : nil
        updated.thresholdGB = gbEnabled ? thresholdGB : nil
        onUpdate(updated)
    }
}

// MARK: - Add Disk Volume View

private struct AddDiskVolumeView: View {
    let onAdd: (DiskVolume) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String = "/"
    @State private var displayName: String = ""
    @State private var thresholdPercent: Double = 10
    @State private var thresholdGB: Double = 5
    @State private var percentEnabled: Bool = true
    @State private var gbEnabled: Bool = true

    private var mountedVolumes: [(path: String, name: String)] {
        let fm = FileManager.default
        let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsLocalKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true
            else { return nil }
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            return (path: url.path, name: name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(NSLocalizedString("Add Volume", comment: ""))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("Volume", comment: ""), systemImage: "internaldrive")
                        .labelStyle(SettingsLabelStyle())
                        .font(.system(.caption, weight: .semibold))
                    Picker("", selection: $selectedPath) {
                        ForEach(mountedVolumes, id: \.path) { vol in
                            Text("\(vol.name)  (\(vol.path))").tag(vol.path)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedPath) { path in
                        if displayName.isEmpty || mountedVolumes.contains(where: { $0.name == displayName }) {
                            displayName = mountedVolumes.first(where: { $0.path == path })?.name ?? path
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("Display Name", comment: ""), systemImage: "textformat")
                        .labelStyle(SettingsLabelStyle())
                        .font(.system(.caption, weight: .semibold))
                    TextField(NSLocalizedString("e.g. Macintosh HD", comment: ""), text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(NSLocalizedString("Alert Thresholds", comment: ""), systemImage: "bell.badge")
                        .labelStyle(SettingsLabelStyle())
                        .font(.system(.caption, weight: .semibold))

                    HStack(spacing: 8) {
                        Toggle("", isOn: $percentEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        Text(NSLocalizedString("Free space below", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $thresholdPercent, in: 1...50, step: 1)
                            .controlSize(.small)
                            .disabled(!percentEnabled)
                        Text("\(Int(thresholdPercent))%")
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(percentEnabled ? .primary : .tertiary)
                    }

                    HStack(spacing: 8) {
                        Toggle("", isOn: $gbEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        Text(NSLocalizedString("Free space below", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $thresholdGB, in: 1...500, step: 1)
                            .controlSize(.small)
                            .disabled(!gbEnabled)
                        Text(formatDiskGB(thresholdGB))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .foregroundStyle(gbEnabled ? .primary : .tertiary)
                    }
                }
            }
            .padding(18)

            Spacer(minLength: 0)
            Divider().opacity(0.5)

            HStack {
                Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button(NSLocalizedString("Add", comment: "")) { addVolume() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 440)
        .background(.regularMaterial)
        .onAppear {
            if let first = mountedVolumes.first {
                selectedPath = first.path
                displayName = first.name
            }
        }
    }

    private func addVolume() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let rawId = selectedPath
            .replacingOccurrences(of: "/", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let id = rawId.isEmpty ? "vol_\(abs(selectedPath.hashValue))" : rawId
        let volume = DiskVolume(
            id: id,
            displayName: name,
            path: selectedPath,
            thresholdPercent: percentEnabled ? thresholdPercent : nil,
            thresholdGB: gbEnabled ? thresholdGB : nil
        )
        onAdd(volume)
        dismiss()
    }
}

// MARK: - Add Process View

private struct AddProcessView: View {
    let onAdd: (ProcessDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var patternsText = ""
    @State private var limitMB: Double = 4096
    @State private var selectedAppPath: String? = nil
    @State private var selectedAppIcon: NSImage? = nil

    private static let minMB: Double = 64
    private static let maxMB: Double = 32768
    private static let stepMB: Double = 64

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !patternsText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Add Process")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                appPickerRow

                fieldGroup(label: NSLocalizedString("Display Name", comment: ""), icon: "textformat") {
                    TextField("e.g. Docker", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                fieldGroup(
                    label: NSLocalizedString("Process Patterns", comment: ""),
                    icon: "magnifyingglass",
                    hint: NSLocalizedString("Comma-separated. Matched against process command names (case-insensitive).", comment: "")
                ) {
                    TextField("e.g. docker, com.docker", text: $patternsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                fieldGroup(label: NSLocalizedString("Memory Limit", comment: ""), icon: "memorychip") {
                    VStack(spacing: 6) {
                        HStack {
                            Slider(value: $limitMB, in: Self.minMB...Self.maxMB, step: Self.stepMB)
                            Stepper("", value: $limitMB, in: Self.minMB...Self.maxMB, step: Self.stepMB)
                                .labelsHidden()
                                .controlSize(.mini)
                        }
                        HStack {
                            Spacer()
                            Text(formatMemory(limitMB))
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.tint.opacity(0.15)))
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .padding(18)

            Spacer(minLength: 0)
            Divider().opacity(0.5)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button("Add") { addProcess() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 440, height: 540)
        .background(.regularMaterial)
    }

    private func fieldGroup<Content: View>(
        label: String,
        icon: String,
        hint: String? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .labelStyle(SettingsLabelStyle())
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.primary)
            content()
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var appPickerRow: some View {
        HStack(spacing: 10) {
            if let icon = selectedAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 22, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.tint.opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedAppPath.map { ($0 as NSString).lastPathComponent } ?? NSLocalizedString("No app selected", comment: ""))
                    .font(.system(.callout, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(selectedAppPath ?? NSLocalizedString("Choose an .app to auto-fill the fields below.", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: chooseApp) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Choose App…")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )
                .foregroundStyle(.white)
                .shadow(color: .accentColor.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose App Panel", comment: "")
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        if FileManager.default.fileExists(atPath: "/Applications") {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        if panel.runModal() == .OK, let url = panel.url {
            applySelectedApp(at: url)
        }
    }

    private func applySelectedApp(at url: URL) {
        let path = url.path
        selectedAppPath = path
        selectedAppIcon = NSWorkspace.shared.icon(forFile: path)
        let bundle = Bundle(url: url)
        let bundleName = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
        let appFileName = url.deletingPathExtension().lastPathComponent
        if displayName.isEmpty { displayName = bundleName ?? appFileName }
        let patternCandidate = "\(appFileName).app"
        if patternsText.isEmpty {
            patternsText = patternCandidate
        } else if !patternsText.contains(patternCandidate) {
            patternsText += ", \(patternCandidate)"
        }
    }

    private func addProcess() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let patterns = patternsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let id = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let definition = ProcessDefinition(
            id: id,
            displayName: name,
            patterns: patterns,
            defaultLimitMB: Int(limitMB)
        )
        onAdd(definition)
        dismiss()
    }
}
