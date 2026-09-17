import Foundation

struct DiskUsageEntry: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let bytes: Int64

    var displayName: String {
        (path as NSString).lastPathComponent
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
