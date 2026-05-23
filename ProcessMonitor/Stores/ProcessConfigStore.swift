import Foundation
import Combine

final class ProcessConfigStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private static let limitsPrefix = "memoryLimit_"
    private static let definitionsKey = "monitoredDefinitions"
    private static let patternVersionKey = "patternSchemaVersion"
    private static let pollIntervalKey = "pollIntervalSeconds"
    private static let isPausedKey = "monitoringPaused"
    private static let currentPatternVersion = 3
    static let defaultPollInterval: Double = 5
    static let minPollInterval: Double = 1
    static let maxPollInterval: Double = 60

    @Published var definitions: [ProcessDefinition] = [] {
        didSet { if isInitialized { persist() } }
    }
    @Published var limits: [String: Int] = [:] {
        didSet { if isInitialized { persist() } }
    }
    @Published var autoRestartLimits: [String: Int] = [:] {
        didSet { if isInitialized { persist() } }
    }
    @Published var pollIntervalSeconds: Double {
        didSet {
            let clamped = min(max(pollIntervalSeconds, Self.minPollInterval), Self.maxPollInterval)
            if clamped != pollIntervalSeconds {
                pollIntervalSeconds = clamped
                return
            }
            if isInitialized { persist() }
        }
    }
    @Published var isPaused: Bool {
        didSet { if isInitialized { persist() } }
    }
    @Published var telemetryEnabled: Bool {
        didSet { if isInitialized { persist() } }
    }
    @Published var preferredLanguage: String? {
        didSet {
            if isInitialized {
                applyLanguagePreference()
                persist()
            }
        }
    }

    private var patternSchemaVersion: Int = 0
    private var isInitialized = false
    private let configFileURL: URL

    private struct PersistedConfig: Codable {
        var definitions: [ProcessDefinition]
        var limits: [String: Int]
        var pollIntervalSeconds: Double
        var isPaused: Bool
        var patternSchemaVersion: Int
        var telemetryEnabled: Bool?
        var preferredLanguage: String?
        var autoRestartLimits: [String: Int]?
    }

    private func applyLanguagePreference() {
        let defaults = UserDefaults.standard
        if let lang = preferredLanguage, !lang.isEmpty {
            defaults.set([lang], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    init() {
        self.configFileURL = Self.defaultConfigFileURL()

        if let loaded = Self.loadFromDisk(at: configFileURL) {
            self.pollIntervalSeconds = loaded.pollIntervalSeconds > 0
                ? loaded.pollIntervalSeconds
                : Self.defaultPollInterval
            self.isPaused = loaded.isPaused
            self.telemetryEnabled = loaded.telemetryEnabled ?? true
            self.preferredLanguage = loaded.preferredLanguage
            self.definitions = loaded.definitions.isEmpty
                ? ProcessDefinition.builtInDefaults
                : loaded.definitions
            self.limits = loaded.limits
            self.autoRestartLimits = loaded.autoRestartLimits ?? [:]
            self.patternSchemaVersion = loaded.patternSchemaVersion
        } else {
            // Migrate from UserDefaults (one-time).
            let storedInterval = defaults.double(forKey: Self.pollIntervalKey)
            self.pollIntervalSeconds = storedInterval > 0 ? storedInterval : Self.defaultPollInterval
            self.isPaused = defaults.bool(forKey: Self.isPausedKey)
            self.telemetryEnabled = true
            self.preferredLanguage = nil
            self.definitions = Self.loadDefinitionsFromDefaults(defaults)
            var loadedLimits: [String: Int] = [:]
            for def in definitions {
                let key = Self.limitsPrefix + def.id
                let stored = defaults.integer(forKey: key)
                loadedLimits[def.id] = stored > 0 ? stored : def.defaultLimitMB
            }
            self.limits = loadedLimits
            self.autoRestartLimits = [:]
            self.patternSchemaVersion = defaults.integer(forKey: Self.patternVersionKey)
        }

        // Ensure limits cover all definitions.
        for def in definitions where limits[def.id] == nil {
            limits[def.id] = def.defaultLimitMB
        }

        migrateBuiltInPatterns()

        isInitialized = true
        // Write out an authoritative config file (creates the file on first run).
        persist()
    }

    /// One-time migration: sync patterns for built-in definitions so that
    /// persisted stores pick up improved matching (e.g. "Cursor" → "Cursor.app").
    private func migrateBuiltInPatterns() {
        guard patternSchemaVersion < Self.currentPatternVersion else { return }

        let builtInMap = Dictionary(
            uniqueKeysWithValues: ProcessDefinition.builtInDefaults.map { ($0.id, $0) }
        )
        for (i, def) in definitions.enumerated() {
            if let builtIn = builtInMap[def.id], def.patterns != builtIn.patterns {
                definitions[i].patterns = builtIn.patterns
            }
        }

        let existingIds = Set(definitions.map(\.id))
        for builtIn in ProcessDefinition.builtInDefaults where !existingIds.contains(builtIn.id) {
            definitions.append(builtIn)
            if limits[builtIn.id] == nil {
                limits[builtIn.id] = builtIn.defaultLimitMB
            }
        }

        patternSchemaVersion = Self.currentPatternVersion
    }

    // MARK: - Limits

    func limit(for definitionId: String) -> Int {
        limits[definitionId] ?? 4096
    }

    func setLimit(_ mb: Int, for definitionId: String) {
        limits[definitionId] = mb
    }

    // MARK: - Auto-restart Limits

    /// Returns the auto-restart threshold in MB, or nil if disabled for this definition.
    func autoRestartLimit(for definitionId: String) -> Int? {
        guard let value = autoRestartLimits[definitionId], value > 0 else { return nil }
        return value
    }

    func setAutoRestartLimit(_ mb: Int?, for definitionId: String) {
        if let mb, mb > 0 {
            autoRestartLimits[definitionId] = mb
        } else {
            autoRestartLimits.removeValue(forKey: definitionId)
        }
    }

    // MARK: - Definitions

    func addDefinition(_ definition: ProcessDefinition) {
        guard !definitions.contains(where: { $0.id == definition.id }) else { return }
        definitions.append(definition)
        limits[definition.id] = definition.defaultLimitMB
    }

    func removeDefinition(id: String) {
        definitions.removeAll { $0.id == id }
        limits.removeValue(forKey: id)
    }

    func updateDefinition(_ definition: ProcessDefinition) {
        guard let idx = definitions.firstIndex(where: { $0.id == definition.id }) else { return }
        definitions[idx] = definition
    }

    func resetToDefaults() {
        definitions = ProcessDefinition.builtInDefaults
        var newLimits: [String: Int] = [:]
        for def in definitions {
            newLimits[def.id] = def.defaultLimitMB
        }
        limits = newLimits
    }

    // MARK: - Persistence

    private func persist() {
        let payload = PersistedConfig(
            definitions: definitions,
            limits: limits,
            pollIntervalSeconds: pollIntervalSeconds,
            isPaused: isPaused,
            patternSchemaVersion: patternSchemaVersion,
            telemetryEnabled: telemetryEnabled,
            preferredLanguage: preferredLanguage,
            autoRestartLimits: autoRestartLimits
        )
        do {
            let dir = configFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            // Persistence failures are non-fatal; in-memory state remains correct.
        }
    }

    private static func loadFromDisk(at url: URL) -> PersistedConfig? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedConfig.self, from: data)
        else { return nil }
        return decoded
    }

    private static func defaultConfigFileURL() -> URL {
        let fm = FileManager.default
        let base: URL
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = appSupport
        } else {
            base = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        }
        return base
            .appendingPathComponent("ProcessMonitor", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func loadDefinitionsFromDefaults(_ defaults: UserDefaults) -> [ProcessDefinition] {
        guard let data = defaults.data(forKey: definitionsKey),
              let stored = try? JSONDecoder().decode([ProcessDefinition].self, from: data),
              !stored.isEmpty
        else {
            return ProcessDefinition.builtInDefaults
        }
        return stored
    }
}
