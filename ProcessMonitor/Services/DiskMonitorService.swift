import Foundation
import Combine

final class DiskMonitorService: ObservableObject {
    @Published var statuses: [DiskVolumeStatus] = []

    private var alertActive: [String: Bool] = [:]
    private let configStore: ProcessConfigStore
    private let notificationService: NotificationService
    private var pollTask: Task<Void, Never>?
    private var configCancellables = Set<AnyCancellable>()
    private var pollInterval: TimeInterval

    init(configStore: ProcessConfigStore, notificationService: NotificationService) {
        self.configStore = configStore
        self.notificationService = notificationService
        self.pollInterval = configStore.pollIntervalSeconds

        configStore.$pollIntervalSeconds
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] interval in self?.applyPollInterval(interval) }
            .store(in: &configCancellables)

        configStore.$isPaused
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] paused in
                if paused { self?.stopPolling() } else { self?.startPolling() }
            }
            .store(in: &configCancellables)
    }

    func startPolling() {
        guard pollTask == nil, !configStore.isPaused else { return }
        let interval = pollInterval
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAsync()
                let ns = UInt64(max(0.1, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.refreshAsync()
        }
    }

    private func applyPollInterval(_ interval: TimeInterval) {
        pollInterval = interval
        guard pollTask != nil else { return }
        stopPolling()
        startPolling()
    }

    private func refreshAsync() async {
        let volumes = configStore.diskVolumes
        let newStatuses: [DiskVolumeStatus] = volumes.compactMap { volume in
            guard
                let attrs = try? FileManager.default.attributesOfFileSystem(forPath: volume.path),
                let freeNum = attrs[.systemFreeSize] as? NSNumber,
                let totalNum = attrs[.systemSize] as? NSNumber
            else { return nil }
            return DiskVolumeStatus(
                volume: volume,
                totalBytes: totalNum.int64Value,
                freeBytes: freeNum.int64Value
            )
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.statuses = newStatuses
            self.checkThresholds(newStatuses)
        }
    }

    private func checkThresholds(_ statuses: [DiskVolumeStatus]) {
        for status in statuses {
            let wasActive = alertActive[status.id] ?? false
            if status.isWarning {
                if !wasActive {
                    alertActive[status.id] = true
                    notificationService.notifyDiskWarning(status: status)
                }
            } else {
                alertActive[status.id] = false
            }
        }
    }
}
