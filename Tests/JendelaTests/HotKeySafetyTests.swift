import AppKit
import XCTest
@testable import Jendela

/// These are Carbon hot keys, registered system-wide. A combination with one
/// modifier takes that combination away from every app on the Mac: a stored
/// ⌘V stopped paste working everywhere, in every application, until the
/// binding was found and changed.
@MainActor
final class HotKeySafetyTests: XCTestCase {
    private func binding(_ key: UInt32, _ flags: NSEvent.ModifierFlags) -> HotKeyBinding {
        HotKeyBinding(keyCode: key, modifiers: flags.rawValue, enabled: true)
    }

    func testSingleModifierCombinationsAreRejected() {
        let v: UInt32 = 9
        for flags: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            XCTAssertFalse(binding(v, flags).isSafeForGlobalUse,
                           "a single modifier would shadow this key everywhere")
            XCTAssertFalse(binding(v, flags).isValid)
        }
    }

    func testTwoModifierCombinationsAreAccepted() {
        XCTAssertTrue(binding(9, [.command, .shift]).isSafeForGlobalUse)      // ⌘⇧V
        XCTAssertTrue(binding(49, [.command, .shift]).isSafeForGlobalUse)     // ⌘⇧Space
        XCTAssertTrue(binding(9, [.command, .option]).isSafeForGlobalUse)
    }

    func testEveryDefaultIsSafe() {
        for action in HotKeyAction.allCases where action.defaultBinding.enabled {
            XCTAssertTrue(action.defaultBinding.isSafeForGlobalUse,
                          "\(action.rawValue) ships with an unsafe default")
        }
    }

    /// The stored ⌘V has to be repaired on load: leaving it in place means
    /// paste stays broken every launch, and the settings screen that would fix
    /// it is behind the shortcut that no longer works.
    func testStoredUnsafeBindingIsReplacedOnLoad() throws {
        let file = SupportDirectory.root.appendingPathComponent("settings.json")
        var settings = JendelaSettings()
        settings.hotKeys = ["clipboard": binding(9, .command)]   // ⌘V, as found on disk
        try JSONEncoder().encode(settings).write(to: file)

        let state = JendelaState()
        let loaded = try XCTUnwrap(state.hotKeys[.clipboard])
        XCTAssertTrue(loaded.isSafeForGlobalUse, "an unsafe stored binding survived the load")
        XCTAssertEqual(loaded, HotKeyAction.clipboard.defaultBinding)
        try? FileManager.default.removeItem(at: file)
    }
}
