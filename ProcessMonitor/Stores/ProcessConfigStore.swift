import Foundation
import Combine

final class ProcessConfigStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private static let limitsPrefix = "memoryLimit_"
    private static let definitionsKey = "monitoredDefinitions"
    private static let patternVersionKey = "patternSchemaVersion"
    private static let currentPatternVersion = 2

    @Published var definitions: [ProcessDefinition] = []
    @Published var limits: [String: Int] = [:]

    init() {
        definitions = Self.loadDefinitions(from: defaults)
        migrateBuiltInPatterns()
        for def in definitions {
            let key = Self.limitsPrefix + def.id
            let stored = defaults.integer(forKey: key)
            limits[def.id] = stored > 0 ? stored : def.defaultLimitMB
        }
    }

    /// One-time migration: sync patterns for built-in definitions so that
    /// persisted stores pick up improved matching (e.g. "Cursor" → "Cursor.app").
    private func migrateBuiltInPatterns() {
        let version = defaults.integer(forKey: Self.patternVersionKey)
        guard version < Self.currentPatternVersion else { return }

        let builtInMap = Dictionary(
            uniqueKeysWithValues: ProcessDefinition.builtInDefaults.map { ($0.id, $0) }
        )
        var changed = false
        for (i, def) in definitions.enumerated() {
            if let builtIn = builtInMap[def.id], def.patterns != builtIn.patterns {
                definitions[i].patterns = builtIn.patterns
                changed = true
            }
        }

        let existingIds = Set(definitions.map(\.id))
        for builtIn in ProcessDefinition.builtInDefaults where !existingIds.contains(builtIn.id) {
            definitions.append(builtIn)
            changed = true
        }

        if changed { persistDefinitions() }
        defaults.set(Self.currentPatternVersion, forKey: Self.patternVersionKey)
    }

    // MARK: - Limits

    func limit(for definitionId: String) -> Int {
        limits[definitionId] ?? 4096
    }

    func setLimit(_ mb: Int, for definitionId: String) {
        limits[definitionId] = mb
        defaults.set(mb, forKey: Self.limitsPrefix + definitionId)
    }

    // MARK: - Definitions

    func addDefinition(_ definition: ProcessDefinition) {
        guard !definitions.contains(where: { $0.id == definition.id }) else { return }
        definitions.append(definition)
        limits[definition.id] = definition.defaultLimitMB
        defaults.set(definition.defaultLimitMB, forKey: Self.limitsPrefix + definition.id)
        persistDefinitions()
    }

    func removeDefinition(id: String) {
        definitions.removeAll { $0.id == id }
        limits.removeValue(forKey: id)
        defaults.removeObject(forKey: Self.limitsPrefix + id)
        persistDefinitions()
    }

    func updateDefinition(_ definition: ProcessDefinition) {
        guard let idx = definitions.firstIndex(where: { $0.id == definition.id }) else { return }
        definitions[idx] = definition
        persistDefinitions()
    }

    func resetToDefaults() {
        definitions = ProcessDefinition.builtInDefaults
        persistDefinitions()
        for def in definitions {
            setLimit(def.defaultLimitMB, for: def.id)
        }
    }

    // MARK: - Persistence

    private func persistDefinitions() {
        guard let data = try? JSONEncoder().encode(definitions) else { return }
        defaults.set(data, forKey: Self.definitionsKey)
    }

    private static func loadDefinitions(from defaults: UserDefaults) -> [ProcessDefinition] {
        guard let data = defaults.data(forKey: definitionsKey),
              let stored = try? JSONDecoder().decode([ProcessDefinition].self, from: data),
              !stored.isEmpty
        else {
            return ProcessDefinition.builtInDefaults
        }
        return stored
    }
}
