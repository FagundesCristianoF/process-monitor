import SwiftUI

struct SettingsView: View {
    @ObservedObject var configStore: ProcessConfigStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            definitionsList
            Divider()
            footerButtons
        }
        .frame(minWidth: 380, minHeight: 460)
        .sheet(isPresented: $showAddForm) {
            AddProcessView { definition in
                configStore.addDefinition(definition)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Monitored Processes", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Spacer()

            Button(action: { showAddForm = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Add a process to monitor")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private var definitionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(configStore.definitions) { def in
                    DefinitionRow(
                        definition: def,
                        currentLimit: configStore.limit(for: def.id),
                        onLimitChanged: { configStore.setLimit($0, for: def.id) },
                        onRemove: { configStore.removeDefinition(id: def.id) }
                    )
                    if def.id != configStore.definitions.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { launchAtLoginStore.isEnabled },
                    set: { launchAtLoginStore.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            if let statusMessage = launchAtLoginStore.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset to Defaults") {
                    configStore.resetToDefaults()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Definition Row

private struct DefinitionRow: View {
    let definition: ProcessDefinition
    let currentLimit: Int
    let onLimitChanged: (Int) -> Void
    let onRemove: () -> Void

    @State private var showConfirmRemove = false
    @State private var limitMB: Double = 0

    private static let minMB: Double = 64
    private static let maxMB: Double = 32768 // 32 GB
    private static let stepMB: Double = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.displayName)
                        .font(.system(.body, weight: .medium))

                    Text(definition.patterns.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: { showConfirmRemove = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove from monitoring")
                .alert(
                    "Remove \(definition.displayName)?",
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

            HStack(spacing: 8) {
                Slider(
                    value: $limitMB,
                    in: Self.minMB...Self.maxMB,
                    step: Self.stepMB
                ) {
                    EmptyView()
                }
                .onChange(of: limitMB) { newValue in
                    onLimitChanged(Int(newValue))
                }

                Text(formatMemory(Double(currentLimit)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Stepper(
                    "",
                    value: $limitMB,
                    in: Self.minMB...Self.maxMB,
                    step: Self.stepMB
                )
                .labelsHidden()
                .frame(width: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            limitMB = Double(currentLimit)
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

    private static let minMB: Double = 64
    private static let maxMB: Double = 32768
    private static let stepMB: Double = 64

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !patternsText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Process")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Docker", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Process Patterns (comma-separated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. docker, com.docker", text: $patternsText)
                        .textFieldStyle(.roundedBorder)
                    Text("Matched against process command names (case-insensitive)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Memory Limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatMemory(limitMB))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Slider(
                            value: $limitMB,
                            in: Self.minMB...Self.maxMB,
                            step: Self.stepMB
                        ) {
                            EmptyView()
                        }

                        Stepper(
                            "",
                            value: $limitMB,
                            in: Self.minMB...Self.maxMB,
                            step: Self.stepMB
                        )
                        .labelsHidden()
                        .frame(width: 36)
                    }
                }
            }
            .padding(16)

            Spacer()
            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addProcess() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 340, height: 340)
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
