import Foundation
import AppKit

/// Detects whether the app has been granted Full Disk Access and routes the user
/// to the right System Settings pane to grant it.
///
/// macOS provides no API to request Full Disk Access programmatically — an app can
/// only detect the current state and deep-link the user to Settings. We detect it
/// by attempting to open the user's TCC database, which is readable only with FDA.
enum FullDiskAccessService {
    /// A TCC-protected file that exists on every Mac and can be opened only when
    /// Full Disk Access is granted to this app.
    private static var probePath: String {
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    }

    /// True when Full Disk Access is granted. If the probe is blocked specifically
    /// by permissions (EACCES/EPERM) we report `false`; any other outcome (including
    /// a missing probe file) is treated as granted so we never nag incorrectly.
    static var isGranted: Bool {
        let fd = open(probePath, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        let err = errno
        return err != EACCES && err != EPERM
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
