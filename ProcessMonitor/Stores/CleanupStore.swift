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
    /// Bytes freed on disk by each command's last run (free-space delta, measured
    /// before/after execution). Accurate because runs are sequential — no overlap.
    @Published private(set) var freedBytes: [UUID: Int64] = [:]

    private let defaults: UserDefaults
    private static let key = "cleanupCommands"
    private static let seededNamesKey = "cleanupSeededNames"
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

    /// Total bytes freed across all commands' last runs.
    var totalFreedBytes: Int64 {
        freedBytes.values.reduce(0, +)
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
        guard cmd.isEnabled else { return }
        performRun(id: id, command: cmd.command)
    }

    func runAll() {
        let enabled = commands.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        runAllSequentially(ids: enabled.map(\.id))
    }

    // MARK: - Private

    /// Runs one command on the serial queue, measuring the disk free-space delta
    /// around execution and recording it in `freedBytes`. Calls `completion` on the
    /// main queue once the terminal state is set. Sequential execution keeps the
    /// per-command measurement accurate — no overlapping windows on the shared disk.
    private func performRun(id: UUID, command: String, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.freedBytes.removeValue(forKey: id)
            self?.setRunState(.running, for: id)
        }
        queue.async { [weak self] in
            let before = Self.freeDiskBytes()
            let output = self?.execute(command) ?? ("", "")
            let after = Self.freeDiskBytes()
            let freed = max(0, after - before)
            let combined = [output.0, output.1].filter { !$0.isEmpty }.joined(separator: "\n")
            DispatchQueue.main.async {
                self?.freedBytes[id] = freed
                if output.1.isEmpty {
                    self?.setRunState(.success(output: combined), for: id)
                } else {
                    self?.setRunState(.failure(output: combined), for: id)
                }
                completion?()
            }
        }
    }

    private func runAllSequentially(ids: [UUID]) {
        guard let first = ids.first else { return }
        guard let cmd = commands.first(where: { $0.id == first }) else {
            runAllSequentially(ids: Array(ids.dropFirst()))
            return
        }
        performRun(id: first, command: cmd.command) { [weak self] in
            self?.runAllSequentially(ids: Array(ids.dropFirst()))
        }
    }

    /// Available bytes on the volume backing the home directory. Used to measure
    /// how much a cleanup command reclaimed.
    static func freeDiskBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    /// Returns (stdout, ""). On non-zero exit, returns ("", combinedOutput).
    private func execute(_ command: String) -> (stdout: String, stderr: String) {
        // Preflight: make sure the command's executable resolves on PATH before
        // running. GUI-launched apps inherit a minimal PATH, so tools installed
        // via Homebrew/nvm (brew, npm, ...) often aren't found. Surface a clear
        // hint instead of a raw "command not found".
        if let exe = Self.executableName(from: command), !isExecutableAvailable(exe) {
            return ("", "\(exe) not found. Check if it's added to PATH.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell (-l) so ~/.zprofile / ~/.zshrc populate PATH the way an
        // interactive terminal would — otherwise brew/npm won't be on PATH.
        // `unsetopt nomatch` so a glob matching nothing (e.g. an already-empty
        // cache dir) is passed through literally for `rm -f` to ignore, instead of
        // zsh aborting the whole command with "no matches found".
        process.arguments = ["-lc", "unsetopt nomatch; " + command]

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

    /// Extracts the executable name from a command string, skipping any leading
    /// `VAR=value` environment assignments. Returns nil for an empty command.
    static func executableName(from command: String) -> String? {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" })
        for token in tokens {
            let t = String(token)
            // Skip leading environment assignments like FOO=bar.
            if let eq = t.firstIndex(of: "="), !t.contains("/"),
               t[..<eq].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), eq != t.startIndex {
                continue
            }
            return t
        }
        return nil
    }

    /// Resolves `name` against the login shell's PATH (matches how `command` runs).
    private func isExecutableAvailable(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v -- \(Self.shellQuoted(name)) >/dev/null 2>&1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Single-quotes a string for safe interpolation into a shell command.
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func setRunState(_ state: RunState, for id: UUID) {
        runStates[id] = state
    }

    // MARK: - Persistence

    private static let seedDefaults: [CleanupCommand] = [
        CleanupCommand(name: "iOS Simulators",     command: "xcrun simctl delete unavailable",                                    isEnabled: true),
        CleanupCommand(name: "iOS Simulator Data", command: "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all",       isEnabled: false),
        CleanupCommand(name: "Homebrew",           command: "brew cleanup --prune=all",                                           isEnabled: true),
        CleanupCommand(name: "npm cache",          command: "npm cache clean --force",                                            isEnabled: true),
        CleanupCommand(name: "Docker",             command: "docker system prune --volumes -f",                                   isEnabled: false),
        CleanupCommand(name: "Android Studio",     command: #"rm -rf ~/Library/Application\ Support/Google/AndroidStudio*"#,                   isEnabled: true),
        CleanupCommand(name: "Claude VM Bundles",  command: #"rm -rf ~/Library/Application\ Support/Claude/vm_bundles"#,          isEnabled: true),
        // Generic dev caches — regenerate on next build, safe to clear.
        CleanupCommand(name: "Gradle Caches",      command: "rm -rf ~/.gradle/caches",                                            isEnabled: true),
        CleanupCommand(name: "Xcode DerivedData",  command: #"rm -rf ~/Library/Developer/Xcode/DerivedData/*"#,                   isEnabled: true),
        CleanupCommand(name: "Xcode Device Support", command: #"rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*"#,         isEnabled: false),
        CleanupCommand(name: "CocoaPods Cache",    command: "pod cache clean --all",                                              isEnabled: false),
        // Cursor (Electron editor) — caches are safe; chat history is opt-in (destructive).
        CleanupCommand(name: "Cursor Cache",       command: #"rm -rf ~/Library/Application\ Support/Cursor/Cache ~/Library/Application\ Support/Cursor/GPUCache ~/Library/Application\ Support/Cursor/Code\ Cache ~/Library/Application\ Support/Cursor/DawnWebGPUCache ~/Library/Application\ Support/Cursor/DawnGraphiteCache ~/Library/Application\ Support/Cursor/CachedProfilesData"#, isEnabled: true),
        CleanupCommand(name: "Cursor Chat History", command: #"find ~/Library/Application\ Support/Cursor/User/workspaceStorage -name "state.vscdb*" -delete; rm -f ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb*"#, isEnabled: false),
        // Read-only scans — answer "what's eating my disk?" without deleting anything.
        CleanupCommand(name: "Scan: Large Build Folders", command: #"find ~ -path "$HOME/Library" -prune -o -type d \( -name build -o -name DerivedData -o -name node_modules -o -name .gradle -o -name Pods \) -prune -exec du -sh {} + 2>/dev/null | sort -rh | head -30"#, isEnabled: false),
        CleanupCommand(name: "Scan: Large Artifacts",     command: #"find ~ -path "$HOME/Library" -prune -o -type f \( -name "*.ipa" -o -name "*.dmg" -o -name "*.hprof" -o -name "*.apk" -o -name "*.aab" -o -name "*.zip" -o -name "*.jar" \) -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -30"#, isEnabled: false),
    ]

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([CleanupCommand].self, from: data),
              !saved.isEmpty
        else {
            commands = Self.seedDefaults
            defaults.set(Self.seedDefaults.map(\.name), forKey: Self.seededNamesKey)
            persist()
            return
        }
        commands = saved
        mergeNewSeeds()
        repairLegacySeedCommands()
    }

    /// Upgrades older default command strings in place when the user still has the
    /// known-buggy version (i.e. they never customized it). Idempotent: once a fix
    /// is applied the old string no longer matches.
    private static let legacyCommandFixes: [(name: String, old: String, new: String)] = [
        ("iOS Simulator Data", "xcrun simctl erase all", "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all"),
    ]

    private func repairLegacySeedCommands() {
        var changed = false
        for fix in Self.legacyCommandFixes {
            for idx in commands.indices where commands[idx].name == fix.name && commands[idx].command == fix.old {
                commands[idx].command = fix.new
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Appends default commands introduced after the user's data was first written,
    /// so existing installs pick up new built-ins without losing customizations or
    /// resurrecting defaults the user deliberately deleted. Idempotent per seed name.
    private func mergeNewSeeds() {
        var seeded = Set(defaults.stringArray(forKey: Self.seededNamesKey) ?? [])
        // First run after upgrading from a pre-migration build: no record exists yet.
        // Assume everything currently present was already seeded so we don't duplicate.
        if seeded.isEmpty {
            seeded = Set(commands.map(\.name))
        }
        var appended = false
        for seed in Self.seedDefaults where !seeded.contains(seed.name) {
            commands.append(seed)
            seeded.insert(seed.name)
            appended = true
        }
        defaults.set(Array(seeded), forKey: Self.seededNamesKey)
        if appended { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
