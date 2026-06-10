import Foundation

struct DiskVolume: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var path: String
    var thresholdPercent: Double?
    var thresholdGB: Double?

    static var bootDefault: DiskVolume {
        let name = volumeName(for: "/") ?? "Macintosh HD"
        return DiskVolume(id: "root", displayName: name, path: "/", thresholdPercent: 10, thresholdGB: 5)
    }

    static func volumeName(for path: String) -> String? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeNameKey]).volumeName
    }
}

struct DiskVolumeStatus: Identifiable {
    let volume: DiskVolume
    let totalBytes: Int64
    let freeBytes: Int64

    var id: String { volume.id }

    var freePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes) * 100
    }

    var freeGB: Double { Double(freeBytes) / 1_073_741_824 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
    var usedGB: Double { totalGB - freeGB }

    var isWarning: Bool {
        if let pct = volume.thresholdPercent, freePercent < pct { return true }
        if let gb = volume.thresholdGB, freeGB < gb { return true }
        return false
    }
}
