import SwiftUI

struct StorageCleanerView: View {
    @ObservedObject var store: CleanupStore

    @State private var showAddSheet = false
    @State private var editingCommand: CleanupCommand? = nil
    @State private var fullDiskAccessGranted = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(
                title: NSLocalizedString("Storage Cleaner", comment: ""),
                trailing: AnyView(headerButtons)
            )

            if !fullDiskAccessGranted {
                fullDiskAccessBanner
            }

            if store.totalFreedBytes > 0 {
                totalReclaimedBanner
            }

            if store.commands.isEmpty {
                emptyState
            } else {
                DetailCard {
                    ForEach(store.commands) { cmd in
                        CleanupCommandRow(
                            command: cmd,
                            runState: store.runState(for: cmd.id),
                            freedBytes: store.freedBytes[cmd.id],
                            anyRunning: store.isAnyRunning,
                            onToggle: {
                                var updated = cmd
                                updated.isEnabled.toggle()
                                store.update(updated)
                            },
                            onEdit: { editingCommand = cmd },
                            onRun: { store.run(id: cmd.id) },
                            onRemove: { store.remove(id: cmd.id) }
                        )
                        if cmd.id != store.commands.last?.id {
                            Divider().opacity(0.4).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CleanupCommandEditSheet(
                mode: .add,
                onSave: { store.add($0) }
            )
        }
        .sheet(item: $editingCommand) { cmd in
            CleanupCommandEditSheet(
                mode: .edit(cmd),
                onSave: { store.update($0) }
            )
        }
        .onAppear { fullDiskAccessGranted = FullDiskAccessService.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccessGranted = FullDiskAccessService.isGranted
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Full Disk Access required")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text("Some caches can't be cleared without it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { FullDiskAccessService.openSettings() }) {
                Text("Open Settings")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .glassBackground(in: Capsule(), tint: .orange, interactive: true)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var totalReclaimedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 0.55))
            Text(String(
                format: NSLocalizedString("Reclaimed %@ total", comment: "Total disk space reclaimed by all cleanup commands"),
                ByteCountFormatter.string(fromByteCount: store.totalFreedBytes, countStyle: .file)
            ))
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.20, green: 0.75, blue: 0.55).opacity(0.12))
        )
    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            runAllButton
            addButton
        }
    }

    private var runAllButton: some View {
        Button(action: { store.runAll() }) {
            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                    .font(.system(size: 10, weight: .bold))
                Text("Run All")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassBackground(
                in: Capsule(),
                tint: Color(red: 0.20, green: 0.75, blue: 0.55),
                interactive: true
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(store.isAnyRunning || store.commands.filter(\.isEnabled).isEmpty)
    }

    private var addButton: some View {
        Button(action: { showAddSheet = true }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassBackground(in: Capsule(), tint: .accentColor, interactive: true)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(store.isAnyRunning)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text("No cleanup commands.")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Tap + to add one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }
}

// MARK: - Command Row

private struct CleanupCommandRow: View {
    let command: CleanupCommand
    let runState: RunState
    let freedBytes: Int64?
    let anyRunning: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRun: () -> Void
    let onRemove: () -> Void

    @State private var outputExpanded = false
    @State private var showConfirmRemove = false

    private var isRunning: Bool { runState == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                statusBadge
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.name)
                        .font(.system(.callout, weight: .semibold))
                    Text(command.command)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if case .success = runState, let freedBytes {
                    freedPill(freedBytes)
                }

                Toggle("", isOn: Binding(get: { command.isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(anyRunning)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(anyRunning)
                .help("Edit command")

                Button(action: { showConfirmRemove = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(anyRunning)
                .help("Remove command")
                .alert(
                    "Remove \"\(command.name)\"?",
                    isPresented: $showConfirmRemove,
                    actions: {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive, action: onRemove)
                    },
                    message: { Text("This command will be permanently deleted.") }
                )

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                } else {
                    Button(action: onRun) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(anyRunning)
                    .help("Run now")
                }
            }

            if let output = outputText, !output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { outputExpanded.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: outputExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text(outputExpanded ? "Hide output" : "Show output")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    if outputExpanded {
                        ScrollView {
                            Text(output)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: runState) { newState in
            if case .running = newState { outputExpanded = false }
            if case .failure = newState { outputExpanded = true }
            if case .success = newState { outputExpanded = false }
        }
    }

    /// Green pill showing bytes reclaimed by this command's last run.
    private func freedPill(_ bytes: Int64) -> some View {
        let label = bytes > 0
            ? String(format: NSLocalizedString("Freed %@", comment: "Disk space freed by a single cleanup command"),
                     ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            : NSLocalizedString("Nothing to free", comment: "A cleanup command ran but reclaimed no disk space")
        return Text(label)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(bytes > 0 ? Color(red: 0.16, green: 0.62, blue: 0.45) : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((bytes > 0 ? Color(red: 0.20, green: 0.75, blue: 0.55) : Color.secondary)
                    .opacity(0.14))
            )
            .fixedSize()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch runState {
        case .idle:
            Image(systemName: "circle.dotted")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }

    private var outputText: String? {
        switch runState {
        case .success(let out): return out.isEmpty ? nil : out
        case .failure(let out): return out.isEmpty ? nil : out
        default: return nil
        }
    }
}

// MARK: - Add / Edit Sheet

private enum SheetMode {
    case add
    case edit(CleanupCommand)
}

private struct CleanupCommandEditSheet: View {
    let mode: SheetMode
    let onSave: (CleanupCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var validationError: String? = nil

    private var title: String {
        switch mode {
        case .add: return "Add Command"
        case .edit: return "Edit Command"
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty &&
        validationError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Name", systemImage: "textformat")
                        .font(.system(.caption, weight: .semibold))
                        .labelStyle(SettingsLabelStyle())
                    TextField("e.g. iOS Simulators", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Command", systemImage: "terminal")
                        .font(.system(.caption, weight: .semibold))
                        .labelStyle(SettingsLabelStyle())
                    TextEditor(text: $command)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .onChange(of: command) { newValue in
                            let result = CommandValidator.validate(newValue)
                            if case .blocked(let reason) = result {
                                validationError = reason
                            } else {
                                validationError = nil
                            }
                        }

                    if let error = validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
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
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 320)
        .background(.regularMaterial)
        .onAppear {
            if case .edit(let cmd) = mode {
                name = cmd.name
                command = cmd.command
                let result = CommandValidator.validate(cmd.command)
                if case .blocked(let reason) = result { validationError = reason }
            }
        }
    }

    private func save() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            onSave(CleanupCommand(name: trimmedName, command: trimmedCommand, isEnabled: true))
        case .edit(let existing):
            var updated = existing
            updated.name = trimmedName
            updated.command = trimmedCommand
            onSave(updated)
        }
        dismiss()
    }
}
