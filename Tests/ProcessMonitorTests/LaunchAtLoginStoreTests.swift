import XCTest
import ServiceManagement
@testable import ProcessMonitor

@MainActor
final class LaunchAtLoginStoreTests: XCTestCase {

    private struct TestError: Error {
        let localizedDescription = "register failed"
    }

    // MARK: - Pure resolver

    func testResolveEnabledKeepsNilMessageAsDefault() {
        let r = LaunchAtLoginStore.resolve(status: .enabled, existingMessage: nil)
        XCTAssertTrue(r.isEnabled)
        XCTAssertNotNil(r.statusMessage)
    }

    func testResolveEnabledKeepsExistingMessage() {
        let r = LaunchAtLoginStore.resolve(status: .enabled, existingMessage: "custom")
        XCTAssertTrue(r.isEnabled)
        XCTAssertEqual(r.statusMessage, "custom")
    }

    func testResolveRequiresApproval() {
        let r = LaunchAtLoginStore.resolve(status: .requiresApproval, existingMessage: nil)
        XCTAssertFalse(r.isEnabled)
        XCTAssertNotNil(r.statusMessage)
    }

    func testResolveNotRegisteredShowsHint() {
        let r = LaunchAtLoginStore.resolve(status: .notRegistered, existingMessage: nil)
        XCTAssertFalse(r.isEnabled)
        XCTAssertNotNil(r.statusMessage)
    }

    func testResolveNotFoundPreservesErrorMessage() {
        let r = LaunchAtLoginStore.resolve(status: .notFound, existingMessage: "boom")
        XCTAssertFalse(r.isEnabled)
        XCTAssertEqual(r.statusMessage, "boom")
    }

    // MARK: - Store with injected status

    func testInitReflectsEnabledStatus() {
        let store = LaunchAtLoginStore(statusProvider: { .enabled })
        XCTAssertTrue(store.isEnabled)
    }

    func testSetEnabledSuccessClearsErrorThenResolves() {
        var registered = false
        let store = LaunchAtLoginStore(
            statusProvider: { registered ? .enabled : .notRegistered },
            register: { registered = true },
            unregister: { registered = false }
        )
        XCTAssertFalse(store.isEnabled)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
    }

    func testSetEnabledFailureSetsErrorMessage() {
        let store = LaunchAtLoginStore(
            statusProvider: { .notRegistered },
            register: { throw TestError() }
        )
        store.setEnabled(true)
        XCTAssertNotNil(store.statusMessage)
        XCTAssertFalse(store.isEnabled)
    }

    func testEnsureRegisteredRegistersWhenNotRegistered() {
        var registerCalls = 0
        var registered = false
        let store = LaunchAtLoginStore(
            statusProvider: { registered ? .enabled : .notRegistered },
            register: { registerCalls += 1; registered = true }
        )
        store.ensureRegistered()
        XCTAssertEqual(registerCalls, 1)
    }

    func testEnsureRegisteredSkipsWhenAlreadyEnabled() {
        var registerCalls = 0
        let store = LaunchAtLoginStore(
            statusProvider: { .enabled },
            register: { registerCalls += 1 }
        )
        store.ensureRegistered()
        XCTAssertEqual(registerCalls, 0)
    }
}
