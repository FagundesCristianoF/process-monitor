# Storage Cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Storage" settings tab with configurable shell cleanup commands, dangerous-command validation, and per-command run controls.

**Architecture:** `CleanupCommand` model + `CommandValidator` (pure logic, fully testable) live in a new `CleanupStore` (`ObservableObject`, UserDefaults-backed). `StorageCleanerView` adds a new sidebar tab following the existing `DetailCard`/`DetailHeader` pattern. `SettingsWindowController` and `ProcessMonitorApp` wire the store in.

**Tech Stack:** SwiftUI, Foundation (`Process`/`Pipe`), UserDefaults JSON persistence, XCTest

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ProcessMonitor/Models/CleanupCommand.swift` | Data model + `CommandValidator` |
| Create | `ProcessMonitor/Stores/CleanupStore.swift` | Persistence, execution, `RunState` |
| Create | `ProcessMonitor/Views/StorageCleanerView.swift` | Tab UI + add/edit sheet |
| Modify | `ProcessMonitor/Views/SettingsView.swift` | Add `.storage` tab case |
| Modify | `ProcessMonitor/Views/SettingsWindowController.swift` | Pass `CleanupStore` to `SettingsView` |
| Modify | `ProcessMonitor/ProcessMonitorApp.swift` | Instantiate `CleanupStore` |
| Create | `Tests/ProcessMonitorTests/CommandValidatorTests.swift` | Validator unit tests |
| Create | `Tests/ProcessMonitorTests/CleanupStoreTests.swift` | Store unit tests |

---

## Task 1: `CleanupCommand` model + `CommandValidator`

**Files:**
- Create: `ProcessMonitor/Models/CleanupCommand.swift`
- Create: `Tests/ProcessMonitorTests/CommandValidatorTests.swift`

- [ ] **Step 1: Write the failing validator tests**

Create `Tests/ProcessMonitorTests/CommandValidatorTests.swift`:

```swift
import XCTest
@testable import ProcessMonitor

final class CommandValidatorTests: XCTestCase {

    // MARK: - Safe commands pass

    func testSafeCommandPasses() {
        XCTAssertEqual(CommandValidator.validate("xcrun simctl delete unavailable"), .ok)
    }

    func testBrewCleanupPasses() {
        XCTAssertEqual(CommandValidator.validate("brew cleanup --prune=all"), .ok)
    }

    func testNpmCachePasses() {
        XCTAssertEqual(CommandValidator.validate("npm cache clean --force"), .ok)
    }

    func testDockerPrunePasses() {
        XCTAssertEqual(CommandValidator.validate("docker system prune --volumes -f"), .ok)
    }

