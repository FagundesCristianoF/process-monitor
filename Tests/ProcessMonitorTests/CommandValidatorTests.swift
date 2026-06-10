import XCTest
@testable import ProcessMonitor

final class CommandValidatorTests: XCTestCase {

    // MARK: - Safe commands pass

    func testSafeCommandPasses() {
        XCTAssertEqual(CommandValidator.validate("xcrun simctl delete unavailable"), .ok)
    }

    func testBrewCleanupPasses() {
        XCTAssertEqual(CommandValidator.validate("brew cleanup --prune=all"), .ok)
    }

    func testNpmCachePasses() {
        XCTAssertEqual(CommandValidator.validate("npm cache clean --force"), .ok)
    }

    func testDockerPrunePasses() {
        XCTAssertEqual(CommandValidator.validate("docker system prune --volumes -f"), .ok)
    }

    func testRmWithSpecificGlobPasses() {
        XCTAssertEqual(
            CommandValidator.validate(#"rm -rf ~/Library/Application\ Support/Google/AndroidStudio2025.*"#),
            .ok
        )
    }

    func testRmRfHomeDollarSubpathPasses() {
        XCTAssertEqual(
            CommandValidator.validate("rm -rf $HOME/Library/Caches"),
            .ok
        )
    }

    // MARK: - chmod / chown blocked

    func testChmodBlocked() {
        if case .blocked = CommandValidator.validate("chmod 777 /etc/hosts") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testChownBlocked() {
        if case .blocked = CommandValidator.validate("chown root /etc/passwd") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - rm -rf on dangerous targets blocked

    func testRmRfRootBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf /") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfRootWithTrailingSpaceBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf / ") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmFrRootBlocked() {
        if case .blocked = CommandValidator.validate("rm -fr /") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfHomeBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf ~") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfHomeDirBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf ~/") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfDollarHomeBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf $HOME") { } else {
            XCTFail("Expected .blocked")
        }
    }

    func testRmRfRootStarBlocked() {
        if case .blocked = CommandValidator.validate("rm -rf /*") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - fork bomb blocked

    func testForkBombBlocked() {
        if case .blocked = CommandValidator.validate(":(){ :|:& };:") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - dd to block device blocked

    func testDdToDeviceBlocked() {
        if case .blocked = CommandValidator.validate("dd if=/dev/zero of=/dev/sda") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - redirect to block device blocked

    func testRedirectToDevSdBlocked() {
        if case .blocked = CommandValidator.validate("echo foo > /dev/sda") { } else {
            XCTFail("Expected .blocked")
        }
    }

    // MARK: - reason string is non-empty

    func testBlockedReasonIsNonEmpty() {
        if case .blocked(let reason) = CommandValidator.validate("chmod 777 /") {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected .blocked")
        }
    }
}
