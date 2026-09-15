import Security
import XCTest
@testable import Jendela

/// The device secret is the only key that opens the encrypted clipboard and
/// chat history. Replacing it makes both unreadable for good, so it may only
/// be replaced when there genuinely is no usable key.
final class DeviceSecretTests: XCTestCase {
    func testAWellFormedKeyIsUsed() {
        XCTAssertEqual(DeviceSecret.outcome(forReadStatus: errSecSuccess, keyLength: 32), .use)
    }

    func testAMissingKeyIsCreated() {
        XCTAssertEqual(DeviceSecret.outcome(forReadStatus: errSecItemNotFound, keyLength: nil), .create)
    }

    func testAMalformedKeyIsReplaced() {
        XCTAssertEqual(DeviceSecret.outcome(forReadStatus: errSecSuccess, keyLength: 16), .create)
    }

    /// The case that destroyed history: a failed read used to delete the item
    /// and mint a new key, even when the Keychain was only locked.
    func testALockedKeychainNeverReplacesTheKey() {
        XCTAssertEqual(DeviceSecret.outcome(forReadStatus: errSecInteractionNotAllowed, keyLength: nil),
                       .unavailable)
    }

    func testAnUnentitledProcessFallsBackToAFile() {
        XCTAssertEqual(DeviceSecret.outcome(forReadStatus: errSecMissingEntitlement, keyLength: nil),
                       .fileFallback)
    }

    /// End to end through whichever store this runner can use: asking twice
    /// must give back the same key, not a fresh one.
    func testTheSameKeyComesBackTwice() throws {
        let account = "device-secret-test-\(UUID().uuidString)"
        let file = "\(account).key"
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.jendela.desktop",
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true
            ] as CFDictionary)
            try? FileManager.default.removeItem(at: SupportDirectory.root.appendingPathComponent(file))
        }
        let first = try XCTUnwrap(DeviceSecret.resolve(account: account, fallbackFileName: file))
        let second = try XCTUnwrap(DeviceSecret.resolve(account: account, fallbackFileName: file))
        XCTAssertEqual(first.key.withUnsafeBytes { Data($0) }, second.key.withUnsafeBytes { Data($0) },
                       "a second read minted a new key, which orphans everything encrypted with the first")
    }
}

/// The clipboard poll rate follows `conserving`, which reads the Battery saver
/// setting as well as the power state.
@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testBatterySaverSettingReschedulesThePoll() {
        let state = JendelaState()
        state.clipboardAutoCapture = true
        state.notchExpanded = false
        state.batterySaverMode = .off
        let monitor = ClipboardMonitor(state: state)
        monitor.start()
        defer { monitor.stop() }

        spin()
        XCTAssertEqual(monitor.currentInterval, 3)

        state.batterySaverMode = .on
        spin()
        XCTAssertEqual(monitor.currentInterval, 8,
                       "switching Battery saver on left the poll at its old rate")

        state.batterySaverMode = .off
        spin()
        XCTAssertEqual(monitor.currentInterval, 3)
    }

    private func spin() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }
}
