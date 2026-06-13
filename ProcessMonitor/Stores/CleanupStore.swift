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
        guard cmd.isEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setRunState(.running, for: id)
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.setRunState(.running, for: first)
        }
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
        process.arguments = ["-lc", command]

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
        CleanupCommand(name: "iOS Simulator Data", command: "xcrun simctl erase all",                                             isEnabled: false),
        CleanupCommand(name: "Homebrew",           command: "brew cleanup --prune=all",                                           isEnabled: true),
        CleanupCommand(name: "npm cache",          command: "npm cache clean --force",                                            isEnabled: true),
        CleanupCommand(name: "Docker",             command: "docker system prune --volumes -f",                                   isEnabled: false),
        CleanupCommand(name: "Android Studio",     command: #"rm -rf ~/Library/Application\ Support/Google/AndroidStudio*"#,                   isEnabled: true),
        CleanupCommand(name: "Claude VM Bundles",  command: #"rm -rf ~/Library/Application\ Support/Claude/vm_bundles"#,          isEnabled: true),
    ]

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([CleanupCommand].self, from: data),
              !saved.isEmpty
        else {
            commands = Self.seedDefaults
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
