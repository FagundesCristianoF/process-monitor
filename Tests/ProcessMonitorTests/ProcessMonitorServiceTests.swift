import XCTest
@testable import ProcessMonitor

final class ProcessMonitorServiceTests: XCTestCase {
    func testStartPollingIsIdempotent() {
        var publisherFactoryCalls = 0
        let service = ProcessMonitorService(
            configStore: ProcessConfigStore(),
            notificationService: NotificationService(),
            pollInterval: 3600,
            processEntriesProvider: { [] },
            pollPublisherFactory: { interval in
                publisherFactoryCalls += 1
                return Timer.publish(every: interval, on: .main, in: .common)
            }
        )

        service.startPolling()
        service.startPolling()

        XCTAssertEqual(publisherFactoryCalls, 1)
        XCTAssertTrue(service.isPolling)

        service.stopPolling()
        XCTAssertFalse(service.isPolling)
    }
}
