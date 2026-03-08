import Foundation

func hasOverLimitProcess(_ processes: [MonitoredProcess]) -> Bool {
    processes.contains { $0.status == .overLimit }
}
