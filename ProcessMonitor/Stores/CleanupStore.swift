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

    private static let seedDefaults: [CleanupCommand] = [
        CleanupCommand(name: "iOS Simulators",     command: "xcrun simctl delete unavailable",                                    isEnabled: true),
        CleanupCommand(name: "iOS Simulator Data", command: "xcrun simctl erase all",                                             isEnabled: false),
        CleanupCommand(name: "Homebrew",           command: "brew cleanup --prune=all",                                           isEnabled: true),
        CleanupCommand(name: "npm cache",          command: "npm cache clean --force",                                            isEnabled: true),
        CleanupCommand(name: "Docker",             command: "docker system prune --volumes -f",                                   isEnabled: true),
        CleanupCommand(name: "Android Studio",     command: #"rm -rf ~/Library/Application\ Support/Google/AndroidStudio$(($(date +%Y)-1)).*"#, isEnabled: true),
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
