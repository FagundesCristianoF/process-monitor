import Foundation

/// Scans common developer disk hotspots and parses `du` output into chart-ready entries.
enum DiskUsageScanner {

    /// Read-only `du -sk` over well-known cache/build locations, sorted largest first.
    static let scanShellCommand = #"""
du -sk \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/Xcode/Archives" \
  "$HOME/Library/Developer/CoreSimulator/Devices" \
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
  "$HOME/Library/Caches" \
  "$HOME/.gradle/caches" \
  "$HOME/.npm" \
  "$HOME/.docker" \
  "$HOME/Library/Application Support/Cursor" \
  "$HOME/Library/Application Support/Google" \
  "$HOME/Library/Application Support/Claude" \
  "$HOME/Library/Caches/org.swift.swiftpm" \
  "$HOME/.m2/repository" \
  "$(command -v brew >/dev/null 2>&1 && brew --cache)" \
  2>/dev/null | awk '$1 > 0' | sort -rn | head -20
"""#

    static func scanTopFolders(limit: Int = 15) -> [DiskUsageEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", scanShellCommand]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseDuOutput(output, limit: limit)
    }

    static func parseDuOutput(_ output: String, limit: Int = 15) -> [DiskUsageEntry] {
        var entries: [DiskUsageEntry] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let entry = parseDuLine(String(line)) else { continue }
            entries.append(entry)
        }
        return Array(entries.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    static func parseDuLine(_ line: String) -> DiskUsageEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let tab = trimmed.firstIndex(of: "\t") {
            let sizePart = trimmed[..<tab]
            let pathPart = trimmed[tab...].trimmingCharacters(in: .whitespaces)
            guard let kb = Int64(sizePart), !pathPart.isEmpty else { return nil }
            return DiskUsageEntry(path: pathPart, bytes: kb * 1024)
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2, let kb = Int64(parts[0]) else { return nil }
        let path = parts.dropFirst().joined(separator: " ")
        guard !path.isEmpty else { return nil }
        return DiskUsageEntry(path: path, bytes: kb * 1024)
    }
}