    func testRmWithSpecificGlobPasses() {
        XCTAssertEqual(
            CommandValidator.validate(#"rm -rf ~/Library/Application\ Support/Google/AndroidStudio2025.*"#),
            .ok
        )
    }

    // MARK: - chmod / chown blocked

    func testChmodBlocked() {
        if case .blocked = CommandValidator.validate("chmod 777 /etc/hosts") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testChownBlocked() {
        if case .blocked = CommandValidator.validate("chown root /etc/passwd") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - rm -rf on dangerous targets blocked

    func testRmRfRootBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf /") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfRootWithTrailingSpaceBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf / ") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmFrRootBlocked() {
        if case .blocked = CommandValidator.validate("rm -fr /") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfHomeBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf ~") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfHomeDirBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf ~/") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfDollarHomeBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf $HOME") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfRootStarBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf /*") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - fork bomb blocked

    func testForkBombBlocked() {
        if case .blocked = CommandValidator.validate(":(){ :|:& };:") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - dd to block device blocked

    func testDdToDeviceBlocked() {
        if case .blocked = CommandValidator.validate("dd if=/dev/zero of=/dev/sda") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - redirect to block device blocked

    func testRedirectToDevSdBlocked() {
        if case .blocked = CommandValidator.validate("echo foo > /dev/sda") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - reason string is non-empty

    func testBlockedReasonIsNonEmpty() {
        if case .blocked(let reason) = CommandValidator.validate("chmod 777 /") {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected .blocked")
        }
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter CommandValidatorTests 2>&1 | tail -20
```
Expected: compile error — `CommandValidator` not found.

- [ ] **Step 3: Create `CleanupCommand.swift`**

Create `ProcessMonitor/Models/CleanupCommand.swift`:

```swift
import Foundation

struct CleanupCommand: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var isEnabled: Bool
}

// MARK: - Validation

enum ValidationResult: Equatable {
    case ok
    case blocked(reason: String)
}

enum CommandValidator {
    private static let rules: [(pattern: String, reason: String)] = [
        (#"\bchmod\b"#,                                         "chmod modifies file permissions"),
        (#"\bchown\b"#,                                         "chown modifies file ownership"),
        (#"rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+/(?:\s|$)"#,          "rm -rf / would erase the root filesystem"),
        (#"rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+~/?\s*$"#,            "rm -rf ~ would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+~/\s"#,               "rm -rf ~/ would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+\$HOME"#,             "rm -rf $HOME would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+/\*"#,                "rm -rf /* would erase all files in root"),
        (#":\s*\(\s*\)\s*\{[^}]*:\s*\|[^}]*:&"#,              "This looks like a fork bomb"),
        (#">\s*/dev/sd"#,                                       "Writing to a raw block device is dangerous"),
        (#"\bdd\b.*\bof=/dev/"#,                                "dd to a block device is dangerous"),
    ]

    static func validate(_ command: String) -> ValidationResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in rules {
            guard let regex = try? NSRegularExpression(
                pattern: rule.pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return .blocked(reason: rule.reason)
            }
        }
        return .ok
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter CommandValidatorTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
rtk git add ProcessMonitor/Models/CleanupCommand.swift Tests/ProcessMonitorTests/CommandValidatorTests.swift
rtk git commit -m "feat(storage): add CleanupCommand model and CommandValidator"
```

---

## Task 2: `CleanupStore`

**Files:**
- Create: `ProcessMonitor/Stores/CleanupStore.swift`
- Create: `Tests/ProcessMonitorTests/CleanupStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/ProcessMonitorTests/CleanupStoreTests.swift`:

```swift
import XCTest
@testable import ProcessMonitor

final class CleanupStoreTests: XCTestCase {

    private func makeStore(defaults: UserDefaults = makeIsolatedDefaults()) -> CleanupStore {
        CleanupStore(defaults: defaults)
    }

    private static func makeIsolatedDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Seeding

    func testSeedsDefaultCommandsOnFirstLoad() {
        let store = makeStore()
        XCTAssertEqual(store.commands.count, 7)
        XCTAssertTrue(store.commands.allSatisfy(\.isEnabled))
    }

    func testDoesNotReseedWhenDataExists() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)
        store1.add(CleanupCommand(id: UUID(), name: "Custom", command: "echo hi", isEnabled: true))
        let store2 = CleanupStore(defaults: defaults)
        XCTAssertEqual(store2.commands.count, 8)
    }

    // MARK: - CRUD

    func testAddCommand() {
        let store = makeStore()
        let cmd = CleanupCommand(id: UUID(), name: "Test", command: "echo hi", isEnabled: true)
        store.add(cmd)
        XCTAssertTrue(store.commands.contains(where: { $0.id == cmd.id }))
    }

    func testUpdateCommand() {
        let store = makeStore()
        var cmd = store.commands[0]
        cmd.name = "Renamed"
        store.update(cmd)
        XCTAssertEqual(store.commands.first(where: { $0.id == cmd.id })?.name, "Renamed")
    }

    func testRemoveCommand() {
        let store = makeStore()
        let id = store.commands[0].id
        store.remove(id: id)
        XCTAssertFalse(store.commands.contains(where: { $0.id == id }))
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)
        let cmd = CleanupCommand(id: UUID(), name: "Persisted", command: "echo ok", isEnabled: false)
        store1.add(cmd)

        let store2 = CleanupStore(defaults: defaults)
        XCTAssertTrue(store2.commands.contains(where: { $0.id == cmd.id && $0.name == "Persisted" }))
    }

    // MARK: - RunState

    func testRunStateDefaultsToIdle() {
        let store = makeStore()
        let id = store.commands[0].id
        XCTAssertEqual(store.runState(for: id), .idle)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter CleanupStoreTests 2>&1 | tail -20
```
Expected: compile error — `CleanupStore` not found.

- [ ] **Step 3: Create `CleanupStore.swift`**

Create `ProcessMonitor/Stores/CleanupStore.swift`:

```swift
import Foundation
import Combine

enum RunState: Equatable {
    case idle
    case running
    case success(output: String)
    case failure(output: String)
}

final class CleanupStore: ObservableObject {
    @Published private(set) var commands: [CleanupCommand] = []
    @Published private(set) var runStates: [UUID: RunState] = [:]

    private let defaults: UserDefaults
    private static let key = "cleanupCommands"
    private let queue = DispatchQueue(label: "CleanupStore.run", qos: .userInitiated)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Accessors

    func runState(for id: UUID) -> RunState {
        runStates[id] ?? .idle
    }

    var isAnyRunning: Bool {
        runStates.values.contains(.running)
    }

    // MARK: - CRUD

    func add(_ command: CleanupCommand) {
        commands.append(command)
        persist()
    }

    func update(_ command: CleanupCommand) {
        guard let idx = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[idx] = command
        persist()
    }

    func remove(id: UUID) {
        commands.removeAll { $0.id == id }
        runStates.removeValue(forKey: id)
        persist()
    }

    // MARK: - Execution

    func run(id: UUID) {
        guard let cmd = commands.first(where: { $0.id == id }) else { return }
        guard runStates[id] != .running else { return }
        setRunState(.running, for: id)
        queue.async { [weak self] in
            let output = self?.execute(cmd.command) ?? ("", "")
            let combined = [output.0, output.1].filter { !$0.isEmpty }.joined(separator: "\n")
            DispatchQueue.main.async {
                if output.1.isEmpty {
                    self?.setRunState(.success(output: combined), for: id)
                } else {
                    self?.setRunState(.failure(output: combined), for: id)
                }
            }
        }
    }

    func runAll() {
        let enabled = commands.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        runAllSequentially(ids: enabled.map(\.id))
    }

    // MARK: - Private

    private func runAllSequentially(ids: [UUID]) {
        guard let first = ids.first else { return }
        guard let cmd = commands.first(where: { $0.id == first }) else {
            runAllSequentially(ids: Array(ids.dropFirst()))
            return
        }
        setRunState(.running, for: first)
        queue.async { [weak self] in
            let output = self?.execute(cmd.command) ?? ("", "")
            let combined = [output.0, output.1].filter { !$0.isEmpty }.joined(separator: "\n")
            DispatchQueue.main.async {
                if output.1.isEmpty {
                    self?.setRunState(.success(output: combined), for: first)
                } else {
                    self?.setRunState(.failure(output: combined), for: first)
                }
                self?.runAllSequentially(ids: Array(ids.dropFirst()))
            }
        }
    }

    /// Returns (stdout, stderr). Non-empty stderr → treat as failure.
    private func execute(_ command: String) -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription)
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            return ("", combined)
        }
        return (stdout, "")
    }

    private func setRunState(_ state: RunState, for id: UUID) {
        runStates[id] = state
    }

    // MARK: - Persistence

    private static let defaults_: [CleanupCommand] = [
        CleanupCommand(id: UUID(), name: "iOS Simulators",        command: "xcrun simctl delete unavailable",                                                                      isEnabled: true),
        CleanupCommand(id: UUID(), name: "iOS Simulator Data",    command: "xcrun simctl erase all",                                                                               isEnabled: false),
        CleanupCommand(id: UUID(), name: "Homebrew",              command: "brew cleanup --prune=all",                                                                             isEnabled: true),
        CleanupCommand(id: UUID(), name: "npm cache",             command: "npm cache clean --force",                                                                              isEnabled: true),
        CleanupCommand(id: UUID(), name: "Docker",                command: "docker system prune --volumes -f",                                                                     isEnabled: true),
        CleanupCommand(id: UUID(), name: "Android Studio",        command: #"rm -rf ~/Library/Application\ Support/Google/AndroidStudio$(($(date +%Y)-1)).*"#,                    isEnabled: true),
        CleanupCommand(id: UUID(), name: "Claude VM Bundles",     command: #"rm -rf ~/Library/Application\ Support/Claude/vm_bundles"#,                                           isEnabled: true),
    ]

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([CleanupCommand].self, from: data),
              !saved.isEmpty
        else {
            commands = Self.defaults_
            persist()
            return
        }
        commands = saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter CleanupStoreTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
rtk git add ProcessMonitor/Stores/CleanupStore.swift Tests/ProcessMonitorTests/CleanupStoreTests.swift
rtk git commit -m "feat(storage): add CleanupStore with persistence and execution"
```

---

## Task 3: `StorageCleanerView`

**Files:**
- Create: `ProcessMonitor/Views/StorageCleanerView.swift`

- [ ] **Step 1: Create the view file**

Create `ProcessMonitor/Views/StorageCleanerView.swift`:

```swift
import SwiftUI

struct StorageCleanerView: View {
    @ObservedObject var store: CleanupStore

    @State private var showAddSheet = false
    @State private var editingCommand: CleanupCommand? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(
                title: NSLocalizedString("Storage Cleaner", comment: ""),
                trailing: AnyView(headerButtons)
            )

            if store.commands.isEmpty {
                emptyState
            } else {
                DetailCard {
                    ForEach(store.commands) { cmd in
                        CleanupCommandRow(
                            command: cmd,
                            runState: store.runState(for: cmd.id),
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
                Image(systemName: store.isAnyRunning ? "stop.circle" : "play.circle")
                    .font(.system(size: 10, weight: .bold))
                Text("Run All")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.75, blue: 0.55),
                                 Color(red: 0.20, green: 0.75, blue: 0.55).opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.20, green: 0.75, blue: 0.55).opacity(0.3), radius: 3, y: 1)
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
                // Status badge
                statusBadge
                    .frame(width: 22, height: 22)

                // Name + command preview
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

                // Controls
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

                // Run / spinner
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

            // Output area
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
            if case .failure = newState { outputExpanded = true }
            if case .success = newState { outputExpanded = false }
        }
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
            // Header
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
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Name", systemImage: "textformat")
                        .font(.system(.caption, weight: .semibold))
                        .labelStyle(SettingsLabelStyle())
                    TextField("e.g. iOS Simulators", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Command field
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
            }
        }
    }

    private func save() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            onSave(CleanupCommand(id: UUID(), name: trimmedName, command: trimmedCommand, isEnabled: true))
        case .edit(let existing):
            var updated = existing
            updated.name = trimmedName
            updated.command = trimmedCommand
            onSave(updated)
        }
        dismiss()
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
rtk git add ProcessMonitor/Views/StorageCleanerView.swift
rtk git commit -m "feat(storage): add StorageCleanerView with add/edit sheet"
```

---

## Task 4: Wire `.storage` tab into `SettingsView`

**Files:**
- Modify: `ProcessMonitor/Views/SettingsView.swift`

- [ ] **Step 1: Add `.storage` case to `SettingsTab`**

In `SettingsView.swift`, find the `enum SettingsTab` (line 8). Add `.storage` between `.disk` and `.preferences`:

```swift
enum SettingsTab: String, CaseIterable, Identifiable {
    case processes, disk, storage, preferences, privacy, about
    // ...
}
```

- [ ] **Step 2: Add `localizedLabel` for `.storage`**

In the `localizedLabel` switch (around line 14), add:
```swift
case .storage:    return NSLocalizedString("Storage", comment: "")
```

- [ ] **Step 3: Add `icon` for `.storage`**

In the `icon` switch (around line 23), add:
```swift
case .storage:     return "sparkles"
```

- [ ] **Step 4: Add `iconColor` for `.storage`**

In the `iconColor` switch (around line 33), add:
```swift
case .storage:     return Color(red: 0.20, green: 0.75, blue: 0.55)
```

- [ ] **Step 5: Add `CleanupStore` to `SettingsView`**

In `SettingsView` (around line 136), add the store property after `diskMonitorService`:
```swift
@ObservedObject var cleanupStore: CleanupStore
```

- [ ] **Step 6: Add `.storage` case to `detailPane`**

In the `detailPane` switch (around line 199), add:
```swift
case .storage:     StorageCleanerView(store: cleanupStore)
```

- [ ] **Step 7: Build to confirm no compile errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` (will fail at call sites — that is expected before Task 5)

---

## Task 5: Wire `CleanupStore` into app entry points

**Files:**
- Modify: `ProcessMonitor/Views/SettingsWindowController.swift`
- Modify: `ProcessMonitor/ProcessMonitorApp.swift`

- [ ] **Step 1: Update `SettingsWindowController.open`**

In `SettingsWindowController.swift`, update the `open` signature and body:

```swift
func open(
    configStore: ProcessConfigStore,
    launchAtLoginStore: LaunchAtLoginStore,
    diskMonitorService: DiskMonitorService,
    cleanupStore: CleanupStore
) {
    dismissMenuBarPopover()
    if let existing = window, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let settingsView = SettingsView(
        configStore: configStore,
        launchAtLoginStore: launchAtLoginStore,
        diskMonitorService: diskMonitorService,
        cleanupStore: cleanupStore
    )
    let hostingView = NSHostingView(rootView: settingsView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 540)

    let newWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    newWindow.title = NSLocalizedString("Process Monitor Settings", comment: "Settings window title")
    newWindow.titlebarAppearsTransparent = false
    newWindow.titleVisibility = .visible
    newWindow.isMovableByWindowBackground = false
    newWindow.contentView = hostingView
    newWindow.minSize = NSSize(width: 680, height: 460)
    newWindow.center()
    newWindow.isReleasedWhenClosed = false
    newWindow.level = .normal
    newWindow.makeKeyAndOrderFront(nil)

    NSApp.activate(ignoringOtherApps: true)
    self.window = newWindow
}
```

- [ ] **Step 2: Add `CleanupStore` to `ProcessMonitorApp`**

In `ProcessMonitorApp.swift`, add the state object and pass it through. Replace the existing `init` and `body`:

```swift
@main
struct ProcessMonitorApp: App {
    @StateObject private var configStore: ProcessConfigStore
    @StateObject private var launchAtLoginStore: LaunchAtLoginStore
    @StateObject private var notificationService: NotificationService
    @StateObject private var monitorService: ProcessMonitorService
    @StateObject private var diskMonitorService: DiskMonitorService
    @StateObject private var cleanupStore: CleanupStore

    init() {
        let config = ProcessConfigStore()
        Telemetry.start(enabled: config.telemetryEnabled)
        Telemetry.breadcrumb("App launched", category: "lifecycle")
        let launchAtLogin = LaunchAtLoginStore()
        let notifications = NotificationService()
        let monitor = ProcessMonitorService(
            configStore: config,
            notificationService: notifications
        )
        let diskMonitor = DiskMonitorService(
            configStore: config,
            notificationService: notifications
        )
        let cleanup = CleanupStore()
        _configStore = StateObject(wrappedValue: config)
        _launchAtLoginStore = StateObject(wrappedValue: launchAtLogin)
        _notificationService = StateObject(wrappedValue: notifications)
        _monitorService = StateObject(wrappedValue: monitor)
        _diskMonitorService = StateObject(wrappedValue: diskMonitor)
        _cleanupStore = StateObject(wrappedValue: cleanup)
        launchAtLogin.ensureRegistered()
        // Defer permission request until run loop is active — requesting during
        // init() causes macOS to auto-decline before the app window appears.
        DispatchQueue.main.async {
            notifications.requestPermissionIfNeeded()
            monitor.startPolling()
            diskMonitor.startPolling()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ProcessListView(
                monitorService: monitorService,
                diskMonitorService: diskMonitorService,
                configStore: configStore,
                launchAtLoginStore: launchAtLoginStore,
                cleanupStore: cleanupStore
            )
            .frame(width: 420, height: 520)
            .onChange(of: configStore.telemetryEnabled) { enabled in
                Telemetry.setEnabled(enabled)
            }
        } label: {
            MenuBarIconLabel(monitorService: monitorService)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Find the `SettingsWindowController.shared.open(...)` call site in `ProcessListView` and add `cleanupStore`**

Search for the call in `ProcessListView.swift`:
```bash
grep -n "SettingsWindowController" ProcessMonitor/Views/ProcessListView.swift
```

Update that call to pass `cleanupStore`. It will look like:
```swift
SettingsWindowController.shared.open(
    configStore: configStore,
    launchAtLoginStore: launchAtLoginStore,
    diskMonitorService: diskMonitorService,
    cleanupStore: cleanupStore
)
```

Also add `@ObservedObject var cleanupStore: CleanupStore` to `ProcessListView`'s properties if not already present.

- [ ] **Step 4: Full build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Run all tests**

```bash
swift test 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
rtk git add ProcessMonitor/Views/SettingsView.swift ProcessMonitor/Views/SettingsWindowController.swift ProcessMonitor/ProcessMonitorApp.swift ProcessMonitor/Views/ProcessListView.swift
rtk git commit -m "feat(storage): wire CleanupStore and storage tab into app"
```

---

## Self-Review

**Spec coverage check:**
- ✅ `CleanupCommand` model — Task 1
- ✅ `CommandValidator` with all 9 blocked patterns — Task 1
- ✅ `CleanupStore` (add/update/remove, persistence, seed defaults, run/runAll, RunState) — Task 2
- ✅ `StorageCleanerView` with row states, edit sheet, Run All button — Task 3
- ✅ `.storage` sidebar tab with correct icon/color — Task 4
- ✅ Wired into app entry points — Task 5
- ✅ Default commands seeded (iOS Simulators, Homebrew, npm, Docker, Android Studio) — Task 2

**Placeholder scan:** None found.

**Type consistency:**
- `CleanupCommand` defined Task 1, used Tasks 2–5 ✅
- `ValidationResult` / `CommandValidator.validate` defined Task 1, used Tasks 2+3 ✅
- `RunState` defined Task 2, used Task 3 ✅
- `CleanupStore` defined Task 2, used Tasks 3–5 ✅
- `SettingsLabelStyle` referenced in Task 3 — already exists in `SettingsView.swift` ✅
- `DetailCard` / `DetailHeader` referenced in Task 3 — already exist in `SettingsView.swift` ✅
