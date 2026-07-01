import Foundation

/// Turns a `CleanupCommand.command` string into a read-only shell command that
/// estimates (in bytes) how much disk space the real command would free, without
/// deleting anything. Returns nil when no heuristic applies — callers must treat
/// that as "no estimate available", not an error.
enum CleanupSizeEstimator {

    static func measurementCommand(for command: String) -> String? {
        if let pathCommand = pathBasedMeasurementCommand(for: command) {
            return pathCommand
        }
        return knownToolMeasurementCommand(for: command)
    }

    // MARK: - Path-based (rm -rf / rm -f / find ... -delete)

    /// Captures everything after `rm -rf`/`rm -f` up to the next `;`/`&&`/`||` or
    /// end of string — may itself contain several space-separated paths (e.g. the
    /// Cursor Cache command lists six), which is fine: `du` accepts multiple operands.
    private static let rmClauseRegex = try! NSRegularExpression(
        pattern: #"rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+([^;&|]+)"#,
        options: [.caseInsensitive]
    )
    /// Captures only the single path argument immediately after `find`, respecting
    /// backslash-escaped spaces (`\ `) so it doesn't stop mid-path.
    private static let findPathRegex = try! NSRegularExpression(
        pattern: #"\bfind\s+((?:\\ |\S)+)"#,
        options: [.caseInsensitive]
    )

    private static func pathBasedMeasurementCommand(for command: String) -> String? {
        // "find" without "-delete" is a read-only scan (e.g. the built-in "Scan:"
        // commands) — nothing will actually be freed, so it gets no estimate.
        let hasFindDelete = command.range(of: #"\bfind\b.*-delete"#, options: [.regularExpression, .caseInsensitive]) != nil
        let hasRm = command.range(of: #"\brm\s+-[a-zA-Z]*f"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard hasFindDelete || hasRm else { return nil }

        let ns = command as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var targets: [String] = []

        // Extract find paths first (to preserve order in original command)
        if hasFindDelete {
            for match in findPathRegex.matches(in: command, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !captured.isEmpty { targets.append(captured) }
            }
        }

        // Then extract rm paths
        for match in rmClauseRegex.matches(in: command, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !captured.isEmpty { targets.append(captured) }
        }

        guard !targets.isEmpty else { return nil }
        return "du -sck \(targets.joined(separator: " ")) 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'"
    }

    // MARK: - Known-tool heuristics (fixed table, matches seeded non-path commands)

    private static func knownToolMeasurementCommand(for command: String) -> String? {
        let lower = command.lowercased()
        return knownTools.first { lower.contains($0.match) }?.command
    }

    private static let knownTools: [(match: String, command: String)] = [
        ("xcrun simctl delete unavailable", simctlUnavailableCommand),
        ("xcrun simctl erase all", simctlEraseAllCommand),
        ("brew cleanup", #"command -v brew >/dev/null 2>&1 && du -sk "$(brew --cache)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("npm cache clean", #"command -v npm >/dev/null 2>&1 && du -sk "$(npm config get cache 2>/dev/null)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("pod cache clean", #"command -v pod >/dev/null 2>&1 && du -sk ~/Library/Caches/CocoaPods 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("docker system prune", dockerReclaimableCommand),
    ]

    /// Lists unavailable-runtime device UDIDs as plain text (no `jq`/JSON parsing
    /// needed) and sums each device directory's size.
    private static let simctlUnavailableCommand = #"xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#

    /// Same approach as above but over every device (approximates "erase all" —
    /// each device folder's full size, not just its resettable Data subfolder).
    private static let simctlEraseAllCommand = #"xcrun simctl list devices 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#

    /// `docker system df --format '{{.Reclaimable}}'` prints one human-readable size
    /// per row (e.g. "1.24GB (76%)") — strip the percentage, convert each unit
    /// suffix to bytes, and sum.
    private static let dockerReclaimableCommand = #"command -v docker >/dev/null 2>&1 && docker system df --format '{{.Reclaimable}}' 2>/dev/null | sed -E 's/ *\([0-9]+%\)//' | awk '/TB$/{gsub(/TB$/,"");sum+=$1*1099511627776} /GB$/{gsub(/GB$/,"");sum+=$1*1073741824} /MB$/{gsub(/MB$/,"");sum+=$1*1048576} /kB$/{gsub(/kB$/,"");sum+=$1*1024} /B$/{gsub(/B$/,"");sum+=$1} END{printf "%d", sum}'"#
}
