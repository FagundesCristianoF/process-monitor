import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal, 4)

            content()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background.opacity(0.5))
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
                )
        }
    }
}

private struct LanguageOption: Identifiable, Hashable {
    let id: String
    let code: String?
    let label: String
}

private let supportedLanguages: [LanguageOption] = [
    LanguageOption(id: "system", code: nil, label: "System default"),
    LanguageOption(id: "en", code: "en", label: "English"),
    LanguageOption(id: "pt-BR", code: "pt-BR", label: "Português (Brasil)"),
    LanguageOption(id: "es", code: "es", label: "Español"),
    LanguageOption(id: "fr", code: "fr", label: "Français"),
    LanguageOption(id: "de", code: "de", label: "Deutsch")
]

struct SettingsView: View {
    @ObservedObject var configStore: ProcessConfigStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @State private var showAddForm = false
    @State private var showRestartAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                processesSection
                preferencesSection
                privacySection
                aboutSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(minWidth: 460, minHeight: 560)
        .background(.regularMaterial)
        .sheet(isPresented: $showAddForm) {
            AddProcessView { definition in
                configStore.addDefinition(definition)
            }
        }
        .alert(
            "Restart required",
            isPresented: $showRestartAlert,
            actions: {
                Button("Restart now", role: .destructive) { Self.relaunch() }
                Button("Later", role: .cancel) {}
            },
            message: {
                Text("Process Monitor needs to restart to apply the new language.")
            }
        )
    }

    // MARK: - Processes Section

    private var processesSection: some View {
        SettingsSection(
            title: NSLocalizedString("Monitored Processes", comment: ""),
            icon: "list.bullet.rectangle.fill",
            trailing: AnyView(
                Button(action: { showAddForm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
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
                .help("Add a process to monitor")
            )
        ) {
            VStack(spacing: 0) {
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
                        Divider().opacity(0.5).padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSection(
            title: NSLocalizedString("Preferences", comment: ""),
            icon: "slider.horizontal.3"
        ) {
            VStack(spacing: 0) {
                settingsRow {
                    HStack {
                        Label("Language", systemImage: "globe")
                            .labelStyle(SettingsLabelStyle())
                        Spacer()
                        Picker("", selection: languageBinding) {
                            ForEach(supportedLanguages) { lang in
                                Text(lang.label).tag(lang.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                Divider().opacity(0.5).padding(.horizontal, 14)
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
                    HStack {
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
                Divider().opacity(0.5).padding(.horizontal, 14)
                settingsRow {
                    HStack(spacing: 12) {
                        Label("Refresh every", systemImage: "clock.arrow.circlepath")
                            .labelStyle(SettingsLabelStyle())
                            .layoutPriority(1)
                        Slider(
                            value: $configStore.pollIntervalSeconds,
                            in: ProcessConfigStore.minPollInterval...ProcessConfigStore.maxPollInterval,
                            step: 1
                        )
                        Text("\(Int(configStore.pollIntervalSeconds))s")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SettingsSection(
            title: NSLocalizedString("Privacy", comment: ""),
            icon: "lock.shield.fill"
        ) {
            VStack(spacing: 0) {
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
                Divider().opacity(0.5).padding(.horizontal, 14)
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

    private var aboutSection: some View {
        SettingsSection(
            title: NSLocalizedString("About", comment: "About section title"),
            icon: "info.circle.fill"
        ) {
            VStack(spacing: 0) {
                settingsRow {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Process Monitor")
                                .font(.callout.weight(.medium))
                            Text(String(
                                format: NSLocalizedString("Version %@", comment: "App version label"),
                                AppInfo.displayVersion
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                        Spacer()
                    }
                }
                Divider().opacity(0.5).padding(.horizontal, 14)
                settingsRow {
                    HStack(spacing: 8) {
                        Link(destination: AppInfo.bugReportURL) {
                            Label(NSLocalizedString("Report a bug", comment: "Bug report link"), systemImage: "ladybug")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                        }
                        Spacer()
                        Link(destination: AppInfo.repositoryURL) {
                            Label(NSLocalizedString("View on GitHub", comment: "GitHub repository link"), systemImage: "arrow.up.right.square")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func settingsRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
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
    private static let maxMB: Double = 32768 // 32 GB
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
                    .background(
                        Capsule().fill(.quaternary.opacity(0.5))
                    )
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
                    String(format: NSLocalizedString("Remove %@?", comment: "Remove process confirmation title"), definition.displayName),
                    isPresented: $showConfirmRemove,
                    actions: {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive, action: onRemove)
                    },
                    message: {
                        Text("This process will no longer be monitored.")
                    }
                )
            }

            VStack(spacing: 6) {
                limitSliderRow(
                    iconColor: .orange,
                    icon: "exclamationmark.triangle.fill",
                    label: NSLocalizedString("Warn at", comment: "Warning threshold label"),
                    value: $limitMB,
                    onChange: { onLimitChanged(Int($0)) }
                )

                if definition.isRestartable {
                    HStack(spacing: 8) {
                        Label(NSLocalizedString("Auto-restart", comment: "Auto-restart toggle"), systemImage: "arrow.triangle.2.circlepath")
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
                            label: NSLocalizedString("Restart at", comment: "Auto-restart threshold label"),
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
            Slider(value: value, in: Self.minMB...Self.maxMB, step: Self.stepMB)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { newValue in
                    onChange(newValue)
                }
            Stepper("", value: value, in: Self.minMB...Self.maxMB, step: Self.stepMB)
                .labelsHidden()
                .controlSize(.mini)
        }
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

                fieldGroup(
                    label: NSLocalizedString("Display Name", comment: ""),
                    icon: "textformat"
                ) {
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

                fieldGroup(
                    label: NSLocalizedString("Memory Limit", comment: ""),
                    icon: "memorychip"
                ) {
                    VStack(spacing: 6) {
                        HStack {
                            Slider(
                                value: $limitMB,
                                in: Self.minMB...Self.maxMB,
                                step: Self.stepMB
                            )
                            Stepper(
                                "",
                                value: $limitMB,
                                in: Self.minMB...Self.maxMB,
                                step: Self.stepMB
                            )
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
                                .background(
                                    Capsule().fill(.tint.opacity(0.15))
                                )
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

        if displayName.isEmpty {
            displayName = bundleName ?? appFileName
        }
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
