import Foundation
import AppKit

/// Appends one CSV row per poll tick for apps the user has opted into
/// file logging, to help debug lags after the fact. One file per app,
/// under ~/Library/Application Support/ProcessMonitor/logs/. No rotation —
/// the UI surfaces a 10MB warning and a manual Clear action instead.
final class ProcessLogWriterService {
    static let warningThresholdBytes: Int64 = 10 * 1024 * 1024 // 10 MB

    private static let header = "timestamp,cpu_percent,memory_mb,swap_mb,process_count\n"

    private let logsDirectory: URL
    private var fileHandles: [String: FileHandle] = [:]
    private let dateFormatter = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "com.cristianofagundes.ProcessMonitor.logwriter")

    init(logsDirectory: URL = ProcessLogWriterService.defaultLogsDirectory()) {
        self.logsDirectory = logsDirectory
    }

    func log(process: MonitoredProcess) {
        guard process.status != .notRunning else { return }
        let processCount = process.children.count + process.rootPids.count
        queue.sync {
            // ISO8601DateFormatter is not documented thread-safe; format
            // inside the serial queue alongside the other shared state.
            let timestamp = dateFormatter.string(from: Date())
            let line = String(
                format: "%@,%.1f,%.1f,%.1f,%d\n",
                timestamp, process.totalCPU, process.totalMemoryMB, process.totalSwapMB, processCount
            )
            appendLine(line, forAppID: process.definition.id)
        }
    }

    func fileSizeBytes(forAppID id: String) -> Int64? {
        queue.sync {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(forAppID: id).path)
            return attrs?[.size] as? Int64
        }
    }

    func clearLog(forAppID id: String) {
        queue.sync {
            try? fileHandles[id]?.close()
            fileHandles[id] = nil
            writeHeaderOnlyFile(forAppID: id)
        }
    }

    func revealLog(forAppID id: String) {
        let url = fileURL(forAppID: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func defaultLogsDirectory() -> URL {
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
            .appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: - Private

    private func fileURL(forAppID id: String) -> URL {
        logsDirectory.appendingPathComponent("\(id).csv")
    }

    private func appendLine(_ line: String, forAppID id: String) {
        guard let handle = fileHandles[id] ?? openOrCreateHandle(forAppID: id) else { return }
        guard let data = line.data(using: .utf8) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func openOrCreateHandle(forAppID id: String) -> FileHandle? {
        let url = fileURL(forAppID: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeHeaderOnlyFile(forAppID: id)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        fileHandles[id] = handle
        return handle
    }

    private func writeHeaderOnlyFile(forAppID id: String) {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: fileURL(forAppID: id).path,
            contents: Self.header.data(using: .utf8)
        )
    }
}
